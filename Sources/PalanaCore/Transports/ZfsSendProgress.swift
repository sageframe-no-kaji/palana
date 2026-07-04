// The zfs send -v parser. Send writes a header naming the estimated
// size, then per-second lines — time, bytes so far, snapshot — all on
// stderr. Fraction computes against the estimate, capped at one:
// estimates are estimates, and a bar past 100 is a bar that lies.

import Foundation

/// Parses `zfs send -v` stderr into progress reports.
struct ZfsSendProgress: Sendable {
    private var buffer = Data()
    private var estimatedBytes: Int64?

    /// A fresh parser — one per transfer step.
    init() {}

    /// Consumes a stderr chunk and returns any completed observations.
    mutating func consume(_ chunk: Data) -> [ProgressReport] {
        buffer.append(chunk)
        var reports: [ProgressReport] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(bytes: buffer[..<newline], encoding: .utf8) ?? ""
            buffer = Data(buffer[buffer.index(after: newline)...])
            if let estimate = Self.estimate(in: line) {
                estimatedBytes = estimate
            } else if let bytes = Self.perSecondBytes(in: line) {
                let fraction = estimatedBytes.map {
                    $0 > 0 ? min(Double(bytes) / Double($0), 1.0) : 1.0
                }
                reports.append(
                    ProgressReport(
                        bytesTransferred: bytes,
                        fraction: fraction,
                        rawLine: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return reports
    }

    /// `full send of tank@snap estimated size is 611M` — the header.
    static func estimate(in line: String) -> Int64? {
        let pattern = /estimated size is ([\d.]+)([KMGTP]?)/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        return humanBytes(String(match.1), unit: String(match.2))
    }

    /// `17:02:03   1.23M   tank@snap` — the cadence line.
    static func perSecondBytes(in line: String) -> Int64? {
        let pattern = /^\s*\d{2}:\d{2}:\d{2}\s+([\d.]+)([KMGTP]?)\s/
        guard let match = line.firstMatch(of: pattern) else { return nil }
        return humanBytes(String(match.1), unit: String(match.2))
    }

    /// zfs's human sizes, back to bytes — close enough for a bar.
    private static func humanBytes(_ value: String, unit: String) -> Int64? {
        guard let number = Double(value) else { return nil }
        let multiplier: Double =
            switch unit {
            case "K": 1024
            case "M": 1024 * 1024
            case "G": 1024 * 1024 * 1024
            case "T": pow(1024, 4)
            case "P": pow(1024, 5)
            default: 1
            }
        return Int64(number * multiplier)
    }
}
