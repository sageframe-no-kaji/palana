// The 2026-11-18 final review's F12: a dataset-tree refresh for host A
// that finishes after the pane moved to host B must not paint A's tree
// and selection under B's header.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// A door where host "slow" answers only after a pause, and every probe
/// fails — so discovery never rewrites the seeded facts.
private actor HostPacedConduit: Conduit {
    func run(on host: String, _ command: String) async throws -> RunningCommand {
        if host == "slow" { try await Task.sleep(for: .milliseconds(300)) }
        return RunningCommand(replayingStdout: Data(), stderr: Data("no".utf8), exitStatus: 1)
    }
    func close(host: String) async {}
    func closeAll() async {}
}

@MainActor
@Suite("Final review F12 — superseded dataset-tree refresh")
struct FinalReviewZFSTreeTests {
    private func facts(_ datasets: [String]) -> HostFacts {
        var facts = HostFacts()
        facts.zfsTopology = Dated(
            value: datasets.map { ZFSDataset(name: $0, mountpoint: "/\($0)", mounted: true) },
            discoveredAt: Date())
        return facts
    }

    @Test("the old host's late tree is discarded; the new host's tree and selection stand")
    func lateRefreshForOldHostIsDiscarded() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-f12-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cache = FieldCache(url: cacheURL)
        try cache.save(["slow": facts(["apool", "apool/data"]), "fast": facts(["bpool"])])
        let conduit = HostPacedConduit()
        let engine = Engine(
            conduit: conduit,
            field: Field(conduit: conduit, hosts: ["slow", "fast"], cache: cache),
            listing: Listing(conduit: conduit))
        let pane = PaneModel(engine: engine)
        pane.state.host = "slow"
        pane.state.path = "/"
        pane.enterZFSMode()

        let first = Task { await pane.refreshZFSTree(engine: engine) }
        try await poll(message: "the first read lands") { pane.zfsDatasets.map(\.name) == ["apool", "apool/data"] }

        // The pane moves to the other host while the first discovery is slow.
        pane.state.host = "fast"
        await pane.refreshZFSTree(engine: engine)
        #expect(pane.zfsDatasets.map(\.name) == ["bpool"])
        #expect(pane.zfsSelectedDataset == "bpool")

        await first.value
        #expect(pane.zfsDatasets.map(\.name) == ["bpool"], "the old host's tree never paints under the new host")
        #expect(pane.zfsSelectedDataset == "bpool")

        // A later refresh on the same host still applies.
        await pane.refreshZFSTree(engine: engine)
        #expect(pane.zfsDatasets.map(\.name) == ["bpool"])
    }

    @Test("a refresh still in flight when the pane leaves zfs mode leaves the tree empty")
    func refreshAfterExitLandsNowhere() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-f12-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cache = FieldCache(url: cacheURL)
        try cache.save(["slow": facts(["apool"])])
        let conduit = HostPacedConduit()
        let engine = Engine(
            conduit: conduit,
            field: Field(conduit: conduit, hosts: ["slow"], cache: cache),
            listing: Listing(conduit: conduit))
        let pane = PaneModel(engine: engine)
        pane.state.host = "slow"
        pane.enterZFSMode()
        let refresh = Task { await pane.refreshZFSTree(engine: engine) }
        try await poll(message: "the first read lands") { !pane.zfsDatasets.isEmpty }
        pane.exitZFSMode()
        await refresh.value
        #expect(pane.zfsDatasets.isEmpty)
        #expect(pane.zfsSelectedDataset == nil)
    }
}
