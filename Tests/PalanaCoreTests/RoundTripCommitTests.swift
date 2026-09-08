// The version-bound send-back, live on this Mac. Every case here would
// have passed under the old shape — read a digest, compose an ordinary
// copy, overwrite — because nothing in that shape looked at the
// destination again. The destination is changed between the check and
// the commit through a step injected into the plan, exactly as another
// writer would change it, and the commit must refuse rather than
// replace work nobody approved for replacement.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Round-trip commit, live", .serialized)
struct RoundTripCommitTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-commit-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private var source: URL { root.appendingPathComponent("edit") }
    private var destination: URL { root.appendingPathComponent("remote") }
    private var name: String { "note.txt" }
    private var target: URL { destination.appendingPathComponent(name) }
    private var staging: URL {
        destination.appendingPathComponent(RemoteVersionGuard.stagingName(token: "t1"))
    }
    private var displaced: URL {
        destination.appendingPathComponent(RemoteVersionGuard.displacedName(token: "t1"))
    }

    private func makeTree(local: String, remote: String?) throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(local.utf8).write(to: source.appendingPathComponent(name))
        if let remote { try Data(remote.utf8).write(to: target) }
    }

    private func digest(_ text: String) -> String {
        RoundTrip.hex(RoundTrip.digest(of: Data(text.utf8)))
    }

    private func entry() -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: .file,
            size: 2,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    private func guardValue(expecting expected: String?) -> RemoteVersionGuard {
        RemoteVersionGuard(
            host: PalanaCore.localHostName,
            pathData: RemoteIdentity.pathData(directory: destination.path, name: Data(name.utf8)),
            expectedDigest: expected,
            token: "t1")
    }

    private func plan(expecting expected: String?) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: [entry()],
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                token: "t1",
                versionGuard: guardValue(expecting: expected)),
            facts: PlanFacts())
    }

    /// A step the test injects between the transfer and the commit —
    /// the other writer, arriving in the window the audit named.
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

    private func refusal(_ error: (any Error)?) -> String? {
        guard case EnactmentError.stepFailed(_, _, let stderrTail)? = error else { return nil }
        return stderrTail
    }

    private func text(_ url: URL) throws -> String {
        String(bytes: try Data(contentsOf: url), encoding: .utf8) ?? ""
    }

    @Test("a destination changed after the check is refused, and its later bytes stand")
    func changedDestinationIsRefused() async throws {
        try makeTree(local: "mine", remote: "checked")
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try plan(expecting: digest("checked"))
        // Another writer, after the check and before the commit.
        plan.steps.insert(
            meanwhile("printf theirs > \(ShellQuote.quote(target.path))"), at: 2)

        let outcome = await enact(plan)
        let stderrTail = try #require(refusal(outcome.error))
        #expect(stderrTail.contains("palana-refused"))
        #expect(stderrTail.contains("\(PalanaCore.localHostName):\(target.path)"))
        #expect(stderrTail.contains("not the version that was checked"))
        // The later bytes were neither lost nor replaced.
        #expect(try text(target) == "theirs")
        // The operator's edit is untouched, and nothing of this run is left.
        #expect(try text(source.appendingPathComponent(name)) == "mine")
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(!FileManager.default.fileExists(atPath: displaced.path))
    }

    @Test("a destination still at the checked version is replaced, and nothing is left behind")
    func boundCommitReplaces() async throws {
        try makeTree(local: "mine", remote: "checked")
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try plan(expecting: digest("checked"))
        let witness = root.appendingPathComponent("witness")
        // Read the destination after the bytes have travelled: nothing
        // may touch the requested pathname before the commit step.
        plan.steps.insert(
            meanwhile("cp \(ShellQuote.quote(target.path)) \(ShellQuote.quote(witness.path))"), at: 2)

        let outcome = await enact(plan)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(try text(witness) == "checked", "the pathname was untouched while bytes transferred")
        #expect(try text(target) == "mine")
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(!FileManager.default.fileExists(atPath: displaced.path))
    }

    @Test("a send-back bound to absence refuses when something now stands there")
    func absenceRefusesAnOccupiedPath() async throws {
        try makeTree(local: "mine", remote: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try plan(expecting: nil)
        plan.steps.insert(
            meanwhile("printf theirs > \(ShellQuote.quote(target.path))"), at: 2)

        let outcome = await enact(plan)
        let stderrTail = try #require(refusal(outcome.error))
        #expect(stderrTail.contains("palana-refused"))
        #expect(try text(target) == "theirs")
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("a send-back bound to absence creates the entry when the path is still free")
    func absenceCreates() async throws {
        try makeTree(local: "mine", remote: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        let outcome = await enact(try plan(expecting: nil))
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(try text(target) == "mine")
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("a destination that became a directory is refused, never replaced")
    func replacedByADirectoryIsRefused() async throws {
        try makeTree(local: "mine", remote: "checked")
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try plan(expecting: digest("checked"))
        plan.steps.insert(
            meanwhile("rm -f \(ShellQuote.quote(target.path)); mkdir \(ShellQuote.quote(target.path))"),
            at: 2)

        let outcome = await enact(plan)
        #expect(refusal(outcome.error) != nil)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("a host with no sha256 tool fails closed — the version cannot be proved, so nothing moves")
    func noDigestToolFailsClosed() async throws {
        try makeTree(local: "mine", remote: "checked")
        defer { try? FileManager.default.removeItem(at: root) }
        // A PATH holding only the movers, so `command -v` finds no
        // digest tool — the shape of a host that cannot prove content.
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for tool in ["rm", "mv", "ln", "cp", "mkdir"] {
            try? FileManager.default.createSymbolicLink(
                atPath: bin.appendingPathComponent(tool).path, withDestinationPath: "/bin/\(tool)")
        }
        var plan = try plan(expecting: digest("checked"))
        let commit = plan.steps[2]
        plan.steps[2] = PlanStep(
            runsOn: commit.runsOn,
            command: "PATH=\(ShellQuote.quote(bin.path)); export PATH; \(commit.command)",
            role: .promote)

        let outcome = await enact(plan)
        let stderrTail = try #require(refusal(outcome.error))
        #expect(stderrTail.contains("no sha256 tool"))
        #expect(try text(target) == "checked")
    }

    @Test("the commit sets the standing version aside before it takes the pathname")
    func promotionDisplacesBeforeItLinks() {
        let program = guardValue(expecting: digest("checked"))
            .commitProgram(directory: destination.path, name: name)
        let displacedAt = try? #require(program.range(of: "mv -- note.txt palana-replaced-t1"))
        let linkedAt = try? #require(
            program.range(of: "ln -- palana-send-t1/note.txt note.txt"))
        #expect(displacedAt != nil)
        #expect(linkedAt != nil)
        if let displacedAt, let linkedAt {
            #expect(displacedAt.lowerBound < linkedAt.lowerBound)
        }
        // Never a bare rename onto the requested pathname: `ln` refuses
        // atomically where `mv` would clobber whatever arrived.
        #expect(!program.contains("mv -- palana-send-t1/note.txt note.txt"))
    }

    @Test("a plan carrying a commit step with no version behind it never runs")
    func unguardedCommitStepRefused() async throws {
        try makeTree(local: "mine", remote: "checked")
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try plan(expecting: digest("checked"))
        // The shape a plan written before the binding existed decodes to.
        plan.versionGuard = nil

        let outcome = await enact(plan)
        guard case EnactmentError.malformedPlan(let reason)? = outcome.error else {
            Issue.record("expected malformedPlan, got \(String(describing: outcome.error))")
            return
        }
        #expect(reason.contains("no remote version behind it"))
        #expect(try text(target) == "checked")
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test("a guard that does not name what the plan sends is refused before composition")
    func unbindableGuardRefused() {
        let elsewhere = RemoteVersionGuard(
            host: "koan",
            pathData: Data("/rpool/cold/note.txt".utf8),
            expectedDigest: digest("checked"),
            token: "t1")
        #expect(throws: PlanError.self) {
            try PlanEngine.plan(
                PlanRequest(
                    operation: .copy,
                    source: Locus(host: PalanaCore.localHostName, directory: source.path),
                    entries: [entry()],
                    destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                    token: "t1",
                    versionGuard: elsewhere),
                facts: PlanFacts())
        }
        #expect(throws: PlanError.self) {
            try PlanEngine.plan(
                PlanRequest(
                    operation: .move,
                    source: Locus(host: PalanaCore.localHostName, directory: source.path),
                    entries: [entry()],
                    destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                    token: "t1",
                    versionGuard: guardValue(expecting: nil)),
                facts: PlanFacts())
        }
    }
}
