// File moves that require copy-then-delete cannot bind deletion to
// non-cooperating writers on a generic POSIX filesystem. Palana refuses
// those plans rather than manufacturing a quarantine it cannot safely
// release. Atomic same-filesystem renames and ZFS moves are separate paths.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Move release fails closed")
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

    @Test("a file move requiring copy-then-delete is refused during composition")
    func genericMoveIsRefused() {
        #expect(throws: PlanError.moveReleaseUnavailable) {
            try PlanEngine.plan(
                PlanRequest(
                    operation: .move,
                    source: Locus(host: "jodo", directory: "/tank/a"),
                    entries: [entry()],
                    destination: Locus(host: "koan", directory: "/rpool/b"),
                    token: "t1"),
                facts: PlanFacts())
        }
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
}
