// Touch compose tests — the in-place mtime verb. One step, exit
// status as the whole verification, exact command strings as always:
// the panel shows exactly these and the operator was promised
// paste-able truth. Refusal locks delete's emptySelection precedent.

import Foundation
import Testing

@testable import PalanaCore

private func makeEntry(_ name: String, kind: FileEntry.Kind = .file, size: Int64 = 100) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

@Suite("PlanEngine touch compose")
struct PlanTouchComposeTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")

    private func planTouch(entries: [FileEntry]) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .touch,
                source: source,
                entries: entries,
                token: "t1"),
            facts: PlanFacts())
    }

    @Test("touch composes one touch -- where the entries stand — quoting held")
    func touchCommand() throws {
        let plan = try planTouch(entries: [makeEntry("a.txt"), makeEntry("with space")])
        #expect(
            plan.steps.map(\.command) == [
                "touch -- /tank/media/a.txt '/tank/media/with space'"
            ])
        #expect(plan.steps.map(\.role) == [.touch])
        #expect(plan.steps.map(\.runsOn) == [.host("jodo")])
        #expect(plan.steps.map(\.gatedOnVerification) == [false])
    }

    @Test("a single subject composes the same shape — the cursor's case")
    func touchSingleSubject() throws {
        let plan = try planTouch(entries: [makeEntry("notes.txt")])
        #expect(plan.steps.map(\.command) == ["touch -- /tank/media/notes.txt"])
    }

    @Test("touch classifies as a modification-time update, transports local")
    func touchClassification() throws {
        let plan = try planTouch(entries: [makeEntry("a.txt")])
        #expect(plan.classification == .modificationTimeUpdate)
        #expect(plan.transport == .local)
        #expect(plan.destination == nil)
        #expect(plan.operation == .touch)
    }

    @Test("no verify steps — the exit status is the whole verification")
    func touchNoVerifySteps() throws {
        let plan = try planTouch(entries: [makeEntry("a.txt"), makeEntry("b.txt")])
        #expect(plan.steps.count == 1)
        #expect(!plan.steps.contains { $0.role == .verify })
    }

    @Test("touch refuses an empty selection — delete's precedent")
    func touchEmptySelection() {
        #expect(throws: PlanError.emptySelection) {
            _ = try planTouch(entries: [])
        }
    }

    @Test("a touch Plan round-trips JSON whole — 'touch' is vocabulary")
    func codableRoundTrip() throws {
        let plan = try planTouch(entries: [makeEntry("a.txt")])
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded == plan)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"touch\""), "PlanOperation.touch raw value is 'touch'")
    }
}
