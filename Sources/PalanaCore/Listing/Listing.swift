// The Listing — remote directory reading, one command per read. The
// flavor fact from ho-03's probe selects the command path; the caller
// passes it in, because the Listing holds no Field and discovers
// nothing. Same taxonomy discipline as the Conduit, one layer up: the
// Conduit types door failures, the Listing types read failures.

import CryptoKit
import Foundation

/// Read failures, classified from the listing command's stderr.
///
/// A door-level failure is not one of these — ``ConduitError`` throws
/// through untouched.
public enum ListingError: Error, Equatable, Sendable {
    /// The directory does not exist.
    case directoryNotFound(path: String)
    /// The directory exists and refused us.
    case permissionDenied(path: String)
    /// The path names something that is not a directory.
    case notADirectory(path: String)
    /// The command failed some other way — typed, never swallowed.
    case listingFailed(exitStatus: Int32, stderr: String)
    /// The command succeeded but its output did not parse. A fixture or
    /// userland surprise, worth surfacing loudly.
    case malformedListing
    /// The file's bytes passed the read's ceiling while streaming. The
    /// command was terminated at the first byte past the limit; nothing
    /// past the limit was retained or written.
    case exceedsLimit(path: String, limit: Int)
    /// The read did not finish inside its timeout. The command was
    /// terminated; whatever arrived is discarded.
    case timedOut(path: String)

    /// Classifies a nonzero listing exit from its stderr.
    static func classify(path: String, exitStatus: Int32, stderr: String) -> Self {
        let text = stderr.lowercased()
        if text.contains("no such file or directory") {
            return .directoryNotFound(path: path)
        }
        if text.contains("permission denied") {
            return .permissionDenied(path: path)
        }
        if text.contains("not a directory") {
            return .notADirectory(path: path)
        }
        return .listingFailed(exitStatus: exitStatus, stderr: stderr)
    }
}

/// Remote directory reading over the Conduit.
public struct Listing: Sendable {
    private let conduit: any Conduit

    /// A listing over the given door.
    public init(conduit: any Conduit) {
        self.conduit = conduit
    }

    /// The exact command a listing runs for a path on a flavor —
    /// exposed so tests and transcripts pin it.
    public static func command(for path: String, flavor: UserlandFlavor) -> String {
        switch flavor {
        case .gnu: GNUListingParser.command(for: path)
        case .bsd: BSDListingParser.command(for: path)
        case .busybox: BusyBoxListingParser.command(for: path)
        }
    }

    /// Reads one directory in one round trip.
    ///
    /// Entries return sorted by name bytes — a deterministic contract;
    /// display order is ``PaneState``'s business. The flavor comes from
    /// the Field's capability fact, passed by the caller.
    public func list(
        on host: String,
        path: String,
        flavor: UserlandFlavor
    ) async throws -> [FileEntry] {
        let result = try await conduit.run(on: host, Self.command(for: path, flavor: flavor))
            .collect()
        guard result.exitStatus == 0 else {
            throw ListingError.classify(
                path: path, exitStatus: result.exitStatus, stderr: result.stderrText)
        }
        return switch flavor {
        case .gnu: try GNUListingParser.parse(result.stdout)
        case .bsd: try BSDListingParser.parse(result.stdout)
        case .busybox: try BusyBoxListingParser.parse(result.stdoutText)
        }
    }

    /// The exact command an existence probe runs — exposed so tests pin it.
    ///
    /// POSIX `test` on the quoted path, answering one of three words. It
    /// runs the same on every flavor pālana reads, and the path rides
    /// inside ``ShellQuote`` armor: nothing in it is ever evaluated.
    public static func presenceCommand(for path: String) -> String {
        let quoted = ShellQuote.quote(path)
        return "if test -d \(quoted); then echo directory; elif test -e \(quoted); then echo file; else echo absent; fi"
    }

    /// Reads the probe command's answer; nil for anything but its three words.
    static func presenceAnswer(_ stdout: String) -> PathPresence? {
        switch stdout.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "directory": .directory
        case "file": .file
        case "absent": .absent
        default: nil
        }
    }

    /// Asks one host whether one path exists, and whether it is a directory.
    ///
    /// One round trip on that host. A door failure throws through
    /// untouched; a command that ran but did not answer in its three words
    /// throws ``ListingError/malformedListing``, and a nonzero exit
    /// ``ListingError/listingFailed(exitStatus:stderr:)`` — the address
    /// recovery reports either as the lookup failing, never as absence.
    public func presence(on host: String, path: String) async throws -> PathPresence {
        let result = try await conduit.run(on: host, Self.presenceCommand(for: path)).collect()
        guard result.exitStatus == 0 else {
            throw ListingError.listingFailed(exitStatus: result.exitStatus, stderr: result.stderrText)
        }
        guard let presence = Self.presenceAnswer(result.stdoutText) else { throw ListingError.malformedListing }
        return presence
    }

    /// The exact command a file read runs — exposed so tests pin it.
    public static func readFileCommand(for path: String) -> String {
        "cat \(ShellQuote.quote(path))"
    }

    /// The ceiling a whole-file read carries unless the caller names one —
    /// the Surface's open limit, 50 MB.
    public static let defaultReadCeiling = 50_000_000

    /// How long a file read may run before its command is terminated.
    public static let defaultReadTimeout = Duration.seconds(120)

    /// How much of a read's stderr is kept for the failure report.
    static let stderrRetention = 64 * 1024

    /// Reads one file's bytes, never more than `limit`.
    ///
    /// The bytes accumulate in memory, so this is for reads a caller
    /// needs whole — a digest, a preview head. The open verb streams to
    /// disk through ``fetchFile(on:path:to:limit:timeout:)`` instead.
    /// The ceiling holds while streaming: a file that grew since it was
    /// listed throws ``ListingError/exceedsLimit(path:limit:)`` with the
    /// command terminated, whatever the listing said its size was.
    public func readFile(
        on host: String,
        path: String,
        limit: Int = defaultReadCeiling,
        timeout: Duration = defaultReadTimeout
    ) async throws -> Data {
        let collected = ByteCollector()
        _ = try await stream(
            on: host,
            path: path,
            command: Self.readFileCommand(for: path),
            bounds: ReadBounds(limit: limit, timeout: timeout)
        ) { collected.append($0) }
        return collected.data
    }

    /// Streams one file's bytes to a local file, never more than `limit`.
    ///
    /// The Surface's open verb — the pane fetches into its temp copy and
    /// hands it to the system. Chunks land on disk as they arrive; no
    /// whole-file `Data` exists. On any failure the destination is
    /// removed, so a partial copy is never opened. Composition stays
    /// here because the Surface never composes shell commands.
    public func fetchFile(
        on host: String,
        path: String,
        to destination: URL,
        limit: Int = defaultReadCeiling,
        timeout: Duration = defaultReadTimeout
    ) async throws -> FetchedFile {
        let writer = try BoundedFileWriter(destination: destination)
        do {
            let byteCount = try await stream(
                on: host,
                path: path,
                command: Self.readFileCommand(for: path),
                bounds: ReadBounds(limit: limit, timeout: timeout)
            ) { try writer.write($0) }
            return FetchedFile(byteCount: byteCount, digest: try writer.finish())
        } catch {
            writer.discard()
            throw error
        }
    }

    /// The two ceilings a streamed read runs under.
    struct ReadBounds {
        /// Bytes delivered before the command is terminated.
        var limit: Int
        /// Wall time before the command is terminated.
        var timeout: Duration
    }

    /// Runs a file-producing command and hands its stdout to `sink` in
    /// chunks, enforcing the ceiling as the bytes arrive.
    ///
    /// The chunk that would carry the byte count past the limit is not
    /// delivered; the command is terminated there — limit plus one byte
    /// is as far as the wire gets. A watchdog terminates the command at
    /// the timeout. A cancelled caller terminates it too and sees
    /// `CancellationError` once the process has gone. stderr is retained
    /// to a bound for the failure report.
    ///
    /// A sink that throws — a full disk under a fetch — stops the
    /// command as well; nothing keeps streaming into a failure.
    ///
    /// - Returns: The number of bytes delivered to `sink`.
    func stream(
        on host: String,
        path: String,
        command: String,
        bounds: ReadBounds,
        sink: @Sendable (Data) throws -> Void
    ) async throws -> Int {
        let running = try await conduit.run(on: host, command)
        let limit = bounds.limit
        let watchdog = Task {
            try? await Task.sleep(for: bounds.timeout)
            guard !Task.isCancelled else { return false }
            running.terminate()
            return true
        }
        defer { watchdog.cancel() }
        let drained: Drained
        do {
            drained = try await withTaskCancellationHandler {
                try await Self.drain(running, limit: limit, sink: sink)
            } onCancel: {
                running.terminate()
            }
        } catch {
            await running.cancel()
            throw error
        }
        try Task.checkCancellation()
        watchdog.cancel()
        let timedOut = await watchdog.value
        if drained.oversize {
            throw ListingError.exceedsLimit(path: path, limit: limit)
        }
        guard drained.exitStatus == 0 else {
            if timedOut { throw ListingError.timedOut(path: path) }
            let stderr = String(bytes: drained.stderr, encoding: .utf8) ?? ""
            if let door = ConduitError.classify(exitStatus: drained.exitStatus, stderr: stderr) {
                throw door
            }
            throw ListingError.classify(path: path, exitStatus: drained.exitStatus, stderr: stderr)
        }
        return drained.delivered
    }

    /// What one drained command left behind.
    private struct Drained {
        var delivered = 0
        var oversize = false
        var stderr = Data()
        var exitStatus: Int32 = 0
    }

    /// Both channels interleaved, stdout to the sink under the ceiling.
    ///
    /// stderr is retained to its bound. Runs to the command's exit — after
    /// a terminate, the streams end when the process does.
    private static func drain(
        _ running: RunningCommand,
        limit: Int,
        sink: @Sendable (Data) throws -> Void
    ) async throws -> Drained {
        var drained = Drained()
        for await chunk in running.output() {
            switch chunk.channel {
            case .stdout:
                guard !drained.oversize else { continue }
                if drained.delivered + chunk.data.count > limit {
                    drained.oversize = true
                    running.terminate()
                    continue
                }
                try sink(chunk.data)
                drained.delivered += chunk.data.count
            case .stderr:
                let room = stderrRetention - drained.stderr.count
                if room > 0 { drained.stderr.append(chunk.data.prefix(room)) }
            }
        }
        drained.exitStatus = await running.exitStatus()
        return drained
    }

    /// The exact command a capped head read runs — exposed so tests pin it.
    ///
    /// `head -c` (bytes) is portable across GNU and BSD userlands.
    public static func readFileHeadCommand(for path: String, limit: Int) -> String {
        "head -c \(limit) \(ShellQuote.quote(path))"
    }

    /// Reads at most `limit` bytes off the front of a remote file, one round trip.
    ///
    /// The preview pane's bounded remote read (ho-16 review), so a huge remote
    /// log is never `cat`'d whole across the wire.
    ///
    /// `head -c` bounds the wire; the same limit is enforced here as the
    /// bytes arrive, so a userland whose `head` misbehaves still cannot
    /// hand back more than asked.
    public func readFileHead(on host: String, path: String, limit: Int) async throws -> Data {
        let collected = ByteCollector()
        _ = try await stream(
            on: host,
            path: path,
            command: Self.readFileHeadCommand(for: path, limit: limit),
            bounds: ReadBounds(limit: limit, timeout: Self.defaultReadTimeout)
        ) { collected.append($0) }
        return collected.data
    }

    /// The recursive size fact for each path, one round trip.
    ///
    /// The plan gathers these fresh, per plan — a size promise with a
    /// timestamp is still a lie. Composition and parsing live in
    /// ``TreeSize``.
    public func treeSizes(
        on host: String,
        paths: [String],
        flavor: UserlandFlavor
    ) async throws -> [RecursiveSize] {
        guard !paths.isEmpty else { return [] }
        // BusyBox's find cannot walk by type — no facts, and the plan
        // shows the inode floor with its flag, ho-06.5's honesty.
        guard flavor != .busybox else { return [] }
        let command = TreeSize.command(for: paths, flavor: flavor)
        let result = try await conduit.run(on: host, command).collect()
        guard result.exitStatus == 0 else {
            throw ListingError.listingFailed(
                exitStatus: result.exitStatus, stderr: result.stderrText)
        }
        return try TreeSize.parse(result.stdoutText, expecting: paths.count)
    }
}

/// What a bounded fetch left on disk.
public struct FetchedFile: Sendable, Equatable {
    /// Bytes written to the destination — never more than the ceiling.
    public let byteCount: Int
    /// SHA-256 of those bytes, computed as they streamed — the same value
    /// ``RoundTrip/digest(of:)`` gives for the file read back whole.
    public let digest: Data

    /// Assembles the record.
    public init(byteCount: Int, digest: Data) {
        self.byteCount = byteCount
        self.digest = digest
    }
}

/// Accumulates a bounded read in memory.
///
/// Appends arrive one at a time from a single drain loop, never
/// concurrently — the unchecked conformance states that, nothing more.
private final class ByteCollector: @unchecked Sendable {
    private(set) var data = Data()

    func append(_ chunk: Data) {
        data.append(chunk)
    }
}

/// Writes a bounded read to a file as it arrives, hashing on the way.
///
/// Writes arrive one at a time from a single drain loop, never
/// concurrently — the unchecked conformance states that, nothing more.
private final class BoundedFileWriter: @unchecked Sendable {
    private let destination: URL
    private let handle: FileHandle
    private var hasher = SHA256()

    init(destination: URL) throws {
        self.destination = destination
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        handle = try FileHandle(forWritingTo: destination)
    }

    func write(_ chunk: Data) throws {
        try handle.write(contentsOf: chunk)
        hasher.update(data: chunk)
    }

    /// Closes the file and returns the digest of everything written.
    func finish() throws -> Data {
        try handle.close()
        return Data(hasher.finalize())
    }

    /// Closes and removes the partial file — nothing partial is ever opened.
    func discard() {
        try? handle.close()
        try? FileManager.default.removeItem(at: destination)
    }
}
