// The host map — pure display model for the floating host map panel. Builds
// ordered host sections from remembered facts; the panel renders sections and
// owns nothing. Everything that can be wrong lives here.

import Foundation

/// The host map panel's pure display model.
///
/// `hosts` arrives ordered (local first — the caller's job, as with
/// `FieldOutline`). Every section is present even when a host has never been
/// visited — the map shows the full roster. ZFS mounts group under pool
/// header lines; non-ZFS storage and network mounts follow as plain ground.
/// Fold state is carried across fact updates via `update(facts:)`.
public struct HostMap: Equatable, Sendable {
    // MARK: - Nested types

    /// A ZFS pool header in a host's mount area.
    ///
    /// Pools collect all ZFS mounts whose source begins with the pool name;
    /// the panel renders a pool line before its members. A pool with no
    /// rendered mounts never appears.
    public struct PoolLine: Equatable, Sendable {
        /// The pool name — the first `/`-segment of the ZFS dataset source.
        public let name: String
        /// Total count of ZFS mounts belonging to this pool.
        public let visibleMountCount: Int
        /// True when the pool's mount rows are currently shown below.
        public let expanded: Bool
    }

    /// One row in a host's mount list — a pool header or a mount entry.
    ///
    /// Pool lines (`.pool`) head each ZFS pool group. Mount rows (`.mount`)
    /// appear after their pool header (ZFS) or after all pools (plain ground).
    public enum MountLine: Equatable, Sendable {
        case pool(PoolLine)
        case mount(MountRow)
    }

    /// One mount row — storage and network only, no system mounts.
    ///
    /// System mounts are counted but not rendered; see `systemMountCount`.
    /// ZFS rows appear inside their pool group, nested by dataset name.
    /// Plain rows appear after all pools, nested by mountpoint path.
    /// Only visible rows appear; collapsed subtrees are absent.
    public struct MountRow: Equatable, Sendable {
        /// The mountpoint path.
        public let target: String
        /// Filesystem type — `ext4`, `apfs`, `nfs`, `zfs`, and others.
        public let fstype: String
        /// Device or remote spec — for ZFS mounts, the dataset name.
        public let source: String
        /// Whether the mount is read-only.
        public let readOnly: Bool
        /// How the filesystem classifies — storage or network.
        public let kind: MountKind
        /// True when the target is exactly a remembered dataset mountpoint.
        ///
        /// Filled means zfs send territory; hollow (plain mount) is indicated
        /// separately by the surface.
        public let isDatasetMountpoint: Bool
        /// How many levels deep this mount sits in its group's tree.
        ///
        /// ZFS rows: 1 + present-dataset-ancestor count (pool header is at 0).
        /// Plain rows: present-path-ancestor count among the plain set.
        public let depth: Int
        /// The count of direct children among the same group's rendered mounts.
        ///
        /// ZFS: direct child datasets by dataset name. Plain: direct child
        /// paths at a component boundary.
        public let childCount: Int
        /// True when this mount's children are currently shown below this row.
        public let expanded: Bool
    }

    /// The display data for one host in the map.
    ///
    /// Carries everything the panel needs to render a host section without
    /// further computation.
    public struct HostSection: Equatable, Sendable {
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
        /// Display lines for this host's mounts — pool headers and mount rows.
        ///
        /// ZFS mounts group under `.pool` header lines; all other storage and
        /// network mounts follow as plain `.mount` rows. System mounts are
        /// counted in `systemMountCount` and do not appear here. Collapsed
        /// pool and mount subtrees are absent.
        public let mounts: [MountLine]
        /// The number of system mounts the classifier excluded from `mounts`.
        ///
        /// The count line, never silent — the surface renders it as a quiet
        /// summary so the operator sees what was hidden.
        public let systemMountCount: Int
        /// When the mounts fact was recorded — nil when never read.
        public let mountsRememberedAt: Date?
    }

    // MARK: - Private types

    /// Collapse key — (host alias, mount target) pair stored in `collapsedMounts`.
    ///
    /// A plain struct rather than a delimited string so the key can never
    /// collide across hosts or across path characters in targets.
    private struct MountKey: Hashable, Sendable {
        let host: String
        let target: String
    }

    /// Collapse key for pool folds — (host alias, pool name) pair.
    ///
    /// Kept separate from `MountKey` so a pool named identically to a mount
    /// target can never collide across the two sets.
    private struct PoolKey: Hashable, Sendable {
        let host: String
        let pool: String
    }

    /// Per-node information built once per host during `buildSections`.
    ///
    /// Used for both path-based (plain) and dataset-name-based (ZFS) trees;
    /// `parentTarget` holds a path or dataset name depending on context.
    private struct MountTreeNode {
        var depth: Int
        var childCount: Int
        let parentTarget: String?
    }

    // MARK: - Stored state

    private let storedHosts: [String]
    private var storedFacts: [String: HostFacts]
    private let storedLocalHost: String
    /// Mount targets collapsed by the operator — absent from this set means expanded.
    ///
    /// Survives `update(facts:)` exactly as `FieldOutline`'s `expandedDatasets`
    /// survives its `update(facts:)`. Stale keys are silently ignored on rebuild.
    private var collapsedMounts: Set<MountKey>
    /// Pool names collapsed by the operator — absent means expanded.
    ///
    /// Keyed by `PoolKey` so a pool name can never collide with a mount target.
    private var collapsedPools: Set<PoolKey>

    /// One section per host, in the order `hosts` arrived.
    ///
    /// Rebuilt after every `update(facts:)`, `toggleMount(host:target:)`, or
    /// `togglePool(host:pool:)` call. Only visible lines appear.
    public private(set) var sections: [HostSection]

    // MARK: - Init

    /// Builds a map from an ordered host list and a fact snapshot.
    ///
    /// `hosts` arrives already ordered (local first, then config order).
    /// The local host's section is bare — Field memory is remote memory.
    /// No mounts or pools are collapsed on init; all arrive visible.
    public init(hosts: [String], facts: [String: HostFacts], localHost: String) {
        storedHosts = hosts
        storedFacts = facts
        storedLocalHost = localHost
        collapsedMounts = []
        collapsedPools = []
        sections = Self.buildSections(
            hosts: hosts,
            facts: facts,
            localHost: localHost,
            collapsed: [],
            collapsedPools: [])
    }

    // MARK: - Update

    /// Rebuilds sections from a new fact snapshot, preserving fold state.
    ///
    /// Mirrors `FieldOutline.update(facts:)` — collapsed mounts and pools
    /// survive the update exactly as expanded datasets survive it there.
    /// Newly appearing mounts and pools arrive expanded.
    public mutating func update(facts newFacts: [String: HostFacts]) {
        storedFacts = newFacts
        rebuild()
    }

    // MARK: - Fold control

    /// Toggles the collapsed state of a mount row.
    ///
    /// No-op when `target` has no children (`childCount == 0`) or when `host`
    /// or `target` are not found in the current sections. When collapsed, the
    /// row's entire subtree disappears from `sections`; when expanded, the
    /// subtree reappears.
    public mutating func toggleMount(host: String, target: String) {
        guard let section = sections.first(where: { $0.alias == host }) else { return }
        let allRows = section.mounts.compactMap { line -> MountRow? in
            guard case .mount(let row) = line else { return nil }
            return row
        }
        let mountRow = allRows.first { $0.target == target }
        guard let mount = mountRow else { return }
        guard mount.childCount > 0 else { return }
        let key = MountKey(host: host, target: target)
        if collapsedMounts.contains(key) {
            collapsedMounts.remove(key)
        } else {
            collapsedMounts.insert(key)
        }
        rebuild()
    }

    /// Toggles the collapsed state of a pool.
    ///
    /// No-op when `pool` is not found among the current section's pool lines.
    /// When collapsed, all of the pool's mount rows disappear; the pool header
    /// remains visible with `expanded == false`. When expanded, the subtree
    /// reappears.
    public mutating func togglePool(host: String, pool: String) {
        guard let section = sections.first(where: { $0.alias == host }) else { return }
        let poolExists = section.mounts.contains { line in
            guard case .pool(let pl) = line else { return false }
            return pl.name == pool
        }
        guard poolExists else { return }
        let key = PoolKey(host: host, pool: pool)
        if collapsedPools.contains(key) {
            collapsedPools.remove(key)
        } else {
            collapsedPools.insert(key)
        }
        rebuild()
    }

    // MARK: - Private

    private mutating func rebuild() {
        sections = Self.buildSections(
            hosts: storedHosts,
            facts: storedFacts,
            localHost: storedLocalHost,
            collapsed: collapsedMounts,
            collapsedPools: collapsedPools)
    }
}

// MARK: - Build helpers

extension HostMap {
    private static func buildSections(
        hosts: [String],
        facts: [String: HostFacts],
        localHost: String,
        collapsed: Set<MountKey>,
        collapsedPools: Set<PoolKey>
    ) -> [HostSection] {
        hosts.map { host in
            if host == localHost {
                return localSection(alias: host)
            }
            return remoteSection(
                alias: host,
                hostFacts: facts[host],
                collapsed: collapsed,
                collapsedPools: collapsedPools)
        }
    }

    private static func localSection(alias: String) -> HostSection {
        HostSection(
            alias: alias,
            isLocal: true,
            visited: false,
            reachability: nil,
            rememberedAt: nil,
            flavor: nil,
            hasZFS: false,
            hasRsync: false,
            mounts: [],
            systemMountCount: 0,
            mountsRememberedAt: nil)
    }

    private static func remoteSection(
        alias: String,
        hostFacts: HostFacts?,
        collapsed: Set<MountKey>,
        collapsedPools: Set<PoolKey>
    ) -> HostSection {
        let allMounts = hostFacts?.mounts?.value ?? []
        let datasets = hostFacts?.zfsTopology?.value ?? []
        let datasetMountpoints = ZFSTopology.mountpointSet(in: datasets)
        let (lines, systemCount) = mountRows(
            from: allMounts,
            datasetMountpoints: datasetMountpoints,
            host: alias,
            collapsed: collapsed,
            collapsedPools: collapsedPools)
        return HostSection(
            alias: alias,
            isLocal: false,
            visited: hostFacts != nil,
            reachability: hostFacts?.reachability?.value,
            rememberedAt: hostFacts?.reachability?.discoveredAt,
            flavor: hostFacts?.capability?.value.flavor,
            hasZFS: hostFacts?.capability?.value.zfs != nil,
            hasRsync: hostFacts?.capability?.value.rsync != nil,
            mounts: lines,
            systemMountCount: systemCount,
            mountsRememberedAt: hostFacts?.mounts?.discoveredAt)
    }

    /// Builds the ordered `[MountLine]` for one host and returns the system count.
    ///
    /// ZFS mounts (fstype `zfs`) group under pool header lines, sorted by pool
    /// name; within each pool they nest by dataset name. All other storage and
    /// network mounts follow as plain ground, nested by mountpoint path among
    /// themselves only — a plain mount never parents into a pool and vice versa.
    private static func mountRows(
        from allMounts: [Mount],
        datasetMountpoints: Set<String>,
        host: String,
        collapsed: Set<MountKey>,
        collapsedPools: Set<PoolKey>
    ) -> ([MountLine], Int) {
        var zfsMounts: [(mount: Mount, isDataset: Bool)] = []
        var plainMounts: [(mount: Mount, isDataset: Bool)] = []
        var systemCount = 0
        for mount in allMounts {
            let kind = MountTable.classify(fstype: mount.fstype)
            if kind == .system {
                systemCount += 1
            } else if mount.fstype == "zfs" {
                zfsMounts.append((mount, datasetMountpoints.contains(normalize(mount.target))))
            } else {
                plainMounts.append((mount, datasetMountpoints.contains(normalize(mount.target))))
            }
        }
        let lines =
            poolSectionLines(from: zfsMounts, host: host, collapsed: collapsed, collapsedPools: collapsedPools)
            + plainGroundLines(from: plainMounts, host: host, collapsed: collapsed)
        return (lines, systemCount)
    }

    /// Builds pool header + dataset-name-nested mount rows for all ZFS mounts.
    private static func poolSectionLines(
        from zfsMounts: [(mount: Mount, isDataset: Bool)],
        host: String,
        collapsed: Set<MountKey>,
        collapsedPools: Set<PoolKey>
    ) -> [MountLine] {
        var poolGroups: [String: [(mount: Mount, isDataset: Bool)]] = [:]
        for item in zfsMounts {
            let pool = poolName(from: item.mount.source)
            poolGroups[pool, default: []].append(item)
        }
        var lines: [MountLine] = []
        for pool in poolGroups.keys.sorted() {
            guard let items = poolGroups[pool] else { continue }
            lines += poolLines(
                pool: pool, items: items, host: host, collapsed: collapsed, collapsedPools: collapsedPools)
        }
        return lines
    }

    /// Builds the pool header line and its (optionally hidden) dataset mount rows.
    private static func poolLines(
        pool: String,
        items: [(mount: Mount, isDataset: Bool)],
        host: String,
        collapsed: Set<MountKey>,
        collapsedPools: Set<PoolKey>
    ) -> [MountLine] {
        let isCollapsedPool = collapsedPools.contains(PoolKey(host: host, pool: pool))
        let datasetNames = Set(items.map { $0.mount.source })
        let datasetTree = computeDatasetTreeInfo(for: datasetNames)
        let orderedDatasets = depthFirstDatasets(in: datasetNames, tree: datasetTree)
        var mountByDataset: [String: (mount: Mount, isDataset: Bool)] = [:]
        for item in items { mountByDataset[item.mount.source] = item }
        var lines: [MountLine] = [
            .pool(PoolLine(name: pool, visibleMountCount: items.count, expanded: !isCollapsedPool))
        ]
        guard !isCollapsedPool else { return lines }
        for dataset in orderedDatasets {
            guard
                isDatasetMountVisible(
                    dataset: dataset,
                    host: host,
                    mountByDataset: mountByDataset,
                    datasetTree: datasetTree,
                    collapsed: collapsed
                )
            else { continue }
            let info = datasetTree[dataset] ?? MountTreeNode(depth: 0, childCount: 0, parentTarget: nil)
            for item in items where item.mount.source == dataset {
                let isMountCollapsed = collapsed.contains(MountKey(host: host, target: item.mount.target))
                lines.append(
                    .mount(
                        MountRow(
                            target: item.mount.target,
                            fstype: item.mount.fstype,
                            source: item.mount.source,
                            readOnly: item.mount.readOnly,
                            kind: MountTable.classify(fstype: item.mount.fstype),
                            isDatasetMountpoint: item.isDataset,
                            depth: info.depth + 1,
                            childCount: info.childCount,
                            expanded: info.childCount > 0 && !isMountCollapsed)))
            }
        }
        return lines
    }

    /// Builds path-nested mount rows for plain (non-ZFS) mounts only.
    private static func plainGroundLines(
        from plainMounts: [(mount: Mount, isDataset: Bool)],
        host: String,
        collapsed: Set<MountKey>
    ) -> [MountLine] {
        let plainTargetSet = Set(plainMounts.map { $0.mount.target })
        let plainTree = computeTreeInfo(for: plainTargetSet)
        let plainOrdered = depthFirstTargets(in: plainTargetSet, tree: plainTree)
        var lines: [MountLine] = []
        for target in plainOrdered {
            guard isMountVisible(target: target, host: host, tree: plainTree, collapsed: collapsed) else { continue }
            let info = plainTree[target] ?? MountTreeNode(depth: 0, childCount: 0, parentTarget: nil)
            let isCollapsed = collapsed.contains(MountKey(host: host, target: target))
            for item in plainMounts where item.mount.target == target {
                lines.append(
                    .mount(
                        MountRow(
                            target: item.mount.target,
                            fstype: item.mount.fstype,
                            source: item.mount.source,
                            readOnly: item.mount.readOnly,
                            kind: MountTable.classify(fstype: item.mount.fstype),
                            isDatasetMountpoint: item.isDataset,
                            depth: info.depth,
                            childCount: info.childCount,
                            expanded: info.childCount > 0 && !isCollapsed)))
            }
        }
        return lines
    }
}

// MARK: - Tree helpers

extension HostMap {
    /// The first `/`-segment of a ZFS dataset source — the pool name.
    ///
    /// `rpool/ROOT/pve-1` → `rpool`. `tank` → `tank`.
    private static func poolName(from source: String) -> String {
        source.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? source
    }

    // MARK: Dataset-name tree (ZFS pool mounts)

    private static func computeDatasetTreeInfo(for names: Set<String>) -> [String: MountTreeNode] {
        var result: [String: MountTreeNode] = [:]
        for name in names {
            let parent = directDatasetParent(of: name, in: names)
            let depth = computeDatasetDepth(of: name, in: names)
            result[name] = MountTreeNode(depth: depth, childCount: 0, parentTarget: parent)
        }
        for name in names {
            if let parent = result[name]?.parentTarget {
                result[parent]?.childCount += 1
            }
        }
        return result
    }

    /// The longest proper dataset-name prefix of `name` present in `names`, or nil.
    ///
    /// Dataset names use `/` as the segment separator (`pool/dataset/sub`).
    /// Parent = longest prefix at a segment boundary that IS in the set.
    private static func directDatasetParent(of name: String, in names: Set<String>) -> String? {
        var components = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return nil }
        components.removeLast()
        while !components.isEmpty {
            let candidate = components.joined(separator: "/")
            if names.contains(candidate) { return candidate }
            components.removeLast()
        }
        return nil
    }

    private static func computeDatasetDepth(of name: String, in names: Set<String>) -> Int {
        var components = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return 0 }
        var depth = 0
        components.removeLast()
        while !components.isEmpty {
            let candidate = components.joined(separator: "/")
            if names.contains(candidate) { depth += 1 }
            components.removeLast()
        }
        return depth
    }

    private static func depthFirstDatasets(in names: Set<String>, tree: [String: MountTreeNode]) -> [String] {
        datasetChildren(of: nil, in: names, tree: tree)
    }

    private static func datasetChildren(
        of parent: String?,
        in names: Set<String>,
        tree: [String: MountTreeNode]
    ) -> [String] {
        let children = names.filter { tree[$0]?.parentTarget == parent }.sorted()
        return children.flatMap { [$0] + datasetChildren(of: $0, in: names, tree: tree) }
    }

    /// True when a pool mount's dataset-name ancestry is unobstructed.
    ///
    /// Recursively checks that each ancestor dataset's mount is not collapsed.
    /// The pool-level collapse is checked at the call site before iterating.
    private static func isDatasetMountVisible(
        dataset: String,
        host: String,
        mountByDataset: [String: (mount: Mount, isDataset: Bool)],
        datasetTree: [String: MountTreeNode],
        collapsed: Set<MountKey>
    ) -> Bool {
        guard let info = datasetTree[dataset] else { return false }
        guard let parentDataset = info.parentTarget else { return true }
        guard let parentItem = mountByDataset[parentDataset] else { return true }
        guard !collapsed.contains(MountKey(host: host, target: parentItem.mount.target)) else { return false }
        return isDatasetMountVisible(
            dataset: parentDataset,
            host: host,
            mountByDataset: mountByDataset,
            datasetTree: datasetTree,
            collapsed: collapsed)
    }

    // MARK: Path tree (plain mounts)

    private static func computeTreeInfo(for targetSet: Set<String>) -> [String: MountTreeNode] {
        var result: [String: MountTreeNode] = [:]
        for target in targetSet {
            let parent = directMountParent(of: target, in: targetSet)
            let depth = computeMountDepth(of: target, in: targetSet)
            result[target] = MountTreeNode(depth: depth, childCount: 0, parentTarget: parent)
        }
        for target in targetSet {
            if let parent = result[target]?.parentTarget {
                result[parent]?.childCount += 1
            }
        }
        return result
    }

    private static func depthFirstTargets(in targetSet: Set<String>, tree: [String: MountTreeNode]) -> [String] {
        childTargets(of: nil, in: targetSet, tree: tree)
    }

    private static func childTargets(
        of parent: String?,
        in targetSet: Set<String>,
        tree: [String: MountTreeNode]
    ) -> [String] {
        let children = targetSet.filter { tree[$0]?.parentTarget == parent }.sorted()
        return children.flatMap { [$0] + childTargets(of: $0, in: targetSet, tree: tree) }
    }

    /// The longest path-prefix of `path` at a component boundary that is
    /// present in `targetSet`, or nil when no such ancestor exists.
    ///
    /// Component boundary means the prefix matches exactly at a `/` separator:
    /// `/opt/services` parents `/opt/services/baserow` but not `/opt/servicesX`.
    /// `/` parents any single-component path when it is in the rendered set.
    private static func directMountParent(of path: String, in targetSet: Set<String>) -> String? {
        guard path != "/" else { return nil }
        var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return nil }
        components.removeLast()
        while !components.isEmpty {
            let candidate = "/" + components.joined(separator: "/")
            if targetSet.contains(candidate) { return candidate }
            components.removeLast()
        }
        return targetSet.contains("/") ? "/" : nil
    }

    private static func computeMountDepth(of path: String, in targetSet: Set<String>) -> Int {
        guard path != "/" else { return 0 }
        var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return 0 }
        var depth = 0
        components.removeLast()
        while !components.isEmpty {
            let candidate = "/" + components.joined(separator: "/")
            if targetSet.contains(candidate) { depth += 1 }
            components.removeLast()
        }
        if targetSet.contains("/") { depth += 1 }
        return depth
    }

    /// True when `target` should appear in the visible plain mount list.
    ///
    /// A mount with no parent (depth 0) is always visible. A mount with a parent
    /// is visible only when that parent is not collapsed and is itself visible
    /// — the full ancestor chain must be unobstructed.
    private static func isMountVisible(
        target: String,
        host: String,
        tree: [String: MountTreeNode],
        collapsed: Set<MountKey>
    ) -> Bool {
        guard let info = tree[target] else { return false }
        guard let parentTarget = info.parentTarget else { return true }
        guard !collapsed.contains(MountKey(host: host, target: parentTarget)) else { return false }
        return isMountVisible(target: parentTarget, host: host, tree: tree, collapsed: collapsed)
    }

    private static func normalize(_ path: String) -> String {
        guard path != "/" else { return "/" }
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
