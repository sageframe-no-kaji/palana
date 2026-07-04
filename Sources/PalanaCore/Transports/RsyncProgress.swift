// The progress2 parser. rsync --info=progress2 emits whole-transfer
// updates as carriage-return-refreshed lines on stdout — bytes, percent,
// rate. The parser is stateful over arbitrary chunk boundaries: a line
// split mid-number across two chunks parses once, whole, when its
// terminator arrives.

import Foundation

/// Parses rsync `--info=progress2` output into progress reports.
struct RsyncProgress: Sendable {
    private var buffer = Data()

    /// A fresh parser — one per transfer step.
    init() {}

    /// Consumes a stdout chunk and returns any completed observations.
    mutating func consume(_ chunk: Data) -> [ProgressReport] {
        buffer.append(chunk)
        var reports: [ProgressReport] = []
        // Lines terminate at \r (refresh) or \n (final). The tail stays
        // buffered until its terminator arrives.
        while let terminator = buffer.firstIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
            let line = buffer[..<terminator]
            buffer = Data(buffer[buffer.index(after: terminator)...])
            if let report = Self.parse(line: String(bytes: line, encoding: .utf8) ?? "") {
                reports.append(report)
            }
        }
        return reports
    }

    /// One progress2 line: `  1,234,567  45%    1.23MB/s    0:00:07 …`.
    ///
    /// Bytes and percent are the stable fields; everything after is
    /// carried raw. Non-progress lines return nil and stay out of the
    /// reports — they still reach the echo as ordinary output.
    static func parse(line: String) -> ProgressReport? {
        let pattern = /^\s*([\d,]+)\s+(\d+)%/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let digits = match.1.replacing(",", with: "")
        guard let bytes = Int64(digits), let percent = Int(match.2) else { return nil }
        return ProgressReport(
            bytesTransferred: bytes,
            fraction: Double(percent) / 100.0,
            rawLine: line.trimmingCharacters(in: .whitespaces))
    }
}
