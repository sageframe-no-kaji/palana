// The Conduit — the single door to the hosts. Every fact discovered, every
// listing read, every byte moved passes through this protocol. No other
// component spawns a process toward a host, ever.

import Foundation

/// SSH execution behind a protocol.
///
/// Tests inject a ``RecordedConduit``; the app injects an ``SSHConduit``.
/// Nothing above the door knows which.
public protocol Conduit: Sendable {
    /// Runs a command on a host. The returned ``RunningCommand`` streams —
    /// the caller drains stdout and stderr and awaits the exit status.
    func run(on host: String, _ command: String) async throws -> RunningCommand

    /// Closes the session to one host, if one is open.
    func close(host: String) async

    /// Closes every open session. The app's quit path owns calling this —
    /// nothing outlives the window.
    func closeAll() async
}

/// A command in flight.
///
/// Single-consumer: each stream and ``output()`` are consumed once.
/// ``collect()`` is the one-call path for callers that don't need live
/// streams. Exit may be awaited by any number of callers.
///
/// The command owns its process group. ``terminate(killAfter:)`` stops
/// it without waiting; ``cancel(killAfter:)`` stops it and awaits the
/// exit; both are idempotent. A task cancelled while draining or
/// collecting terminates the process the same way — cancellation is
/// reported only after the group has gone.
public struct RunningCommand: Sendable {
    /// The grace between SIGTERM and SIGKILL when none is given.
    public static let defaultKillGrace = Duration.seconds(2)

    /// The remote command's standard output, chunked as it arrives.
    public let stdout: AsyncStream<Data>
    /// The remote command's standard error, chunked as it arrives.
    public let stderr: AsyncStream<Data>
    private let exit: @Sendable () async -> Int32
    private let stop: @Sendable (Duration) -> Void

    /// Wraps live streams, an exit awaiter, and the process's stop.
    ///
    /// `terminate` receives the SIGTERM-to-SIGKILL grace; it must be
    /// idempotent and must never signal after exit. The default does
    /// nothing — the shape of a replay, which has no process to stop.
    public init(
        stdout: AsyncStream<Data>,
        stderr: AsyncStream<Data>,
        exitStatus: @escaping @Sendable () async -> Int32,
        terminate: @escaping @Sendable (Duration) -> Void = { _ in }
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exit = exitStatus
        self.stop = terminate
    }

    /// Replay shape — a command whose output already exists as data.
    /// ``RecordedConduit`` playback and ``RecordingConduit`` re-emission.
    public init(replayingStdout stdoutData: Data, stderr stderrData: Data, exitStatus: Int32) {
        self.init(
            stdout: Self.singleYield(stdoutData),
            stderr: Self.singleYield(stderrData)
        ) { exitStatus }
    }

    /// Awaits process exit. ssh reserves 255 for its own failures — the
    /// taxonomy's job, applied in ``collect()`` or by the caller.
    ///
    /// A process ended by a signal reports 128 plus the signal number,
    /// as a shell would.
    public func exitStatus() async -> Int32 {
        await exit()
    }

    /// Stops the process group without waiting.
    ///
    /// SIGTERM now, SIGKILL after `grace` if it is still running.
    /// Idempotent.
    public func terminate(killAfter grace: Duration = defaultKillGrace) {
        stop(grace)
    }

    /// Stops the process group and awaits its exit.
    ///
    /// Idempotent — a command already stopped or exited returns its
    /// status at once.
    @discardableResult
    public func cancel(killAfter grace: Duration = defaultKillGrace) async -> Int32 {
        stop(grace)
        return await exit()
    }

    /// Both channels interleaved as they arrive.
    ///
    /// Neither channel is waited on ahead of the other, so a command
    /// that fills one while holding the other open still drains.
    /// Single-consumer, like the channels it merges.
    ///
    /// A consumer that walks away — cancelled, or broken out of
    /// mid-read — stops the command's process group, not merely the two
    /// pumps feeding this stream. Cancelling the reader while leaving
    /// the child running was the shape a stalled Workbench read took
    /// (2026-09-08 audit): the panel moved on, the process did not.
    /// Normal completion signals nothing: a command whose output has
    /// simply ended is finishing on its own terms.
    public func output() -> AsyncStream<OutputChunk> {
        let stdout = stdout
        let stderr = stderr
        let stop = stop
        return AsyncStream { continuation in
            let pump = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await data in stdout {
                            continuation.yield(OutputChunk(channel: .stdout, data: data))
                        }
                    }
                    group.addTask {
                        for await data in stderr {
                            continuation.yield(OutputChunk(channel: .stderr, data: data))
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { termination in
                pump.cancel()
                guard case .cancelled = termination else { return }
                stop(Self.defaultKillGrace)
            }
        }
    }

    /// Drains both streams concurrently, awaits exit, applies the taxonomy.
    ///
    /// A remote command exiting nonzero is data, not an error — errors are
    /// the door failing, not the command. A cancelled task stops the
    /// process and throws `CancellationError` once it has exited.
    public func collect() async throws -> CommandResult {
        let result = await withTaskCancellationHandler {
            async let stdoutData = Self.drain(stdout)
            async let stderrData = Self.drain(stderr)
            let status = await exitStatus()
            return CommandResult(
                exitStatus: status,
                stdout: await stdoutData,
                stderr: await stderrData
            )
        } onCancel: {
            terminate()
        }
        try Task.checkCancellation()
        if let failure = ConduitError.classify(exitStatus: result.exitStatus, stderr: result.stderrText) {
            throw failure
        }
        return result
    }

    static func drain(_ stream: AsyncStream<Data>) async -> Data {
        var data = Data()
        for await chunk in stream {
            data.append(chunk)
        }
        return data
    }

    private static func singleYield(_ data: Data) -> AsyncStream<Data> {
        AsyncStream { continuation in
            if !data.isEmpty {
                continuation.yield(data)
            }
            continuation.finish()
        }
    }
}

/// One piece of a command's output, labelled with the channel it came from.
public struct OutputChunk: Sendable, Equatable {
    /// Which channel wrote it.
    public let channel: OutputChannel
    /// The bytes, as they arrived.
    public let data: Data

    /// Labels a chunk.
    public init(channel: OutputChannel, data: Data) {
        self.channel = channel
        self.data = data
    }
}

/// What a completed command produced.
///
/// Exit status is data — the taxonomy already ruled out door-level failure
/// by the time one of these exists.
public struct CommandResult: Sendable, Equatable {
    /// The remote command's exit status.
    public let exitStatus: Int32
    /// Everything the command wrote to standard output.
    public let stdout: Data
    /// Everything the command wrote to standard error.
    public let stderr: Data

    /// Assembles a result from its parts.
    public init(exitStatus: Int32, stdout: Data, stderr: Data) {
        self.exitStatus = exitStatus
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Standard output decoded as UTF-8; empty when not decodable.
    public var stdoutText: String { String(bytes: stdout, encoding: .utf8) ?? "" }
    /// Standard error decoded as UTF-8; empty when not decodable.
    public var stderrText: String { String(bytes: stderr, encoding: .utf8) ?? "" }
}
