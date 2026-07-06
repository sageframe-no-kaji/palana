// The host map — pure display model for the floating host map panel. Builds
// ordered host sections from remembered facts; the panel renders sections and
// owns nothing. Everything that can be wrong lives here.

import Foundation

/// The host map panel's pure display model.
///
/// `hosts` arrives ordered (local first — the caller's job, as with
/// `FieldOutline`). Every section is present even when a host has never been
/// visited — the map shows the full roster. Mount rows nest by mountpoint
/// path; fold state is carried across fact updates via `update(facts:)`.
public struct HostMap: Equatable, Sendable {
    // MARK: - Nested types

    /// One row in a host's mount list — storage and network only.
    ///
    /// System mounts are counted but not rendered; see `systemMountCount`.
    /// Rows appear in depth-first tree order — children immediately follow
    /// their parent, siblings sorted by target within each parent group.
    /// Only visible rows appear; collapsed subtrees are absent.
    public struct MountRow: Equatable, Sendable {
        /// The mountpoint path.
        public let target: String
        /// Filesystem type — `ext4`, `apfs`, `nfs`, and others.
        public let fstype: String
        /// Device or remote spec.
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
        /// How many levels deep this mount sits in the rendered path tree.
        ///
        /// 0 for mounts whose path has no rendered ancestor. Increases by
        /// one for each rendered ancestor present in the path chain.
        public let depth: Int
        /// The count of direct children among the same host's rendered mounts.
        ///
        /// A mount is a direct child when its direct parent — the longest
        /// path-prefix at a component boundary present in the rendered set
        /// — equals this mount's target.
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
        /// Visible storage and network mounts, in depth-first tree order.
        ///
        /// System mounts are excluded here; their count is in `systemMountCount`.
        /// Collapsed subtrees are absent — only currently visible rows appear.
        public let mounts: [MountRow]
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

    /// Per-node information built once per host during `buildSections`.
    private struct MountTreeNode {
        var depth: Int
        var childCount: Int
        let parentTarget: String?
    }

    // MARK: - Stored state

    private let storedHosts: [String]
    private var storedFacts: [String: HostFacts]
    private let storedLocalHost: String
    /// Targets collapsed by the operator — absent from this set means expanded.
    ///
    /// Survives `update(facts:)` exactly as `FieldOutline`'s `expandedDatasets`
    /// survives its `update(facts:)`. Stale keys are silently ignored on rebuild.
    private var collapsedMounts: Set<MountKey>

    /// One section per host, in the order `hosts` arrived.
    ///
    /// Rebuilt after every `update(facts:)` or `toggleMount(host:target:)` call.
    /// Only visible mount rows appear in each section's `mounts` array.
    public private(set) var sections: [HostSection]

    // MARK: - Init

    /// Builds a map from an ordered host list and a fact snapshot.
    ///
    /// `hosts` arrives already ordered (local first, then config order).
    /// The local host's section is bare — Field memory is remote memory.
    /// No mounts are collapsed on init; all arrive visible.
    public init(hosts: [String], facts: [String: HostFacts], localHost: String) {
        storedHosts = hosts
        storedFacts = facts
        storedLocalHost = localHost
        collapsedMounts = []
        sections = Self.buildSections(
            hosts: hosts,
            facts: facts,
            localHost: localHost,
            collapsed: [])
    }

    // MARK: - Update

    /// Rebuilds sections from a new fact snapshot, preserving fold state.
    ///
    /// Mirrors `FieldOutline.update(facts:)` — collapsed mounts survive the
    /// update exactly as expanded datasets survive it there. Newly appearing
    /// mounts arrive expanded (absent from the collapsed set).
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
        guard let mount = section.mounts.first(where: { $0.target == target }) else { return }
        guard mount.childCount > 0 else { return }
        let key = MountKey(host: host, target: target)
        if collapsedMounts.contains(key) {
            collapsedMounts.remove(key)
        } else {
            collapsedMounts.insert(key)
        }
        rebuild()
    }

    // MARK: - Private

    private mutating func rebuild() {
        sections = Self.buildSections(
            hosts: storedHosts,
            facts: storedFacts,
            localHost: storedLocalHost,
            collapsed: collapsedMounts)
    }
}

// MARK: - Build helpers

extension HostMap {
    private static func buildSections(
        hosts: [String],
        facts: [String: HostFacts],
        localHost: String,
        collapsed: Set<MountKey>
    ) -> [HostSection] {
        hosts.map { host in
            if host == localHost {
                return localSection(alias: host)
            }
            return remoteSection(alias: host, hostFacts: facts[host], collapsed: collapsed)
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
        collapsed: Set<MountKey>
    ) -> HostSection {
        let allMounts = hostFacts?.mounts?.value ?? []
        let datasets = hostFacts?.zfsTopology?.value ?? []
        let datasetMountpoints = ZFSTopology.mountpointSet(in: datasets)
        let (rows, systemCount) = mountRows(
            from: allMounts,
            datasetMountpoints: datasetMountpoints,
            host: alias,
            collapsed: collapsed)
        return HostSection(
            alias: alias,
            isLocal: false,
            visited: hostFacts != nil,
            reachability: hostFacts?.reachability?.value,
            rememberedAt: hostFacts?.reachability?.discoveredAt,
            flavor: hostFacts?.capability?.value.flavor,
            hasZFS: hostFacts?.capability?.value.zfs != nil,
            hasRsync: hostFacts?.capability?.value.rsync != nil,
            mounts: rows,
            systemMountCount: systemCount,
            mountsRememberedAt: hostFacts?.mounts?.discoveredAt)
    }

    private static func mountRows(
        from allMounts: [Mount],
        datasetMountpoints: Set<String>,
        host: String,
        collapsed: Set<MountKey>
    ) -> ([MountRow], Int) {
        var rawRendered: [(mount: Mount, isDataset: Bool)] = []
        var systemCount = 0
        for mount in allMounts {
            let kind = MountTable.classify(fstype: mount.fstype)
            if kind == .system {
                systemCount += 1
            } else {
                rawRendered.append((mount, datasetMountpoints.contains(normalize(mount.target))))
            }
        }
        let targetSet = Set(rawRendered.map { $0.mount.target })
        let tree = computeTreeInfo(for: targetSet)
        let ordered = depthFirstTargets(in: targetSet, tree: tree)
        var rows: [MountRow] = []
        for target in ordered {
            guard isMountVisible(target: target, host: host, tree: tree, collapsed: collapsed)
            else { continue }
            let info = tree[target] ?? MountTreeNode(depth: 0, childCount: 0, parentTarget: nil)
            let isCollapsed = collapsed.contains(MountKey(host: host, target: target))
            for item in rawRendered where item.mount.target == target {
                rows.append(
                    MountRow(
                        target: item.mount.target,
                        fstype: item.mount.fstype,
                        source: item.mount.source,
                        readOnly: item.mount.readOnly,
                        kind: MountTable.classify(fstype: item.mount.fstype),
                        isDatasetMountpoint: item.isDataset,
                        depth: info.depth,
                        childCount: info.childCount,
                        expanded: info.childCount > 0 && !isCollapsed))
            }
        }
        return (rows, systemCount)
    }
}

// MARK: - Tree helpers

extension HostMap {
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

    /// True when `target` should appear in the visible mount list.
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
