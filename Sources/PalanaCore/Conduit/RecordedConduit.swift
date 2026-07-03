// The test seam. RecordedConduit plays back captured transcripts at full
// speed with no network; RecordingConduit wraps a live conduit and writes
// the same format — including real zfs output captured once from a
// throwaway pool. This is the pattern every downstream ho tests against.

import Foundation

/// A recorded exchange set, JSON on disk, human-readable.
public struct ConduitTranscript: Codable, Sendable, Equatable {
    /// One captured exchange: what was asked of which host, what came back.
    public struct Entry: Codable, Sendable, Equatable {
        /// The host the command ran on.
        public var host: String
        /// The exact command line.
        public var command: String
        /// Captured standard output, UTF-8.
        public var stdout: String
        /// Captured standard error, UTF-8.
        public var stderr: String
        /// The exit status, ssh's own 255s included.
        public var exit: Int32

        /// Assembles an entry from its parts.
        public init(host: String, command: String, stdout: String, stderr: String, exit: Int32) {
            self.host = host
            self.command = command
            self.stdout = stdout
            self.stderr = stderr
            self.exit = exit
        }
    }

    /// The exchanges, in capture order.
    public var entries: [Entry]

    /// Wraps a set of entries.
    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Loads a transcript from a JSON file.
    public init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    /// Writes the transcript as pretty-printed, key-sorted JSON.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}

/// A command the transcript does not carry.
///
/// A test-infrastructure failure, deliberately outside ``ConduitError`` —
/// the taxonomy types host failures, not fixture rot.
public struct UnrecordedCommand: Error, Equatable, Sendable {
    /// The host the unmatched command targeted.
    public let host: String
    /// The command no transcript entry matched.
    public let command: String
}

/// Playback.
///
/// Lookup is exact `(host, command)` — a miss names the unmatched command
/// instead of falling through silently.
public struct RecordedConduit: Conduit {
    private let transcript: ConduitTranscript

    /// Plays back the given transcript.
    public init(transcript: ConduitTranscript) {
        self.transcript = transcript
    }

    /// Plays back a transcript loaded from a JSON file.
    public init(contentsOf url: URL) throws {
        self.init(transcript: try ConduitTranscript(contentsOf: url))
    }

    /// Replays the recorded exchange for `(host, command)`, or throws
    /// ``UnrecordedCommand``.
    public func run(on host: String, _ command: String) async throws -> RunningCommand {
        guard
            let entry = transcript.entries.first(where: {
                $0.host == host && $0.command == command
            })
        else {
            throw UnrecordedCommand(host: host, command: command)
        }
        return RunningCommand(
            replayingStdout: Data(entry.stdout.utf8),
            stderr: Data(entry.stderr.utf8),
            exitStatus: entry.exit
        )
    }

    /// No session to close — playback holds nothing open.
    public func close(host: String) async {}

    /// No sessions to close — playback holds nothing open.
    public func closeAll() async {}
}

/// Capture.
///
/// Wraps any conduit, records every exchange, re-emits the result
/// unchanged — door-level failures included, so playback reproduces them
/// for the taxonomy's tests.
public actor RecordingConduit: Conduit {
    private let base: any Conduit
    private var entries: [ConduitTranscript.Entry] = []

    /// Wraps a conduit and starts recording.
    public init(wrapping base: any Conduit) {
        self.base = base
    }

    /// Runs the command on the wrapped conduit, records the exchange, and
    /// re-emits the result as a replay.
    public func run(on host: String, _ command: String) async throws -> RunningCommand {
        let live = try await base.run(on: host, command)
        async let stdoutData = RunningCommand.drain(live.stdout)
        async let stderrData = RunningCommand.drain(live.stderr)
        let status = await live.exitStatus()
        let stdout = await stdoutData
        let stderr = await stderrData
        entries.append(
            ConduitTranscript.Entry(
                host: host,
                command: command,
                stdout: String(bytes: stdout, encoding: .utf8) ?? "",
                stderr: String(bytes: stderr, encoding: .utf8) ?? "",
                exit: status
            ))
        return RunningCommand(replayingStdout: stdout, stderr: stderr, exitStatus: status)
    }

    /// Everything captured so far.
    public func transcript() -> ConduitTranscript {
        ConduitTranscript(entries: entries)
    }

    /// Writes the captured transcript to disk.
    public func write(to url: URL) throws {
        try transcript().write(to: url)
    }

    /// Forwards to the wrapped conduit.
    public func close(host: String) async {
        await base.close(host: host)
    }

    /// Forwards to the wrapped conduit.
    public func closeAll() async {
        await base.closeAll()
    }
}
