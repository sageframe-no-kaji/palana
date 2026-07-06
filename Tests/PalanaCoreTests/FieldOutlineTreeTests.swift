// FieldOutline dataset-tree battery — the nested expand/collapse behaviour
// introduced in ho-9.3. All pure; no wire, no fixtures beyond the shared
// ZFSDataset/HostFacts builders duplicated here to keep both files self-contained.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Shared fixtures (tree file)

private let treeEpoch = Date(timeIntervalSince1970: 0)

private func treeFacts(
    flavor: UserlandFlavor = .gnu,
    zfsVersion: String? = nil,
    datasets: [ZFSDataset] = []
) -> HostFacts {
    let cap = HostCapability(
        kernel: "Linux",
        flavor: flavor,
        zfs: zfsVersion,
        rsync: "rsync 3.2.7"
    )
    var topology: Dated<[ZFSDataset]>?
    if !datasets.isEmpty {
        topology = Dated(value: datasets, discoveredAt: treeEpoch)
    }
    return HostFacts(
        reachability: Dated(value: .reachable, discoveredAt: treeEpoch),
        capability: Dated(value: cap, discoveredAt: treeEpoch),
        zfsTopology: topology
    )
}

// MARK: - Dataset tree tests

@Suite("FieldOutline — dataset tree")
struct FieldOutlineDatasetTreeTests {
    @Test("nested build shape — dataset tree with two levels")
    func nestedBuildShape() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
            ZFSDataset(name: "tank/data/photos", mountpoint: "/tank/data/photos", mounted: true),
            ZFSDataset(name: "tank/extra", mountpoint: "/tank/extra", mounted: true),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": treeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // jodo
        outline.expand()  // host expanded — only tank (depth 0) visible; cursor stays at jodo(1)
        #expect(outline.lines.count == 3)  // local + jodo + tank

        guard case .dataset(let tank) = outline.lines[2] else {
            Issue.record("expected tank at index 2")
            return
        }
        #expect(tank.depth == 0)
        #expect(tank.childCount == 2)  // tank/data and tank/extra

        outline.cursorDown()  // move cursor from jodo(1) to tank(2)
        outline.expand()  // expand tank — tank/data and tank/extra appear
        #expect(outline.lines.count == 5)  // local + jodo + tank + tank/data + tank/extra

        guard case .dataset(let tankData) = outline.lines[3] else {
            Issue.record("expected tank/data at index 3")
            return
        }
        #expect(tankData.name == "tank/data")
        #expect(tankData.depth == 1)
        #expect(tankData.childCount == 1)
        #expect(!tankData.expanded)

        // Move cursor to tank/data and expand it (cursor is at tank=2 after above expand)
        outline.cursorDown()  // tank/data at index 3
        outline.expand()  // tank/data expanded — tank/data/photos appears
        #expect(outline.lines.count == 6)

        guard case .dataset(let photos) = outline.lines[4] else {
            Issue.record("expected tank/data/photos at index 4")
            return
        }
        #expect(photos.name == "tank/data/photos")
        #expect(photos.depth == 2)
        #expect(photos.childCount == 0)
    }

    @Test("ancestor-chain visibility — child hidden when any ancestor is collapsed")
    func ancestorChainVisibility() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
            ZFSDataset(name: "tank/data/photos", mountpoint: "/tank/data/photos", mounted: true),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": treeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // jodo
        outline.expand()  // host: tank visible; cursor stays at jodo(1)
        outline.cursorDown()  // move cursor to tank(2)
        outline.expand()  // tank: tank/data visible, tank/data/photos still hidden
        #expect(outline.lines.count == 4)  // local + jodo + tank + tank/data
        // Confirm tank/data/photos is absent (tank/data collapsed)
        #expect(
            !outline.lines.contains {
                guard case .dataset(let dl) = $0 else { return false }
                return dl.name == "tank/data/photos"
            })

        // Expand tank/data — photos becomes visible (cursor is at tank=2 after above expand)
        outline.cursorDown()  // tank/data at index 3
        outline.expand()
        #expect(outline.lines.count == 5)
        #expect(
            outline.lines.contains {
                guard case .dataset(let dl) = $0 else { return false }
                return dl.name == "tank/data/photos"
            })
    }

    @Test("collapse-to-parent cursor moves on leaf and collapsed dataset rows")
    func collapseToParentCursorMoves() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": treeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // jodo
        outline.expand()  // host: tank visible; cursor stays at jodo(1)
        outline.cursorDown()  // move cursor to tank(2)
        outline.expand()  // tank: tank/data visible; cursor stays at tank(2)
        outline.cursorDown()  // tank/data at index 3 (leaf, depth 1)
        #expect(outline.cursor == 3)

        // Collapse on a leaf: moves cursor to parent dataset (tank at index 2).
        outline.collapse()
        #expect(outline.cursor == 2)
        guard case .dataset(let tankAfter) = outline.lines[2] else {
            Issue.record("expected tank at index 2 after collapse")
            return
        }
        #expect(tankAfter.name == "tank")
        #expect(!tankAfter.expanded)  // collapsed by the leaf's h-press

        // Now tank is collapsed (depth 0, no children showing); collapse again
        // should walk to the host and collapse it.
        outline.collapse()
        #expect(outline.lines.count == 2)  // local + jodo (collapsed)
        #expect(outline.cursor == 1)
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host line at index 1")
            return
        }
        #expect(!hl.expanded)
    }

    @Test("dataset expansion survives update(facts:) — sticky expansion")
    func datasetExpansionSurvivesUpdate() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data", mountpoint: "/tank/data", mounted: true),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": treeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()
        outline.expand()  // host expanded; cursor stays at jodo(1)
        outline.cursorDown()  // move cursor to tank(2)
        outline.expand()  // tank expanded — tank/data visible
        #expect(outline.lines.count == 4)

        // Simulate a reprobe that returns the same datasets (flavor update only).
        let updatedFacts = treeFacts(flavor: .busybox, zfsVersion: "zfs-2.2.2", datasets: datasets)
        outline.update(facts: ["jodo": updatedFacts])

        // Dataset expansion survived — tank/data still visible.
        #expect(outline.lines.count == 4)
        guard case .host(let hl) = outline.lines[1] else {
            Issue.record("expected host at index 1")
            return
        }
        #expect(hl.flavor == .busybox)
    }

    @Test("hierarchy with a hole — grandparent present, parent absent")
    func hierarchyWithHole() {
        // tank and tank/data/photos exist; tank/data does not.
        // tank/data/photos should appear at depth 1 under tank (longest present prefix).
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/data/photos", mountpoint: "/tank/data/photos", mounted: true),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": treeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()  // jodo
        outline.expand()  // host: tank visible (childCount 1); cursor stays at jodo(1)
        guard case .dataset(let tank) = outline.lines[2] else {
            Issue.record("expected tank at index 2")
            return
        }
        #expect(tank.childCount == 1)
        #expect(tank.depth == 0)

        // tank/data/photos is hidden until tank is expanded
        outline.cursorDown()  // move cursor to tank(2)
        outline.expand()  // expand tank
        #expect(outline.lines.count == 4)
        guard case .dataset(let photos) = outline.lines[3] else {
            Issue.record("expected tank/data/photos at index 3")
            return
        }
        #expect(photos.name == "tank/data/photos")
        #expect(photos.depth == 1)  // one present ancestor (tank)
        #expect(photos.childCount == 0)
    }

    @Test("childCount correctness — only direct children counted, not grandchildren")
    func childCountCorrectness() {
        let datasets = [
            ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            ZFSDataset(name: "tank/a", mountpoint: "/tank/a", mounted: true),
            ZFSDataset(name: "tank/a/x", mountpoint: "/tank/a/x", mounted: true),
            ZFSDataset(name: "tank/b", mountpoint: "/tank/b", mounted: true),
        ]
        var outline = FieldOutline(
            hosts: ["local", "jodo"],
            facts: ["jodo": treeFacts(zfsVersion: "zfs-2.2.2", datasets: datasets)],
            localHost: "local"
        )
        outline.cursorDown()
        outline.expand()  // host; cursor stays at jodo(1)
        // tank is depth 0; direct children are tank/a and tank/b.
        guard case .dataset(let tank) = outline.lines[2] else {
            Issue.record("expected tank at index 2")
            return
        }
        #expect(tank.childCount == 2)  // tank/a and tank/b only; tank/a/x is grandchild

        outline.cursorDown()  // move cursor to tank(2)
        outline.expand()  // expand tank
        // tank/a should have childCount 1 (tank/a/x), tank/b should have childCount 0.
        guard case .dataset(let tankA) = outline.lines[3] else {
            Issue.record("expected tank/a at index 3")
            return
        }
        #expect(tankA.name == "tank/a")
        #expect(tankA.childCount == 1)
        guard case .dataset(let tankB) = outline.lines[4] else {
            Issue.record("expected tank/b at index 4")
            return
        }
        #expect(tankB.name == "tank/b")
        #expect(tankB.childCount == 0)
    }
}
