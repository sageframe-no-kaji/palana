// The BSD listing path — self-aligned records, targets as a keyed map.
// BSD stat cannot emit NUL from its format string (\0 truncates the
// format, verified on Darwin), so each entry is a stat line the shell
// can't corrupt followed by find's own -print0 name: line, then NUL
// name, self-aligned in one traversal. Symlink targets arrive in a
// second section keyed by name — race-safe by construction. Cost,
// named: one stat fork per entry. BSD means a Mac target in practice,
// and correctness buys the forks.

import Foundation

/// Composes and parses the BSD userland listing.
enum BSDListingParser {
    /// Separates the entry records from the symlink-target section.
    ///
    /// Cannot collide with a name: `-print0` names always carry the
    /// `./` prefix.
    static let linksMarker = "PALANA-LINKS"

    /// The one-round-trip listing command for a BSD userland.
    static func command(for path: String) -> String {
        let quoted = ShellQuote.quote(path)
        let statFormat = "%HT\t%z\t%m\t%Lp\t%Su\t%Sg"
        return "cd \(quoted) && { "
            + "find . -mindepth 1 -maxdepth 1 -exec stat -f '\(statFormat)' {} \\; -print0; "
            + "printf '\(linksMarker)\\0'; "
            + "find . -mindepth 1 -maxdepth 1 -type l -exec sh -c "
            + #"'for f; do printf "%s\0" "$f"; readlink -n -- "$f"; printf "\0"; done' palana {} +;"#
            + " }"
    }

    /// Parses line-then-NUL-name records plus the keyed link section,
    /// sorted by name bytes.
    static func parse(_ data: Data) throws -> [FileEntry] {
        var remainder = data[...]
        var records: [(attributes: [String], nameData: Data)] = []

        let marker = Data(linksMarker.utf8) + [0]
        while !remainder.isEmpty, !remainder.starts(with: marker) {
            guard let newline = remainder.firstIndex(of: UInt8(ascii: "\n")) else {
                throw ListingError.malformedListing
            }
            // swiftlint:disable:next optional_data_string_conversion
            let line = String(decoding: remainder[..<newline], as: UTF8.self)  // ASCII by format
            let attributes = line.components(separatedBy: "\t")
            remainder = remainder[remainder.index(after: newline)...]
            guard let nul = remainder.firstIndex(of: 0) else {
                throw ListingError.malformedListing
            }
            records.append((attributes, stripDotSlash(remainder[..<nul])))
            remainder = remainder[remainder.index(after: nul)...]
        }

        var targets: [Data: Data] = [:]
        if remainder.starts(with: marker) {
            remainder = remainder.dropFirst(marker.count)
            while !remainder.isEmpty {
                guard let nameEnd = remainder.firstIndex(of: 0) else {
                    throw ListingError.malformedListing
                }
                let name = stripDotSlash(remainder[..<nameEnd])
                let afterName = remainder.index(after: nameEnd)
                guard let targetEnd = remainder[afterName...].firstIndex(of: 0) else {
                    throw ListingError.malformedListing
                }
                targets[name] = Data(remainder[afterName..<targetEnd])
                remainder = remainder[remainder.index(after: targetEnd)...]
            }
        }

        let entries = try records.map {
            try entry(attributes: $0.attributes, nameData: $0.nameData, targets: targets)
        }
        return entries.sorted { $0.nameData.lexicographicallyPrecedes($1.nameData) }
    }

    private static func entry(
        attributes: [String],
        nameData: Data,
        targets: [Data: Data]
    ) throws -> FileEntry {
        guard
            attributes.count == 6,
            let size = Int64(attributes[1]),
            let epoch = Double(attributes[2])
        else {
            throw ListingError.malformedListing
        }
        let kind = kind(ofStatType: attributes[0])
        return FileEntry(
            nameData: nameData,
            kind: kind,
            size: size,
            modified: Date(timeIntervalSince1970: epoch),
            permissions: attributes[3],
            owner: attributes[4],
            group: attributes[5],
            symlinkTarget: kind == .symlink ? targets[nameData] : nil
        )
    }

    /// stat's %HT type words.
    private static func kind(ofStatType type: String) -> FileEntry.Kind {
        switch type {
        case "Regular File": .file
        case "Directory": .directory
        case "Symbolic Link": .symlink
        default: .other
        }
    }

    /// Names from `-print0` carry the traversal prefix — exactly `./`.
    private static func stripDotSlash(_ bytes: Data.SubSequence) -> Data {
        let name = Data(bytes)
        guard name.count > 2, name[name.startIndex] == UInt8(ascii: "."),
            name[name.index(after: name.startIndex)] == UInt8(ascii: "/")
        else { return name }
        return Data(name.dropFirst(2))
    }
}
