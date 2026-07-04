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

    /// A pane, pointed or not.
    public init(
        host: String? = nil,
        path: String = "/",
        entries: [FileEntry] = [],
        selection: Set<FileEntry.ID> = [],
        cursor: FileEntry.ID? = nil,
        sort: Sort = .byName
    ) {
        self.host = host
        self.path = path
        self.entries = entries
        self.selection = selection
        self.cursor = cursor
        self.sort = sort
    }

    /// The entries in the active sort order.
    ///
    /// Name sorting uses `localizedStandardCompare` — the Finder's
    /// ordering, where `file2` precedes `file10`. Ties break on name
    /// bytes so the order is total and stable.
    public func sortedEntries() -> [FileEntry] {
        let ordered = entries.sorted { lhs, rhs in
            switch sort.key {
            case .name:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                guard comparison == .orderedSame else { return comparison == .orderedAscending }
                return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            case .size:
                guard lhs.size == rhs.size else { return lhs.size < rhs.size }
                return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            case .modified:
                guard lhs.modified == rhs.modified else { return lhs.modified < rhs.modified }
                return lhs.nameData.lexicographicallyPrecedes(rhs.nameData)
            }
        }
        return sort.ascending ? ordered : Array(ordered.reversed())
    }
}
