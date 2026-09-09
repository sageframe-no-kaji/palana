import Foundation
import Testing

@testable import PalanaCore

@Suite("Merge route")
struct MergeRouteTests {
    private func collision() -> Collision {
        Collision(
            nameData: Data("dir".utf8),
            standingKind: .directory,
            standingSize: 0,
            standingModified: Date(timeIntervalSince1970: 0),
            arrivingKind: .directory)
    }

    private func directory() -> FileEntry {
        FileEntry(
            nameData: Data("dir".utf8),
            kind: .directory,
            size: 0,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "755",
            owner: "op",
            group: "op")
    }

    private func request(_ operation: PlanOperation) -> PlanRequest {
        PlanRequest(
            operation: operation,
            source: Locus(host: "jodo", directory: "/tank/a"),
            entries: [directory()],
            destination: Locus(host: "jodo", directory: "/tank/b"),
            token: "t1")
    }

    @Test("a directory merge is never claimed as an atomic rename")
    func mergeClassification() {
        let facts = PlanFacts(
            sourceMountTarget: "/tank",
            destinationMountTarget: "/tank",
            collisions: [collision()])
        #expect(PlanEngine.classify(request(.move), facts: facts) == .crossDatasetCopyPlusDelete)
    }

    @Test("a directory merge move refuses rather than copy then delete")
    func mergeMoveRefuses() {
        let facts = PlanFacts(
            sourceMountTarget: "/tank",
            destinationMountTarget: "/tank",
            collisions: [collision()])
        #expect(throws: PlanError.moveReleaseUnavailable) {
            try PlanEngine.plan(request(.move), facts: facts)
        }
    }

    @Test("a directory merge copy remains available")
    func mergeCopyRemainsAvailable() throws {
        let facts = PlanFacts(
            sourceMountTarget: "/tank",
            destinationMountTarget: "/tank",
            collisions: [collision()])
        let plan = try PlanEngine.plan(request(.copy), facts: facts)
        #expect(plan.operation == .copy)
        #expect(plan.steps.map(\.role) == [.copy])
    }
}
