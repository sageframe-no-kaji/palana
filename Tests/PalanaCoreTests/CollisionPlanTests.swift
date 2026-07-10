// Collision plan carry-through — the report rides the Plan for every
// destination-ful request and stays nil where a guard already refuses.
// Split from CollisionTests.swift for the file-length budget.

import Foundation
import Testing

@testable import PalanaCore

private let source = Locus(host: "jodo", directory: "/tank/src")
private let dest = Locus(host: "jodo", directory: "/tank/dst")

@Suite("Collision plan carry-through")
struct CollisionPlanCarryThroughTests {
    private func makeEntry(_ name: String, kind: FileEntry.Kind = .file) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: 100,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    private func copyPlan(facts: PlanFacts) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: [makeEntry("a.txt")],
                destination: dest,
                token: "t1"),
            facts: facts)
    }

    @Test("a copy plan with gathered collisions exposes the report")
    func copyWithCollisions() throws {
        let collision = Collision(
            nameData: Data("a.txt".utf8),
            standingKind: .file,
            standingSize: 500,
            standingModified: .distantPast,
            arrivingKind: .file)
        let facts = PlanFacts(collisions: [collision])
        let plan = try copyPlan(facts: facts)
        let report = try #require(plan.collisions)
        #expect(report.gathered == true)
        #expect(report.items.count == 1)
        #expect(report.items[0].nameData == Data("a.txt".utf8))
    }

    @Test("a copy plan with nil collision facts reads gathered: false")
    func copyWithUngatheredFacts() throws {
        let plan = try copyPlan(facts: PlanFacts())
        let report = try #require(plan.collisions)
        #expect(report.gathered == false)
        #expect(report.items.isEmpty)
    }

    @Test("a copy plan with empty gathered collisions is clean")
    func copyWithEmptyCollisions() throws {
        let facts = PlanFacts(collisions: [])
        let plan = try copyPlan(facts: facts)
        let report = try #require(plan.collisions)
        #expect(report.gathered == true)
        #expect(report.items.isEmpty)
        #expect(report.sentence() == nil)
    }

    @Test("a within-dataset move carries the report — mv overwrites too")
    func withinDatasetMoveCarriesReport() throws {
        // The classification is .withinDatasetRename, shared with the
        // guarded rename — the report keys on the destination directory,
        // and a move has one.
        let collision = Collision(
            nameData: Data("a.txt".utf8),
            standingKind: .file,
            standingSize: 500,
            standingModified: .distantPast,
            arrivingKind: .file)
        let tank = ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: source,
                entries: [makeEntry("a.txt")],
                destination: dest,
                token: "t1"),
            facts: PlanFacts(
                sourceDataset: tank,
                destinationDataset: tank,
                collisions: [collision]))
        #expect(plan.classification == .withinDatasetRename)
        let report = try #require(plan.collisions)
        #expect(report.gathered == true)
        #expect(report.items.count == 1)
    }

    @Test("a rename plan carries nil — no destination directory")
    func renamePlanNilCollisions() throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .rename,
                source: source,
                entries: [makeEntry("old.txt")],
                destination: nil,
                token: "t1",
                targetName: "new.txt"),
            facts: PlanFacts())
        #expect(plan.collisions == nil)
    }

    @Test("a create plan carries nil — no destination directory")
    func createPlanNilCollisions() throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .create,
                source: source,
                entries: [],
                destination: nil,
                token: "t1",
                targetName: "newdir/"),
            facts: PlanFacts())
        #expect(plan.collisions == nil)
    }

    @Test("a touch plan carries nil — no destination directory")
    func touchPlanNilCollisions() throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .touch,
                source: source,
                entries: [makeEntry("a.txt")],
                destination: nil,
                token: "t1"),
            facts: PlanFacts())
        #expect(plan.collisions == nil)
    }

    @Test("a delete plan carries nil — no destination directory")
    func deletePlanNilCollisions() throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .delete,
                source: source,
                entries: [makeEntry("a.txt")],
                destination: nil,
                token: "t1"),
            facts: PlanFacts())
        #expect(plan.collisions == nil)
    }

    @Test("a cross-host copy plan carries a collision report")
    func crossHostCopyPlanCarriesReport() throws {
        let crossDest = Locus(host: "koan", directory: "/rpool/dst")
        let collision = Collision(
            nameData: Data("img.jpg".utf8),
            standingKind: .file,
            standingSize: 5_000_000,
            standingModified: .distantPast,
            arrivingKind: .file)
        let facts = PlanFacts(collisions: [collision])
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: [makeEntry("img.jpg")],
                destination: crossDest,
                token: "t1"),
            facts: facts)
        let report = try #require(plan.collisions)
        #expect(report.gathered == true)
        #expect(report.items.count == 1)
    }

    @Test("Codable round-trip of a plan with a collision report")
    func codableRoundTrip() throws {
        let collision = Collision(
            nameData: Data("notes.txt".utf8),
            standingKind: .file,
            standingSize: 1000,
            standingModified: Date(timeIntervalSince1970: 1_000_000),
            arrivingKind: .file)
        let facts = PlanFacts(collisions: [collision])
        let plan = try copyPlan(facts: facts)
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded == plan)
        let report = try #require(decoded.collisions)
        #expect(report.gathered == true)
        #expect(report.items[0].standingSize == 1000)
    }

    @Test("composed copy command is byte-identical with and without collision facts")
    func composeUnchangedByCollisionFacts() throws {
        let entry = makeEntry("a.txt")
        let planWithoutCollisions = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: [entry],
                destination: dest,
                token: "t1"),
            facts: PlanFacts())
        let collision = Collision(
            nameData: Data("a.txt".utf8),
            standingKind: .file,
            standingSize: 999,
            standingModified: .distantPast,
            arrivingKind: .file)
        let planWithCollisions = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: [entry],
                destination: dest,
                token: "t1"),
            facts: PlanFacts(collisions: [collision]))
        #expect(
            planWithoutCollisions.steps.map(\.command)
                == planWithCollisions.steps.map(\.command),
            "composed commands must not change when collision facts are added")
    }
}
