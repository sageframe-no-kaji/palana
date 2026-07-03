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
/// Single-consumer: each stream and the exit status are consumed once.
/// ``collect()`` is the one-call path for callers that don't need live
/// streams.
public struct RunningCommand: Sendable {
    /// The remote command's standard output, chunked as it arrives.
    public let stdout: AsyncStream<Data>
    /// The remote command's standard error, chunked as it arrives.
    public let stderr: AsyncStream<Data>
    private let exit: @Sendable () async -> Int32

    /// Wraps live streams and an exit awaiter.
    public init(
        stdout: AsyncStream<Data>,
        stderr: AsyncStream<Data>,
        exitStatus: @escaping @Sendable () async -> Int32
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exit = exitStatus
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
    public func exitStatus() async -> Int32 {
        await exit()
    }

    /// Drains both streams concurrently, awaits exit, applies the taxonomy.
    ///
    /// A remote command exiting nonzero is data, not an error — errors are
    /// the door failing, not the command.
    public func collect() async throws -> CommandResult {
        async let stdoutData = Self.drain(stdout)
        async let stderrData = Self.drain(stderr)
        let status = await exitStatus()
        let result = CommandResult(
            exitStatus: status,
            stdout: await stdoutData,
            stderr: await stderrData
        )
        if let failure = ConduitError.classify(exitStatus: status, stderr: result.stderrText) {
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
