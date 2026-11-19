// Collision facts the destination filesystem decides (owner ruling
// 2026-11-18, final review F02).
//
// The byte-exact compare is right wherever names are compared as bytes,
// and wrong on storage that resolves `Report.txt` and `report.txt` to one
// entry — case-insensitive APFS, SMB shares, ZFS with casesensitivity
// off: the listing shows no match, and the copy replaces the file without
// a line about it. So for every arriving name the compare did not match,
// the destination itself is asked whether the name already resolves. A
// hit is a collision with the one listing entry that folds to it; a hit
// that names no single listed entry makes the facts unknown, which the
// plan says out loud. Case-sensitive storage answers "absent", so its
// results stay exactly byte-exact.

import Foundation

extension Collision {
    /// The arriving entries the byte-exact compare found no standing entry for.
    public static func unmatched(sources: [FileEntry], destinationListing: [FileEntry]) -> [FileEntry] {
        let standing = Set(destinationListing.map(\.nameData))
        return sources.filter { !standing.contains($0.nameData) }
    }

    /// Collisions for arrivals the destination says already resolve.
    ///
    /// Each hit is matched to the one listed entry whose name folds to
    /// the same text (case and Unicode normalization), and the collision
    /// carries that entry's spelling, kind, size, and date.
    ///
    /// - Parameters:
    ///   - arrivals: The unmatched arriving entries, in probe order.
    ///   - hits: The indexes into `arrivals` the destination resolved.
    ///   - destinationListing: The destination listing the compare used.
    /// - Returns: The collisions, or nil when a hit names no single listed
    ///   entry — the destination holds something the listing cannot show,
    ///   so the facts are unknown.
    public static func resolved(
        arrivals: [FileEntry],
        hits: Set<Int>,
        destinationListing: [FileEntry]
    ) -> [Self]? {
        var collisions: [Self] = []
        for index in hits.sorted() {
            guard arrivals.indices.contains(index) else { return nil }
            let arriving = arrivals[index]
            let key = folded(arriving.name)
            let candidates = destinationListing.filter { folded($0.name) == key }
            guard candidates.count == 1, let standing = candidates.first else { return nil }
            collisions.append(
                Self(
                    nameData: standing.nameData,
                    standingKind: standing.kind,
                    standingSize: standing.size,
                    standingModified: standing.modified,
                    arrivingKind: arriving.kind))
        }
        return collisions
    }

    /// A name as case- and normalization-insensitive storage compares it.
    static func folded(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
    }
}

extension Listing {
    /// How many names one resolution command carries — a bound on the
    /// command line, not on the selection.
    static let resolutionBatch = 200

    /// The command that asks, in the destination directory, which of
    /// `names` already resolve to an entry there.
    ///
    /// Prints the 1-based position of each name that exists (a dangling
    /// symlink counts), one per line. Exit 3 when the directory cannot be
    /// entered.
    public static func resolutionCommand(directory: String, names: [String]) -> String {
        let quoted = names.map(ShellQuote.quote).joined(separator: " ")
        return "cd -- \(ShellQuote.quote(directory)) || exit 3; i=0; for n in \(quoted); do i=$((i+1));"
            + " if [ -e \"$n\" ] || [ -L \"$n\" ]; then echo \"$i\"; fi; done"
    }

    /// Reads the resolution command's answer: 0-based indexes, or nil
    /// for anything but positions within `count`.
    static func resolutionAnswer(_ stdout: String, count: Int) -> Set<Int>? {
        var hits = Set<Int>()
        for line in stdout.split(whereSeparator: \.isNewline) {
            guard let position = Int(line), (1...count).contains(position) else { return nil }
            hits.insert(position - 1)
        }
        return hits
    }

    /// Asks one host which of `names` already resolve in `directory`.
    ///
    /// One round trip per ``resolutionBatch`` names. A door failure throws
    /// through; a nonzero exit throws ``ListingError/listingFailed(exitStatus:stderr:)``
    /// and an unreadable answer ``ListingError/malformedListing`` — the
    /// gather reports either as collisions unknown, never as none.
    ///
    /// - Returns: 0-based indexes into `names`.
    public func resolving(names: [String], in directory: String, on host: String) async throws -> Set<Int> {
        var hits = Set<Int>()
        var start = 0
        while start < names.count {
            let batch = Array(names[start..<min(start + Self.resolutionBatch, names.count)])
            let command = Self.resolutionCommand(directory: directory, names: batch)
            let result = try await conduit.run(on: host, command).collect()
            guard result.exitStatus == 0 else {
                throw ListingError.listingFailed(exitStatus: result.exitStatus, stderr: result.stderrText)
            }
            guard let found = Self.resolutionAnswer(result.stdoutText, count: batch.count) else {
                throw ListingError.malformedListing
            }
            hits.formUnion(found.map { $0 + start })
            start += batch.count
        }
        return hits
    }
}
