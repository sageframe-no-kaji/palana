// The whole gate, live on this Mac: a real copy-freeze-then-gated-delete
// plan composed by the engine for a local move with no filesystem proof,
// enacted through LocalConduit against a temporary tree. The faithful
// case deletes the frozen source; a destination tampered between copy
// and check keeps every byte of it, under the named recovery directory
// the run reports.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Transports local gate, live", .serialized)
struct TransportsLocalGateTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-gate-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private var source: URL { root.appendingPathComponent("src") }
    private var destination: URL { root.appendingPathComponent("dst") }

    private func makeTree() throws {
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("nested".utf8).write(to: source.appendingPathComponent("dir/b.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("dir/link").path, withDestinationPath: "b.txt")
    }

    private func listing() async throws -> [FileEntry] {
        try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: source.path, flavor: .bsd)
    }

    private func plan(entries: [FileEntry]) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: entries,
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                token: "t1"),
            // No mount facts: unproven, so the verified copy-then-delete.
            facts: PlanFacts())
    }

    /// Where a frozen source stands while the gate decides.
    private var quarantine: URL {
        source.appendingPathComponent(MoveRelease.quarantineName(token: "t1"))
    }

    /// The recovery note the run emitted, if any.
    private func retained(_ events: [EnactmentEvent]) -> RecoveryNote? {
        events.compactMap { event -> RecoveryNote? in
            guard case .recovery(let note) = event, note.kind == .retained else { return nil }
            return note
        }.first
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

    @Test("a faithful local move: copy, both manifests agree, the source is deleted")
    func faithfulMoveDeletesSource() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try await listing()
        #expect(Set(entries.map(\.name)) == ["a.txt", "dir"])
        let plan = try plan(entries: entries)
        #expect(plan.classification == .crossDatasetCopyPlusDelete)
        #expect(plan.steps.map(\.role) == [.copy, .quarantine, .delete])

        let outcome = await enact(plan)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(outcome.events.last == .finished)
        let matched = outcome.events.contains {
            if case .verified(.manifests(let src, let dst)) = $0 {
                return src == dst && src.entries.count == 4
            }
            return false
        }
        #expect(matched)
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("a.txt").path))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("dir").path))
        let landed = try Data(contentsOf: destination.appendingPathComponent("dir/b.txt"))
        #expect(landed == Data("nested".utf8))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: destination.appendingPathComponent("dir/link").path) == "b.txt")
    }

    @Test("a destination that differs after the copy keeps the source untouched")
    func tamperedDestinationKeepsSource() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try await listing()
        var plan = try plan(entries: entries)
        // Stand in for a copy that landed wrong: the destination already
        // holds the names, one byte different at the same size, and the
        // copy step itself does nothing. Same counts, same names.
        let sabotage =
            "cp -R -P \(ShellQuote.quote(source.path))/. \(ShellQuote.quote(destination.path))/"
            + " && printf jello > \(ShellQuote.quote(destination.appendingPathComponent("a.txt").path))"
        plan.steps[0] = PlanStep(runsOn: plan.steps[0].runsOn, command: sabotage, role: .copy)

        let outcome = await enact(plan)
        guard case EnactmentError.verificationFailed(.manifests(let src, let dst))? = outcome.error else {
            Issue.record("expected verificationFailed, got \(String(describing: outcome.error))")
            return
        }
        #expect(src.entries.count == dst.entries.count)
        #expect(src.firstUnmatched(in: dst) == "a.txt")
        #expect(
            !outcome.events.contains {
                guard case .stepBegan(2, _) = $0 else { return false }
                return true
            })
        // Every byte survives, under the recovery name the run named.
        let kept = try Data(contentsOf: quarantine.appendingPathComponent("a.txt"))
        #expect(kept == Data("hello".utf8))
        #expect(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent("dir/b.txt").path))
        let note = try #require(retained(outcome.events))
        #expect(note.detail.contains(quarantine.path))
    }

    @Test("a copy step that silently dropped a file keeps the source — the manifest omits it")
    func droppedFileKeepsSource() async throws {
        try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try await listing()
        var plan = try plan(entries: entries)
        // Only the directory lands; a.txt never does. The old count gate
        // would have asked find about a missing path and read 0 as truth.
        plan.steps[0] = PlanStep(
            runsOn: plan.steps[0].runsOn,
            command: "cp -R -P \(ShellQuote.quote(source.appendingPathComponent("dir").path)) "
                + "\(ShellQuote.quote(destination.path))/",
            role: .copy)

        let outcome = await enact(plan)
        guard case EnactmentError.verificationUnavailable(let host, let detail)? = outcome.error else {
            Issue.record("expected verificationUnavailable, got \(String(describing: outcome.error))")
            return
        }
        #expect(host == PalanaCore.localHostName)
        #expect(detail.contains("missing: ./a.txt"))
        #expect(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent("a.txt").path))
        let note = try #require(retained(outcome.events))
        #expect(note.detail.contains(quarantine.path))
    }
}
