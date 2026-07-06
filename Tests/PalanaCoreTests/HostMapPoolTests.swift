// HostMap pool grouping tests — ZFS mounts group under pool headers,
// nest by dataset name, fold independently, and never cross into plain ground.
// No wire contact of any kind.

import Foundation
import Testing

@testable import PalanaCore

@Suite("HostMap — pool grouping")
struct HostMapPoolTests {
    private static let stamp = Date(timeIntervalSince1970: 1_751_500_800)

    private static func makeMap(mounts: [Mount]) -> HostMap {
        let facts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp),
            mounts: Dated(value: mounts, discoveredAt: stamp)
        )
        return HostMap(hosts: ["remote"], facts: ["remote": facts], localHost: "local")
    }

    // MARK: - Pool grouping by source first segment

    @Test("zfs mounts group under their pool by source first segment")
    func poolGroupingBySource() {
        let mounts: [Mount] = [
            Mount(source: "rpool/ROOT/pve-1", target: "/", fstype: "zfs", readOnly: false),
            Mount(source: "data/vm-disks", target: "/var/lib/vz", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/boot", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        // Two pools sorted by name ("data" before "rpool"), then plain ground.
        // Lines: pool(data), mount(/var/lib/vz), pool(rpool), mount(/), mount(/boot) = 5
        #expect(section.mounts.count == 5)

        guard case .pool(let dataPool) = section.mounts[0] else {
            Issue.record("expected pool(data) at index 0")
            return
        }
        #expect(dataPool.name == "data")
        #expect(dataPool.visibleMountCount == 1)

        guard case .mount(let vzMount) = section.mounts[1] else {
            Issue.record("expected mount(/var/lib/vz) at index 1")
            return
        }
        #expect(vzMount.target == "/var/lib/vz")
        #expect(vzMount.depth == 1, "pool mount sits one level below the pool header")

        guard case .pool(let rpoolPool) = section.mounts[2] else {
            Issue.record("expected pool(rpool) at index 2")
            return
        }
        #expect(rpoolPool.name == "rpool")
        #expect(rpoolPool.visibleMountCount == 1)

        guard case .mount(let rootMount) = section.mounts[3] else {
            Issue.record("expected mount(/) at index 3")
            return
        }
        #expect(rootMount.target == "/")
        #expect(rootMount.depth == 1)

        guard case .mount(let bootMount) = section.mounts[4] else {
            Issue.record("expected mount(/boot) at index 4")
            return
        }
        #expect(bootMount.target == "/boot")
        #expect(bootMount.depth == 0, "/boot is plain ground with no plain ancestor")
    }

    // MARK: - Dataset-name nesting

    @Test("zfs mounts nest by dataset name, not target path")
    func datasetNameNesting() {
        // citadel-rex/backups → /srv/backups
        // citadel-rex/backups/borg → /srv/backups/borg  (child of backups by dataset name)
        // citadel-rex/media → /srv/media                (sibling of backups)
        let mounts: [Mount] = [
            Mount(source: "citadel-rex/backups", target: "/srv/backups", fstype: "zfs", readOnly: false),
            Mount(source: "citadel-rex/backups/borg", target: "/srv/backups/borg", fstype: "zfs", readOnly: false),
            Mount(source: "citadel-rex/media", target: "/srv/media", fstype: "zfs", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        guard case .pool(let pool) = section.mounts[0] else {
            Issue.record("expected pool(citadel-rex)")
            return
        }
        #expect(pool.name == "citadel-rex")
        #expect(pool.visibleMountCount == 3)

        // Depth-first by dataset name: backups → backups/borg → media
        let backupsMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/srv/backups" else { return nil }
            return row
        }.first
        #expect(backupsMount?.depth == 1, "backups is a pool-level dataset at depth 1")
        #expect(backupsMount?.childCount == 1, "backups parents borg by dataset name")

        let borgMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/srv/backups/borg" else { return nil }
            return row
        }.first
        #expect(borgMount?.depth == 2, "borg is nested under backups at depth 2")
        #expect(borgMount?.childCount == 0)

        let mediaMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/srv/media" else { return nil }
            return row
        }.first
        #expect(mediaMount?.depth == 1, "media is a sibling of backups at depth 1")
    }

    // MARK: - / inside its pool

    @Test("/ mounted as a zfs dataset lands inside its pool, not as a tree root")
    func rootInsidePool() {
        let mounts: [Mount] = [
            Mount(source: "rpool/ROOT/pve-1", target: "/", fstype: "zfs", readOnly: false),
            Mount(source: "tank/data", target: "/tank/data", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/boot", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        // / is inside pool "rpool" at depth 1 — it does not swallow anything.
        let rootMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/" else { return nil }
            return row
        }.first
        #expect(rootMount?.depth == 1, "/ is inside pool rpool at depth 1, not a tree root")
        #expect(rootMount?.childCount == 0, "/ does not parent other pool mounts by dataset name")

        // /boot is plain ground at depth 0 — unaffected by the ZFS /.
        let bootMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/boot" else { return nil }
            return row
        }.first
        #expect(bootMount?.depth == 0, "/boot is plain ground")
    }

    // MARK: - Plain never crosses into pools

    @Test("plain mounts never parent into pools and pool mounts never parent into plain")
    func plainAndPoolNeverCross() {
        // /data is ZFS (pool "tank"); /data/ext is plain (ext4).
        // /data/ext must NOT be a child of the ZFS /data mount.
        let mounts: [Mount] = [
            Mount(source: "tank/data", target: "/data", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/data/ext", fstype: "ext4", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        let extMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/data/ext" else { return nil }
            return row
        }.first
        #expect(extMount?.depth == 0, "/data/ext is a plain root — /data lives in the pool, not the plain tree")
    }

    // MARK: - No-zfs host unchanged

    @Test("a host with no zfs mounts renders as plain ground with no pool lines")
    func noZfsHostUnchanged() {
        let mounts: [Mount] = [
            Mount(source: "/dev/sda1", target: "/", fstype: "ext4", readOnly: false),
            Mount(source: "/dev/sda2", target: "/home", fstype: "ext4", readOnly: false),
            Mount(source: "nfs:/share", target: "/mnt/share", fstype: "nfs", readOnly: false),
        ]
        let map = Self.makeMap(mounts: mounts)
        let section = map.sections[0]

        let poolLines = section.mounts.filter {
            guard case .pool = $0 else { return false }
            return true
        }
        #expect(poolLines.isEmpty, "no pool lines for a non-ZFS host")
        // Three plain mounts — / parents /home and /mnt/share.
        #expect(section.mounts.count == 3)

        let rootMount = section.mounts.compactMap { line -> HostMap.MountRow? in
            guard case .mount(let row) = line, row.target == "/" else { return nil }
            return row
        }.first
        #expect(rootMount?.childCount == 2, "/ parents /home and /mnt/share")
        #expect(rootMount?.depth == 0)
    }

    // MARK: - Pool fold

    @Test("collapsing a pool hides all its mounts; pool header stays visible")
    func poolFoldHidesSubtree() {
        let mounts: [Mount] = [
            Mount(source: "rpool/ROOT", target: "/", fstype: "zfs", readOnly: false),
            Mount(source: "rpool/data", target: "/data", fstype: "zfs", readOnly: false),
            Mount(source: "rpool/data/logs", target: "/data/logs", fstype: "zfs", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // pool(rpool, expanded) + 3 mount rows = 4
        #expect(map.sections[0].mounts.count == 4)

        map.togglePool(host: "remote", pool: "rpool")
        // pool(rpool, collapsed) = 1
        #expect(map.sections[0].mounts.count == 1, "only pool header remains after collapse")
        guard case .pool(let collapsed) = map.sections[0].mounts[0] else {
            Issue.record("expected pool header after collapse")
            return
        }
        #expect(!collapsed.expanded)
        #expect(collapsed.visibleMountCount == 3, "count unchanged by collapse")

        map.togglePool(host: "remote", pool: "rpool")
        #expect(map.sections[0].mounts.count == 4, "all mounts return after re-expand")
        guard case .pool(let expanded) = map.sections[0].mounts[0] else {
            Issue.record("expected pool header after re-expand")
            return
        }
        #expect(expanded.expanded)
    }

    @Test("pool fold state survives update(facts:) and new plain mounts arrive expanded")
    func poolFoldSurvivesUpdate() {
        let mounts: [Mount] = [
            Mount(source: "tank", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "/dev/sda1", target: "/tank/data", fstype: "ext4", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // pool(tank) + mount(/tank) + mount(/tank/data) = 3
        #expect(map.sections[0].mounts.count == 3)

        // Collapse pool "tank".
        map.togglePool(host: "remote", pool: "tank")
        // pool(collapsed) + mount(/tank/data) = 2
        #expect(map.sections[0].mounts.count == 2, "pool mount hidden after collapse")

        // Rebuild with a fresh timestamp — same mounts, simulates a reprobe.
        let stamp2 = Date(timeIntervalSince1970: 1_751_600_000)
        let updatedFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp2),
            mounts: Dated(value: mounts, discoveredAt: stamp2)
        )
        map.update(facts: ["remote": updatedFacts])
        #expect(map.sections[0].mounts.count == 2, "collapsed pool persists after update")

        // A new plain mount /logs appears — defaults expanded.
        var expandedMounts = mounts
        expandedMounts.append(Mount(source: "/dev/sdb1", target: "/logs", fstype: "ext4", readOnly: false))
        let expandedFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: stamp2),
            mounts: Dated(value: expandedMounts, discoveredAt: stamp2)
        )
        map.update(facts: ["remote": expandedFacts])

        // pool(collapsed) + /tank/data + /logs = 3
        #expect(map.sections[0].mounts.count == 3)
        let plainTargets = map.sections[0].mounts.compactMap { line -> String? in
            guard case .mount(let row) = line else { return nil }
            return row.target
        }
        #expect(plainTargets.contains("/tank/data"))
        #expect(plainTargets.contains("/logs"))
    }

    @Test("collapsing a pool mount hides its dataset-name children")
    func poolMountCollapseHidesDatasetChildren() {
        let mounts: [Mount] = [
            Mount(source: "rpool/data", target: "/data", fstype: "zfs", readOnly: false),
            Mount(source: "rpool/data/db", target: "/data/db", fstype: "zfs", readOnly: false),
            Mount(source: "rpool/data/logs", target: "/data/logs", fstype: "zfs", readOnly: false),
        ]
        var map = Self.makeMap(mounts: mounts)
        // pool(rpool) + mount(/data, childCount:2) + mount(/data/db) + mount(/data/logs) = 4
        #expect(map.sections[0].mounts.count == 4)

        // Collapse /data — its dataset children disappear.
        map.toggleMount(host: "remote", target: "/data")
        // pool(rpool) + mount(/data, collapsed) = 2
        #expect(map.sections[0].mounts.count == 2, "/data collapsed, dataset children hidden")

        map.toggleMount(host: "remote", target: "/data")
        #expect(map.sections[0].mounts.count == 4, "dataset children return after re-expand")
    }
}
