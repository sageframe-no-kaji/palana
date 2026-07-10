// The BSD listing path — batched stat blocks paired with NUL-framed
// names by count. BSD stat cannot emit NUL from its format string
// (\0 prints literally, verified on Darwin), so the pairing rides
// structure instead: each find batch emits its stat lines, one NUL,
// then the same files' names NUL-terminated in the same order — counts
// must agree or the parse refuses. The first cut ran one stat fork per
// entry ("correctness buys the forks") — the second hands session
// found 600 forks cost 3.5 seconds on a Mac's /tmp, and the batch
// shape buys the same correctness at two forks per thousand entries.

import Foundation

/// Composes and parses the BSD userland listing.
enum BSDListingParser {
    /// Separates the entry records from the symlink-target section.
    ///
    /// Cannot collide with a name: `-print0` names always carry the
    /// `./` prefix.
    static let linksMarker = "PALANA-LINKS"

    /// The one-round-trip listing command for a BSD userland.
    ///
    /// The stat format now carries eight tab-separated fields:
    /// type (`%HT`), size (`%z`), mtime-epoch (`%m`), perms (`%Lp`),
    /// owner (`%Su`), group (`%Sg`), birth-epoch (`%B`), ctime-epoch (`%c`).
    ///
    /// `%B` and `%c` emit raw Unix epoch seconds, matching `%m`'s integer
    /// format exactly. APFS carries real birth times; HFS+ and network
    /// filesystems may echo mtime — the parser records what stat says,
    /// never adjusts.
    static func command(for path: String) -> String {
        let quoted = ShellQuote.quote(path)
        let statFormat = "%HT\t%z\t%m\t%Lp\t%Su\t%Sg\t%B\t%c"
        let batch =
            #"stat -f "\#(statFormat)" -- "$@"; printf "\0"; printf "%s\0" "$@""#
        return "cd \(quoted) && { "
            + "find . -mindepth 1 -maxdepth 1 -exec sh -c '\(batch)' palana {} +; "
            + "printf '\(linksMarker)\\0'; "
            + "find . -mindepth 1 -maxdepth 1 -type l -exec sh -c "
            + #"'for f; do printf "%s\0" "$f"; readlink -n -- "$f"; printf "\0"; done' palana {} +;"#
            + " }"
    }

    /// Parses batch-paired records plus the keyed link section, sorted
    /// by name bytes.
    ///
    /// Per batch: a NUL-terminated block of stat lines, then exactly as
    /// many NUL-terminated names, traversal order both. A count
    /// mismatch is a malformed listing, never a guess.
    static func parse(_ data: Data) throws -> [FileEntry] {
        var remainder = data[...]
        var records: [(attributes: [String], nameData: Data)] = []

        let marker = Data(linksMarker.utf8) + [0]
        while !remainder.isEmpty, !remainder.starts(with: marker) {
            guard let blockEnd = remainder.firstIndex(of: 0) else {
                throw ListingError.malformedListing
            }
            // swiftlint:disable:next optional_data_string_conversion
            let block = String(decoding: remainder[..<blockEnd], as: UTF8.self)  // ASCII by format
            remainder = remainder[remainder.index(after: blockEnd)...]
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                throw ListingError.malformedListing
            }
            for line in lines {
                let attributes = line.components(separatedBy: "\t")
                guard let nul = remainder.firstIndex(of: 0) else {
                    throw ListingError.malformedListing
                }
                let nameBytes = remainder[..<nul]
                // Every paired name carries find's ./ prefix — a
                // segment without it is a desynced batch, refused, so
                // a mismatch can never swallow the marker as a name.
                guard nameBytes.starts(with: [UInt8(ascii: "."), UInt8(ascii: "/")]) else {
                    throw ListingError.malformedListing
                }
                records.append((attributes, stripDotSlash(nameBytes)))
                remainder = remainder[remainder.index(after: nul)...]
            }
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
        // Field layout (0-indexed):
        // 0 type (%HT), 1 size (%z), 2 mtime-epoch (%m),
        // 3 perms (%Lp), 4 owner (%Su), 5 group (%Sg),
        // 6 birth-epoch (%B), 7 ctime-epoch (%c).
        guard
            attributes.count == 8,
            let size = Int64(attributes[1]),
            let mepoch = Double(attributes[2]),
            let birthEpoch = Double(attributes[6]),
            let cepoch = Double(attributes[7])
        else {
            throw ListingError.malformedListing
        }
        let kind = kind(ofStatType: attributes[0])
        return FileEntry(
            nameData: nameData,
            kind: kind,
            size: size,
            modified: Date(timeIntervalSince1970: mepoch),
            created: Date(timeIntervalSince1970: birthEpoch),
            changed: Date(timeIntervalSince1970: cepoch),
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

    /// Names from the batch pairing carry the traversal prefix — `./`.
    private static func stripDotSlash(_ bytes: Data.SubSequence) -> Data {
        let name = Data(bytes)
        guard name.count > 2, name[name.startIndex] == UInt8(ascii: "."),
            name[name.index(after: name.startIndex)] == UInt8(ascii: "/")
        else { return name }
        return Data(name.dropFirst(2))
    }
}
