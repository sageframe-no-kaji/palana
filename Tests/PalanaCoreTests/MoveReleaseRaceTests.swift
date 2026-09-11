// Progressive rsync moves are explicit about their operating contract:
// files leave the source after transfer, and either location changing
// during the run is outside that contract. Atomic same-filesystem renames
// and ZFS moves remain separate paths.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Move release boundaries")
struct MoveReleaseRaceTests {
    private func entry(_ name: String = "a.txt") -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: .file,
            size: 5,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    @Test("a progressive move is available only through a supported rsync")
    func genericMoveNeedsRsync() throws {
        let request = PlanRequest(
            operation: .move,
            source: Locus(host: "jodo", directory: "/tank/a"),
            entries: [entry()],
            destination: Locus(host: "koan", directory: "/rpool/b"),
            token: "t1")
        #expect(throws: PlanError.moveReleaseUnavailable) {
            try PlanEngine.plan(request, facts: PlanFacts())
        }
        let rsync = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")
        let plan = try PlanEngine.plan(
            request,
            facts: PlanFacts(
                sourceCapability: rsync,
                destinationCapability: rsync,
                agentForwarding: .available))
        #expect(plan.usesProgressiveRsyncMove)
        #expect(plan.steps[0].command.contains("--remove-source-files"))
    }

    @Test("a known same-filesystem move remains one atomic rename")
    func sameFilesystemMoveRemainsAtomic() throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "jodo", directory: "/tank/a"),
                entries: [entry()],
                destination: Locus(host: "jodo", directory: "/tank/b"),
                token: "t1"),
            facts: PlanFacts(
                sourceMountTarget: "/tank",
                destinationMountTarget: "/tank",
                collisions: []))

        #expect(plan.classification == .withinDatasetRename)
        #expect(plan.steps.map(\.role) == [.rename])
    }

    @Test("a decoded legacy quarantine plan is refused before any command runs")
    func legacyMoveReleaseIsRefused() async throws {
        let plan = Plan(
            operation: .move,
            classification: .crossDatasetCopyPlusDelete,
            entries: [entry()],
            totalSize: 5,
            source: Locus(host: "jodo", directory: "/tank/a"),
            destination: Locus(host: "jodo", directory: "/tank/b"),
            transport: .local,
            steps: [
                PlanStep(
                    runsOn: .host("jodo"),
                    command: "mkdir -- /tank/a/palana-recover-t1; mv -- /tank/a/a.txt /tank/a/palana-recover-t1/",
                    role: .quarantine),
                PlanStep(
                    runsOn: .host("jodo"),
                    command: "rm -rf -- /tank/a/palana-recover-t1",
                    role: .delete,
                    gatedOnVerification: true),
            ])
        let transports = Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript())
        ) { _, _, _ in 0 }

        await #expect(throws: EnactmentError.self) {
            try await transports.run(plan) { _ in }
        }
    }

    @Test("a decoded copy cannot carry a source-removing rsync option")
    func decodedCopyCannotRemoveSource() async {
        let plan = Plan(
            operation: .copy,
            classification: .crossHostCopy,
            entries: [entry()],
            totalSize: 5,
            source: Locus(host: "jodo", directory: "/tank/a"),
            destination: Locus(host: "koan", directory: "/rpool/b"),
            transport: .rsyncAgentForwarded,
            steps: [
                PlanStep(
                    runsOn: .host("jodo"),
                    command: "rsync --remove-source-files /tank/a/a.txt koan:/rpool/b/",
                    role: .transfer)
            ])
        let transports = Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript())
        ) { _, _, _ in 0 }

        await #expect(throws: EnactmentError.self) {
            try await transports.run(plan) { _ in }
        }
    }

    @Test("a decoded progressive move must carry removal and accounting")
    func decodedMoveMustCarryItsContract() async {
        let plan = Plan(
            operation: .move,
            classification: .crossHostTransfer,
            entries: [entry()],
            totalSize: 5,
            source: Locus(host: "jodo", directory: "/tank/a"),
            destination: Locus(host: "koan", directory: "/rpool/b"),
            transport: .rsyncAgentForwarded,
            steps: [
                PlanStep(
                    runsOn: .host("jodo"),
                    command: "rsync /tank/a/a.txt koan:/rpool/b/",
                    role: .transfer)
            ])
        let transports = Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript())
        ) { _, _, _ in 0 }

        await #expect(throws: EnactmentError.self) {
            try await transports.run(plan) { _ in }
        }
    }
}
