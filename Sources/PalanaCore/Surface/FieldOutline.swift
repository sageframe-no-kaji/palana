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
        /// A dataset row — visible only while its host is expanded and every
        /// ancestor dataset is also expanded.
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
        /// True when the last probe found passwordless sudo — matches the
        /// host map's `sudoNoPassword` fact (ho-10.4-AT-02, F1).
        public let hasSudoNoPassword: Bool
        /// True when this host's dataset rows are visible below.
        public let expanded: Bool
        /// The count of remembered datasets — 0 when none known.
        public let datasetCount: Int
    }

    /// The display data for one dataset row.
    ///
    /// Appears below its host row while that host is expanded and every
    /// ancestor dataset is also expanded. Nesting depth is computed from
    /// the presence of name-prefix ancestors in the same host's remembered
    /// dataset list — `a/b/c` sits under `a/b` which sits under `a`.
    public struct DatasetLine: Equatable, Sendable {
        /// The owning host's SSH alias.
        public let host: String
        /// The dataset name — e.g., `tank/media/photos`.
        public let name: String
        /// The mountpoint property — a path, `legacy`, or `none`.
        public let mountpoint: String
        /// True only when the dataset is mounted and the mountpoint begins with `/`.
        public let pointable: Bool
        /// How many levels deep this dataset sits in the tree.
        ///
        /// 0 for datasets whose name prefix has no ancestor present in the
        /// host's remembered list. Increases by one for each ancestor present.
        public let depth: Int
        /// The count of direct children among the same host's remembered datasets.
        ///
        /// A dataset is a direct child of this one when its `directParent`
        /// (longest name-prefix present in the list) is this dataset's name.
        public let childCount: Int
        /// True when this dataset's children are currently shown below this row.
        public let expanded: Bool
    }

    // MARK: - Pointing

    /// A resolved pointer — a host and a path the pane can be aimed at.
    public struct Pointing: Equatable, Sendable {
        /// The target host's SSH alias.
        public let host: String
        /// The path on that host.
        public let path: String
    }

    // MARK: - Private nested types

    /// Expansion key — (host, dataset name) pair stored in `expandedDatasets`.
    ///
    /// A plain struct rather than a delimited string so the key can never
    /// collide across hosts or across path separators that appear in names.
    private struct DatasetKey: Hashable, Sendable {
        let host: String
        let name: String
    }

    /// Per-node information built once per host during `build()`.
    private struct TreeNodeInfo {
        var depth: Int
        var childCount: Int
        let parentName: String?
    }

    // MARK: - Stored state

    private let hosts: [String]
    private var facts: [String: HostFacts]
    private let localHost: String
    private var expandedHosts: Set<String>
    /// Dataset expansion state keyed by host+name — survives `update(facts:)`
    /// exactly as `expandedHosts` does; stale keys are silently ignored during build.
    private var expandedDatasets: Set<DatasetKey>

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
        self.expandedDatasets = []
        self.cursor = 0
        self.lines = Self.build(
            hosts: hosts,
            facts: facts,
            localHost: localHost,
            expandedHosts: [],
            expandedDatasets: [])
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

    /// Expands the row under the cursor.
    ///
    /// On a host row with remembered datasets: expands the host, showing its
    /// depth-0 dataset rows. On a dataset row with children: expands that
    /// dataset, showing its direct children. No-op otherwise.
    public mutating func expand() {
        guard !lines.isEmpty else { return }
        switch lines[cursor] {
        case .host(let hl):
            guard hl.datasetCount > 0 else { return }
            let alias = hl.alias
            expandedHosts.insert(alias)
            rebuild()
            cursor = Self.hostIndex(for: alias, in: lines) ?? cursor
        case .dataset(let dl):
            guard dl.childCount > 0 else { return }
            let key = DatasetKey(host: dl.host, name: dl.name)
            expandedDatasets.insert(key)
            rebuild()
            cursor = Self.datasetIndex(for: dl.host, name: dl.name, in: lines) ?? cursor
        }
    }

    /// Toggles the expansion of the row under the cursor.
    ///
    /// On a host row with datasets or a dataset row with children: expands when
    /// collapsed, collapses when expanded. On a datasetless host row or a leaf
    /// dataset row: no-op. Delegates to `expand()` and `collapse()` so rebuild
    /// logic stays in one place.
    public mutating func toggleExpansion() {
        guard !lines.isEmpty else { return }
        switch lines[cursor] {
        case .host(let hl):
            guard hl.datasetCount > 0 else { return }
            if hl.expanded { collapse() } else { expand() }
        case .dataset(let dl):
            guard dl.childCount > 0 else { return }  // leaf: no-op
            if dl.expanded { collapse() } else { expand() }
        }
    }

    /// Collapses the current row or walks up to its parent.
    ///
    /// - On an expanded host row: collapses it; cursor stays on the host.
    /// - On an unexpanded host row: no-op.
    /// - On an expanded dataset row (children are showing): collapses it;
    ///   cursor stays on that dataset.
    /// - On a leaf or collapsed dataset row: collapses its direct parent
    ///   dataset, or its host when no parent dataset is present in the list;
    ///   cursor moves to the collapsed parent.
    public mutating func collapse() {
        guard !lines.isEmpty else { return }
        switch lines[cursor] {
        case .host(let hl):
            guard expandedHosts.contains(hl.alias) else { return }
            let alias = hl.alias
            expandedHosts.remove(alias)
            rebuild()
            cursor = Self.hostIndex(for: alias, in: lines) ?? cursor
        case .dataset(let dl):
            if dl.expanded {
                // Expanded dataset — collapse it; cursor stays on this row.
                expandedDatasets.remove(DatasetKey(host: dl.host, name: dl.name))
                rebuild()
                cursor = Self.datasetIndex(for: dl.host, name: dl.name, in: lines) ?? cursor
            } else {
                // Leaf or collapsed dataset — walk up to the parent.
                collapseParentOf(dl)
            }
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

    /// Rebuilds lines from a new fact snapshot, preserving expansion state and cursor.
    ///
    /// Both host and dataset expansion state survive the update. The cursor follows
    /// its line by identity — host alias for host rows, host and dataset name for
    /// dataset rows. When that line no longer exists in the new snapshot, the cursor
    /// clamps to the nearest valid index.
    public mutating func update(facts newFacts: [String: HostFacts]) {
        let identity = lineIdentity(at: cursor)
        facts = newFacts
        rebuild()
        cursor = restoredCursor(for: identity, in: lines)
    }

    // MARK: - Private helpers

    private mutating func rebuild() {
        lines = Self.build(
            hosts: hosts,
            facts: facts,
            localHost: localHost,
            expandedHosts: expandedHosts,
            expandedDatasets: expandedDatasets)
    }

    /// Collapses the parent of `dl` — the direct parent dataset if present in the
    /// list, otherwise the owning host — and moves the cursor there.
    private mutating func collapseParentOf(_ dl: DatasetLine) {
        let datasets = facts[dl.host]?.zfsTopology?.value ?? []
        let nameSet = Set(datasets.map(\.name))
        let parentName = Self.directParent(of: dl.name, in: nameSet)
        if let parentName {
            expandedDatasets.remove(DatasetKey(host: dl.host, name: parentName))
            rebuild()
            cursor = Self.datasetIndex(for: dl.host, name: parentName, in: lines) ?? cursor
        } else {
            // depth 0 — no dataset parent; collapse the host
            expandedHosts.remove(dl.host)
            rebuild()
            cursor = Self.hostIndex(for: dl.host, in: lines) ?? 0
        }
    }
}

// MARK: - Build helpers

extension FieldOutline {
    private static func build(
        hosts: [String],
        facts: [String: HostFacts],
        localHost: String,
        expandedHosts: Set<String>,
        expandedDatasets: Set<DatasetKey>
    ) -> [Line] {
        var result: [Line] = []
        for host in hosts {
            if host == localHost {
                result.append(.host(localLine(host)))
                continue
            }
            let hostFacts = facts[host]
            let datasets = hostFacts?.zfsTopology?.value ?? []
            let isExpanded = expandedHosts.contains(host) && !datasets.isEmpty
            result.append(
                .host(
                    remoteLine(
                        host: host, facts: hostFacts, datasets: datasets, isExpanded: isExpanded)))
            guard isExpanded else { continue }
            result.append(
                contentsOf: datasetLines(
                    for: host, datasets: datasets, expandedDatasets: expandedDatasets))
        }
        return result
    }

    private static func localLine(_ host: String) -> HostLine {
        HostLine(
            alias: host,
            isLocal: true,
            visited: false,
            reachability: nil,
            rememberedAt: nil,
            flavor: nil,
            hasZFS: false,
            hasRsync: false,
            hasSudoNoPassword: false,
            expanded: false,
            datasetCount: 0)
    }

    private static func remoteLine(
        host: String, facts: HostFacts?, datasets: [ZFSDataset], isExpanded: Bool
    ) -> HostLine {
        HostLine(
            alias: host,
            isLocal: false,
            visited: facts != nil,
            reachability: facts?.reachability?.value,
            rememberedAt: facts?.reachability?.discoveredAt,
            flavor: facts?.capability?.value.flavor,
            hasZFS: facts?.capability?.value.zfs != nil,
            hasRsync: facts?.capability?.value.rsync != nil,
            hasSudoNoPassword: facts?.sudoNoPassword?.value ?? false,
            expanded: isExpanded,
            datasetCount: datasets.count)
    }

    /// Renders the visible dataset rows for one expanded host.
    ///
    /// Depth-0 datasets (no ancestor present in the list) appear whenever the
    /// host is expanded. Deeper datasets appear only when every ancestor dataset
    /// in the chain is in `expandedDatasets`.
    private static func datasetLines(
        for host: String,
        datasets: [ZFSDataset],
        expandedDatasets: Set<DatasetKey>
    ) -> [Line] {
        let treeInfo = computeTreeInfo(for: datasets)
        var result: [Line] = []
        for dataset in datasets {
            let info = treeInfo[dataset.name] ?? TreeNodeInfo(depth: 0, childCount: 0, parentName: nil)
            guard
                isDatasetVisible(
                    name: dataset.name,
                    host: host,
                    tree: treeInfo,
                    expandedDatasets: expandedDatasets)
            else { continue }
            let key = DatasetKey(host: host, name: dataset.name)
            let isExpanded = expandedDatasets.contains(key) && info.childCount > 0
            result.append(
                .dataset(
                    DatasetLine(
                        host: host,
                        name: dataset.name,
                        mountpoint: dataset.mountpoint,
                        pointable: dataset.mounted && dataset.mountpoint.hasPrefix("/"),
                        depth: info.depth,
                        childCount: info.childCount,
                        expanded: isExpanded)))
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

    /// The index of the first dataset row matching host+name in `someLines`, or nil.
    private static func datasetIndex(for host: String, name: String, in someLines: [Line]) -> Int? {
        someLines.firstIndex {
            guard case .dataset(let dl) = $0 else { return false }
            return dl.host == host && dl.name == name
        }
    }
}

// MARK: - Tree helpers

extension FieldOutline {
    /// Builds the tree metadata for one host's dataset list.
    ///
    /// For each dataset: depth (count of ancestors present in the list),
    /// childCount (direct children), parentName (longest present prefix).
    private static func computeTreeInfo(for datasets: [ZFSDataset]) -> [String: TreeNodeInfo] {
        let nameSet = Set(datasets.map(\.name))
        var result: [String: TreeNodeInfo] = [:]
        for dataset in datasets {
            let parentName = directParent(of: dataset.name, in: nameSet)
            let depth = computeDepth(of: dataset.name, in: nameSet)
            result[dataset.name] = TreeNodeInfo(depth: depth, childCount: 0, parentName: parentName)
        }
        for dataset in datasets {
            if let parent = result[dataset.name]?.parentName {
                result[parent]?.childCount += 1
            }
        }
        return result
    }

    /// The longest proper name-prefix of `name` (by `/` segments) that is
    /// present in `nameSet`, or nil when no prefix is present.
    ///
    /// Example: for `a/b/c` in `{a, a/b/c}` the result is `a` (not `a/b`,
    /// which is absent), satisfying "hierarchy with a hole".
    private static func directParent(of name: String, in nameSet: Set<String>) -> String? {
        var parts = name.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return nil }
        parts.removeLast()
        while !parts.isEmpty {
            let candidate = parts.joined(separator: "/")
            if nameSet.contains(candidate) { return candidate }
            parts.removeLast()
        }
        return nil
    }

    /// The count of ancestors of `name` that are present in `nameSet`.
    ///
    /// A dataset with no ancestors in the list has depth 0; each present
    /// ancestor adds one to the depth regardless of absent intermediaries.
    private static func computeDepth(of name: String, in nameSet: Set<String>) -> Int {
        var parts = name.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return 0 }
        var depth = 0
        parts.removeLast()
        while !parts.isEmpty {
            let candidate = parts.joined(separator: "/")
            if nameSet.contains(candidate) { depth += 1 }
            parts.removeLast()
        }
        return depth
    }

    /// True when `name` should appear in the rendered list.
    ///
    /// Depth-0 datasets (no parent in the tree) are always visible once
    /// the host is expanded. Deeper datasets require every ancestor in the
    /// chain to be in `expandedDatasets`.
    private static func isDatasetVisible(
        name: String,
        host: String,
        tree: [String: TreeNodeInfo],
        expandedDatasets: Set<DatasetKey>
    ) -> Bool {
        guard let info = tree[name] else { return false }
        guard let parentName = info.parentName else { return true }  // depth 0
        guard expandedDatasets.contains(DatasetKey(host: host, name: parentName)) else { return false }
        return isDatasetVisible(
            name: parentName,
            host: host,
            tree: tree,
            expandedDatasets: expandedDatasets)
    }
}

// MARK: - Cursor identity helpers

extension FieldOutline {
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
