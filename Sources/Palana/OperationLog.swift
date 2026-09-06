// The operations log — append-only plain text file at
// ~/Library/Application Support/palana/operations.log.
// A full disk or permission error must never break a transfer — and it
// must never vanish either. Every failure to record is retained and
// surfaced beside the run while the run's own outcome stands untouched.
// Companion to SessionStore: same application-support directory, same
// discipline — one file, append-only, human-readable.

import Foundation
import Observation
import PalanaCore

/// The slice of `FileHandle` the log writes through.
///
/// Injectable so a test can fail any single step — open, seek, write,
/// flush, close — without a disk that is actually full and without
/// touching the operator's application-support directory.
protocol OperationLogSink: AnyObject {
    /// Moves the write position to the end of the file.
    func seekToEnd() throws -> UInt64
    /// Appends bytes at the write position.
    func write(contentsOf data: Data) throws
    /// Pushes buffered bytes to disk.
    func synchronize() throws
    /// Releases the descriptor.
    func close() throws
}

extension FileHandle: OperationLogSink {}

/// Append-only log for enacted runs, with observable health.
///
/// One instance lives in OperationModel for the session's lifetime.
/// Gathering-phase notes are not logged — only enacted runs write here.
/// The log URL is injectable so callers can point at a temp path; the
/// opener is injectable so tests can hand in a failing sink.
///
/// Health is separate from transfer outcome by design: a run that ran
/// and checked out is `.finished` whether or not its record landed. The
/// first failure to record is kept for the session and later ones are
/// counted, so the panel can say, persistently, that the record has a
/// gap and where the file is.
@MainActor
@Observable
final class OperationLog {
    /// Which step of recording failed.
    enum Stage: String, Sendable {
        /// Creating the application-support directory.
        case directory
        /// Creating or opening the file.
        case open
        /// Moving to the end before a write.
        case seek
        /// Appending bytes.
        case write
        /// Pushing bytes to disk at completion.
        case flush
        /// Releasing the handle at teardown.
        case close
    }

    /// One failure to record, retained from the moment it happened.
    struct Failure: Equatable, Sendable {
        /// Where in the write path it failed.
        let stage: Stage
        /// The error's own words.
        let detail: String
    }

    /// How the log opens its file — the real handle by default.
    typealias Opener = (URL) throws -> any OperationLogSink

    /// Where the log file lives.
    let url: URL

    /// The first failure to record this session, kept until the process ends.
    private(set) var failure: Failure?

    /// How many recording steps have failed — the first is kept, all are counted.
    private(set) var failureCount = 0

    private let opener: Opener
    @ObservationIgnored private var sink: (any OperationLogSink)?

    /// True while every write has landed.
    var isHealthy: Bool { failure == nil }

    /// One sentence for the operator, or nil while every write has landed.
    var warning: String? {
        guard let failure else { return nil }
        let tally = failureCount > 1 ? " (\(failureCount) failures)" : ""
        return
            "the run record is incomplete — \(failure.stage.rawValue) failed: \(failure.detail)\(tally) · \(url.path)"
    }

    /// The default path — beside the session file in Application Support.
    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("palana", isDirectory: true)
            .appendingPathComponent("operations.log")
    }

    /// Builds a log pointing at `url`, lazily creating the file on first write.
    init(url: URL = OperationLog.defaultURL(), opener: @escaping Opener = { try FileHandle(forWritingTo: $0) }) {
        self.url = url
        self.opener = opener
    }

    isolated deinit {
        // Best effort — a failure here has no one left to tell.
        try? sink?.close()
    }

    // MARK: - Write

    /// Appends one line to the log (trailing newline added).
    func appendLine(_ text: String) {
        writeData((text + "\n").data(using: .utf8))
    }

    /// Appends text as-is — for raw output chunks that carry their own newlines.
    func appendRaw(_ text: String) {
        writeData(text.data(using: .utf8))
    }

    /// Pushes buffered bytes to disk — the completion of a run calls this.
    func flush() {
        guard let sink else { return }
        do {
            try sink.synchronize()
        } catch {
            record(.flush, error)
        }
    }

    /// Releases the handle — teardown calls this.
    ///
    /// A later write reopens, so closing early costs nothing but a descriptor.
    func close() {
        guard let sink else { return }
        self.sink = nil
        do {
            try sink.close()
        } catch {
            record(.close, error)
        }
    }

    // MARK: - Formatting

    /// The session header line for a plan.
    ///
    /// Format: `── <ISO8601 timestamp> · <verb> · <source host:dir> [→ <destination host:dir>]`
    ///
    /// Static so the format is testable without a live file handle.
    static func headerLine(for plan: Plan) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date())
        let source = "\(plan.source.host):\(plan.source.directory)"
        let route: String
        if let dest = plan.destination {
            route = "\(source) → \(dest.host):\(dest.directory)"
        } else {
            route = source
        }
        return "── \(timestamp) · \(plan.operation.rawValue) · \(route)"
    }

    // MARK: - Private

    private func writeData(_ data: Data?) {
        guard let data, !data.isEmpty else { return }
        guard let sink = openedSink() else { return }
        do {
            _ = try sink.seekToEnd()
        } catch {
            // Without the end, an append could land mid-file — say so, write nothing.
            record(.seek, error)
            return
        }
        do {
            try sink.write(contentsOf: data)
        } catch {
            record(.write, error)
        }
    }

    private func openedSink() -> (any OperationLogSink)? {
        if let sink { return sink }
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            record(.directory, error)
            return nil
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                record(.open, "the file could not be created")
                return nil
            }
        }
        do {
            sink = try opener(url)
        } catch {
            record(.open, error)
        }
        return sink
    }

    private func record(_ stage: Stage, _ error: any Error) {
        record(stage, error.localizedDescription)
    }

    private func record(_ stage: Stage, _ detail: String) {
        failureCount += 1
        // The first failure is the one that explains the gap; keep it.
        if failure == nil {
            failure = Failure(stage: stage, detail: detail)
        }
    }
}
