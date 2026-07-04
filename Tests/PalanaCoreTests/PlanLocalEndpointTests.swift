// "local" is a host, and now the engine knows it — rsync runs on this
// machine when the selection or the destination lives here, the plan
// names this machine's agent instead of claiming a forwarding that
// isn't happening, and the whole-dataset helper answers the facts
// assembly without reimplementing boundary arithmetic.

import Foundation
import Testing

@testable import PalanaCore

private func makeEntry(_ name: String, kind: FileEntry.Kind = .file, size: Int64 = 0) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

@Suite("PlanEngine local endpoints")
struct PlanLocalEndpointTests {
    private let here = Locus(host: "local", directory: "/Users/op/files")
    private let koan = Locus(host: "koan", directory: "/rpool/cold")
    private let twoFiles = [makeEntry("a.txt", size: 100), makeEntry("with space", size: 41)]

    private static let remoteRsync = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")
    private static let remoteBare = HostCapability(
        kernel: "Linux", flavor: .bsd, zfs: nil, rsync: nil)
    private static let localModern = HostCapability(
        kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "rsync  version 3.4.1")
    private static let localFloor = HostCapability(
        kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "openrsync: protocol version 29")

    private func plan(
        _ operation: PlanOperation,
        from source: Locus,
        to destination: Locus?,
        facts: PlanFacts = PlanFacts()
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: source,
                entries: twoFiles,
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    @Test("pushing runs rsync here toward the remote, named honestly")
    func pushCopy() throws {
        // An openrsync Mac — the flags stay openrsync-safe, no -s.
        let facts = PlanFacts(
            sourceCapability: Self.localFloor, destinationCapability: Self.remoteRsync)
        let plan = try plan(.copy, from: here, to: koan, facts: facts)
        #expect(plan.transport == .rsyncDirect)
        #expect(
            plan.steps.map(\.command) == [
                "rsync -a --partial /Users/op/files/a.txt "
                    + "'/Users/op/files/with space' koan:/rpool/cold/"
            ])
        #expect(plan.steps.first?.runsOn == .host("local"))
        #expect(plan.transport.rawValue.contains("this machine's agent"))
    }

    @Test("an unknown local rsync falls to tar — the composes are incompatible")
    func unknownLocalRsyncFallsToTar() throws {
        let facts = PlanFacts(destinationCapability: Self.remoteRsync)
        let plan = try plan(.copy, from: here, to: koan, facts: facts)
        #expect(plan.transport == .tarStreamDirect)
    }

    @Test("a modern local rsync carries progress2")
    func modernLocalRsyncSpeaksProgress() throws {
        let facts = PlanFacts(
            sourceCapability: Self.localModern, destinationCapability: Self.remoteRsync)
        let plan = try plan(.copy, from: here, to: koan, facts: facts)
        #expect(plan.steps[0].command.hasPrefix("rsync -a -s --partial --info=progress2 "))
    }

    @Test("pulling runs rsync here with remote sources")
    func pullCopy() throws {
        let facts = PlanFacts(
            sourceCapability: Self.remoteRsync, destinationCapability: Self.localFloor)
        let plan = try plan(.copy, from: koan, to: here, facts: facts)
        #expect(plan.transport == .rsyncDirect)
        // The floor has no -s, so the spaced remote path rides an inner
        // quote the remote shell unwraps.
        #expect(
            plan.steps.map(\.command) == [
                "rsync -a --partial koan:/rpool/cold/a.txt "
                    + #"'koan:'\''/rpool/cold/with space'\''' /Users/op/files/"#
            ])
        #expect(plan.steps.first?.runsOn == .host("local"))
    }

    @Test("a remote without rsync sends a tar stream from this machine")
    func bareRemoteFallsToTarDirect() throws {
        let facts = PlanFacts(destinationCapability: Self.remoteBare)
        let plan = try plan(.copy, from: here, to: koan, facts: facts)
        #expect(plan.transport == .tarStreamDirect)
        #expect(
            plan.steps.map(\.command) == [
                "tar -cf - -C /Users/op/files -- a.txt 'with space' | "
                    + "ssh koan 'tar -xpf - -C /rpool/cold'"
            ])
        #expect(plan.steps.first?.runsOn == .host("local"))
    }

    @Test("a bare-remote pull runs the unpack here")
    func bareRemotePullTarDirect() throws {
        let facts = PlanFacts(sourceCapability: Self.remoteBare)
        let plan = try plan(.move, from: koan, to: here, facts: facts)
        #expect(plan.transport == .tarStreamDirect)
        #expect(
            plan.steps[0].command
                == "ssh koan 'tar -cf - -C /rpool/cold -- a.txt '\\''with space'\\''' | "
                + "tar -xpf - -C /Users/op/files")
        #expect(plan.steps[1].runsOn == .host("koan"))
        #expect(plan.steps[1].gatedOnVerification)
    }

    @Test("a push move gates its delete on this machine")
    func pushMoveGatesDeleteHere() throws {
        let facts = PlanFacts(destinationCapability: Self.remoteRsync)
        let plan = try plan(.move, from: here, to: koan, facts: facts)
        #expect(plan.steps.count == 2)
        #expect(plan.steps[1].command == "rm -rf /Users/op/files/a.txt '/Users/op/files/with space'")
        #expect(plan.steps[1].runsOn == .host("local"))
        #expect(plan.steps[1].gatedOnVerification)
    }

    @Test("a pull move gates its delete on the remote")
    func pullMoveGatesDeleteRemote() throws {
        let facts = PlanFacts(sourceCapability: Self.remoteRsync)
        let plan = try plan(.move, from: koan, to: here, facts: facts)
        #expect(plan.steps[1].runsOn == .host("koan"))
        #expect(plan.steps[1].gatedOnVerification)
    }

    @Test("a local end wins over forwarding and the whole-dataset gate")
    func localBeatsForwardingAndZfs() throws {
        let dataset = ZFSDataset(name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true)
        var facts = PlanFacts(
            sourceDataset: dataset,
            selectionWholeDataset: dataset,
            agentForwarding: .available)
        facts.sourceCapability = Self.remoteRsync
        facts.destinationCapability = Self.localModern
        let plan = try plan(.copy, from: koan, to: here, facts: facts)
        #expect(plan.transport == .rsyncDirect)
        #expect(plan.receivedDataset == nil)
    }

    @Test("classification is untouched — a local push is still a cross-host copy")
    func classificationUnchanged() throws {
        let plan = try plan(.copy, from: here, to: koan)
        #expect(plan.classification == .crossHostCopy)
    }
}

@Suite("ZFSTopology whole-dataset selection")
struct WholeDatasetSelectionTests {
    private let datasets = [
        ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
        ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true),
        ZFSDataset(name: "tank/frozen", mountpoint: "/tank/frozen", mounted: false),
    ]

    @Test("one directory exactly at a mountpoint matches its dataset")
    func exactMountpointMatches() {
        let selection = [makeEntry("media", kind: .directory)]
        let match = ZFSTopology.wholeDatasetSelection(
            entries: selection, sourceDirectory: "/tank", datasets: datasets)
        #expect(match?.name == "tank/media")
    }

    @Test("a subdirectory inside a dataset is not the dataset")
    func subdirectoryDoesNotMatch() {
        let selection = [makeEntry("photos", kind: .directory)]
        let match = ZFSTopology.wholeDatasetSelection(
            entries: selection, sourceDirectory: "/tank/media", datasets: datasets)
        #expect(match == nil)
    }

    @Test("two entries never match — send carries one dataset")
    func multipleEntriesDoNotMatch() {
        let selection = [makeEntry("media", kind: .directory), makeEntry("x", kind: .directory)]
        let match = ZFSTopology.wholeDatasetSelection(
            entries: selection, sourceDirectory: "/tank", datasets: datasets)
        #expect(match == nil)
    }

    @Test("a file at the mountpoint's name is not a dataset")
    func fileDoesNotMatch() {
        let selection = [makeEntry("media")]
        let match = ZFSTopology.wholeDatasetSelection(
            entries: selection, sourceDirectory: "/tank", datasets: datasets)
        #expect(match == nil)
    }

    @Test("an unmounted dataset's mountpoint is an intention, not a match")
    func unmountedDoesNotMatch() {
        let selection = [makeEntry("frozen", kind: .directory)]
        let match = ZFSTopology.wholeDatasetSelection(
            entries: selection, sourceDirectory: "/tank", datasets: datasets)
        #expect(match == nil)
    }
}
