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
