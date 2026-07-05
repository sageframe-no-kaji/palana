// Composed commands against hand-verified equivalents — exact strings,
// because the plan panel shows exactly these and the operator was
// promised paste-able truth. The corpus test runs the whole engine over
// ho-03's recorded pool and ho-04's recorded listing: facts from
// committed transcripts, Plans out.

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

@Suite("PlanEngine composition")
struct PlanCompositionTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")
    private let sameHostDest = Locus(host: "jodo", directory: "/tank/other")
    private let crossHostDest = Locus(host: "koan", directory: "/rpool/cold")
    private let twoFiles = [makeEntry("a.txt", size: 100), makeEntry("with space", size: 41)]

    private func plan(
        _ operation: PlanOperation,
        to destination: Locus?,
        entries: [FileEntry]? = nil,
        facts: PlanFacts = PlanFacts()
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: source,
                entries: entries ?? twoFiles,
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    @Test("a true rename is one mv toward the destination directory")
    func renameCommand() throws {
        let facts = PlanFacts(
            sourceDataset: ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            destinationDataset: ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true))
        let plan = try plan(.move, to: sameHostDest, facts: facts)
        #expect(
            plan.steps.map(\.command) == [
                "mv /tank/media/a.txt '/tank/media/with space' /tank/other/"
            ])
        #expect(plan.steps.first?.role == .rename)
        #expect(plan.steps.first?.runsOn == .host("jodo"))
    }

    @Test("a cross-dataset move is cp -a then a gated rm — never a bare mv")
    func crossDatasetCommands() throws {
        let plan = try plan(.move, to: sameHostDest)
        #expect(
            plan.steps.map(\.command) == [
                "cp -a /tank/media/a.txt '/tank/media/with space' /tank/other/",
                "rm -rf /tank/media/a.txt '/tank/media/with space'",
            ])
        #expect(plan.steps.map(\.gatedOnVerification) == [false, true])
    }

    @Test("a deletion is one rm where the entries stand")
    func deleteCommand() throws {
        let plan = try plan(.delete, to: nil)
        #expect(
            plan.steps.map(\.command) == [
                "rm -rf /tank/media/a.txt '/tank/media/with space'"
            ])
        #expect(plan.steps.first?.gatedOnVerification == false, "Enter is the gate for delete")
    }

    private static let rsyncHost = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")

    private static var forwardedRsyncFacts: PlanFacts {
        PlanFacts(
            sourceCapability: rsyncHost,
            destinationCapability: rsyncHost,
            agentForwarding: .available)
    }

    @Test("a forwarded cross-host move is rsync on the source host plus a gated rm")
    func rsyncCommands() throws {
        let plan = try plan(.move, to: crossHostDest, facts: Self.forwardedRsyncFacts)
        #expect(plan.transport == .rsyncAgentForwarded)
        #expect(
            plan.steps.map(\.command) == [
                "rsync -a -s --partial --info=progress2 /tank/media/a.txt "
                    + "'/tank/media/with space' koan:/rpool/cold/",
                "rm -rf /tank/media/a.txt '/tank/media/with space'",
            ])
        #expect(plan.steps.map(\.runsOn) == [.host("jodo"), .host("jodo")])
    }

    @Test("a copy composes the same transfer minus the delete")
    func copyLeavesSource() throws {
        let plan = try plan(.copy, to: crossHostDest, facts: Self.forwardedRsyncFacts)
        #expect(plan.classification == .crossHostCopy)
        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.role == .transfer)
    }

    @Test("a same-host copy rides rsync when the host carries it")
    func sameHostCopyPrefersRsync() throws {
        let facts = PlanFacts(sourceCapability: Self.rsyncHost)
        let plan = try plan(.copy, to: sameHostDest, facts: facts)
        #expect(plan.transport == .local)
        #expect(
            plan.steps.map(\.command) == [
                "rsync -a -s --partial --info=progress2 /tank/media/a.txt "
                    + "'/tank/media/with space' /tank/other/"
            ])
        #expect(plan.steps.first?.role == .copy)
    }

    @Test("a same-host move between datasets gates its rm behind the rsync copy")
    func sameHostMovePrefersRsync() throws {
        let facts = PlanFacts(sourceCapability: Self.rsyncHost)
        let plan = try plan(.move, to: sameHostDest, facts: facts)
        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].command.hasPrefix("rsync -a -s --partial"))
        #expect(plan.steps[1].gatedOnVerification)
    }

    @Test("the proxy path is two ssh commands piped on the operator's machine")
    func tarStreamCommands() throws {
        let plan = try plan(.move, to: crossHostDest)
        #expect(plan.transport == .tarStreamProxied)
        #expect(
            plan.steps.map(\.command) == [
                "ssh jodo 'tar -cf - -C /tank/media -- a.txt '\\''with space'\\''' | "
                    + "ssh koan 'tar -xpf - -C /rpool/cold'",
                "rm -rf /tank/media/a.txt '/tank/media/with space'",
            ])
        #expect(plan.steps.first?.runsOn == .operatorMachine)
    }

    @Test("a whole-dataset move composes snapshot, send/receive, and gated destroys")
    func zfsCommands() throws {
        let facts = PlanFacts(
            sourceDataset: ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            destinationDataset: ZFSDataset(
                name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
            selectionWholeDataset: ZFSDataset(
                name: "tank/media", mountpoint: "/tank/media", mounted: true),
            sourceCapability: HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil),
            destinationCapability: HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil),
            agentForwarding: .available)
        let plan = try plan(
            .move,
            to: crossHostDest,
            entries: [makeEntry("media", kind: .directory)],
            facts: facts)
        #expect(plan.transport == .zfsSendReceiveForwarded)
        #expect(
            plan.steps.map(\.command) == [
                "zfs snapshot -r tank/media@t1",
                "zfs send -R -v tank/media@t1 | ssh koan 'zfs receive -u rpool/cold/media'",
                "zfs destroy -r rpool/cold/media@t1",
                "zfs destroy -r tank/media",
            ])
        #expect(plan.steps.map(\.role) == [.snapshot, .transfer, .cleanup, .delete])
        #expect(plan.steps.map(\.gatedOnVerification) == [false, false, true, true])
        #expect(
            plan.steps.map(\.runsOn) == [
                .host("jodo"), .host("jodo"), .host("koan"), .host("jodo"),
            ])
    }

    @Test("the proxied zfs pipeline runs on the operator's machine, copy keeps source")
    func zfsProxiedCopy() throws {
        let facts = PlanFacts(
            destinationDataset: ZFSDataset(
                name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
            selectionWholeDataset: ZFSDataset(
                name: "tank/media", mountpoint: "/tank/media", mounted: true),
            sourceCapability: HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil),
            destinationCapability: HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil))
        let plan = try plan(
            .copy,
            to: crossHostDest,
            entries: [makeEntry("media", kind: .directory)],
            facts: facts)
        #expect(plan.transport == .zfsSendReceiveProxied)
        #expect(
            plan.steps.map(\.command) == [
                "zfs snapshot -r tank/media@t1",
                "ssh jodo 'zfs send -R -v tank/media@t1' | ssh koan 'zfs receive -u rpool/cold/media'",
                "zfs destroy -r rpool/cold/media@t1",
                "zfs destroy -r tank/media@t1",
            ])
        #expect(plan.steps[1].runsOn == .operatorMachine)
        #expect(plan.steps.map(\.role) == [.snapshot, .transfer, .cleanup, .cleanup])
    }

    @Test("hostile names ride quoted through every composed command")
    func hostileNamesQuoted() throws {
        let entries = [makeEntry("new\nline"), makeEntry("it's here")]
        let plan = try plan(.delete, to: nil, entries: entries)
        let expected = "rm -rf '/tank/media/new\nline' '/tank/media/it'\\''s here'"
        #expect(plan.steps.first?.command == expected)
    }
}

@Suite("Plan corpus — the engine over recorded truth")
struct PlanCorpusTests {
    @Test("facts from the recorded pool and listing compose a whole-dataset plan")
    func planOverRecordedPool() throws {
        let transcript = try ConduitTranscript(
            contentsOf: SSHFixture.repoRoot.appendingPathComponent(
                "Tests/PalanaCoreTests/Fixtures/zfs-pool.json"))
        let listEntry = try #require(
            transcript.entries.first { $0.command == ZFSTopology.listCommand })
        let datasets = ZFSTopology.parse(listEntry.stdout)

        // The selection is the photos dataset's root; the destination is
        // exactly the svc dataset's mountpoint — the recorded topology
        // carries both shapes.
        let photos = try #require(datasets.first { $0.name == "palana/tank/media/photos" })
        let svc = try #require(datasets.first { $0.name == "palana/svc" })
        let facts = PlanFacts(
            sourceDataset: ZFSTopology.datasetContaining("/palana/tank/media", in: datasets),
            destinationDataset: svc,
            selectionWholeDataset: photos,
            sourceCapability: HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: "zfs-2.4.1", rsync: "rsync 3.4.1"),
            destinationCapability: HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: "zfs-2.4.1", rsync: "rsync 3.4.1"),
            agentForwarding: .available)

        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "lima-palana-zfs", directory: "/palana/tank/media"),
                entries: [makeEntry("photos", kind: .directory)],
                destination: Locus(host: "koan", directory: svc.mountpoint),
                token: "corpus"),
            facts: facts)

        #expect(plan.classification == .crossHostTransfer)
        #expect(plan.transport == .zfsSendReceiveForwarded)
        #expect(
            plan.steps.map(\.command) == [
                "zfs snapshot -r palana/tank/media/photos@corpus",
                "zfs send -R -v palana/tank/media/photos@corpus | "
                    + "ssh koan 'zfs receive -u palana/svc/photos'",
                "zfs destroy -r palana/svc/photos@corpus",
                "zfs destroy -r palana/tank/media/photos",
            ])
    }

    @Test("the recorded hostile listing plans a proxied move, every name armored")
    func planOverRecordedListing() throws {
        let transcript = try ConduitTranscript(
            contentsOf: SSHFixture.repoRoot.appendingPathComponent(
                "Tests/PalanaCoreTests/Fixtures/listing-container.json"))
        let listCommand = Listing.command(for: "/tmp/palana-listing-corpus", flavor: .gnu)
        let recorded = try #require(transcript.entries.first { $0.command == listCommand })
        let entries = try GNUListingParser.parse(Data(recorded.stdout.utf8))
        #expect(entries.count == 11)

        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "palana@localhost", directory: "/tmp/palana-listing-corpus"),
                entries: entries,
                destination: Locus(host: "koan", directory: "/rpool/cold"),
                token: "corpus"),
            facts: PlanFacts())

        #expect(plan.transport == .tarStreamProxied, "unprobed forwarding proxies")
        let transfer = try #require(plan.steps.first)
        #expect(transfer.command.contains("'new\nline'"), "hostile names armored in the pipe")
        #expect(plan.steps.last?.gatedOnVerification == true)
        #expect(plan.totalSize == entries.map(\.size).reduce(0, +))
    }
}

// MARK: - Operator flags placement

@Suite("PlanEngine rsync operator flags")
struct PlanRsyncOperatorFlagsTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")
    private let crossHostDest = Locus(host: "koan", directory: "/rpool/cold")
    private let sameHostDest = Locus(host: "jodo", directory: "/tank/other")
    private let oneFile = [makeEntry("a.txt", size: 100)]

    private static let remoteRsync = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")
    private static let localModern = HostCapability(
        kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "rsync  version 3.4.1")

    @Test("forwarded rsync: operator flags land after base flags and before paths")
    func forwardedRsyncCarriesFlags() throws {
        let facts = PlanFacts(
            sourceCapability: Self.remoteRsync,
            destinationCapability: Self.remoteRsync,
            agentForwarding: .available,
            rsyncOperatorFlags: "--exclude .DS_Store")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: oneFile,
                destination: crossHostDest,
                token: "t1"),
            facts: facts)
        #expect(plan.transport == .rsyncAgentForwarded)
        let cmd = try #require(plan.steps.first?.command)
        // Base flags, then operator flag, then source path
        #expect(
            cmd == "rsync -a -s --partial --info=progress2 --exclude .DS_Store "
                + "/tank/media/a.txt koan:/rpool/cold/")
    }

    @Test("direct rsync: operator flags land after base flags and before paths")
    func directRsyncCarriesFlags() throws {
        let facts = PlanFacts(
            sourceCapability: Self.localModern,
            destinationCapability: Self.remoteRsync,
            rsyncOperatorFlags: "--exclude .DS_Store")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: "local", directory: "/Users/op/files"),
                entries: oneFile,
                destination: crossHostDest,
                token: "t1"),
            facts: facts)
        #expect(plan.transport == .rsyncDirect)
        let cmd = try #require(plan.steps.first?.command)
        #expect(
            cmd == "rsync -a -s --partial --info=progress2 --exclude .DS_Store "
                + "/Users/op/files/a.txt koan:/rpool/cold/")
    }

    @Test("same-host rsync: operator flags land after base flags and before paths")
    func sameHostRsyncCarriesFlags() throws {
        let facts = PlanFacts(
            sourceCapability: Self.remoteRsync,
            rsyncOperatorFlags: "--exclude .DS_Store")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: oneFile,
                destination: sameHostDest,
                token: "t1"),
            facts: facts)
        #expect(plan.transport == .local)
        let cmd = try #require(plan.steps.first?.command)
        #expect(
            cmd == "rsync -a -s --partial --info=progress2 --exclude .DS_Store "
                + "/tank/media/a.txt /tank/other/")
    }

    @Test("nil operator flags produce no extra token in the command")
    func nilFlagsAbsent() throws {
        let facts = PlanFacts(
            sourceCapability: Self.remoteRsync,
            destinationCapability: Self.remoteRsync,
            agentForwarding: .available)
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: oneFile,
                destination: crossHostDest,
                token: "t1"),
            facts: facts)
        let cmd = try #require(plan.steps.first?.command)
        #expect(
            cmd == "rsync -a -s --partial --info=progress2 "
                + "/tank/media/a.txt koan:/rpool/cold/")
    }

    @Test("whitespace-only operator flags are trimmed to empty and absent")
    func whitespaceOnlyFlagsAbsent() throws {
        let facts = PlanFacts(
            sourceCapability: Self.remoteRsync,
            destinationCapability: Self.remoteRsync,
            agentForwarding: .available,
            rsyncOperatorFlags: "   ")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: oneFile,
                destination: crossHostDest,
                token: "t1"),
            facts: facts)
        let cmd = try #require(plan.steps.first?.command)
        #expect(
            cmd == "rsync -a -s --partial --info=progress2 "
                + "/tank/media/a.txt koan:/rpool/cold/")
    }

    @Test("operator flags with leading and trailing spaces are trimmed")
    func flagsTrimmed() throws {
        let facts = PlanFacts(
            sourceCapability: Self.remoteRsync,
            destinationCapability: Self.remoteRsync,
            agentForwarding: .available,
            rsyncOperatorFlags: "  --exclude .DS_Store  ")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: oneFile,
                destination: crossHostDest,
                token: "t1"),
            facts: facts)
        let cmd = try #require(plan.steps.first?.command)
        #expect(cmd.contains("--info=progress2 --exclude .DS_Store /tank"))
    }
}
