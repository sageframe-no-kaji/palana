// The Transports — enactment, first half (ho-06.1). Executes an
// approved Plan exactly as composed: no improvisation between approval
// and execution. Host steps run through the Conduit; proxied pipelines
// run in-process through an injected runner. A ZFS cleanup gate opens
// only when its bound destination dataset exists.

import Foundation

/// Runs Plans and streams what actually happens.
public struct Transports: Sendable {
    /// Enacts a proxied pipeline step — both halves spawned, bytes
    /// counted between them.
    ///
    /// Injectable so gate logic unit-tests without spawning ssh. The
    /// arguments are the pipeline, the step index, and the event sink.
    public typealias PipelineRunner =
        @Sendable (Pipeline, Int, @Sendable (EnactmentEvent) -> Void) async throws -> Int32

    private let conduit: any Conduit
    private let pipelineRunner: PipelineRunner

    /// A transports layer over the given door.
    ///
    /// The default pipeline runner spawns real ssh halves with this
    /// configuration; tests inject a fake.
    public init(
        conduit: any Conduit,
        configuration: SSHConfiguration = SSHConfiguration(),
        pipelineRunner: PipelineRunner? = nil
    ) {
        self.conduit = conduit
        self.pipelineRunner =
            pipelineRunner
            ?? { pipeline, stepIndex, emit in
                try await SSHPipeline.run(
                    pipeline, configuration: configuration, stepIndex: stepIndex, emit: emit)
            }
    }

    /// Enacts the plan, streaming events as they happen.
    ///
    /// The stream throws ``EnactmentError`` on failure and
    /// ``ConduitError`` when the door itself fails. Gated steps run
    /// only after a matched verification. Ending the stream early
    /// stops the active command's process group; a caller that needs
    /// to await that teardown uses ``run(_:emit:)`` in its own task.
    public func enact(_ plan: Plan) -> AsyncThrowingStream<EnactmentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(plan) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Enacts the plan in the calling task, handing each event to `emit`.
    ///
    /// The structured form of ``enact(_:)``: cancelling the task stops
    /// the active host command or both pipeline halves, and the call
    /// throws `CancellationError` only once every owned process has
    /// exited — so a caller that awaits this has awaited the teardown.
    public func run(_ plan: Plan, emit: @Sendable (EnactmentEvent) -> Void) async throws {
        try Self.refuseUnrunnable(plan)
        var state = EnactmentState()
        for (index, step) in plan.steps.enumerated() {
            try Task.checkCancellation()
            try await openGate(for: step, plan: plan, state: &state, emit: emit)
            emit(.stepBegan(index: index, step: step))
            let result = try await runStep(step, index: index, plan: plan, emit: emit)
            emit(.stepEnded(index: index, exitStatus: result.exitStatus))
            for note in RecoveryNote.notes(in: result.stderrTail, host: Self.hostLabel(step)) {
                emit(.recovery(note))
            }
            try Self.raise(result, index: index)
        }
        emit(.finished)
    }

    /// What the run has established — never a Boolean.
    private struct EnactmentState {
        /// What the passed gate authorised, and over which evidence.
        var authorization: GateAuthorization?
    }

    /// What a passed gate authorises.
    private enum GateAuthorization {
        /// A zfs transfer whose received dataset exists.
        case dataset(String)
    }

    /// Refuses, before a single step runs, a plan whose shape cannot
    /// carry the authority its steps claim.
    ///
    /// A commit step with no version behind it and a gated ZFS destroy
    /// with no receive binding are shapes a plan written before these
    /// bindings existed takes. Neither may run: a plan decoded from an
    /// older file stays readable and stays harmless.
    private static func refuseUnrunnable(_ plan: Plan) throws {
        // A plan the engine would have refused must not run from here
        // either: the tool fails mid-way on the clash, after earlier
        // entries already moved.
        if let collisions = plan.collisions, collisions.hasKindClash {
            throw EnactmentError.malformedPlan(
                collisions.clashSentence() ?? "kind clash at the destination")
        }
        let commits = plan.steps.contains { $0.role == .promote }
        if commits, plan.versionGuard == nil {
            throw EnactmentError.malformedPlan(
                "a commit step with no remote version behind it — nothing may be replaced")
        }
        if plan.versionGuard != nil, !commits {
            throw EnactmentError.malformedPlan(
                "a version-bound send-back with no commit step — nothing may be replaced")
        }
        if let versionGuard = plan.versionGuard {
            try validateVersionBoundPlan(plan, guard: versionGuard)
        }
        if let zfsReleaseGuard = plan.zfsReleaseGuard {
            try validateZFSReleasePlan(plan, guard: zfsReleaseGuard)
        }
        guard plan.steps.contains(where: \.gatedOnVerification) else { return }
        guard plan.receivedDataset != nil, plan.zfsReleaseGuard != nil else {
            throw EnactmentError.malformedPlan(
                "a gated step with no bound ZFS receive behind it — nothing may be deleted")
        }
    }

    /// A decoded or mutated plan receives no authority merely because it carries a guard value.
    ///
    /// Its privileged steps must be the exact stage
    /// and commit described by that guard, on that host, in that order.
    private static func validateVersionBoundPlan(
        _ plan: Plan, guard versionGuard: RemoteVersionGuard
    ) throws {
        guard PlanEngine.validOperationToken(versionGuard.token),
            let destination = plan.destination,
            destination.host == versionGuard.host,
            plan.entries.count == 1
        else {
            throw EnactmentError.malformedPlan("the version-bound plan has an invalid identity")
        }
        let pathData = RemoteIdentity.pathData(
            directory: destination.directory, name: plan.entries[0].nameData)
        guard pathData == versionGuard.pathData else {
            throw EnactmentError.malformedPlan("the version guard names a different destination")
        }
        let stages = plan.steps.enumerated().filter { $0.element.role == .stage }
        let promotes = plan.steps.enumerated().filter { $0.element.role == .promote }
        guard stages.count == 1, promotes.count == 1,
            let stage = stages.first, let promote = promotes.first,
            stage.offset < promote.offset
        else {
            throw EnactmentError.malformedPlan("the version-bound plan has no unique stage and commit")
        }
        let runner = Runner.host(destination.host)
        let staging = RemoteVersionGuard.stagingDirectory(
            in: destination.directory, token: versionGuard.token)
        let expectedStage = PlanStep(
            runsOn: runner,
            command: "mkdir -- \(ShellQuote.quote(staging))",
            role: .stage)
        let expectedPromote = PlanStep(
            runsOn: runner,
            command: versionGuard.commitProgram(
                directory: destination.directory, name: plan.entries[0].name),
            role: .promote)
        guard stage.element == expectedStage, promote.element == expectedPromote else {
            throw EnactmentError.malformedPlan(
                "the version-bound plan's privileged steps do not match its guard")
        }
    }

    /// A received dataset authorizes only the cleanup steps composed from
    /// the same hosts, datasets, operation identity, and move/copy intent.
    private static func validateZFSReleasePlan(
        _ plan: Plan, guard release: ZFSReleaseGuard
    ) throws {
        guard PlanEngine.validOperationToken(release.token),
            plan.transport == .zfsSendReceiveForwarded
                || plan.transport == .zfsSendReceiveProxied,
            plan.source.host == release.sourceHost,
            plan.destination?.host == release.destinationHost,
            plan.receivedDataset == release.receivedDataset,
            (plan.operation == .move) == release.deletesSource
        else {
            throw EnactmentError.malformedPlan("the ZFS release has an invalid identity")
        }
        let gated = plan.steps.filter(\.gatedOnVerification)
        guard gated == release.releaseSteps else {
            throw EnactmentError.malformedPlan(
                "the gated ZFS steps do not match the receive they claim")
        }
    }

    /// Verifies once, then proves this particular step is the one the
    /// verification authorised.
    private func openGate(
        for step: PlanStep,
        plan: Plan,
        state: inout EnactmentState,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws {
        guard step.gatedOnVerification else { return }
        if state.authorization == nil {
            let report = try await verify(plan, emit: emit)
            emit(.verified(report))
            guard report.matched else {
                throw EnactmentError.verificationFailed(report)
            }
            state.authorization = try Self.authorization(from: report)
        }
        guard let release = plan.zfsReleaseGuard,
            case .dataset(let received)? = state.authorization,
            received == release.receivedDataset,
            release.releaseSteps.contains(step)
        else {
            throw EnactmentError.malformedPlan(
                "the gated ZFS step is not authorized by this receive")
        }
    }

    /// Turns a matched report into the authority a step may claim.
    private static func authorization(
        from report: VerificationReport
    ) throws -> GateAuthorization {
        switch report {
        case .datasetReceived(let name, _):
            return .dataset(name)
        case .manifests:
            throw EnactmentError.malformedPlan(
                "file-manifest deletion has no atomic release primitive")
        }
    }

    /// The host a step's output is attributed to.
    private static func hostLabel(_ step: PlanStep) -> String {
        switch step.runsOn {
        case .operatorMachine: PalanaCore.localHostName
        case .host(let host): host
        }
    }

    /// Raises a nonzero step, door failures first.
    private static func raise(_ result: StepResult, index: Int) throws {
        guard result.exitStatus != 0 else { return }
        let doorFailure = ConduitError.classify(
            exitStatus: result.exitStatus, stderr: result.stderrTail)
        if let doorFailure { throw doorFailure }
        throw EnactmentError.stepFailed(
            index: index, exitStatus: result.exitStatus, stderrTail: result.stderrTail)
    }

    // MARK: - Steps

    private struct StepResult {
        var exitStatus: Int32
        var stderrTail: String
    }

    private func runStep(
        _ step: PlanStep,
        index: Int,
        plan: Plan,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> StepResult {
        switch step.runsOn {
        case .operatorMachine:
            guard let pipeline = step.pipeline else {
                throw EnactmentError.malformedPlan(
                    "operator-machine step without a pipeline: \(step.command)")
            }
            let status = try await pipelineRunner(pipeline, index, emit)
            return StepResult(exitStatus: status, stderrTail: "")
        case .host(let host):
            return try await runHostStep(step, on: host, index: index, plan: plan, emit: emit)
        }
    }

    /// Whether a composed command runs rsync — the binary named by its
    /// first token, by last path component.
    ///
    /// `rsync -a …` and `/opt/homebrew/bin/rsync -a …` both match;
    /// `rsyncd …` and `myrsync …` do not. A single-quoted first token
    /// (a path with a space, quoted by the engine) is read through to
    /// its closing quote. Progress parsing keys on this, so a plan that
    /// names its binary absolutely still gets a bar.
    static func isRsyncCommand(_ command: String) -> Bool {
        let firstToken: Substring
        if command.hasPrefix("'") {
            let body = command.dropFirst()
            guard let close = body.firstIndex(of: "'") else { return false }
            firstToken = body[..<close]
        } else {
            firstToken = command.prefix { !$0.isWhitespace }
        }
        return firstToken.split(separator: "/", omittingEmptySubsequences: false).last == "rsync"
    }

    private func runHostStep(
        _ step: PlanStep,
        on host: String,
        index: Int,
        plan: Plan,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> StepResult {
        let running = try await conduit.run(on: host, step.command)
        // Only rsync speaks progress2, and every rsync step starts with
        // the binary — same-host copies included, whatever the transport.
        let parseProgress = Self.isRsyncCommand(step.command)
        // The forwarded zfs path's progress arrives on stderr — send -v.
        let parseSendProgress =
            step.role == .transfer && plan.transport == .zfsSendReceiveForwarded

        // A cancelled task stops the command's process group at once;
        // the drains end, the exit is awaited, and only then does the
        // cancellation surface — the process is gone before it does.
        let result = await withTaskCancellationHandler {
            async let stderrTail: Data = {
                var tail = Data()
                var sendProgress = ZfsSendProgress()
                for await chunk in running.stderr {
                    emit(.outputChunk(stepIndex: index, channel: .stderr, data: chunk))
                    if parseSendProgress {
                        for report in sendProgress.consume(chunk) {
                            emit(.progress(report))
                        }
                    }
                    tail.append(chunk)
                    if tail.count > 4096 {
                        tail = tail.suffix(4096)
                    }
                }
                return tail
            }()

            var progress = RsyncProgress()
            for await chunk in running.stdout {
                emit(.outputChunk(stepIndex: index, channel: .stdout, data: chunk))
                if parseProgress {
                    for report in progress.consume(chunk) {
                        emit(.progress(report))
                    }
                }
            }

            let tail = await stderrTail
            let status = await running.exitStatus()
            return StepResult(
                exitStatus: status,
                stderrTail: String(bytes: tail, encoding: .utf8) ?? "")
        } onCancel: {
            running.terminate()
        }
        try Task.checkCancellation()
        return result
    }

    // MARK: - Verification

    /// Reads the bound destination dataset's existence through the Conduit.
    private func verify(
        _ plan: Plan,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> VerificationReport {
        guard let destination = plan.destination else {
            throw EnactmentError.malformedPlan("gated steps but no destination to verify against")
        }
        guard let received = plan.receivedDataset else {
            throw EnactmentError.malformedPlan("a ZFS gate has no received dataset")
        }
        let command = "zfs list -H -o name \(ShellQuote.quote(received))"
        emit(.verifying(host: destination.host, command: command))
        let result = try await conduit.run(on: destination.host, command).collect()
        return .datasetReceived(name: received, exists: result.exitStatus == 0)
    }
}
