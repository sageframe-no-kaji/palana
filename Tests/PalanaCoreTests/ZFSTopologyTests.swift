// The topology parser and the boundary question — synthetic shapes here,
// the recorded pool replays in FieldCorpusTests. The boundary rule under
// test: longest mounted mountpoint prefix, component boundaries honored,
// legacy and unmounted never match.

import Foundation
import Testing

@testable import PalanaCore

@Suite("ZFSTopology")
struct ZFSTopologyTests {
    private let datasets = [
        ZFSDataset(name: "palana", mountpoint: "/palana", mounted: true),
        ZFSDataset(name: "palana/tank", mountpoint: "/palana/tank", mounted: true),
        ZFSDataset(name: "palana/tank/media", mountpoint: "/palana/tank/media", mounted: true),
        ZFSDataset(name: "palana/svc", mountpoint: "/opt/services", mounted: true),
        ZFSDataset(name: "palana/legacy", mountpoint: "legacy", mounted: false),
        ZFSDataset(name: "palana/detached", mountpoint: "/palana/detached", mounted: false),
        ZFSDataset(name: "palana/none", mountpoint: "none", mounted: false),
    ]

    @Test("tab-separated -H output parses; noise lines are skipped")
    func parseListOutput() {
        let stdout = """
            palana\t/palana\tyes
            palana/tank\t/palana/tank\tyes
            palana/legacy\tlegacy\tno
            stray noise without tabs
            """
        let parsed = ZFSTopology.parse(stdout)
        #expect(parsed.count == 3)
        #expect(parsed[0] == ZFSDataset(name: "palana", mountpoint: "/palana", mounted: true))
        #expect(parsed[2].mounted == false)
    }

    @Test("the deepest containing dataset wins")
    func longestPrefixWins() {
        let hit = ZFSTopology.datasetContaining("/palana/tank/media/photos/img.raw", in: datasets)
        #expect(hit?.name == "palana/tank/media")
    }

    @Test("a path equal to the mountpoint is contained")
    func exactMountpointMatch() {
        #expect(ZFSTopology.datasetContaining("/palana/tank", in: datasets)?.name == "palana/tank")
        #expect(
            ZFSTopology.datasetContaining("/palana/tank/", in: datasets)?.name == "palana/tank")
    }

    @Test("prefix binds at component boundaries, not string prefixes")
    func componentBoundary() {
        let sneaky = [ZFSDataset(name: "t/data", mountpoint: "/tank/data", mounted: true)]
        #expect(ZFSTopology.datasetContaining("/tank/database", in: sneaky) == nil)
        #expect(ZFSTopology.datasetContaining("/tank/data/x", in: sneaky)?.name == "t/data")
    }

    @Test("legacy, none, and unmounted datasets never match a path query")
    func nonLocationsNeverMatch() {
        #expect(ZFSTopology.datasetContaining("/palana/detached/file", in: datasets)?.name == "palana")
        let onlyDead = datasets.filter { !$0.mounted }
        #expect(ZFSTopology.datasetContaining("/palana/detached/file", in: onlyDead) == nil)
    }

    @Test("a dataset mounted at / contains everything")
    func rootMountpoint() {
        let root = [ZFSDataset(name: "pool/root", mountpoint: "/", mounted: true)]
        #expect(ZFSTopology.datasetContaining("/etc/hosts", in: root)?.name == "pool/root")
        #expect(ZFSTopology.datasetContaining("/", in: root)?.name == "pool/root")
    }

    @Test("a path outside every mountpoint resolves to nothing")
    func noMatch() {
        #expect(ZFSTopology.datasetContaining("/var/log/syslog", in: datasets) == nil)
        #expect(ZFSTopology.datasetContaining("/var/log", in: []) == nil)
    }
}
