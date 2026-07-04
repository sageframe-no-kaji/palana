// The BusyBox listing path — `ls -lane`, the one long listing a
// stat-less, trimmed-find userland can actually produce (ho-07.5,
// zencat's recon). Degradations are named, never hidden: owner and
// group are numeric, the mtime is ls's own clock text with the
// remote's timezone unstated, a symlink name containing " -> " loses
// to its target at the first arrow, and a name that breaks the line
// structure refuses the whole listing loudly — malformed, never a
// silently wrong row.

import Foundation

/// Composes and parses the BusyBox userland listing.
enum BusyBoxListingParser {
    /// The one-round-trip listing command for a BusyBox userland.
    ///
    /// `-l` long, `-a` dotfiles, `-n` numeric ids (no name lookups to
    /// go wrong) — then the date-precision ladder, because BusyBox
    /// flag sets are vendor-build-dependent (zencat's 1.25 has `-e`,
    /// Alpine's 1.37 has `--full-time` instead): full seconds where
    /// the build allows, minute-or-year short dates as the floor, one
    /// round trip either way.
    static func command(for path: String) -> String {
        "cd \(ShellQuote.quote(path)) && "
            + "{ ls -lane 2>/dev/null || ls -lan --full-time 2>/dev/null || ls -lan; }"
    }

    /// Parses `ls -lane` output, sorted by name bytes.
    static func parse(_ stdout: String) throws -> [FileEntry] {
        // One line: mode, links, uid, gid, size, one of the three date
        // shapes the ladder can produce, then the name bytes to end of
        // line. Local because Regex is not Sendable — the compile cost
        // per listing is noise.
        let date =
            #"\w{3}\s+\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4}"#  // -e full date
            + #"|\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+[+-]\d{4}"#  // --full-time
            + #"|\w{3}\s+\d{1,2}\s+(?:\d{1,2}:\d{2}|\d{4})"#  // short floor
        let line = try Regex(
            #"^([a-z-][rwxsStT-]{9}\+?)\s+\d+\s+(\d+)\s+(\d+)\s+(\d+)\s+("#
                + date + #")\s(.*)$"#,
            as: (Substring, Substring, Substring, Substring, Substring, Substring, Substring).self)
        var entries: [FileEntry] = []
        for raw in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            if raw.hasPrefix("total ") { continue }
            guard let match = raw.wholeMatch(of: line) else {
                // A name with a newline, a shape we've never seen —
                // refuse loudly rather than guess at rows.
                throw ListingError.malformedListing
            }
            let mode = String(match.1)
            var nameText = String(match.6)
            if nameText == "." || nameText == ".." { continue }
            let kind = kind(ofMode: mode)
            var target: Data?
            if kind == .symlink, let arrow = nameText.range(of: " -> ") {
                target = Data(nameText[arrow.upperBound...].utf8)
                nameText = String(nameText[..<arrow.lowerBound])
            }
            guard let size = Int64(match.4) else { throw ListingError.malformedListing }
            entries.append(
                FileEntry(
                    nameData: Data(nameText.utf8),
                    kind: kind,
                    size: size,
                    modified: Self.date(from: String(match.5)) ?? Date(timeIntervalSince1970: 0),
                    permissions: String(mode.dropFirst()),
                    owner: String(match.2),
                    group: String(match.3),
                    symlinkTarget: target
                ))
        }
        return entries.sorted { $0.nameData.lexicographicallyPrecedes($1.nameData) }
    }

    private static func kind(ofMode mode: String) -> FileEntry.Kind {
        switch mode.first {
        case "-": .file
        case "d": .directory
        case "l": .symlink
        default: .other
        }
    }

    /// ls's date, whichever rung the ladder reached.
    ///
    /// full-time carries a real timezone; the others read as UTC and
    /// the approximation is named. Short dates without a year read as
    /// the current year, ls's own convention for recent files.
    private static func date(from text: String) -> Date? {
        let squeezed = text.split(separator: " ").joined(separator: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["EEE MMM d HH:mm:ss yyyy", "yyyy-MM-dd HH:mm:ss Z", "MMM d yyyy"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: squeezed) {
                return parsed
            }
        }
        formatter.dateFormat = "yyyy MMM d HH:mm"
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return formatter.date(from: "\(year) \(squeezed)")
    }
}
