// The pane state model — the value the Surface renders. Committed here,
// three hos before any pane exists, so ho-05 composes plans against
// selections and ho-07 binds a table to a shape that already exists.
// The model decides nothing about presentation.

import Foundation

/// One pane: where it points, what it holds, what the operator has
/// selected.
public struct PaneState: Sendable, Equatable {
    /// What the entries are ordered by.
    public enum SortKey: String, Codable, Sendable {
        /// By display name, Finder-style comparison. The default.
        case name
        /// By size in bytes.
        case size
        /// By modification time.
        case modified
        /// By creation time — nil on GNU and BusyBox, sorts last.
        case created
        /// By status-change time — nil on BusyBox, sorts last.
        case changed
        /// By permission bits as an octal string — lexicographic.
        case permissions
        /// By owning user name — lexicographic.
        case owner
        /// By owning group name — lexicographic.
        case group
    }

    /// A sort order: key plus direction.
    public struct Sort: Sendable, Equatable, Codable {
        /// What to order by.
        public var key: SortKey
        /// Ascending when true.
        public var ascending: Bool

        /// A sort order.
        public init(key: SortKey, ascending: Bool = true) {
            self.key = key
            self.ascending = ascending
        }

        /// Name ascending — the pane's opening state.
        public static let byName = Self(key: .name)
    }

    /// The host the pane points at. nil when the pane points nowhere yet.
    public var host: String?
    /// The directory path on that host.
    public var path: String
    /// The entries the last read produced.
    public var entries: [FileEntry]
    /// Selected entries, by identity.
    public var selection: Set<FileEntry.ID>
    /// The entry the cursor sits on, by identity.
    public var cursor: FileEntry.ID?
    /// The active sort order.
    public var sort: Sort
    /// Whether dotfiles display — hidden is the opening state.
    public var showHidden: Bool

    /// A pane, pointed or not.
    public init(
        host: String? = nil,
        path: String = "/",
        entries: [FileEntry] = [],
        selection: Set<FileEntry.ID> = [],
        cursor: FileEntry.ID? = nil,
        sort: Sort = .byName,
        showHidden: Bool = false
    ) {
        self.host = host
        self.path = path
        self.entries = entries
        self.selection = selection
        self.cursor = cursor
        self.sort = sort
        self.showHidden = showHidden
    }

    // swiftlint:disable cyclomatic_complexity
    /// The displayed entries in the active sort order.
    ///
    /// Dotfiles are filtered out unless ``showHidden`` says otherwise.
    /// Name sorting uses `localizedStandardCompare` — the Finder's
    /// ordering, where `file2` precedes `file10`. Ties break on name
    /// bytes so the order is total and stable.
    ///
    /// Optional fields (`created`, `changed`) sort nils last in **both**
    /// directions — a column of dashes never shuffles when the direction
    /// flips. Non-optional keys bake direction into the comparator.
    public func sortedEntries() -> [FileEntry] {
        // swiftlint:enable cyclomatic_complexity
        let visible = showHidden ? entries : entries.filter { !$0.isHidden }
        let asc = sort.ascending
        let ordered = visible.sorted { lhs, rhs in
            switch sort.key {
            case .name:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                guard comparison == .orderedSame else {
                    let lt = comparison == .orderedAscending
                    return asc ? lt : !lt
                }
                let lt = lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
                return asc ? lt : !lt
            case .size:
                guard lhs.size == rhs.size else {
                    return asc ? lhs.size < rhs.size : lhs.size > rhs.size
                }
                return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            case .modified:
                guard lhs.modified == rhs.modified else {
                    return asc ? lhs.modified < rhs.modified : lhs.modified > rhs.modified
                }
                return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            case .created:
                // Nils last in both directions.
                return Self.compareOptionalNilsLast(lhs.created, rhs.created, ascending: asc)
                    ?? lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            case .changed:
                return Self.compareOptionalNilsLast(lhs.changed, rhs.changed, ascending: asc)
                    ?? lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            case .permissions:
                guard lhs.permissions != rhs.permissions else {
                    return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
                }
                return asc
                    ? lhs.permissions < rhs.permissions
                    : lhs.permissions > rhs.permissions
            case .owner:
                guard lhs.owner != rhs.owner else {
                    return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
                }
                return asc ? lhs.owner < rhs.owner : lhs.owner > rhs.owner
            case .group:
                guard lhs.group != rhs.group else {
                    return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
                }
                return asc ? lhs.group < rhs.group : lhs.group > rhs.group
            }
        }
        return ordered
    }

    // swiftlint:disable discouraged_optional_boolean
    /// Compares two optional `Comparable` values with nils always last,
    /// regardless of direction.
    ///
    /// Returns a three-valued result (lhs precedes / rhs precedes / equal)
    /// encoded as `true`, `false`, and `nil` so the caller can fall through
    /// to the name-byte tie-break on equal. The optional return type is
    /// intentional — three states that cannot be expressed as a non-optional
    /// Bool; the disable suppresses the SwiftLint nit.
    private static func compareOptionalNilsLast<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?,
        ascending: Bool
    ) -> Bool? {
        // swiftlint:enable discouraged_optional_boolean
        switch (lhs, rhs) {
        case (nil, nil): nil  // equal — caller breaks tie
        case (nil, _): false  // nil goes last: lhs does NOT precede
        case (_, nil): true  // non-nil beats nil: lhs precedes
        case (let lval?, let rval?):
            if lval == rval {
                nil
            }  // equal — caller breaks tie
            else {
                ascending ? lval < rval : lval > rval
            }
        }
    }
}
