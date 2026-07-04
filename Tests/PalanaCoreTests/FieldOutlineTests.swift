// FieldOutline battery — line building, expansion, cursor, pointing, update,
// and age formatting. All pure; no wire, no fixtures. Each suite is one
// concern, each test pins one claim.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Shared fixtures

private let epoch = Date(timeIntervalSince1970: 0)

private func makeCapability(
    flavor: UserlandFlavor,
    zfsVersion: String? = nil,
    rsyncVersion: String? = "rsync 3.2.7"
) -> HostCapability {
    HostCapability(
        kernel: "Linux",
        flavor: flavor,
        zfs: zfsVersion,
        rsync: rsyncVersion
    )
}

private func makeFacts(
    reachable: Bool = true,
    flavor: UserlandFlavor = .gnu,
    zfsVersion: String? = nil,
    rsyncVersion: String? = "rsync 3.2.7",
    datasets: [ZFSDataset] = [],
    at date: Date = epoch
) -> HostFacts {
    let cap = makeCapability(flavor: flavor, zfsVersion: zfsVersion, rsyncVersion: rsyncVersion)
    let reachValue: Reachability = reachable ? .reachable : .unreachable(detail: "refused")
    var topology: Dated<[ZFSDataset]>?
    if !datasets.isEmpty {
        topology = Dated(value: datasets, discoveredAt: date)
    }
    return HostFacts(
        reachability: Dated(value: reachValue, discoveredAt: date),
        capability: Dated(value: cap, discoveredAt: date),
        zfsTopology: topology
    )
}

// MARK: - Line building

@Suite("FieldOutline — line building")
struct FieldOutlineLineBuildingTests {
    @Test("local host row is isLocal, carries no facts")
    func localHostRow() {
        let outline = FieldOutline(hosts: ["local", "jodo"], facts: [:], localHost: "local")
        guard case .host(let hl) = outline.lines[0] else {
            Issue.record("expected host line at index 0")
            return
        }
        #expect(hl.alias == "local")
        #expect(hl.isLocal)
        #expect(!hl.visited)
        #expect(hl.reachability == nil)
        #expect(hl.rememberedAt == nil)
        #expect(hl.flavor == nil)
        #expect(!hl.hasZFS)
        #expect(!hl.hasRsync)
        #expect(!hl.expanded)
        #expect(hl.datasetCount == 0)
    }

    @Test("visited host row carries facts from the snapshot")
    func visitedHostRow() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
        ]
        let facts = makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)
        let outline = FieldOutline(hosts: ["local", "jodo"], facts: ["jodo": facts], localHost: "local")
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line at index 1")
            return
        }
        #expect(hl.alias == "jodo")
        #expect(!hl.isLocal)
        #expect(hl.visited)
        #expect(hl.reachability == .reachable)
        #expect(hl.rememberedAt == epoch)
        #expect(hl.flavor == .gnu)
        #expect(hl.hasZFS)
        #expect(hl.hasRsync)
        #expect(!hl.expanded)
        #expect(hl.datasetCount == 2)
    }

    @Test("never-visited host row appears with visited false and nil fields")
    func neverVisitedHostRow() {
        let outline = FieldOutline(hosts: ["local", "ghost"], facts: [:], localHost: "local")
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line at index 1")
            return
        }
        #expect(hl.alias == "ghost")
        #expect(!hl.visited)
        #expect(hl.reachability == nil)
        #expect(hl.flavor == nil)
        #expect(!hl.hasZFS)
        #expect(!hl.hasRsync)
        #expect(hl.datasetCount == 0)
    }

    @Test("unreachable host row carries reachability and rememberedAt")
    func unreachableHostRow() {
        let unreachFacts = HostFacts(
            reachability: Dated(value: .unreachable(detail: "refused"), discoveredAt: epoch)
        )
        let outline = FieldOutline(
            hosts: ["local", "koan"],
            facts: ["koan": unreachFacts],
            localHost: "local"
        )
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line at index 1")
            return
        }
        #expect(hl.visited)
        guard case .unreachable(let detail) = hl.reachability else {
            Issue.record("expected unreachable reachability")
            return
        }
        #expect(detail == "refused")
        #expect(hl.rememberedAt == epoch)
    }
}

// MARK: - Expansion

@Suite("FieldOutline — expansion")
struct FieldOutlineExpansionTests {
    @Test("expand shows datasets in remembered order below the host row")
    func expandShowsDatasetsInOrder() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true),
            ZFSDataset(name: "tank/legacy", mountpoint: "legacy", mounted: false),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // move to jodo at index 1
        outline.expand()
        #expect(outline.lines.count == 5)  // local + jodo + 3 datasets
        guard case .dataset(let d0) = outline.lines[2] else {
            Issue.record("expected dataset at index 2")
            return
        }
        #expect(d0.name == "tank")
        guard case .dataset(let d1) = outline.lines[3] else {
            Issue.record("expected dataset at index 3")
            return
        }
        #expect(d1.name == "tank/media")
        guard case .dataset(let d2) = outline.lines[4] else {
            Issue.record("expected dataset at index 4")
            return
        }
        #expect(d2.name == "tank/legacy")
    }

    @Test("collapse from a dataset line lands the cursor on its host row")
    func collapseFromDatasetLandsCursorOnHost() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // index 1 (jodo)
        outline.expand()  // still index 1, dataset appears at index 2
        outline.cursorDown()  // index 2 (dataset)
        #expect(outline.cursor == 2)
        outline.collapse()
        #expect(outline.lines.count == 2)
        #expect(outline.cursor == 1)
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line after collapse")
            return
        }
        #expect(hl.alias == "jodo")
        #expect(!hl.expanded)
    }

    @Test("legacy, none, and unmounted datasets have pointable false")
    func nonPointableDatasetsVariants() {
        let datasets = [
            ZFSDataset(name: "tank/mounted", mountpoint: "/tank/mounted", mounted: true),
            ZFSDataset(name: "tank/legacy", mountpoint: "legacy", mounted: false),
            ZFSDataset(name: "tank/none", mountpoint: "none", mounted: false),
            ZFSDataset(name: "tank/unmounted", mountpoint: "/tank/unmounted", mounted: false),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()
        outline.expand()
        guard case .dataset(let mounted) = outline.lines[2] else {
            Issue.record("expected dataset at index 2")
            return
        }
        #expect(mounted.pointable)
        guard case .dataset(let legacy) = outline.lines[3] else {
            Issue.record("expected dataset at index 3")
            return
        }
        #expect(!legacy.pointable)
        guard case .dataset(let none) = outline.lines[4] else {
            Issue.record("expected dataset at index 4")
            return
        }
        #expect(!none.pointable)
        guard case .dataset(let unmounted) = outline.lines[5] else {
            Issue.record("expected dataset at index 5")
            return
        }
        #expect(!unmounted.pointable)
    }

    @Test("collapse on an unexpanded host row is a no-op")
    func collapseUnexpandedIsNoop() {
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts()],
            localHost: "local"
        )
        outline.cursorDown()
        let before = outline.lines
        outline.collapse()
        #expect(outline.lines == before)
        #expect(outline.cursor == 1)
    }
}

// MARK: - Cursor

@Suite("FieldOutline — cursor")
struct FieldOutlineCursorTests {
    @Test("cursorDown clamps at the last row")
    func downClampsAtEnd() {
        var outline = FieldOutline(hosts: ["local", "jodo"], facts: [:], localHost: "local")
        outline.cursorDown()
        outline.cursorDown()
        outline.cursorDown()
        #expect(outline.cursor == 1)
    }

    @Test("cursorUp clamps at the first row")
    func upClampsAtStart() {
        var outline = FieldOutline(hosts: ["local", "jodo"], facts: [:], localHost: "local")
        outline.cursorUp()
        outline.cursorUp()
        #expect(outline.cursor == 0)
    }

    @Test("cursor moves across host and dataset lines")
    func cursorTraversesHostAndDataset() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // index 1 (jodo)
        outline.expand()  // still index 1
        outline.cursorDown()  // index 2 (tank dataset)
        #expect(outline.cursor == 2)
        guard case .dataset(let dl) = outline.lines[2] else {
            Issue.record("expected dataset at index 2")
            return
        }
        #expect(dl.name == "tank")
        outline.cursorUp()
        #expect(outline.cursor == 1)
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host at index 1")
            return
        }
        #expect(hl.alias == "jodo")
    }
}

// MARK: - moveCursor and toggleExpansion

@Suite("FieldOutline — moveCursor and toggleExpansion")
struct FieldOutlineMoveAndToggleTests {
    @Test("moveCursor(to:) lands, clamps, and no-ops on empty")
    func moveCursorClampingAndRange() {
        var outline = FieldOutline(hosts: ["local", "jodo", "chumon"], facts: [:], localHost: "local")
        outline.moveCursor(to: 2)
        #expect(outline.cursor == 2)
        outline.moveCursor(to: -5)
        #expect(outline.cursor == 0)
        outline.moveCursor(to: 100)
        #expect(outline.cursor == 2)
        var empty = FieldOutline(hosts: [], facts: [:], localHost: "local")
        empty.moveCursor(to: 0)
        #expect(empty.cursor == 0)
    }

    @Test("toggleExpansion expands then folds — l-l round-trip, cursor stays on host row")
    func toggleExpansionRoundTrip() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local")
        outline.cursorDown()  // index 1 (jodo)
        outline.toggleExpansion()
        #expect(outline.lines.count == 3)
        guard case .host(let expanded) = outline.lines[1] else {
            Issue.record("expected host line at index 1 after expand")
            return
        }
        #expect(expanded.expanded)
        #expect(outline.cursor == 1)
        outline.toggleExpansion()
        #expect(outline.lines.count == 2)
        guard case .host(let folded) = outline.lines[1] else {
            Issue.record("expected host line at index 1 after fold")
            return
        }
        #expect(!folded.expanded)
        #expect(outline.cursor == 1)
    }

    @Test("toggleExpansion is a no-op on a datasetless host and on a dataset row")
    func toggleExpansionNoops() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var noDatasets = FieldOutline(hosts: ["local", "ghost"], facts: ["ghost": makeFacts()], localHost: "local")
        noDatasets.cursorDown()
        let beforeHost = noDatasets.lines
        noDatasets.toggleExpansion()
        #expect(noDatasets.lines == beforeHost)
        var withDatasets = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local")
        withDatasets.cursorDown()
        withDatasets.expand()
        withDatasets.cursorDown()  // on the dataset row
        let beforeDataset = withDatasets.lines
        withDatasets.toggleExpansion()
        #expect(withDatasets.lines == beforeDataset)
        #expect(withDatasets.cursor == 2)
    }
}

// MARK: - Pointing

@Suite("FieldOutline — pointing")
struct FieldOutlinePointingTests {
    @Test("host row resolves to (alias, ~)")
    func hostRowPointing() {
        var outline = FieldOutline(hosts: ["local", "jodo"], facts: [:], localHost: "local")
        outline.cursorDown()
        #expect(outline.pointing() == FieldOutline.Pointing(host: "jodo", path: "~"))
    }

    @Test("local host row resolves to (localHost, ~)")
    func localHostPointing() {
        let outline = FieldOutline(hosts: ["local", "jodo"], facts: [:], localHost: "local")
        // cursor starts at 0 (local)
        #expect(outline.pointing() == FieldOutline.Pointing(host: "local", path: "~"))
    }

    @Test("mounted dataset row resolves to (host, mountpoint)")
    func mountedDatasetPointing() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // jodo
        outline.expand()
        outline.cursorDown()  // tank dataset
        #expect(outline.pointing() == FieldOutline.Pointing(host: "jodo", path: "/tank"))
    }

    @Test("unmounted dataset row resolves to nil")
    func unmountedDatasetPointingNil() {
        let datasets = [ZFSDataset(name: "tank/legacy", mountpoint: "legacy", mounted: false)]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()
        outline.expand()
        outline.cursorDown()  // legacy dataset
        #expect(outline.pointing() == nil)
    }

    @Test("empty outline resolves pointing and hostUnderCursor to nil")
    func emptyOutlineReturnsNil() {
        let outline = FieldOutline(hosts: [], facts: [:], localHost: "local")
        #expect(outline.pointing() == nil)
        #expect(outline.hostUnderCursor() == nil)
    }

    @Test("hostUnderCursor returns owning host for a dataset row")
    func hostUnderCursorOnDataset() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()
        outline.expand()
        outline.cursorDown()
        #expect(outline.hostUnderCursor() == "jodo")
    }
}

// MARK: - Update

@Suite("FieldOutline — update")
struct FieldOutlineUpdateTests {
    @Test("BSD-to-BusyBox flavor update applies in place, expansion and cursor survive")
    func updateFlavorInPlace() {
        // zencat's stale-flavor shape: was classified BSD, now BusyBox
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        let bsdCap = Dated(
            value: makeCapability(flavor: .bsd, zfsVersion: "zfs-2.2.2"),
            discoveredAt: epoch
        )
        let bsdFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: epoch),
            capability: bsdCap,
            zfsTopology: Dated(value: datasets, discoveredAt: epoch)
        )
        var outline = FieldOutline(
            hosts: ["local", "zencat"],
            facts: ["zencat": bsdFacts],
            localHost: "local"
        )
        outline.cursorDown()  // index 1 (zencat)
        outline.expand()  // still index 1
        outline.cursorDown()  // index 2 (tank dataset)
        #expect(outline.cursor == 2)

        let busyCap = Dated(
            value: makeCapability(flavor: .busybox, zfsVersion: "zfs-2.2.2"),
            discoveredAt: epoch
        )
        let busyFacts = HostFacts(
            reachability: Dated(value: .reachable, discoveredAt: epoch),
            capability: busyCap,
            zfsTopology: Dated(value: datasets, discoveredAt: epoch)
        )
        outline.update(facts: ["zencat": busyFacts])

        // Expansion survived — dataset line still present
        #expect(outline.lines.count == 3)
        // Cursor followed the dataset line
        #expect(outline.cursor == 2)
        // Host line carries the updated flavor
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line at index 1")
            return
        }
        #expect(hl.flavor == .busybox)
    }

    @Test("update clamps the cursor when its dataset line vanishes")
    func updateClampsCursorOnVanishingDataset() {
        let datasets = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "server"],
            facts: ["server": makeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // index 1 (server)
        outline.expand()  // still index 1
        outline.cursorDown()  // index 2 (tank dataset)
        #expect(outline.cursor == 2)

        // Update removes ZFS topology entirely
        outline.update(facts: ["server": makeFacts()])

        // Dataset line is gone; lines are [local, server]
        #expect(outline.lines.count == 2)
        // Cursor clamped to last valid index
        #expect(outline.cursor == 1)
    }

    @Test("update expansion persists when updated facts still carry datasets")
    func updateExpansionPersistsWhenDatasetsPresent() {
        let initial = [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)]
        var outline = FieldOutline(
            hosts: ["local", "server"],
            facts: ["server": makeFacts(zfsVersion: "zfs-2.2.2", datasets: initial)],
            localHost: "local"
        )
        outline.cursorDown()
        outline.expand()
        #expect(outline.lines.count == 3)

        // Update with an additional dataset — expansion set still contains "server"
        let more = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
        ]
        outline.update(facts: ["server": makeFacts(zfsVersion: "zfs-2.2.2", datasets: more)])

        // Both datasets appear because expansion survived
        #expect(outline.lines.count == 4)
    }
}

// MARK: - FieldAge

@Suite("FieldAge")
struct FieldAgeTests {
    @Test("under 60 seconds reads as just now")
    func under60Seconds() {
        let date = Date(timeIntervalSince1970: 1_000)
        let ref = Date(timeIntervalSince1970: 1_059)
        #expect(FieldAge.describe(date, now: ref) == "just now")
    }

    @Test("between 60 seconds and 1 hour reads as Nm ago")
    func minutesAgo() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 300)  // 5 minutes
        #expect(FieldAge.describe(date, now: ref) == "5m ago")
    }

    @Test("between 1 hour and 1 day reads as Nh ago")
    func hoursAgo() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 10_800)  // 3 hours
        #expect(FieldAge.describe(date, now: ref) == "3h ago")
    }

    @Test("one day or more reads as Nd ago")
    func daysAgo() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 172_800)  // 2 days
        #expect(FieldAge.describe(date, now: ref) == "2d ago")
    }

    @Test("a future date reads as just now")
    func futureDateReadsJustNow() {
        let date = Date(timeIntervalSince1970: 2_000)
        let ref = Date(timeIntervalSince1970: 1_000)  // ref is behind date
        #expect(FieldAge.describe(date, now: ref) == "just now")
    }

    @Test("integer truncation — 89 seconds reads as 1m ago, not 2m ago")
    func integerTruncation() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 89)
        #expect(FieldAge.describe(date, now: ref) == "1m ago")
    }
}
