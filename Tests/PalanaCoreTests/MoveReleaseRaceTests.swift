// The move's release under a source and a destination that move
// underneath it, live on this Mac. Each case injects the other writer
// as a step in the plan — the window the 2026-09-08 audit named, made
// deterministic — and asks the only question that matters: what did the
// delete remove.
//
// Under the old shape the delete was `rm -rf` over the selected
// pathnames, released by a Boolean that a pair of snapshot manifests had
// flipped. A file created at one of those pathnames after the manifest
// was destroyed by a move that never carried it; a source edited after
// its manifest was destroyed by a move that carried the older bytes.

import Foundation
import Testing

@testable import PalanaCore

/// A sink the enactment's `@Sendable` emit can write to.
private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [EnactmentEvent] = []

    func append(_ event: EnactmentEvent) { lock.withLock { stored.append(event) } }
    var events: [EnactmentEvent] { lock.withLock { stored } }
}

@Suite("MoveRelease under a moving source and destination", .serialized)
struct MoveReleaseRaceTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-release-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private var source: URL { root.appendingPathComponent("src") }
    private var destination: URL { root.appendingPathComponent("dst") }
    private var quarantine: URL {
        source.appendingPathComponent(MoveRelease.quarantineName(token: "t1"))
    }

    private func makeTree() throws {
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("nested".utf8).write(to: source.appendingPathComponent("dir/b.txt"))
    }

    private func plan() async throws -> Plan {
        let entries = try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: source.path, flavor: .bsd)
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: entries,
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                token: "t1"),
            // No mount facts: unproven, so the verified copy-then-delete.
            facts: PlanFacts())
    }

    /// The other writer, arriving as a step at a chosen point.
    private func meanwhile(_ command: String) -> PlanStep {
        PlanStep(runsOn: .host(PalanaCore.localHostName), command: command, role: .copy)
    }

    private func enact(_ plan: Plan) async -> (error: (any Error)?, events: [EnactmentEvent]) {
        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        var events: [EnactmentEvent] = []
        do {
            for try await event in transports.enact(plan) {
                events.append(event)
            }
            return (nil, events)
        } catch {
            return (error, events)
        }
    }

    private func retained(_ events: [EnactmentEvent]) -> RecoveryNote? {
        events.compactMap { event -> RecoveryNote? in
            guard case .recovery(let note) = event, note.kind == .retained else { return nil }
            return note
        }.first
    }

    private func text(_ url: URL) throws -> String {
        String(bytes: try Data(contentsOf: url), encoding: .utf8) ?? ""
    }

    @Test("an entry created at a released pathname survives the delete")
    func newEntryAtTheOldPathnameSurvives() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try await plan()
        #expect(plan.steps.map(\.role) == [.copy, .quarantine, .delete])
        // The operator writes a new a.txt at a name this move no longer
        // holds — after the freeze, before the delete.
        plan.steps.insert(
            meanwhile("printf brandnew > \(ShellQuote.quote(source.appendingPathComponent("a.txt").path))"),
            at: 2)

        let outcome = await enact(plan)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(outcome.events.last == .finished)
        // The delete removed the frozen bytes and nothing else.
        #expect(try text(source.appendingPathComponent("a.txt")) == "brandnew")
        #expect(!FileManager.default.fileExists(atPath: quarantine.path))
        #expect(try text(destination.appendingPathComponent("a.txt")) == "hello")
    }

    @Test("a source edited after the copy is never deleted as though its newer bytes travelled")
    func sourceEditedAfterCopyIsKept() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try await plan()
        // The edit lands after the bytes travelled and before the freeze,
        // so the frozen source no longer matches what reached the
        // destination — and its newer bytes are the ones at stake.
        plan.steps.insert(
            meanwhile(
                "printf edited-after-the-copy > "
                    + "\(ShellQuote.quote(source.appendingPathComponent("a.txt").path))"),
            at: 1)

        let outcome = await enact(plan)
        guard case EnactmentError.verificationFailed(.manifests(let src, let dst))? = outcome.error else {
            Issue.record("expected verificationFailed, got \(String(describing: outcome.error))")
            return
        }
        #expect(src.firstUnmatched(in: dst) == "a.txt")
        #expect(try text(quarantine.appendingPathComponent("a.txt")) == "edited-after-the-copy")
        let note = try #require(retained(outcome.events))
        #expect(note.host == PalanaCore.localHostName)
        #expect(note.detail.contains(quarantine.path))
    }

    @Test("a destination changed before the evidence is read never authorises the delete")
    func changedDestinationNeverAuthorises() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try await plan()
        plan.steps.insert(
            meanwhile(
                "printf tampered > "
                    + "\(ShellQuote.quote(destination.appendingPathComponent("a.txt").path))"),
            at: 1)

        let outcome = await enact(plan)
        #expect(EnactmentErrorShape.isVerificationFailed(outcome.error))
        // Every source byte is recoverable, and the run said where.
        #expect(try text(quarantine.appendingPathComponent("a.txt")) == "hello")
        #expect(try text(quarantine.appendingPathComponent("dir/b.txt")) == "nested")
        #expect(retained(outcome.events)?.detail.contains(quarantine.path) == true)
    }

    @Test("an interruption after the freeze leaves a named, recoverable source")
    func cancellationAfterTheFreezeLeavesTheSource() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try await plan()
        let marker = root.appendingPathComponent("running")
        plan.steps.insert(
            meanwhile("touch \(ShellQuote.quote(marker.path)); sleep 30"), at: 2)

        let box = EventBox()
        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        let run = Task {
            try await transports.run(plan) { box.append($0) }
        }
        _ = await ProcessFixture.waitUntil {
            FileManager.default.fileExists(atPath: marker.path)
        }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }

        #expect(try text(quarantine.appendingPathComponent("a.txt")) == "hello")
        #expect(try text(quarantine.appendingPathComponent("dir/b.txt")) == "nested")
        let note = try #require(retained(box.events))
        #expect(note.detail.contains(quarantine.path))
    }

    @Test("a plan whose delete has no frozen source behind it never runs")
    func unfrozenGatedDeleteRefused() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try await plan()
        // The shape a plan written before the binding existed decodes to:
        // a gated `rm -rf` over the selected pathnames, and no freeze.
        plan.moveRelease = nil
        plan.steps = [
            plan.steps[0],
            PlanStep(
                runsOn: .host(PalanaCore.localHostName),
                command: "rm -rf \(ShellQuote.quote(source.appendingPathComponent("a.txt").path))",
                role: .delete,
                gatedOnVerification: true),
        ]

        let outcome = await enact(plan)
        guard case EnactmentError.malformedPlan(let reason)? = outcome.error else {
            Issue.record("expected malformedPlan, got \(String(describing: outcome.error))")
            return
        }
        #expect(reason.contains("no frozen source behind it"))
        #expect(try text(source.appendingPathComponent("a.txt")) == "hello")
    }

    @Test("the freeze refuses a quarantine name it does not own, and deletes nothing")
    func occupiedQuarantineNameRefuses() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let plan = try await plan()

        let outcome = await enact(plan)
        guard case EnactmentError.stepFailed(let index, _, let stderrTail)? = outcome.error else {
            Issue.record("expected stepFailed, got \(String(describing: outcome.error))")
            return
        }
        #expect(index == 1)
        #expect(stderrTail.contains("palana-refused"))
        #expect(try text(source.appendingPathComponent("a.txt")) == "hello")
    }
}

/// Shape questions the race cases ask of a thrown error.
enum EnactmentErrorShape {
    static func isVerificationFailed(_ error: (any Error)?) -> Bool {
        guard case EnactmentError.verificationFailed(let report)? = error else { return false }
        return !report.matched
    }
}
