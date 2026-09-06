// The in-process proxy pipeline. Two ssh halves — same configuration,
// same ControlMaster options the Conduit uses — with pālana's own byte
// counter between them. The Plan's command string is the paste-able
// shell equivalent; this is the same semantics with a counter the shell
// version doesn't have. Backpressure is the pipe's own: a full write
// blocks the reader's queue, which stops the read, which is the point.
//
// Both halves are owned: a consumer that fails to launch takes the
// producer down with it, a cancelled task stops both and waits for
// them, and every exit path closes the pump's handles.

import Foundation

/// Spawns and joins a proxied pipeline's two halves.
enum SSHPipeline {
    /// Spawns one half.
    ///
    /// Injectable so a test can refuse one half deterministically. The
    /// arguments are host, command, configuration, and whether stdin is
    /// the pump's pipe.
    typealias HalfSpawner = @Sendable (String, String, SSHConfiguration, Bool) throws -> Half

    /// Runs the pipeline's two halves joined by the counting pump.
    ///
    /// `ssh fromHost fromCommand | ssh toHost toCommand`, bytes counted
    /// in the middle, echo and progress emitted. Returns the failing
    /// half's status, or zero. Throws `CancellationError` when the task
    /// is cancelled — after both halves have exited.
    static func run(
        _ pipeline: Pipeline,
        configuration: SSHConfiguration,
        stepIndex: Int,
        emit: @Sendable (EnactmentEvent) -> Void,
        spawn: HalfSpawner = { host, command, configuration, pipedInput in
            try spawnHalf(
                host: host, command: command, configuration: configuration, pipedInput: pipedInput)
        }
    ) async throws -> Int32 {
        // Both destinations are checked before either half exists: a
        // hostile consumer alias must not cost a producer launch.
        try SSHConduit.validateDestination(pipeline.fromHost)
        try SSHConduit.validateDestination(pipeline.toHost)
        let producer = try spawn(pipeline.fromHost, pipeline.fromCommand, configuration, false)
        let consumer: Half
        do {
            consumer = try spawn(pipeline.toHost, pipeline.toCommand, configuration, true)
        } catch {
            // No consumer, no pipeline: the producer stops before the
            // failure is reported, its handles closed behind it.
            producer.process.terminate(killAfter: RunningCommand.defaultKillGrace)
            _ = await producer.process.exit()
            OwnedProcess.closeQuietly(producer.stdoutRead)
            throw error
        }

        let statuses = await withTaskCancellationHandler {
            await join(producer, consumer, stepIndex: stepIndex, emit: emit)
        } onCancel: {
            producer.process.terminate(killAfter: RunningCommand.defaultKillGrace)
            consumer.process.terminate(killAfter: RunningCommand.defaultKillGrace)
        }
        try Task.checkCancellation()
        return statuses.producer != 0 ? statuses.producer : statuses.consumer
    }

    /// Pumps producer to consumer, echoes both stderrs, awaits both exits.
    private static func join(
        _ producer: Half,
        _ consumer: Half,
        stepIndex: Int,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async -> (producer: Int32, consumer: Int32) {
        // The counting pump: producer stdout → count → consumer stdin.
        // readabilityHandler runs on its own queue; a blocking write to
        // a full pipe pauses further reads — natural backpressure, and
        // no second blocking reader to starve (the ho-01 lesson).
        let pumped = AsyncStream<Int64> { continuation in
            let producerOut = producer.stdoutRead
            guard let consumerIn = consumer.stdinWrite else {
                continuation.finish()
                return
            }
            // A consumer that has died turns the next write into an
            // error rather than a SIGPIPE at the app.
            _ = fcntl(consumerIn.fileDescriptor, F_SETNOSIGPIPE, 1)
            nonisolated(unsafe) var total: Int64 = 0
            producerOut.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                do {
                    try consumerIn.write(contentsOf: chunk)
                } catch {
                    // The consumer let go. Stop pumping and stop the
                    // producer — a transfer with no receiver is over,
                    // and a producer must not be drained to nowhere.
                    handle.readabilityHandler = nil
                    producer.process.terminate(killAfter: RunningCommand.defaultKillGrace)
                    continuation.finish()
                    return
                }
                total += Int64(chunk.count)
                continuation.yield(total)
            }
            continuation.onTermination = { _ in
                OwnedProcess.closeQuietly(producerOut)
                OwnedProcess.closeQuietly(consumerIn)
            }
        }

        async let producerStderr: Void = pump(
            producer.stderrStream, stepIndex: stepIndex, emit: emit)
        async let consumerStderr: Void = pump(
            consumer.stderrStream, stepIndex: stepIndex, emit: emit)

        for await total in pumped {
            emit(.progress(ProgressReport(bytesTransferred: total)))
        }
        _ = await (producerStderr, consumerStderr)

        let producerStatus = await producer.process.exit()
        let consumerStatus = await consumer.process.exit()
        return (producerStatus, consumerStatus)
    }

    private static func pump(
        _ stream: AsyncStream<Data>,
        stepIndex: Int,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async {
        for await chunk in stream {
            emit(.outputChunk(stepIndex: stepIndex, channel: .stderr, data: chunk))
        }
    }

    // MARK: - Halves

    /// One spawned half: its process, the pump's ends, its stderr.
    struct Half: @unchecked Sendable {
        /// The owned process — the half's group, exit, and signals.
        var process: OwnedProcess
        /// The read end of the half's stdout.
        var stdoutRead: FileHandle
        /// The write end of the half's stdin; nil when stdin is /dev/null.
        var stdinWrite: FileHandle?
        /// The half's stderr, chunked; closes its own handle when done.
        var stderrStream: AsyncStream<Data>
    }

    /// One ssh half, multiplexed exactly as the Conduit's sessions are.
    ///
    /// The host and the command are separate argv elements — the alias
    /// is never re-read as shell syntax on the way to the process — and
    /// the door's own grammar check refuses anything but a plain alias
    /// before the half spawns. The control directory is checked as the
    /// Conduit checks it: a directory another user owns or can reach
    /// closes this route too.
    static func spawnHalf(
        host: String,
        command: String,
        configuration: SSHConfiguration,
        pipedInput: Bool = false
    ) throws -> Half {
        let arguments = try SSHConduit.arguments(
            host: host, command: command, configuration: configuration)
        try SSHConduit.ensureControlDirectory(configuration.controlDirectory)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = pipedInput ? Pipe() : nil
        let process = try OwnedProcess.spawn(
            executable: configuration.sshExecutablePath,
            arguments: arguments,
            stdin: stdinPipe,
            stdout: stdoutPipe,
            stderr: stderrPipe)
        return Half(
            process: process,
            stdoutRead: stdoutPipe.fileHandleForReading,
            stdinWrite: stdinPipe?.fileHandleForWriting,
            stderrStream: SSHConduit.stream(from: stderrPipe.fileHandleForReading))
    }
}
