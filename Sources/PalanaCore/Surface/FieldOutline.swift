// The field outline — pure display model for the topology overlay. Builds
// display lines from remembered host facts, drives cursor and expand/collapse
// transitions, and resolves pointing queries. The Surface renders lines and
// owns nothing; everything that can be wrong lives here.

import Foundation

/// The topology overlay's pure display model.
///
/// `hosts` arrives ordered (local first, then config order); `facts` is the
/// last-remembered snapshot. Every transition is a pure mutation — the
/// Surface renders `lines` and delegates each keystroke here.
public struct FieldOutline: Equatable, Sendable {
    // MARK: - Line types

    /// One row in the topology overlay.
    public enum Line: Equatable, Sendable {
        /// A host row.
        case host(HostLine)
        /// A dataset row — visible only while its host is expanded.
        case dataset(DatasetLine)
    }

    /// The display data for one host row.
    ///
    /// Carries everything the overlay needs to render a host without further
    /// computation — the Surface reads and styles, it never interprets facts.
    public struct HostLine: Equatable, Sendable {
        /// The host's SSH alias.
        public let alias: String
        /// True when this row represents the operator's own machine.
        public let isLocal: Bool
        /// True when any facts exist for this host.
        public let visited: Bool
        /// The last known reachability — nil when never discovered.
        public let reachability: Reachability?
        /// When the reachability fact was recorded — nil when never discovered.
        public let rememberedAt: Date?
        /// Userland flavor — nil when never probed.
        public let flavor: UserlandFlavor?
        /// True when the last probe found ZFS.
        public let hasZFS: Bool
        /// True when the last probe found rsync.
        public let hasRsync: Bool
        /// True when this host's dataset rows are visible below.
        public let expanded: Bool
        /// The count of remembered datasets — 0 when none known.
        public let datasetCount: Int
    }

    /// The display data for one dataset row.
    ///
    /// Appears below its host row while that host is expanded.
    public struct DatasetLine: Equatable, Sendable {
        /// The owning host's SSH alias.
        public let host: String
        /// The dataset name — e.g., `tank/media/photos`.
        public let name: String
        /// The mountpoint property — a path, `legacy`, or `none`.
        public let mountpoint: String
        /// True only when the dataset is mounted and the mountpoint begins with `/`.
        public let pointable: Bool
    }

    // MARK: - Pointing

    /// A resolved pointer — a host and a path the pane can be aimed at.
    public struct Pointing: Equatable, Sendable {
        /// The target host's SSH alias.
        public let host: String
        /// The path on that host.
        public let path: String
    }

    // MARK: - Stored state

    private let hosts: [String]
    private var facts: [String: HostFacts]
    private let localHost: String
    private var expandedHosts: Set<String>

    /// The rendered display lines — rebuilt after every transition.
    public private(set) var lines: [Line]

    /// The cursor's current index into `lines`, clamped to the valid range.
    public private(set) var cursor: Int

    // MARK: - Init

    /// Builds an outline from an ordered host list and a fact snapshot.
    ///
    /// `hosts` arrives already ordered (local first, then config order).
    /// `localHost` is `PalanaCore.localHostName`'s value — the local row
    /// never carries facts. No hosts are expanded on init; the cursor lands
    /// on the first row.
    public init(hosts: [String], facts: [String: HostFacts], localHost: String) {
        self.hosts = hosts
        self.facts = facts
        self.localHost = localHost
        self.expandedHosts = []
        self.cursor = 0
        self.lines = Self.build(hosts: hosts, facts: facts, localHost: localHost, expanded: [])
    }

    // MARK: - Cursor transitions

    /// Moves the cursor one row toward the end, clamped at the last row.
    public mutating func cursorDown() {
        guard !lines.isEmpty else { return }
        cursor = min(cursor + 1, lines.count - 1)
    }

    /// Moves the cursor one row toward the top, clamped at the first row.
    public mutating func cursorUp() {
        cursor = max(cursor - 1, 0)
    }

    /// Moves the cursor to the given index.
    ///
    /// Clamps `index` into `[0, lines.count − 1]`. No-op when the outline is empty.
    public mutating func moveCursor(to index: Int) {
        guard !lines.isEmpty else { return }
        cursor = max(0, min(index, lines.count - 1))
    }

    // MARK: - Expand / Collapse

    /// Expands the host row under the cursor, showing its remembered datasets.
    ///
    /// No-op unless the cursor is on a host row with at least one remembered
    /// dataset.
    public mutating func expand() {
        guard !lines.isEmpty, case .host(let hl) = lines[cursor], hl.datasetCount > 0 else { return }
        let alias = hl.alias
        expandedHosts.insert(alias)
        lines = Self.build(hosts: hosts, facts: facts, localHost: localHost, expanded: expandedHosts)
        cursor = Self.hostIndex(for: alias, in: lines) ?? cursor
    }

    /// Toggles the expansion of the host row under the cursor.
    ///
    /// On a host row with at least one remembered dataset: expands when
    /// collapsed, collapses when expanded. On a dataset row or a datasetless
    /// host row: no-op. Delegates to `expand()` and `collapse()` so the
    /// rebuild logic stays in one place.
    public mutating func toggleExpansion() {
        guard !lines.isEmpty, case .host(let hl) = lines[cursor], hl.datasetCount > 0 else { return }
        if hl.expanded {
            collapse()
        } else {
            expand()
        }
    }

    /// Collapses the current host or the dataset's owning host.
    ///
    /// On a dataset row: collapses its host and moves the cursor to that host
    /// row. On an expanded host row: collapses it; the cursor stays on the
    /// host row. Otherwise: no-op.
    public mutating func collapse() {
        guard !lines.isEmpty else { return }
        switch lines[cursor] {
        case .host(let hl):
            guard expandedHosts.contains(hl.alias) else { return }
            let alias = hl.alias
            expandedHosts.remove(alias)
            lines = Self.build(hosts: hosts, facts: facts, localHost: localHost, expanded: expandedHosts)
            cursor = Self.hostIndex(for: alias, in: lines) ?? cursor
        case .dataset(let dl):
            let owningHost = dl.host
            expandedHosts.remove(owningHost)
            lines = Self.build(hosts: hosts, facts: facts, localHost: localHost, expanded: expandedHosts)
            cursor = Self.hostIndex(for: owningHost, in: lines) ?? 0
        }
    }

    // MARK: - Queries

    /// Resolves a pointing target from the cursor's current row.
    ///
    /// A host row resolves to `(alias, "~")`. A pointable dataset row resolves
    /// to `(host, mountpoint)`. A non-pointable dataset and an empty outline
    /// return nil.
    public func pointing() -> Pointing? {
        guard !lines.isEmpty else { return nil }
        switch lines[cursor] {
        case .host(let hl):
            return Pointing(host: hl.alias, path: "~")
        case .dataset(let dl):
            return dl.pointable ? Pointing(host: dl.host, path: dl.mountpoint) : nil
        }
    }

    /// The alias of the host row under the cursor, or the dataset's owning host.
    ///
    /// Nil when the outline is empty.
    public func hostUnderCursor() -> String? {
        guard !lines.isEmpty else { return nil }
        switch lines[cursor] {
        case .host(let hl): return hl.alias
        case .dataset(let dl): return dl.host
        }
    }

    // MARK: - Update

    /// Rebuilds lines from a new fact snapshot, preserving expansion set and cursor.
    ///
    /// The cursor follows its line by identity — host alias for host rows, host
    /// and dataset name for dataset rows. When that line no longer exists in the
    /// new snapshot, the cursor clamps to the nearest valid index.
    public mutating func update(facts newFacts: [String: HostFacts]) {
        let identity = lineIdentity(at: cursor)
        facts = newFacts
        lines = Self.build(hosts: hosts, facts: facts, localHost: localHost, expanded: expandedHosts)
        cursor = restoredCursor(for: identity, in: lines)
    }

    // MARK: - Private helpers

    private static func build(
        hosts: [String],
        facts: [String: HostFacts],
        localHost: String,
        expanded: Set<String>
    ) -> [Line] {
        var result: [Line] = []
        for host in hosts {
            if host == localHost {
                let local = HostLine(
                    alias: host,
                    isLocal: true,
                    visited: false,
                    reachability: nil,
                    rememberedAt: nil,
                    flavor: nil,
                    hasZFS: false,
                    hasRsync: false,
                    expanded: false,
                    datasetCount: 0
                )
                result.append(.host(local))
                continue
            }
            let hostFacts = facts[host]
            let datasets = hostFacts?.zfsTopology?.value ?? []
            let isExpanded = expanded.contains(host) && !datasets.isEmpty
            let remote = HostLine(
                alias: host,
                isLocal: false,
                visited: hostFacts != nil,
                reachability: hostFacts?.reachability?.value,
                rememberedAt: hostFacts?.reachability?.discoveredAt,
                flavor: hostFacts?.capability?.value.flavor,
                hasZFS: hostFacts?.capability?.value.zfs != nil,
                hasRsync: hostFacts?.capability?.value.rsync != nil,
                expanded: isExpanded,
                datasetCount: datasets.count
            )
            result.append(.host(remote))
            guard isExpanded else { continue }
            for dataset in datasets {
                let dLine = DatasetLine(
                    host: host,
                    name: dataset.name,
                    mountpoint: dataset.mountpoint,
                    pointable: dataset.mounted && dataset.mountpoint.hasPrefix("/")
                )
                result.append(.dataset(dLine))
            }
        }
        return result
    }

    /// The index of the first host row with the given alias in `someLines`, or nil.
    private static func hostIndex(for alias: String, in someLines: [Line]) -> Int? {
        someLines.firstIndex {
            guard case .host(let hl) = $0 else { return false }
            return hl.alias == alias
        }
    }

    private enum LineIdentity: Equatable {
        case host(String)
        case dataset(String, String)
    }

    private func lineIdentity(at index: Int) -> LineIdentity? {
        guard index >= 0, index < lines.count else { return nil }
        switch lines[index] {
        case .host(let hl): return .host(hl.alias)
        case .dataset(let dl): return .dataset(dl.host, dl.name)
        }
    }

    private func restoredCursor(for identity: LineIdentity?, in newLines: [Line]) -> Int {
        let clamped = max(0, min(cursor, newLines.count - 1))
        guard let identity else { return clamped }
        let found = newLines.firstIndex { lineMatchesIdentity($0, identity: identity) }
        return found ?? clamped
    }

    private func lineMatchesIdentity(_ line: Line, identity: LineIdentity) -> Bool {
        switch (line, identity) {
        case (.host(let hl), .host(let alias)): hl.alias == alias
        case (.dataset(let dl), .dataset(let host, let name)): dl.host == host && dl.name == name
        default: false
        }
    }
}

// MARK: - FieldAge

/// Formats the age of a remembered fact for display.
///
/// All formatting is relative to a supplied `now`, making it fully testable
/// without live clocks. Future dates read as "just now" — clocks are not
/// trusted to be perfectly synchronized.
public enum FieldAge {
    /// Describes `date` relative to `now` as a compact human string.
    ///
    /// Returns "just now" when `date` is less than 60 seconds old or lies in
    /// the future. Above that threshold: "Nm ago", "Nh ago", "Nd ago" at
    /// integer-truncated minute, hour, and day boundaries.
    public static func describe(_ date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600))h ago" }
        return "\(Int(elapsed / 86_400))d ago"
    }
}
