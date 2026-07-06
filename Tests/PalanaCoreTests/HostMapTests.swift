// HostMap's unit battery — sections order and fact projection, mount
// classification and sort, dataset correlation, pool grouping, and edge
// cases. No wire contact of any kind.

import Foundation
import Testing

@testable import PalanaCore

@Suite("HostMap")
struct HostMapTests {
    private static let stamp = Date(timeIntervalSince1970: 1_751_500_800)

    // Fixtures: a host with ZFS and mounts, a host without, an unvisited host.
    //
    // jodo: Linux, zfs pool "tank" at /tank, mounts include /, /home,
    //       /nfs/share (network), /proc (system), /sys (system),
    //       /tank (zfs — pool "tank", dataset mountpoint)
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

    @Test("storage and network mounts render; system mounts count; pool line heads the zfs group")
    func mountClassification() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        // jodoMounts: /(ext4), /home(ext4), /nfs/share(nfs), /proc(proc-sys), /sys(sysfs-sys),
        //             /tank(zfs → pool "tank")
        // Lines: pool(tank) + mount(/tank) + mount(/) + mount(/home) + mount(/nfs/share) = 5
        // System: /proc, /sys = 2
        #expect(jodo.mounts.count == 5)
        #expect(jodo.systemMountCount == 2)

        // Exactly one pool line — pool "tank".
        let poolLines = jodo.mounts.compactMap { line -> HostMap.PoolLine? in
            guard case .pool(let pl) = line else { return nil }
            return pl
        }
        #expect(poolLines.count == 1)
        #expect(poolLines[0].name == "tank")

        // Four mount rows: /tank, /, /home, /nfs/share.
        let mountRows = jodo.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line else { return nil }
            return row
        }
        #expect(mountRows.count == 4)
        let kinds = mountRows.map(\.kind)
        #expect(kinds.contains(.storage))
        #expect(kinds.contains(.network))
        #expect(!kinds.contains(.system), "system mounts do not appear in the list")
    }

    @Test("pool sections sort before plain ground")
    func mountsAreSortedByTarget() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        // First line must be a pool; the first plain mount must come after.
        guard case .pool = jodo.mounts[0] else {
            Issue.record("first line should be a pool header")
            return
        }
        // The last pool-related line (pool mount /tank at index 1) precedes the
        // first plain mount (/ at index 2).
        guard case .mount(let tankMount) = jodo.mounts[1] else {
            Issue.record("second line should be the pool mount /tank")
            return
        }
        #expect(tankMount.fstype == "zfs")
        guard case .mount(let firstPlain) = jodo.mounts[2] else {
            Issue.record("third line should be the first plain mount")
            return
        }
        #expect(firstPlain.fstype != "zfs", "plain ground follows pool content")
    }

    @Test("pool comes first, then pool mounts, then plain ground depth-first")
    func mountSortOrder() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        // [pool(tank), mount(/tank), mount(/), mount(/home), mount(/nfs/share)]
        guard case .pool(let poolLine) = jodo.mounts[0] else {
            Issue.record("expected pool(tank) at index 0")
            return
        }
        #expect(poolLine.name == "tank")

        guard case .mount(let tankMount) = jodo.mounts[1] else {
            Issue.record("expected mount(/tank) at index 1")
            return
        }
        #expect(tankMount.target == "/tank")

        guard case .mount(let rootMount) = jodo.mounts[2] else {
            Issue.record("expected mount(/) at index 2")
            return
        }
        #expect(rootMount.target == "/")

        guard case .mount(let homeMount) = jodo.mounts[3] else {
            Issue.record("expected mount(/home) at index 3")
            return
        }
        #expect(homeMount.target == "/home")

        guard case .mount(let nfsMount) = jodo.mounts[4] else {
            Issue.record("expected mount(/nfs/share) at index 4")
            return
        }
        #expect(nfsMount.target == "/nfs/share")
    }

    // MARK: - Dataset correlation

    @Test("dataset mountpoint is marked isDatasetMountpoint")
    func datasetMountpointMarked() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        let tankRow = jodo.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/tank" else { return nil }
            return row
        }.first
        #expect(tankRow?.isDatasetMountpoint == true, "/tank is exactly the dataset mountpoint")
    }

    @Test("non-dataset mounts are not marked isDatasetMountpoint")
    func nonDatasetMountsNotMarked() {
        let map = Self.makeMap()
        let jodo = map.sections[1]
        for line in jodo.mounts {
            guard case .mount(let row) = line, row.target != "/tank" else { continue }
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
        let mountRow = remote.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line else { return nil }
            return row
        }.first
        #expect(mountRow?.isDatasetMountpoint == false)
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

// MARK: - Mount tree tests (plain ground)

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

    // MARK: - Parent resolution at component boundaries (plain ground)

    @Test("false path prefix excluded — plain mounts respect component boundaries")
    func falsePrefixExcluded() {
        // /palana/tank (zfs) goes to pool "tank"; the rest are plain ground.
        let mounts: [Mount] = [
            Mount(source: "/dev/sda1", target: "/palana", fstype: "ext4", readOnly: false),
            Mount(source: "tank", target: "/palana/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sdb1", target: "/palana/tankX", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sdc1", target: "/palana/tank/data", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        // Pool "tank" has one mount (/palana/tank).
        guard case .pool(let pool) = section.mounts[0] else {
            Issue.record("expected pool header at index 0")
            return
        }
        #expect(pool.name == "tank")
        #expect(pool.visibleMountCount == 1)

        // /palana/tank is the pool mount at depth 1.
        let tankMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/palana/tank" else { return nil }
            return row
        }.first
        #expect(tankMount?.depth == 1)
        #expect(tankMount?.childCount == 0, "/palana/tank has no dataset children in pool \"tank\"")

        // Plain ground: /palana (depth 0), /palana/tank/data (depth 1), /palana/tankX (depth 1).
        // /palana/tank is NOT in the plain set, so /palana/tank/data parents to /palana.
        let palana = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/palana" else { return nil }
            return row
        }.first
        #expect(palana?.depth == 0)
        #expect(palana?.childCount == 2, "/palana has two plain children: /palana/tank/data and /palana/tankX")

        let tankX = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/palana/tankX" else { return nil }
            return row
        }.first
        #expect(tankX?.depth == 1, "/palana/tankX is a plain child of /palana — component boundary rule")
        #expect(tankX?.childCount == 0)

        let tankData = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/palana/tank/data" else { return nil }
            return row
        }.first
        #expect(tankData?.depth == 1, "/palana/tank/data parents to /palana (its plain ancestor)")
    }

    @Test("/ parents all top-level paths when rendered in plain ground")
    func rootAsUniversalParent() {
        let mounts: [Mount] = [
            Mount(source: "/dev/sda1", target: "/", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/home", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda3", target: "/opt", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        let root = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/" else { return nil }
            return row
        }.first
        #expect(root?.depth == 0)
        #expect(root?.childCount == 2, "/ parents /home and /opt")

        let home = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/home" else { return nil }
            return row
        }.first
        #expect(home?.depth == 1)

        let opt = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/opt" else { return nil }
            return row
        }.first
        #expect(opt?.depth == 1)
    }

    // MARK: - System mounts excluded from parent resolution

    @Test("system mounts are invisible to plain parent resolution")
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

        let data = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/data" else { return nil }
            return row
        }.first
        // /sys is system — /data is a plain root (depth 0).
        #expect(data?.depth == 0, "/data has no rendered ancestor")
        #expect(data?.childCount == 1)

        let dataLogs = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/data/logs" else { return nil }
            return row
        }.first
        #expect(dataLogs?.depth == 1, "/data/logs is a child of /data")
    }

    // MARK: - Collapse behaviour

    @Test("collapsing a pool hides pool mounts; plain ground stays visible")
    func collapseHidesEntireSubtree() {
        // /tank is ZFS (pool "tank"); /tank/data and /tank/data/media are plain.
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/data", fstype: "ext4", readOnly: false),
            Mount(source: "srv:/share", target: "/tank/data/media", fstype: "nfs", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // pool(tank) + mount(/tank) + mount(/tank/data) + mount(/tank/data/media) = 4
        #expect(map.sections[0].mounts.count == 4, "all visible initially")

        // Collapse pool "tank" — pool header stays, pool mount disappears.
        // Plain ground (/tank/data and /tank/data/media) is unaffected.
        map.togglePool(host: "remote", pool: "tank")
        // pool(collapsed) + mount(/tank/data) + mount(/tank/data/media) = 3
        #expect(map.sections[0].mounts.count == 3, "pool mount hidden; plain ground unchanged")
        guard case .pool(let poolLine) = map.sections[0].mounts[0] else {
            Issue.record("expected pool header after collapse")
            return
        }
        #expect(!poolLine.expanded)

        // Re-expand — pool mount returns.
        map.togglePool(host: "remote", pool: "tank")
        #expect(map.sections[0].mounts.count == 4, "all visible after re-expand")

        // Collapsing a plain parent hides its plain subtree.
        map.toggleMount(host: "remote", target: "/tank/data")
        // pool(tank) + mount(/tank) + mount(/tank/data, collapsed) = 3
        #expect(map.sections[0].mounts.count == 3, "/tank/data collapsed, /tank/data/media hidden")
        map.toggleMount(host: "remote", target: "/tank/data")
        #expect(map.sections[0].mounts.count == 4, "/tank/data/media returns after re-expand")
    }

    @Test("toggleMount is a no-op on childless rows")
    func toggleMountNoOpOnLeaf() {
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/data", fstype: "ext4", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // pool(tank) + mount(/tank, childCount:0) + mount(/tank/data, childCount:0) = 3
        #expect(map.sections[0].mounts.count == 3)

        // /tank/data is a plain leaf — toggle should not collapse it.
        map.toggleMount(host: "remote", target: "/tank/data")
        #expect(map.sections[0].mounts.count == 3, "no-op on plain leaf: count unchanged")

        // /tank is a pool mount with no dataset children — toggle is also a no-op.
        map.toggleMount(host: "remote", target: "/tank")
        #expect(map.sections[0].mounts.count == 3, "no-op on pool mount with no dataset children")
    }

    // MARK: - Fold state across rebuilds

    @Test("mount fold state survives update(facts:) and newly-appearing mounts arrive expanded")
    func foldStateSurvivesUpdate() {
        // Use a pure plain scenario so toggleMount is exercised without pools.
        let mounts: [Mount] = [
            Mount(source: "/dev/sda1", target: "/data", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/data/logs", fstype: "ext4", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // mount(/data, childCount:1) + mount(/data/logs) = 2
        #expect(map.sections[0].mounts.count == 2)

        // Collapse /data.
        map.toggleMount(host: "remote", target: "/data")
        #expect(map.sections[0].mounts.count == 1, "/data collapsed, /data/logs hidden")

        // Rebuild with a fresh timestamp — same mounts, simulates a reprobe.
        let stamp2 = Date(timeIntervalSince1970: 1_751_600_000)
        let updatedFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp2),
            mounts: Dated(value: mounts, discoveredAt: stamp2)
        )
        map.update(facts: ["remote": updatedFacts])
        #expect(map.sections[0].mounts.count == 1, "collapsed /data persists after update")

        // A new sibling /logs appears — defaults expanded (no prior collapse state).
        var expandedMounts = mounts
        expandedMounts.append(Mount(source: "/dev/sdb1", target: "/logs", fstype: "ext4", readOnly: false))
        let expandedFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp2),
            mounts: Dated(value: expandedMounts, discoveredAt: stamp2)
        )
        map.update(facts: ["remote": expandedFacts])

        // /data still collapsed, /logs newly visible.
        #expect(map.sections[0].mounts.count == 2, "/data (collapsed) + /logs (new, expanded)")
        let targets = Set(
            map.sections[0].mounts.compactMap { line -> String? in
                guard case .mount(let row) = line else { return nil }
                return row.target
            })
        #expect(targets.contains("/data"))
        #expect(targets.contains("/logs"))
    }

    // MARK: - childCount correctness

    @Test("childCount counts direct children only, not grandchildren")
    func childCountDirectOnly() {
        // /tank is ZFS (pool "tank"); /tank/a, /tank/a/x, /tank/b are plain ground.
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/a", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/tank/a/x", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda3", target: "/tank/b", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        // /tank is in pool "tank" with no dataset children.
        let tankMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/tank" else { return nil }
            return row
        }.first
        #expect(tankMount?.childCount == 0, "/tank is a pool mount with no dataset children")

        // /tank is not in the plain set, so /tank/a and /tank/b are plain roots (depth 0).
        let tankA = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/tank/a" else { return nil }
            return row
        }.first
        #expect(tankA?.depth == 0, "/tank/a is a plain root — /tank lives in the pool")
        #expect(tankA?.childCount == 1, "/tank/a has one direct child: /tank/a/x")

        let tankB = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/tank/b" else { return nil }
            return row
        }.first
        #expect(tankB?.depth == 0, "/tank/b is a plain root")
        #expect(tankB?.childCount == 0)

        let tankAX = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/tank/a/x" else { return nil }
            return row
        }.first
        #expect(tankAX?.childCount == 0)
        #expect(tankAX?.depth == 1)
    }
}
