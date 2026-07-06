// The operations log — append-only plain text file at
// ~/Library/Application Support/palana/operations.log.
// A full disk or permission error must never break a transfer;
// every write failure is silently ignored. Companion to
// SessionStore: same application-support directory, same
// discipline — one file, append-only, human-readable.

import Foundation
import PalanaCore

/// Append-only log for enacted runs.
///
/// One instance lives in OperationModel for the session's lifetime.
/// Gathering-phase notes are not logged — only enacted runs write here.
/// The log URL is injectable so callers can point at a temp path.
///
/// `headerLine(for:)` is a pure static function so its format is
/// verifiable without a live file handle; since the app target carries
/// no test target, verification is build + lint + hands.
@MainActor
final class OperationLog {
    /// Where the log file lives.
    let url: URL

    private var fileHandle: FileHandle?

    /// The default path — beside the session file in Application Support.
    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("palana", isDirectory: true)
            .appendingPathComponent("operations.log")
    }

    /// Builds a log pointing at `url`, lazily creating the file on first write.
    init(url: URL = OperationLog.defaultURL()) {
        self.url = url
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
        guard let handle = openedHandle() else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func openedHandle() -> FileHandle? {
        if let fileHandle { return fileHandle }
        let dir = url.deletingLastPathComponent()
        // Directory and file creation failures are ignored — a full disk or
        // permission issue must never surface to the operator.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        return fileHandle
    }
}
