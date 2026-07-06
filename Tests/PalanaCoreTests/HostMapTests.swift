// HostMap's unit battery — sections order and fact projection, mount
// classification and sort, dataset correlation, and edge cases. No wire
// contact of any kind.

import Foundation
import Testing

@testable import PalanaCore

@Suite("HostMap")
struct HostMapTests {
    private static let stamp = Date(timeIntervalSince1970: 1_751_500_800)

    // Fixtures: a host with ZFS and mounts, a host without, an unvisited host.
    //
    // jodo: Linux, zfs at /tank, mounts include /, /home, /nfs/share (network),
    //        /proc (system), /sys (system), /tank (zfs = storage + dataset mountpoint)
    // mac:  BSD, no zfs, no mounts recorded
    // local: the operator's machine — bare section, no facts ever

    private static let jodoDatasets = [
        ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)
    ]

    private static let jodoMounts: [Mount] = [
        Mount(source: "/dev/sda1", target: "/", fstype: "ext4", readOnly: false),
        Mount(source: "/dev/sda2", target: "/home", fstype: "ext4", readOnly: false),
        Mount(source: "server:/share", target: "/nfs/share", fstype: "nfs", readOnly: false),
        Mount(source: "proc", target: "/proc", fstype: "proc", readOnly: false),
        Mount(source: "sysfs", target: "/sys", fstype: "sysfs", readOnly: false),
        Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
    ]

    private static let capability = HostCapability(
        kernel: "Linux",
        flavor: .gnu,
        zfs: "zfs-2.2.2",
        rsync: "rsync  version 3.2.7"
    )

    private static func jodoFacts() -> HostFacts {
        HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp),
            capability: Dated(value: capability, discoveredAt: stamp),
            zfsTopology: Dated(value: jodoDatasets, discoveredAt: stamp),
            mounts: Dated(value: jodoMounts, discoveredAt: stamp)
        )
    }

    private static func macFacts() -> HostFacts {
        let bsdCap = HostCapability(kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: nil)
        return HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp),
            capability: Dated(value: bsdCap, discoveredAt: stamp)
        )
    }

    private static func makeMap(
        hosts: [String] = ["local", "jodo", "mac", "unvisited"],
        facts: [String: HostFacts]? = nil
    ) -> HostMap {
        let allFacts = facts ?? ["jodo": jodoFacts(), "mac": macFacts()]
        return HostMap(hosts: hosts, facts: allFacts, localHost: "local")
    }

    // MARK: - Sections order and fact projection

    @Test("sections arrive in host order")
    func sectionsOrder() {
        let map = Self.makeMap()
        let aliases = map.sections.map(\.alias)
        #expect(aliases == ["local", "jodo", "mac", "unvisited"])
    }

    @Test("local section is bare — no facts, isLocal true")
    func localSectionIsBare() {
        let map = Self.makeMap()
        let local = map.sections[0]
        #expect(local.isLocal == true)
        #expect(local.visited == false)
        #expect(local.reachability == nil)
        #expect(local.rememberedAt == nil)
        #expect(local.flavor == nil)
        #expect(local.hasZFS == false)
        #expect(local.hasRsync == false)
        #expect(local.mounts.isEmpty)
        #expect(local.systemMountCount == 0)
        #expect(local.mountsRememberedAt == nil)
    }

    @Test("never-visited host produces an empty-but-present section")
    func unvisitedHostPresent() {
        let map = Self.makeMap()
        let unvisited = map.sections[3]
        #expect(unvisited.alias == "unvisited")
        #expect(unvisited.isLocal == false)
        #expect(unvisited.visited == false)
        #expect(unvisited.mounts.isEmpty)
        #expect(unvisited.systemMountCount == 0)
        #expect(unvisited.mountsRememberedAt == nil)
    }

    @Test("visited host carries reachability, flavor, zfs, rsync flags")
    func jodoFactLine() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        #expect(jodo.alias == "jodo")
        #expect(jodo.isLocal == false)
        #expect(jodo.visited == true)
        #expect(jodo.reachability == .reachable)
        #expect(jodo.rememberedAt == Self.stamp)
        #expect(jodo.flavor == .gnu)
        #expect(jodo.hasZFS == true)
        #expect(jodo.hasRsync == true)
        #expect(jodo.mountsRememberedAt == Self.stamp)
    }

    // MARK: - Mount classification and sort

    @Test("storage and network mounts render, system mounts count")
    func mountClassification() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        // jodoMounts: /(ext4-storage), /home(ext4-storage), /nfs/share(nfs-network),
        //             /proc(proc-system), /sys(sysfs-system), /tank(zfs-storage)
        // visible: /, /home, /nfs/share, /tank = 4
        // system: /proc, /sys = 2
        #expect(jodo.mounts.count == 4, "/ + /home + /nfs/share + /tank")
        #expect(jodo.systemMountCount == 2, "/proc + /sys")
        let kinds = jodo.mounts.map(\.kind)
        #expect(kinds.contains(.storage))
        #expect(kinds.contains(.network))
        #expect(!kinds.contains(.system), "system mounts do not appear in the list")
    }

    @Test("visible mounts are sorted by target")
    func mountsAreSortedByTarget() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        let targets = jodo.mounts.map(\.target)
        #expect(targets == targets.sorted(), "mounts arrive sorted by target")
    }

    @Test("sorted order: / < /home < /nfs/share < /tank")
    func mountSortOrder() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        let targets = jodo.mounts.map(\.target)
        #expect(targets == ["/", "/home", "/nfs/share", "/tank"])
    }

    // MARK: - Dataset correlation

    @Test("dataset mountpoint is marked isDatasetMountpoint")
    func datasetMountpointMarked() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        let tankRow = jodo.mounts.first { $0.target == "/tank" }
        #expect(tankRow?.isDatasetMountpoint == true, "/tank is exactly the dataset mountpoint")
    }

    @Test("non-dataset mounts are not marked isDatasetMountpoint")
    func nonDatasetMountsNotMarked() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        for row in jodo.mounts where row.target != "/tank" {
            #expect(
                row.isDatasetMountpoint == false,
                "\(row.target) should not be a dataset mountpoint"
            )
        }
    }

    @Test("host with no remembered datasets has no dataset mountpoints")
    func noDatasetsMeansNoMarks() {
        let noZfsFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: Self.stamp),
            mounts: Dated(
                value: [Mount(source: "/dev/sda1", target: "/", fstype: "ext4", readOnly: false)],
                discoveredAt: Self.stamp
            )
        )
        let map = HostMap(hosts: ["remote"], facts: ["remote": noZfsFacts], localHost: "local")
        let remote = map.sections[0]
        #expect(remote.mounts.first?.isDatasetMountpoint == false)
    }

    // MARK: - No mounts fact

    @Test("host with no mounts fact has empty mounts and zero system count")
    func noMountsFact() {
        let map = Self.makeMap()
        let mac = map.sections[2]
        #expect(mac.mounts.isEmpty)
        #expect(mac.systemMountCount == 0)
        #expect(mac.mountsRememberedAt == nil)
    }
}

// MARK: - Mount tree tests

@Suite("HostMap — mount tree")
struct HostMapMountTreeTests {
    private static let stamp = Date(timeIntervalSince1970: 1_751_500_800)

    private static func makeMap(mounts: [Mount]) -> HostMap {
        let facts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp),
            mounts: Dated(value: mounts, discoveredAt: stamp)
        )
        return HostMap(hosts: ["remote"], facts: ["remote": facts], localHost: "local")
    }

    private static func makeMapWithDatasets(mounts: [Mount], datasets: [ZFSDataset]) -> HostMap {
        let cap = HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil)
        let facts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp),
            capability: Dated(value: cap, discoveredAt: stamp),
            zfsTopology: Dated(value: datasets, discoveredAt: stamp),
            mounts: Dated(value: mounts, discoveredAt: stamp)
        )
        return HostMap(hosts: ["remote"], facts: ["remote": facts], localHost: "local")
    }

    // MARK: - Parent resolution at component boundaries

    @Test("false path prefix excluded — /palana/tank does not parent /palana/tankX")
    func falsePrefixExcluded() {
        let mounts: [Mount] = [
            Mount(source: "/dev/sda1", target: "/palana", fstype: "ext4", readOnly: false),
            Mount(source: "tank", target: "/palana/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sdb1", target: "/palana/tankX", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sdc1", target: "/palana/tank/data", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        let palana = section.mounts.first { $0.target == "/palana" }
        // /palana parents /palana/tank and /palana/tankX (not /palana/tank/data directly)
        #expect(palana?.depth == 0)
        #expect(palana?.childCount == 2, "/palana has two direct children")

        let tank = section.mounts.first { $0.target == "/palana/tank" }
        #expect(tank?.depth == 1)
        #expect(tank?.childCount == 1, "/palana/tank has one child: /palana/tank/data")

        let tankX = section.mounts.first { $0.target == "/palana/tankX" }
        // /palana/tankX's parent must be /palana, not /palana/tank (component boundary rule)
        #expect(tankX?.depth == 1, "/palana/tankX is depth 1 — child of /palana, not /palana/tank")
        #expect(tankX?.childCount == 0)

        let tankData = section.mounts.first { $0.target == "/palana/tank/data" }
        #expect(tankData?.depth == 2, "/palana/tank/data is two levels deep")
    }

    @Test("/ parents all top-level paths when rendered")
    func rootAsUniversalParent() {
        let mounts: [Mount] = [
            Mount(source: "/dev/sda1", target: "/", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/home", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda3", target: "/opt", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        let root = section.mounts.first { $0.target == "/" }
        #expect(root?.depth == 0)
        #expect(root?.childCount == 2, "/ parents /home and /opt")

        let home = section.mounts.first { $0.target == "/home" }
        #expect(home?.depth == 1)

        let opt = section.mounts.first { $0.target == "/opt" }
        #expect(opt?.depth == 1)
    }

    // MARK: - System mounts excluded from parent resolution

    @Test("system mounts are invisible to parent resolution")
    func systemMountsExcludedFromParentResolution() {
        // /sys and /sys/kernel/debug are both system — they must not act as
        // parents for rendered mounts, even when their path is a prefix.
        let mounts: [Mount] = [
            Mount(source: "sysfs", target: "/sys", fstype: "sysfs", readOnly: false),
            Mount(source: "debugfs", target: "/sys/kernel/debug", fstype: "debugfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/data", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/data/logs", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        // Only /data and /data/logs are rendered.
        #expect(section.mounts.count == 2)
        #expect(section.systemMountCount == 2)

        let data = section.mounts.first { $0.target == "/data" }
        // /sys is system and not in the rendered set — /data is a root (depth 0).
        #expect(data?.depth == 0, "/data has no rendered ancestor")
        #expect(data?.childCount == 1)

        let dataLogs = section.mounts.first { $0.target == "/data/logs" }
        #expect(dataLogs?.depth == 1, "/data/logs is a child of /data")
    }

    // MARK: - Collapse behaviour

    @Test("collapse hides entire subtree, not just direct children")
    func collapseHidesEntireSubtree() {
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/data", fstype: "ext4", readOnly: false),
            Mount(source: "srv:/share", target: "/tank/data/media", fstype: "nfs", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        #expect(map.sections[0].mounts.count == 3, "all visible initially")

        // Collapse /tank — both child and grandchild disappear.
        map.toggleMount(host: "remote", target: "/tank")
        #expect(map.sections[0].mounts.count == 1, "only /tank visible after collapse")
        #expect(map.sections[0].mounts[0].target == "/tank")
        #expect(map.sections[0].mounts[0].expanded == false)

        // Re-expand — all three return.
        map.toggleMount(host: "remote", target: "/tank")
        #expect(map.sections[0].mounts.count == 3)
        #expect(map.sections[0].mounts[0].expanded == true)
    }

    @Test("toggleMount is a no-op on childless rows")
    func toggleMountNoOpOnLeaf() {
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/data", fstype: "ext4", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // /tank/data is a leaf — toggle should not collapse it.
        map.toggleMount(host: "remote", target: "/tank/data")
        #expect(map.sections[0].mounts.count == 2, "no-op on leaf: count unchanged")
    }

    // MARK: - Fold state across rebuilds

    @Test("fold state survives update(facts:) and newly-appearing mounts arrive expanded")
    func foldStateSurvivesUpdate() {
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/data", fstype: "ext4", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)

        // Collapse /tank.
        map.toggleMount(host: "remote", target: "/tank")
        #expect(map.sections[0].mounts.count == 1)

        // Rebuild with a fresh timestamp — same mounts, simulates a reprobe.
        let stamp2 = Date(timeIntervalSince1970: 1_751_600_000)
        let updatedFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp2),
            mounts: Dated(value: mounts, discoveredAt: stamp2)
        )
        map.update(facts: ["remote": updatedFacts])
        #expect(map.sections[0].mounts.count == 1, "collapsed /tank persists after update")

        // A new sibling /logs appears — defaults expanded (depth 0, no prior collapse state).
        var expandedMounts = mounts
        expandedMounts.append(Mount(source: "/dev/sdb1", target: "/logs", fstype: "ext4", readOnly: false))
        let expandedFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp2),
            mounts: Dated(value: expandedMounts, discoveredAt: stamp2)
        )
        map.update(facts: ["remote": expandedFacts])

        // /tank still collapsed, /logs newly visible.
        #expect(map.sections[0].mounts.count == 2, "/tank (collapsed) + /logs (new, expanded)")
        let targets = Set(map.sections[0].mounts.map(\.target))
        #expect(targets.contains("/tank"))
        #expect(targets.contains("/logs"))
    }

    // MARK: - childCount correctness

    @Test("childCount counts direct children only, not grandchildren")
    func childCountDirectOnly() {
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/a", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/tank/a/x", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda3", target: "/tank/b", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        let tank = section.mounts.first { $0.target == "/tank" }
        // /tank/a/x is a grandchild of /tank, not a direct child.
        #expect(tank?.childCount == 2, "/tank has two direct children: /tank/a and /tank/b")

        let tankA = section.mounts.first { $0.target == "/tank/a" }
        #expect(tankA?.childCount == 1, "/tank/a has one direct child: /tank/a/x")

        let tankB = section.mounts.first { $0.target == "/tank/b" }
        #expect(tankB?.childCount == 0)

        let tankAX = section.mounts.first { $0.target == "/tank/a/x" }
        #expect(tankAX?.childCount == 0)
    }
}
