// The GNU listing path — one find -printf, NUL everywhere. NUL is the
// one byte a filename cannot contain, so names and symlink targets
// survive byte for byte by construction. This is the fast path and the
// fleet's path: one process on the remote regardless of entry count.

import Foundation

/// Composes and parses the GNU userland listing.
enum GNUListingParser {
    /// Fields per record — name, type, size, mtime, perms, owner, group,
    /// link target.
    static let fieldCount = 8

    /// The one-round-trip listing command for a GNU userland.
    static func command(for path: String) -> String {
        "cd \(ShellQuote.quote(path)) && find . -mindepth 1 -maxdepth 1 "
            + #"-printf '%f\0%y\0%s\0%T@\0%m\0%u\0%g\0%l\0'"#
    }

    /// Parses NUL-delimited records into entries, sorted by name bytes.
    static func parse(_ data: Data) throws -> [FileEntry] {
        guard !data.isEmpty else { return [] }
        guard data.last == 0 else { throw ListingError.malformedListing }
        let fields = data.dropLast().split(separator: 0, omittingEmptySubsequences: false)
        guard fields.count.isMultiple(of: fieldCount) else {
            throw ListingError.malformedListing
        }
        var entries: [FileEntry] = []
        for start in stride(from: 0, to: fields.count, by: fieldCount) {
            let record = fields[start..<start + fieldCount].map { Data($0) }
            entries.append(try entry(from: record))
        }
        return entries.sorted { $0.nameData.lexicographicallyPrecedes($1.nameData) }
    }

    private static func entry(from record: [Data]) throws -> FileEntry {
        let type = text(record[1])
        guard
            let size = Int64(text(record[2])),
            let epoch = Double(text(record[3]))
        else {
            throw ListingError.malformedListing
        }
        let target = record[7]
        return FileEntry(
            nameData: record[0],
            kind: kind(ofFindType: type),
            size: size,
            modified: Date(timeIntervalSince1970: epoch),
            permissions: text(record[4]),
            owner: text(record[5]),
            group: text(record[6]),
            symlinkTarget: target.isEmpty ? nil : target
        )
    }

    /// find's %y single-character types.
    private static func kind(ofFindType type: String) -> FileEntry.Kind {
        switch type {
        case "f": .file
        case "d": .directory
        case "l": .symlink
        default: .other
        }
    }

    private static func text(_ field: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: field, as: UTF8.self)  // non-name fields are ASCII by format
    }
}
