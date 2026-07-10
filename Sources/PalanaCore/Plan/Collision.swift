// Collision — what a copy or move will overwrite, named before it runs.
// Pure PalanaCore: no I/O, no gather. Detection is a pure function over
// source entries and a destination listing; the report rides the Plan.

// ── MESSAGE GRAMMAR ───────────────────────────────────────────────────────────
//
// All operator-facing text in pālana follows six rules:
//
// 1. A plan speaks in the future:
//      "will replace notes.txt (3 kB)"
//      "will merge into media"
//      "will delete the source after the copy is verified"
//
// 2. A running step speaks through its command — the $ line IS the narration;
//    surrounding text stays minimal and present-tense:
//      "check on koan: $ find …"
//
// 3. A finished run speaks in the past with its proof:
//      "done — copied 3, checked 3"
//      "done — every step ran and checked out"
//
// 4. A refusal names the thing and the reason in one line:
//      "won't run — <thing>: <reason>"
//      "won't work — notes is a folder here and a file there"
//
// 5. Anything unknown is named unknown:
//      "couldn't check the destination — this may overwrite files there"
//
// 6. No jargon in operator-facing text: run / check / build / send, never
//    enact / gather / compose / classification / transport-as-a-word.
//    Lowercase voice · middle dots (·) join clauses · no semicolons · no !
//    Commands, paths, host names stay verbatim.
//    Domain nouns that ARE the thing (rsync, zfs, ssh, dataset, mountpoint,
//    snapshot) are kept — the rule bans arcana, not precision.
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

/// One name that a planned transfer will strike at the destination.
///
/// The arriving entry shares a byte-exact name with something already
/// standing at the destination. The nature of the collision — replace,
/// merge, or kind clash — is derived from the two kinds.
public struct Collision: Codable, Sendable, Equatable {
    /// The kind of collision the two entries produce.
    public enum Nature: String, Codable, Sendable, Equatable {
        /// A file arriving on a file — the standing entry is replaced.
        case replace
        /// A directory arriving on a directory — the standing tree is
        /// merged into. rsync and `cp -a` both merge; "replaces" is a lie.
        case merge
        /// Mixed kinds — the tool will refuse at enactment. The plan
        /// names why before the operator finds out.
        case kindClash = "kind-clash"
    }

    /// The byte-exact filename as the listing reports it.
    public var nameData: Data
    /// What stands at the destination — its kind.
    public var standingKind: FileEntry.Kind
    /// What stands at the destination — its byte count.
    public var standingSize: Int64
    /// What stands at the destination — its modification time.
    public var standingModified: Date
    /// What arrives from the source — its kind.
    public var arrivingKind: FileEntry.Kind

    /// Assembles a collision fact.
    public init(
        nameData: Data,
        standingKind: FileEntry.Kind,
        standingSize: Int64,
        standingModified: Date,
        arrivingKind: FileEntry.Kind
    ) {
        self.nameData = nameData
        self.standingKind = standingKind
        self.standingSize = standingSize
        self.standingModified = standingModified
        self.arrivingKind = arrivingKind
    }

    /// The filename for display — lossy UTF-8, never for composition.
    ///
    /// Uses `String(decoding:as:)` deliberately — lossy is the point:
    /// every name displays, even unparseable byte sequences.
    public var name: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: nameData, as: UTF8.self)
    }

    /// What the collision means: replace, merge, or kind clash.
    public var nature: Nature {
        switch (standingKind, arrivingKind) {
        case (.directory, .directory):
            return .merge
        case (.file, .file), (.symlink, .file), (.symlink, .symlink),
            (.file, .symlink), (.other, .other):
            return .replace
        default:
            return .kindClash
        }
    }

    /// Computes collision facts between source entries and a destination
    /// listing, byte-exact on names.
    ///
    /// Order follows destination-listing appearance. Symlinks at the
    /// destination are compared by name like any other entry; a symlink
    /// standing at the destination is `.replace` when a file arrives —
    /// rsync replaces the link, not the referent.
    public static func detect(
        sources: [FileEntry],
        destinationListing: [FileEntry]
    ) -> [Self] {
        // A well-formed listing never repeats a name, but a malformed one
        // must not crash the detect — first occurrence wins.
        let sourceIndex: [Data: FileEntry.Kind] = Dictionary(
            sources.map { ($0.nameData, $0.kind) }
        ) { first, _ in first }
        var collisions: [Self] = []
        for standing in destinationListing {
            guard let arrivingKind = sourceIndex[standing.nameData] else { continue }
            collisions.append(
                Self(
                    nameData: standing.nameData,
                    standingKind: standing.kind,
                    standingSize: standing.size,
                    standingModified: standing.modified,
                    arrivingKind: arrivingKind))
        }
        return collisions
    }
}

/// The collision facts carried on a Plan — items found plus a gathered flag.
///
/// `gathered: false` means the destination listing was unavailable;
/// the panel must say so in alarm, never silently.
public struct CollisionReport: Codable, Sendable, Equatable {
    /// The collisions found, in destination-listing order.
    public var items: [Collision]
    /// True when the destination listing was successfully read.
    ///
    /// False means the items array is empty because the gather failed,
    /// not because the destination was clean.
    public var gathered: Bool

    /// Assembles a report.
    public init(items: [Collision], gathered: Bool) {
        self.items = items
        self.gathered = gathered
    }

    /// Composes the panel line for this report.
    ///
    /// Returns `nil` when gathered and the destination is clean (silence
    /// is licensed only when the third — ungathered — state is loud).
    /// Returns a fixed alarm string when ungathered. Otherwise returns a
    /// sentence naming replaces, merges, and kind clashes with sizes,
    /// names capped at four per clause with an honest "and N more."
    public func sentence() -> String? {
        guard gathered else {
            return "couldn't check the destination — this may overwrite files there"
        }
        guard !items.isEmpty else { return nil }

        var clauses: [String] = []

        let replaces = items.filter { $0.nature == .replace }
        if !replaces.isEmpty {
            clauses.append(replaceClause(replaces))
        }

        let merges = items.filter { $0.nature == .merge }
        if !merges.isEmpty {
            clauses.append(mergeClause(merges))
        }

        let clashes = items.filter { $0.nature == .kindClash }
        if !clashes.isEmpty {
            clauses.append(clashClause(clashes))
        }

        return clauses.joined(separator: " · ")
    }

    // MARK: - Clause composers

    private func replaceClause(_ items: [Collision]) -> String {
        let totalSize = items.map(\.standingSize).reduce(0, +)
        let bytes = totalSize.formatted(.byteCount(style: .file))
        let names = cappedNames(items)
        return "will replace \(names) (\(bytes))"
    }

    private func mergeClause(_ items: [Collision]) -> String {
        let names = cappedNames(items)
        return "will merge into \(names)"
    }

    private func clashClause(_ items: [Collision]) -> String {
        // Report which way the clash goes — folder-here or file-here.
        // When there is one item, name the exact direction. When there
        // are multiple, each may differ; fall back to "kind mismatch".
        if items.count == 1, let first = items.first {
            let name = first.name
            guard first.standingKind == .directory else {
                return "won't work — \(name) is a file here and a folder there"
            }
            return "won't work — \(name) is a folder here and a file there"
        }
        let names = cappedNames(items)
        return "won't work — kind mismatch: \(names)"
    }

    /// Renders up to four names joined by commas, with "and N more" when
    /// the list exceeds four.
    private func cappedNames(_ items: [Collision]) -> String {
        let cap = 4
        if items.count <= cap {
            return items.map(\.name).joined(separator: ", ")
        }
        let shown = items.prefix(cap).map(\.name).joined(separator: ", ")
        let remainder = items.count - cap
        return "\(shown), and \(remainder) more"
    }
}
