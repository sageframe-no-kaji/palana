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
    sudoNoPassword: Bool = false,
    at date: Date = epoch
) -> HostFacts {
    let cap = makeCapability(flavor: flavor, zfsVersion: zfsVersion, rsyncVersion: rsyncVersion)
    let reachValue: Reachability = reachable ? .reachable : .unreachable(detail: "refused")
    var topology: Dated<[ZFSDataset]>?
    if !datasets.isEmpty {
        topology = Dated(value: datasets, discoveredAt: date)
    }
    // false stays unprobed (nil) — matching `datasets`' empty-means-no-fact
    // pattern; true records a fact, the only shape the F1 test needs.
    let sudoFact: Dated<Bool>? = sudoNoPassword ? Dated(value: true, discoveredAt: date) : nil
    return HostFacts(
        reachability: Dated(value: reachValue, discoveredAt: date),
        capability: Dated(value: cap, discoveredAt: date),
        zfsTopology: topology,
        sudoNoPassword: sudoFact
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
        #expect(!hl.hasSudoNoPassword)
        #expect(!hl.expanded)
        #expect(hl.datasetCount == 0)
    }

    @Test("visited host row carries facts from the snapshot")
    func visitedHostRow() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
        ]
        let facts = makeFacts(
            zfsVersion: "zfs-2.2.2", datasets: datasets, sudoNoPassword: true)
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
        #expect(hl.hasSudoNoPassword)
        #expect(!hl.expanded)
        #expect(hl.datasetCount == 2)
    }

    @Test("visited host row without a sudo probe reads hasSudoNoPassword false (ho-10.4-AT-02, F1)")
    func visitedHostRowNoSudoFact() {
        let facts = makeFacts(zfsVersion: "zfs-2.2.2")
        let outline = FieldOutline(hosts: ["local", "jodo"], facts: ["jodo": facts], localHost: "local")
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line at index 1")
            return
        }
        #expect(!hl.hasSudoNoPassword)
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
    @Test("expand host shows depth-0 datasets; expanding a dataset shows its children")
    func expandShowsDatasetsInOrder() {
        // tank is the depth-0 root; tank/media and tank/legacy are its children.
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

        // Only tank (depth 0) appears — tank/media and tank/legacy are children
        // of tank and only appear after tank itself is expanded.
        #expect(outline.lines.count == 3)  // local + jodo + tank
        guard case .dataset(let root) = outline.lines[2] else {
            Issue.record("expected dataset at index 2")
            return
        }
        #expect(root.name == "tank")
        #expect(root.depth == 0)
        #expect(root.childCount == 2)
        #expect(!root.expanded)

        // Expand tank — its two children appear below it.
        outline.cursorDown()  // move cursor from jodo(1) to tank(2)
        outline.expand()  // tank expanded
        #expect(outline.lines.count == 5)  // local + jodo + tank + tank/media + tank/legacy
        guard case .dataset(let expandedRoot) = outline.lines[2] else {
            Issue.record("expected dataset at index 2 after expansion")
            return
        }
        #expect(expandedRoot.expanded)
        guard case .dataset(let d1) = outline.lines[3] else {
            Issue.record("expected dataset at index 3")
            return
        }
        #expect(d1.name == "tank/media")
        #expect(d1.depth == 1)
        #expect(d1.childCount == 0)
        guard case .dataset(let d2) = outline.lines[4] else {
            Issue.record("expected dataset at index 4")
            return
        }
        #expect(d2.name == "tank/legacy")
        #expect(d2.depth == 1)
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
        #expect(outline.lines.count == 3)  // local + server + tank

        // Update with an additional dataset — tank now has a child.
        let more = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
        ]
        outline.update(facts: ["server": makeFacts(zfsVersion: "zfs-2.2.2", datasets: more)])

        // Host expansion survived; tank appears with childCount 1 but is itself
        // collapsed (never expanded as a dataset) — so tank/data is not yet visible.
        #expect(outline.lines.count == 3)  // local + server + tank (collapsed)
        guard case .dataset(let tankLine) = outline.lines[2] else {
            Issue.record("expected dataset at index 2")
            return
        }
        #expect(tankLine.childCount == 1)
        #expect(!tankLine.expanded)
    }
}

// MARK: - FieldAge

// FieldAgeTests moved to FieldAgeTests.swift
