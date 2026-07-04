// Recursive size facts — the whole contents, not the next level down
// (ho-06.5, on the practitioner's word). One round trip sums apparent
// bytes under each selected directory: find walks, awk sums remotely,
// and a completeness flag rides with every number because a silent
// undercount is a lie. Same flavor split, same boundary discipline as
// the listing.

import Foundation

/// The true byte total under one directory, with its honesty flag.
public struct RecursiveSize: Codable, Sendable, Equatable {
    /// Apparent bytes — the sum of file sizes under the path.
    public var bytes: Int64
    /// False when some subtree refused the walk — the number is a
    /// floor, not the truth, and the plan must say so.
    public var complete: Bool

    /// A size fact.
    public init(bytes: Int64, complete: Bool) {
        self.bytes = bytes
        self.complete = complete
    }
}

/// Composes and parses the tree-size command.
public enum TreeSize {
    /// One `<bytes> <errorFlag>` line per path, in input order.
    ///
    /// find's stderr merges into the pipe: awk sums the numeric lines
    /// and flags anything else, so a refused subtree can never
    /// disappear into a clean-looking number. Apparent bytes, symlinks
    /// not followed — the promise matches what a transport moves.
    public static func command(for paths: [String], flavor: UserlandFlavor) -> String {
        paths.map { path in
            let quoted = ShellQuote.quote(path)
            let sizes =
                switch flavor {
                case .gnu: #"find \#(quoted) -type f -printf '%s\n' 2>&1"#
                case .bsd: #"find \#(quoted) -type f -exec stat -f %z {} + 2>&1"#
                }
            return "{ \(sizes); } | " + #"awk '/^[0-9]+$/{s+=$1} !/^[0-9]+$/{e=1} "#
                + #"END{printf "%.0f %d\n", s+0, e+0}'"#
        }
        .joined(separator: "; ")
    }

    /// Parses one size fact per requested path.
    public static func parse(_ stdout: String, expecting count: Int) throws -> [RecursiveSize] {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count == count else { throw ListingError.malformedListing }
        return try lines.map { line in
            let fields = line.split(separator: " ")
            guard fields.count == 2, let bytes = Int64(fields[0]), let flag = Int(fields[1])
            else { throw ListingError.malformedListing }
            return RecursiveSize(bytes: bytes, complete: flag == 0)
        }
    }
}
