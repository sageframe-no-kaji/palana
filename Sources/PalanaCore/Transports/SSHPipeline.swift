// The in-process proxy pipeline. Two ssh halves — same configuration,
// same ControlMaster options the Conduit uses — with pālana's own byte
// counter between them. The Plan's command string is the paste-able
// shell equivalent; this is the same semantics with a counter the shell
// version doesn't have. Backpressure is the pipe's own: a full write
// blocks the reader's queue, which stops the read, which is the point.

import Foundation

/// Spawns and joins a proxied pipeline's two halves.
enum SSHPipeline {
    /// Runs the pipeline's two halves joined by the counting pump.
    ///
    /// `ssh fromHost fromCommand | ssh toHost toCommand`, bytes counted
    /// in the middle, echo and progress emitted. Returns the failing
    /// half's status, or zero.
    static func run(
        _ pipeline: Pipeline,
        configuration: SSHConfiguration,
        stepIndex: Int,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async throws -> Int32 {
        let producer = try spawnHalf(
            host: pipeline.fromHost,
            command: pipeline.fromCommand,
            configuration: configuration)
        let consumer = try spawnHalf(
            host: pipeline.toHost,
            command: pipeline.toCommand,
            configuration: configuration,
            pipedInput: true)

        // The counting pump: producer stdout → count → consumer stdin.
        // readabilityHandler runs on its own queue; a blocking write to
        // a full pipe pauses further reads — natural backpressure, and
        // no second blocking reader to starve (the ho-01 lesson).
        let pumped = AsyncStream<Int64> { continuation in
            let producerOut = producer.stdoutPipe.fileHandleForReading
            let consumerIn = consumer.stdinPipe.fileHandleForWriting
            nonisolated(unsafe) var total: Int64 = 0
            producerOut.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    try? consumerIn.close()
                    continuation.finish()
                } else {
                    total += Int64(chunk.count)
                    try? consumerIn.write(contentsOf: chunk)
                    continuation.yield(total)
                }
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

        let producerStatus = await producer.exit()
        let consumerStatus = await consumer.exit()
        return producerStatus != 0 ? producerStatus : consumerStatus
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

    struct Half {
        var stdoutPipe: Pipe
        var stdinPipe: Pipe
        var stderrStream: AsyncStream<Data>
        var exit: @Sendable () async -> Int32
    }

    /// One ssh half, multiplexed exactly as the Conduit's sessions are.
    private static func spawnHalf(
        host: String,
        command: String,
        configuration: SSHConfiguration,
        pipedInput: Bool = false
    ) throws -> Half {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.sshExecutablePath)
        process.arguments = SSHConduit.arguments(
            host: host, command: command, configuration: configuration)

        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = pipedInput ? stdinPipe : FileHandle.nullDevice

        let (exitStream, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw ConduitError.launchFailed(error.localizedDescription)
        }

        let stderrStream = AsyncStream<Data> { continuation in
            let handle = stderrPipe.fileHandleForReading
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }

        return Half(
            stdoutPipe: stdoutPipe,
            stdinPipe: stdinPipe,
            stderrStream: stderrStream
        ) {
            var status: Int32 = -1
            for await code in exitStream {
                status = code
            }
            return status
        }
    }
}
