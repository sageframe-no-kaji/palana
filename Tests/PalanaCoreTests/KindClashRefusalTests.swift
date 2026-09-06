// A kind clash — a folder arriving where a file stands, or the reverse
// — used to ride the Plan as a "won't work" sentence while Enter still
// ran it; cp, rsync, and tar fail on the clashing entry after the
// entries before it moved (2026-09-06 review). The engine now refuses
// to compose over one, and enactment refuses a Plan that carries one.

import Foundation
import Testing

@testable import PalanaCore

private let source = Locus(host: "jodo", directory: "/tank/src")
private let sameHostDest = Locus(host: "jodo", directory: "/tank/dst")
private let otherHostDest = Locus(host: "koan", directory: "/rpool/dst")

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

private func collision(
    _ name: String, standing: FileEntry.Kind, arriving: FileEntry.Kind
) -> Collision {
    Collision(
        nameData: Data(name.utf8),
        standingKind: standing,
        standingSize: 500,
        standingModified: .distantPast,
        arrivingKind: arriving)
}

@Suite("Kind clash refusal")
struct KindClashRefusalTests {
    private func plan(
        _ operation: PlanOperation,
        entries: [FileEntry],
        to destination: Locus,
        collisions: [Collision]?
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: source,
                entries: entries,
                destination: destination,
                token: "t1"),
            facts: PlanFacts(collisions: collisions))
    }

    @Test("a move whose entry is a file here and a folder there is refused, by name")
    func moveOverFolderRefused() {
        let clash = collision("notes", standing: .directory, arriving: .file)
        #expect(throws: PlanError.kindClash(CollisionReport(items: [clash], gathered: true))) {
            try plan(.move, entries: [makeEntry("notes")], to: sameHostDest, collisions: [clash])
        }
    }

    @Test("a copy over the other kind is refused the same way — cp fails on it too")
    func copyOverFileRefused() {
        let clash = collision("notes", standing: .file, arriving: .directory)
        #expect(throws: PlanError.kindClash(CollisionReport(items: [clash], gathered: true))) {
            try plan(
                .copy,
                entries: [makeEntry("notes", kind: .directory)],
                to: otherHostDest,
                collisions: [clash])
        }
    }

    @Test("a mixed selection — replaces, merges, and one clash — is refused whole")
    func mixedSelectionRefused() {
        let items = [
            collision("a.txt", standing: .file, arriving: .file),
            collision("media", standing: .directory, arriving: .directory),
            collision("notes", standing: .directory, arriving: .file),
        ]
        let entries = [
            makeEntry("a.txt"), makeEntry("media", kind: .directory), makeEntry("notes"),
            makeEntry("untouched"),
        ]
        // Without the refusal, rsync would replace a.txt and merge media
        // before failing on notes — a partial destination.
        #expect(throws: PlanError.self) {
            try plan(.move, entries: entries, to: sameHostDest, collisions: items)
        }
    }

    @Test("the refusal's sentence names the clash alone, not the replaces beside it")
    func refusalSentenceNamesTheClash() {
        let items = [
            collision("a.txt", standing: .file, arriving: .file),
            collision("notes", standing: .directory, arriving: .file),
        ]
        let report = CollisionReport(items: items, gathered: true)
        #expect(report.hasKindClash)
        #expect(report.clashSentence() == "won't work — notes is a folder here and a file there")
        let clean = CollisionReport(items: [items[0]], gathered: true)
        #expect(!clean.hasKindClash)
        #expect(clean.clashSentence() == nil)
    }

    @Test("replaces and merges still compose — they are named, not refused")
    func replaceAndMergeStillCompose() throws {
        let items = [
            collision("a.txt", standing: .file, arriving: .file),
            collision("media", standing: .directory, arriving: .directory),
            collision("link", standing: .symlink, arriving: .file),
        ]
        let entries = [
            makeEntry("a.txt"), makeEntry("media", kind: .directory), makeEntry("link"),
        ]
        let plan = try plan(.move, entries: entries, to: sameHostDest, collisions: items)
        let report = try #require(plan.collisions)
        #expect(report.items.count == 3)
        #expect(!report.hasKindClash)
    }

    @Test("an ungathered destination is not a clash — the alarm line carries that truth")
    func ungatheredIsNotAClash() throws {
        let plan = try plan(.move, entries: [makeEntry("notes")], to: sameHostDest, collisions: nil)
        #expect(plan.collisions?.gathered == false)
    }

    @Test("enactment refuses a Plan that carries a clash — nothing runs, the door is never opened")
    func enactmentRefusesCarriedClash() async throws {
        let clash = collision("notes", standing: .directory, arriving: .file)
        var plan = try plan(.move, entries: [makeEntry("notes")], to: sameHostDest, collisions: [])
        // A Plan is a value — decoded from a queue, built by hand — so
        // the gate must hold here too, not only in the engine.
        plan.collisions = CollisionReport(items: [clash], gathered: true)
        let transports = Transports(conduit: RecordedConduit(transcript: ConduitTranscript())) { _, _, _ in
            Issue.record("nothing should run")
            return -1
        }
        var events: [EnactmentEvent] = []
        await #expect(throws: EnactmentError.self) {
            for try await event in transports.enact(plan) {
                events.append(event)
            }
        }
        #expect(events.isEmpty)
    }
}
