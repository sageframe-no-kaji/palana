// Create and rename against dangling symbolic links — the plan's guard
// judges the directory entry itself, not what it points at. Every case
// composes a real plan and runs its steps in a local shell over a fresh
// temporary directory: `test -e` alone let `touch` and `mv` land through
// a dangling link onto its target, outside the chosen directory (review).

import Foundation
import Testing

@testable import PalanaCore

@Suite("Plan create/rename — dangling symlink refusal")
struct PlanSymlinkGuardTests {
    private let directory: URL
    private let elsewhere: URL

    init() throws {
        directory = try ProcessFixture.makeDirectory()
        elsewhere = directory.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    }

    private var source: Locus { Locus(host: PalanaCore.localHostName, directory: directory.path) }

    private func entry(_ name: String, kind: FileEntry.Kind) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: 0,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    /// A link at `name` pointing at a path under `elsewhere` that does not exist.
    private func danglingLink(named name: String) throws -> URL {
        let link = directory.appendingPathComponent(name)
        let target = elsewhere.appendingPathComponent("target-of-\(name)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return target
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Runs the plan's steps in order in the local shell, stopping at the
    /// first nonzero exit — the workbench's discipline, in miniature.
    private func run(_ plan: Plan) async throws -> (status: Int32, stderr: String) {
        for step in plan.steps {
            let result = try await LocalConduit().run(on: "local", step.command).collect()
            if result.exitStatus != 0 { return (result.exitStatus, result.stderrText) }
        }
        return (0, "")
    }

    @Test("create file refuses a dangling link and never creates its target")
    func createFileRefusesDanglingLink() async throws {
        let target = try danglingLink(named: "newfile.txt")
        let plan = try PlanEngine.plan(
            PlanRequest(operation: .create, source: source, entries: [], targetName: "newfile.txt"),
            facts: PlanFacts())

        let outcome = try await run(plan)

        #expect(outcome.status == 1)
        #expect(outcome.stderr.contains("refused"), "the refusal is a sentence, not a bare exit")
        #expect(!FileManager.default.fileExists(atPath: target.path), "touch must not follow the link")
        #expect(isSymlink(directory.appendingPathComponent("newfile.txt")), "the link is left as it was")
    }

    @Test("create directory refuses a dangling link, legibly")
    func createDirectoryRefusesDanglingLink() async throws {
        let target = try danglingLink(named: "newdir")
        let plan = try PlanEngine.plan(
            PlanRequest(operation: .create, source: source, entries: [], targetName: "newdir/"),
            facts: PlanFacts())

        let outcome = try await run(plan)

        #expect(outcome.status == 1)
        #expect(outcome.stderr.contains("refused"))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("rename refuses a dangling link at the new name and leaves both entries alone")
    func renameRefusesDanglingLink() async throws {
        let old = directory.appendingPathComponent("old.txt")
        try Data("keep".utf8).write(to: old)
        let target = try danglingLink(named: "new.txt")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .rename,
                source: source,
                entries: [entry("old.txt", kind: .file)],
                targetName: "new.txt"),
            facts: PlanFacts())

        let outcome = try await run(plan)

        #expect(outcome.status == 1)
        #expect(outcome.stderr.contains("refused"))
        #expect(FileManager.default.fileExists(atPath: old.path), "mv never ran")
        #expect(isSymlink(directory.appendingPathComponent("new.txt")), "the link was not replaced")
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("renaming a dangling link itself verifies on the entry, not its missing target")
    func renameOfDanglingLinkVerifies() async throws {
        _ = try danglingLink(named: "link")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .rename,
                source: source,
                entries: [entry("link", kind: .symlink)],
                targetName: "moved-link"),
            facts: PlanFacts())

        let outcome = try await run(plan)

        #expect(outcome.status == 0, "the verify step must see the renamed link: \(outcome.stderr)")
        #expect(isSymlink(directory.appendingPathComponent("moved-link")))
        #expect(!isSymlink(directory.appendingPathComponent("link")))
    }

    @Test("create file where nothing exists lands as a regular file and verifies")
    func createFileLands() async throws {
        let plan = try PlanEngine.plan(
            PlanRequest(operation: .create, source: source, entries: [], targetName: "fresh.txt"),
            facts: PlanFacts())

        let outcome = try await run(plan)

        #expect(outcome.status == 0, "\(outcome.stderr)")
        let fresh = directory.appendingPathComponent("fresh.txt")
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(!isSymlink(fresh))
    }

    @Test("create directory where nothing exists lands and verifies")
    func createDirectoryLands() async throws {
        let plan = try PlanEngine.plan(
            PlanRequest(operation: .create, source: source, entries: [], targetName: "fresh-dir/"),
            facts: PlanFacts())

        let outcome = try await run(plan)

        #expect(outcome.status == 0, "\(outcome.stderr)")
        var isDirectory: ObjCBool = false
        let fresh = directory.appendingPathComponent("fresh-dir")
        #expect(FileManager.default.fileExists(atPath: fresh.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
