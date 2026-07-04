// The Transports — enactment, first half (ho-06.1). Executes an
// approved Plan exactly as composed: no improvisation between approval
// and execution. Host steps run through the Conduit; proxied pipelines
// run in-process through an injected runner. Gates open only when the
// counts say the copy landed.

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
    /// only after a matched verification.
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

    private func run(_ plan: Plan, emit: @Sendable (EnactmentEvent) -> Void) async throws {
        if plan.transport == .zfsSendReceiveForwarded || plan.transport == .zfsSendReceiveProxied {
            throw EnactmentError.unsupportedTransport(plan.transport)
        }
        var gatesReleased = false
        for (index, step) in plan.steps.enumerated() {
            if step.gatedOnVerification, !gatesReleased {
                let report = try await verify(plan, emit: emit)
                emit(.verified(report))
                guard report.matched else {
                    throw EnactmentError.verificationFailed(report)
                }
                gatesReleased = true
            }
            emit(.stepBegan(index: index, step: step))
            let result = try await runStep(step, index: index, plan: plan, emit: emit)
            emit(.stepEnded(index: index, exitStatus: result.exitStatus))
            if result.exitStatus != 0 {
                let doorFailure = ConduitError.classify(
                    exitStatus: result.exitStatus, stderr: result.stderrTail)
                if let doorFailure {
                    throw doorFailure
                }
                throw EnactmentError.stepFailed(
                    index: index, exitStatus: result.exitStatus, stderrTail: result.stderrTail)
            }
        }
        emit(.finished)
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

    private func runHostStep(
        _ step: PlanStep,
        on host: String,
        index: Int,
        plan: Plan,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> StepResult {
        let running = try await conduit.run(on: host, step.command)
        let parseProgress = step.role == .transfer && plan.transport == .rsyncAgentForwarded

        async let stderrTail: Data = {
            var tail = Data()
            for await chunk in running.stderr {
                emit(.outputChunk(stepIndex: index, channel: .stderr, data: chunk))
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
    }

    // MARK: - Verification

    /// Counts entries under the source selection and their transplanted
    /// names at the destination — visibly, through the Conduit.
    private func verify(
        _ plan: Plan,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> VerificationReport {
        guard let destination = plan.destination else {
            throw EnactmentError.malformedPlan("gated steps but no destination to verify against")
        }
        let sourcePaths = plan.entries.map { join(plan.source.directory, $0.name) }
        let destinationPaths = plan.entries.map { join(destination.directory, $0.name) }
        let sourceCount = try await count(paths: sourcePaths, on: plan.source.host, emit: emit)
        let destinationCount = try await count(
            paths: destinationPaths, on: destination.host, emit: emit)
        return VerificationReport(sourceCount: sourceCount, destinationCount: destinationCount)
    }

    private func count(
        paths: [String],
        on host: String,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> Int {
        let quoted = paths.map(ShellQuote.quote).joined(separator: " ")
        let command = "find \(quoted) | wc -l"
        emit(.verifying(host: host, command: command))
        let result = try await conduit.run(on: host, command).collect()
        let text = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitStatus == 0, let value = Int(text) else {
            throw EnactmentError.verificationUnavailable(host: host, detail: result.stderrText)
        }
        return value
    }

    private func join(_ directory: String, _ name: String) -> String {
        var base = directory
        while base.count > 1, base.hasSuffix("/") {
            base.removeLast()
        }
        return base == "/" ? "/\(name)" : "\(base)/\(name)"
    }
}
