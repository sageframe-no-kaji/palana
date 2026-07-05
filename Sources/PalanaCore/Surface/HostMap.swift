// The host map — pure display model for the floating host map panel. Builds
// ordered host sections from remembered facts; the panel renders sections and
// owns nothing. Everything that can be wrong lives here.

import Foundation

/// The host map panel's pure display model.
///
/// `hosts` arrives ordered (local first — the caller's job, as with
/// `FieldOutline`). Every section is present even when a host has never been
/// visited — the map shows the full roster.
public struct HostMap: Equatable, Sendable {
    /// One row in a host's mount list — storage and network only.
    ///
    /// System mounts are counted but not rendered; see `systemMountCount`.
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
        /// Storage and network mounts, sorted by target.
        ///
        /// System mounts are excluded here; their count is in `systemMountCount`.
        public let mounts: [MountRow]
        /// The number of system mounts the classifier excluded from `mounts`.
        ///
        /// The count line, never silent — the surface renders it as a quiet
        /// summary so the operator sees what was hidden.
        public let systemMountCount: Int
        /// When the mounts fact was recorded — nil when never read.
        public let mountsRememberedAt: Date?
    }

    /// One section per host, in the order `hosts` arrived.
    public let sections: [HostSection]

    /// Builds a map from an ordered host list and a fact snapshot.
    ///
    /// `hosts` arrives already ordered (local first, then config order).
    /// The local host's section is bare — the Field's memory is remote
    /// memory; growing local discovery is out of this ho's scope.
    public init(hosts: [String], facts: [String: HostFacts], localHost: String) {
        sections = hosts.map { host in
            guard host != localHost else {
                return HostSection(
                    alias: host,
                    isLocal: true,
                    visited: false,
                    reachability: nil,
                    rememberedAt: nil,
                    flavor: nil,
                    hasZFS: false,
                    hasRsync: false,
                    mounts: [],
                    systemMountCount: 0,
                    mountsRememberedAt: nil
                )
            }
            let hostFacts = facts[host]
            let allMounts = hostFacts?.mounts?.value ?? []
            let datasets = hostFacts?.zfsTopology?.value ?? []
            let datasetMountpoints = ZFSTopology.mountpointSet(in: datasets)
            var visibleMounts: [MountRow] = []
            var systemCount = 0
            for mount in allMounts {
                let kind = MountTable.classify(fstype: mount.fstype)
                if kind == .system {
                    systemCount += 1
                } else {
                    let normalizedTarget = Self.normalize(mount.target)
                    visibleMounts.append(
                        MountRow(
                            target: mount.target,
                            fstype: mount.fstype,
                            source: mount.source,
                            readOnly: mount.readOnly,
                            kind: kind,
                            isDatasetMountpoint: datasetMountpoints.contains(normalizedTarget)
                        ))
                }
            }
            visibleMounts.sort { $0.target < $1.target }
            return HostSection(
                alias: host,
                isLocal: false,
                visited: hostFacts != nil,
                reachability: hostFacts?.reachability?.value,
                rememberedAt: hostFacts?.reachability?.discoveredAt,
                flavor: hostFacts?.capability?.value.flavor,
                hasZFS: hostFacts?.capability?.value.zfs != nil,
                hasRsync: hostFacts?.capability?.value.rsync != nil,
                mounts: visibleMounts,
                systemMountCount: systemCount,
                mountsRememberedAt: hostFacts?.mounts?.discoveredAt
            )
        }
    }

    // MARK: - Private helpers

    private static func normalize(_ path: String) -> String {
        guard path != "/" else { return "/" }
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
