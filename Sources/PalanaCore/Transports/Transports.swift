// The Transports — enactment, first half (ho-06.1). Executes an
// approved Plan exactly as composed: no improvisation between approval
// and execution. Host steps run through the Conduit; proxied pipelines
// run in-process through an injected runner. Gates open only when the
// destination's manifest carries every entry of the source's — each
// object's kind, size, link target, and SHA-256 — identically.

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
        do {
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
                if step.role == .quarantine { state.quarantined = true }
            }
        } catch {
            // A source already frozen is a source the operator must be
            // able to find, whatever stopped the run — a failed step, a
            // closed gate, a cancellation.
            if state.quarantined, let release = plan.moveRelease {
                emit(
                    .recovery(
                        RecoveryNote(
                            kind: .retained, host: release.host, detail: release.recoverySentence)))
            }
            throw error
        }
        emit(.finished)
    }

    /// What the run has established — never a Boolean.
    private struct EnactmentState {
        /// What the passed gate authorised, and over which evidence.
        var authorization: GateAuthorization?
        /// True once the source has been frozen under the quarantine.
        var quarantined = false
    }

    /// What a passed gate authorises.
    private enum GateAuthorization {
        /// A file move whose frozen source and destination both manifested.
        case release(MoveReleaseAuthorization)
        /// A zfs transfer whose received dataset exists.
        case dataset(String)
    }

    /// Refuses, before a single step runs, a plan whose shape cannot
    /// carry the authority its steps claim.
    ///
    /// A commit step with no version behind it and a gated delete with
    /// no frozen source behind it are the shapes a plan written before
    /// these bindings existed takes. Neither may run: a plan decoded
    /// from an older file stays readable and stays harmless.
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
        guard plan.steps.contains(where: \.gatedOnVerification) else { return }
        guard plan.receivedDataset != nil || plan.moveRelease != nil else {
            throw EnactmentError.malformedPlan(
                "a gated delete with no frozen source behind it — nothing may be deleted")
        }
        if plan.moveRelease != nil, !plan.steps.contains(where: { $0.role == .quarantine }) {
            throw EnactmentError.malformedPlan(
                "a move bound to a frozen source with no step that freezes it")
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
            state.authorization = try Self.authorization(
                from: report, plan: plan, quarantined: state.quarantined)
        }
        guard step.role == .delete, let release = plan.moveRelease else { return }
        guard case .release(let authorized)? = state.authorization, authorized.release == release
        else {
            throw EnactmentError.malformedPlan(
                "the delete is not bound to the source this run froze")
        }
        emit(.released(authorized))
    }

    /// Turns a matched report into the authority a step may claim.
    private static func authorization(
        from report: VerificationReport,
        plan: Plan,
        quarantined: Bool
    ) throws -> GateAuthorization {
        switch report {
        case .datasetReceived(let name, _):
            return .dataset(name)
        case .manifests(let source, let destination):
            guard let release = plan.moveRelease, quarantined else {
                throw EnactmentError.malformedPlan(
                    "manifests taken over a source that was never frozen — nothing may be deleted")
            }
            return .release(
                MoveReleaseAuthorization(
                    release: release, source: source, destination: destination))
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

    /// The gate's evidence, shaped per transport: manifests both ends
    /// for file transfers, dataset existence for zfs — visibly, through
    /// the Conduit.
    ///
    /// Both manifests must exist before either is read against the
    /// other: a source that will not manifest is as closed a gate as a
    /// destination that differs.
    private func verify(
        _ plan: Plan,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> VerificationReport {
        guard let destination = plan.destination else {
            throw EnactmentError.malformedPlan("gated steps but no destination to verify against")
        }
        if let received = plan.receivedDataset {
            let command = "zfs list -H -o name \(ShellQuote.quote(received))"
            emit(.verifying(host: destination.host, command: command))
            let result = try await conduit.run(on: destination.host, command).collect()
            return .datasetReceived(name: received, exists: result.exitStatus == 0)
        }
        // The source manifest is taken over the quarantine, not the
        // pathnames the operator has since been free to refill — a move
        // proves the bytes it froze, and deletes only those.
        let release = plan.moveRelease
        let names = release?.names ?? plan.entries.map(\.name)
        let source = try await manifest(
            directory: release?.quarantineDirectory ?? plan.source.directory,
            names: names,
            on: release?.host ?? plan.source.host,
            emit: emit)
        let landed = try await manifest(
            directory: destination.directory, names: names, on: destination.host, emit: emit)
        return .manifests(source: source, destination: landed)
    }

    /// One end's manifest, or `verificationUnavailable`.
    ///
    /// Unavailable on any nonzero status (a missing name, an unreadable
    /// file, no SHA-256 tool), on bytes that do not parse as a
    /// manifest, and on a manifest that omits a selected name — the
    /// shape a masked `find` failure takes. Each keeps the gate closed.
    private func manifest(
        directory: String,
        names: [String],
        on host: String,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> TransferManifest {
        let command = TransferManifest.command(directory: directory, names: names)
        emit(.verifying(host: host, command: command))
        let result = try await conduit.run(on: host, command).collect()
        guard result.exitStatus == 0 else {
            let tail = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw EnactmentError.verificationUnavailable(
                host: host, detail: "manifest exited \(result.exitStatus): \(tail)")
        }
        let manifest: TransferManifest
        do {
            manifest = try TransferManifest.parse(result.stdout)
        } catch {
            throw EnactmentError.verificationUnavailable(
                host: host, detail: "manifest unreadable: \(error)")
        }
        let missing = manifest.missingNames(from: names)
        guard missing.isEmpty else {
            throw EnactmentError.verificationUnavailable(
                host: host, detail: "manifest omitted \(missing.joined(separator: ", "))")
        }
        return manifest
    }
}
