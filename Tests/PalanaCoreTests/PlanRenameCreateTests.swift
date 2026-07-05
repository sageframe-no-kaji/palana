// Rename and create compose tests — the engine's two new verbs. Exact
// command strings are the contract: the panel shows exactly these and
// the operator was promised paste-able truth. Refusal tests lock the
// typed PlanError values. The Codable round-trip confirms PlanOperation
// raw values belong to the on-disk vocabulary.

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

@Suite("PlanEngine rename compose")
struct PlanRenameComposeTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")

    private func planRename(
        entry: FileEntry,
        targetName: String,
        destination: Locus? = nil
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .rename,
                source: source,
                entries: [entry],
                destination: destination,
                token: "t1",
                targetName: targetName),
            facts: PlanFacts())
    }

    @Test("rename composes a guarded mv and a verification step — safe names")
    func renameSimpleNames() throws {
        let plan = try planRename(entry: makeEntry("document.txt"), targetName: "renamed.txt")
        #expect(
            plan.steps.map(\.command) == [
                "test -e /tank/media/renamed.txt && { echo refused: /tank/media/renamed.txt exists >&2; exit 1; };"
                    + " mv -- /tank/media/document.txt /tank/media/renamed.txt",
                "test -e /tank/media/renamed.txt && test ! -e /tank/media/document.txt",
            ])
        #expect(plan.steps.map(\.role) == [.rename, .verify])
        #expect(plan.steps.map(\.runsOn) == [.host("jodo"), .host("jodo")])
        #expect(plan.steps.map(\.gatedOnVerification) == [false, false])
    }

    @Test("rename quotes spaced names through the full command — paste-able truth")
    func renameSpacedNames() throws {
        let plan = try planRename(entry: makeEntry("old file.txt"), targetName: "new name.txt")
        #expect(
            plan.steps.map(\.command) == [
                "test -e '/tank/media/new name.txt' && { echo refused: '/tank/media/new name.txt' exists >&2; exit 1; };"
                    + " mv -- '/tank/media/old file.txt' '/tank/media/new name.txt'",
                "test -e '/tank/media/new name.txt' && test ! -e '/tank/media/old file.txt'",
            ])
    }

    @Test("rename classifies as withinDatasetRename, transports local, destination nil")
    func renameClassification() throws {
        let plan = try planRename(entry: makeEntry("a.txt"), targetName: "b.txt")
        #expect(plan.classification == .withinDatasetRename)
        #expect(plan.transport == .local)
        #expect(plan.destination == nil)
        #expect(plan.operation == .rename)
    }

    @Test("rename refuses more than one selected entry")
    func renameRequiresOneEntry() {
        let entries = [makeEntry("a.txt"), makeEntry("b.txt")]
        #expect(throws: PlanError.renameRequiresOneEntry) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .rename,
                    source: source,
                    entries: entries,
                    targetName: "c.txt"),
                facts: PlanFacts())
        }
    }

    @Test("rename refuses an empty targetName")
    func renameEmptyName() {
        #expect(throws: PlanError.targetNameRequired) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .rename,
                    source: source,
                    entries: [makeEntry("a.txt")],
                    targetName: ""),
                facts: PlanFacts())
        }
    }

    @Test("rename refuses a nil targetName")
    func renameNilTargetName() {
        #expect(throws: PlanError.targetNameRequired) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .rename,
                    source: source,
                    entries: [makeEntry("a.txt")]),
                facts: PlanFacts())
        }
    }

    @Test("rename refuses a targetName containing a path separator")
    func renameEmbeddedSlash() {
        for name in ["sub/dir", "/abs", "a/b/c"] {
            #expect(throws: PlanError.targetNameContainsSeparator) {
                _ = try PlanEngine.plan(
                    PlanRequest(
                        operation: .rename,
                        source: source,
                        entries: [makeEntry("a.txt")],
                        targetName: name),
                    facts: PlanFacts())
            }
        }
    }

    @Test("rename refuses when the target name is the current name")
    func renameUnchangedName() {
        #expect(throws: PlanError.targetNameUnchanged) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .rename,
                    source: source,
                    entries: [makeEntry("a.txt")],
                    targetName: "a.txt"),
                facts: PlanFacts())
        }
    }

    @Test("rename refuses a non-nil destination")
    func renameDestinationForbidden() {
        #expect(throws: PlanError.destinationForbidden) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .rename,
                    source: source,
                    entries: [makeEntry("a.txt")],
                    destination: Locus(host: "jodo", directory: "/tank/other"),
                    targetName: "b.txt"),
                facts: PlanFacts())
        }
    }

    @Test("a rename Plan round-trips JSON whole — PlanOperation raw value is vocabulary")
    func codableRoundTrip() throws {
        let plan = try planRename(entry: makeEntry("a.txt"), targetName: "b.txt")
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded == plan)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"rename\""), "PlanOperation.rename raw value is 'rename'")
    }
}

@Suite("PlanEngine create compose")
struct PlanCreateComposeTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")

    private func planCreate(
        name: String,
        destination: Locus? = nil,
        entries: [FileEntry] = []
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .create,
                source: source,
                entries: entries,
                destination: destination,
                token: "t1",
                targetName: name),
            facts: PlanFacts())
    }

    @Test("create directory composes mkdir and a test -d verification step")
    func createDirectory() throws {
        let plan = try planCreate(name: "newdir/")
        #expect(
            plan.steps.map(\.command) == [
                "mkdir -- /tank/media/newdir",
                "test -d /tank/media/newdir",
            ])
        #expect(plan.steps.map(\.role) == [.create, .verify])
        #expect(plan.steps.map(\.runsOn) == [.host("jodo"), .host("jodo")])
        #expect(plan.steps.map(\.gatedOnVerification) == [false, false])
    }

    @Test("create directory quotes spaced names through both steps")
    func createDirectorySpacedName() throws {
        let plan = try planCreate(name: "new dir/")
        #expect(
            plan.steps.map(\.command) == [
                "mkdir -- '/tank/media/new dir'",
                "test -d '/tank/media/new dir'",
            ])
    }

    @Test("create file composes a guarded touch and a test -f verification step")
    func createFile() throws {
        let plan = try planCreate(name: "newfile.txt")
        #expect(
            plan.steps.map(\.command) == [
                "test -e /tank/media/newfile.txt && { echo refused: /tank/media/newfile.txt exists >&2; exit 1; };"
                    + " touch -- /tank/media/newfile.txt",
                "test -f /tank/media/newfile.txt",
            ])
        #expect(plan.steps.map(\.role) == [.create, .verify])
    }

    @Test("create classifies as creation, transports local, destination nil")
    func createClassification() throws {
        let plan = try planCreate(name: "foo.txt")
        #expect(plan.classification == .creation)
        #expect(plan.transport == .local)
        #expect(plan.destination == nil)
        #expect(plan.operation == .create)
    }

    @Test("create refuses an empty targetName")
    func createEmptyName() {
        #expect(throws: PlanError.targetNameRequired) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .create,
                    source: source,
                    entries: [],
                    targetName: ""),
                facts: PlanFacts())
        }
    }

    @Test("create refuses a bare slash — the directory marker needs a name")
    func createBareSlash() {
        #expect(throws: PlanError.targetNameRequired) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .create,
                    source: source,
                    entries: [],
                    targetName: "/"),
                facts: PlanFacts())
        }
    }

    @Test("create refuses a targetName with an embedded separator")
    func createEmbeddedSlash() {
        for name in ["sub/dir/", "sub/file", "/abs"] {
            #expect(throws: PlanError.targetNameContainsSeparator) {
                _ = try PlanEngine.plan(
                    PlanRequest(
                        operation: .create,
                        source: source,
                        entries: [],
                        targetName: name),
                    facts: PlanFacts())
            }
        }
    }

    @Test("create refuses a non-nil destination")
    func createDestinationForbidden() {
        #expect(throws: PlanError.destinationForbidden) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .create,
                    source: source,
                    entries: [],
                    destination: Locus(host: "jodo", directory: "/tank/other"),
                    targetName: "foo.txt"),
                facts: PlanFacts())
        }
    }

    @Test("create refuses a non-empty selection")
    func createEntriesForbidden() {
        #expect(throws: PlanError.entriesForbiddenForCreate) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .create,
                    source: source,
                    entries: [makeEntry("a.txt")],
                    targetName: "b.txt"),
                facts: PlanFacts())
        }
    }
}
