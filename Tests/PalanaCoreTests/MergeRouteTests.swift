// A merge is never a rename. A same-disk move whose report said "will
// merge into dir" used to compose as `mv a/dir b/` — and with `b/dir`
// standing, mv does not merge: rename(2) refuses a non-empty directory,
// and some userlands nest the source as `b/dir/dir` instead. The plan
// text was false, and renames never reach the manifest gate, so nothing
// caught it (2026-09-07 hands session). The engine now routes any plan
// carrying a `.merge` collision through copy, check, then delete, proof
// of a shared filesystem or not; replaces still rename.

import Foundation
import Testing

@testable import PalanaCore

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

private func collision(_ name: String, standing: FileEntry.Kind, arriving: FileEntry.Kind) -> Collision {
    Collision(
        nameData: Data(name.utf8),
        standingKind: standing,
        standingSize: 500,
        standingModified: .distantPast,
        arrivingKind: arriving)
}

@Suite("Merge route — a merge is never a rename")
struct MergeRouteTests {
    private let source = Locus(host: "jodo", directory: "/tank/a")
    private let destination = Locus(host: "jodo", directory: "/tank/b")
    private let tank = ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)

    private func plan(entries: [FileEntry], facts: PlanFacts) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: source,
                entries: entries,
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    @Test("a merge on a proven-shared mount composes copy, check, then delete — never mv")
    func mergeOnSharedMountCopiesThenDeletes() throws {
        let merge = collision("dir", standing: .directory, arriving: .directory)
        let plan = try plan(
            entries: [makeEntry("dir", kind: .directory)],
            facts: PlanFacts(sourceMountTarget: "/tank", destinationMountTarget: "/tank", collisions: [merge]))
        #expect(plan.classification == .crossDatasetCopyPlusDelete)
        #expect(plan.steps.map(\.role) == [.copy, .quarantine, .delete])
        #expect(plan.steps.map(\.gatedOnVerification) == [false, false, true])
        #expect(
            plan.steps.map(\.command) == [
                "cp -a /tank/a/dir /tank/b/",
                MoveFixture.quarantine("jodo", "/tank/a", ["dir"], "t1"),
                MoveFixture.remove("/tank/a", "t1"),
            ])
        #expect(!plan.steps.contains { $0.command.hasPrefix("mv ") })
        #expect(plan.collisions?.sentence() == "will merge into dir")
    }

    @Test("a merge on a proven-same dataset takes the same route — the ZFS proof does not rename it")
    func mergeOnSameDatasetCopiesThenDeletes() throws {
        let merge = collision("dir", standing: .directory, arriving: .directory)
        let plan = try plan(
            entries: [makeEntry("dir", kind: .directory)],
            facts: PlanFacts(sourceDataset: tank, destinationDataset: tank, collisions: [merge]))
        #expect(plan.classification == .crossDatasetCopyPlusDelete)
        #expect(plan.steps.map(\.role) == [.copy, .quarantine, .delete])
        #expect(plan.steps.last?.gatedOnVerification == true)
    }

    @Test("the plan's text names the route honestly — no 'instant', copy then check then delete")
    func planTextNamesTheRoute() throws {
        let merge = collision("dir", standing: .directory, arriving: .directory)
        let plan = try plan(
            entries: [makeEntry("dir", kind: .directory)],
            facts: PlanFacts(sourceMountTarget: "/tank", destinationMountTarget: "/tank", collisions: [merge]))
        let name = plan.classification.plainName
        #expect(!name.contains("instant"))
        #expect(!name.contains("same disk"))
        #expect(name == "copy, check, then delete the original")
    }

    @Test("one merge among many entries reroutes the whole plan — mv runs the batch, not the entry")
    func oneMergeReroutesTheBatch() throws {
        let items = [
            collision("a.txt", standing: .file, arriving: .file),
            collision("dir", standing: .directory, arriving: .directory),
        ]
        let plan = try plan(
            entries: [makeEntry("a.txt"), makeEntry("dir", kind: .directory), makeEntry("free")],
            facts: PlanFacts(sourceMountTarget: "/tank", destinationMountTarget: "/tank", collisions: items))
        #expect(plan.classification == .crossDatasetCopyPlusDelete)
        #expect(plan.steps.map(\.role) == [.copy, .quarantine, .delete])
    }

    @Test("a replace on a proven-shared mount still renames — mv overwrites a file as the plan says")
    func replaceStillRenames() throws {
        let replace = collision("a.txt", standing: .file, arriving: .file)
        let plan = try plan(
            entries: [makeEntry("a.txt")],
            facts: PlanFacts(sourceMountTarget: "/tank", destinationMountTarget: "/tank", collisions: [replace]))
        #expect(plan.classification == .withinDatasetRename)
        #expect(plan.steps.map(\.command) == ["mv /tank/a/a.txt /tank/b/"])
        #expect(plan.classification.plainName == "move on the same disk (instant)")
    }

    @Test("a clean or ungathered destination on a proven-shared mount still renames")
    func cleanDestinationStillRenames() throws {
        for collisions in [[Collision]?.some([]), nil] {
            let plan = try plan(
                entries: [makeEntry("dir", kind: .directory)],
                facts: PlanFacts(
                    sourceMountTarget: "/tank", destinationMountTarget: "/tank", collisions: collisions))
            #expect(plan.classification == .withinDatasetRename)
            #expect(plan.steps.map(\.role) == [.rename])
        }
    }
}

@Suite("Merge route, live on this Mac", .serialized)
struct MergeRouteLiveTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-merge-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private var sourceDirectory: URL { root.appendingPathComponent("a") }
    private var destinationDirectory: URL { root.appendingPathComponent("b") }

    /// `a/dir/x.txt` arriving on a standing `b/dir/old.txt`.
    private func makeTrees() throws {
        try FileManager.default.createDirectory(
            at: sourceDirectory.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: destinationDirectory.appendingPathComponent("dir"), withIntermediateDirectories: true)
        try Data("arriving".utf8).write(to: sourceDirectory.appendingPathComponent("dir/x.txt"))
        try Data("standing".utf8).write(to: destinationDirectory.appendingPathComponent("dir/old.txt"))
    }

    private func listing(_ directory: URL) async throws -> [FileEntry] {
        try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: directory.path, flavor: .bsd)
    }

    @Test("a/dir onto a standing b/dir lands x.txt beside old.txt, never as b/dir/dir, and deletes a/dir")
    func liveMergeLandsBesideAndDeletesSource() async throws {
        try makeTrees()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try await listing(sourceDirectory)
        let collisions = Collision.detect(
            sources: entries, destinationListing: try await listing(destinationDirectory))
        #expect(collisions.map(\.nature) == [.merge])

        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: sourceDirectory.path),
                entries: entries,
                destination: Locus(host: PalanaCore.localHostName, directory: destinationDirectory.path),
                token: "t1"),
            // Both ends proven on one mount — the case that used to be mv.
            facts: PlanFacts(sourceMountTarget: "/", destinationMountTarget: "/", collisions: collisions))
        #expect(plan.classification == .crossDatasetCopyPlusDelete)
        #expect(plan.steps.map(\.role) == [.copy, .quarantine, .delete])

        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        var events: [EnactmentEvent] = []
        do {
            for try await event in transports.enact(plan) {
                events.append(event)
            }
        } catch {
            Issue.record("enactment threw \(error)")
        }
        #expect(events.last == .finished)
        let verified = events.contains {
            if case .verified(let report) = $0 { return report.matched }
            return false
        }
        #expect(verified, "the subset gate released the delete over the standing old.txt")

        let landed = destinationDirectory.appendingPathComponent("dir")
        #expect(try Data(contentsOf: landed.appendingPathComponent("x.txt")) == Data("arriving".utf8))
        #expect(try Data(contentsOf: landed.appendingPathComponent("old.txt")) == Data("standing".utf8))
        #expect(!FileManager.default.fileExists(atPath: landed.appendingPathComponent("dir").path))
        #expect(!FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("dir").path))
    }
}

@Suite("Merge gate over transcripts — the subset rule releases and holds")
struct MergeGateTranscriptTests {
    private static func directoryMove() throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank/a"),
                entries: [makeEntry("dir", kind: .directory)],
                destination: Locus(host: "j", directory: "/tank/b"),
                token: "t1"),
            facts: PlanFacts())
    }

    private static func entry(_ command: String, stdout: String = "") -> ConduitTranscript.Entry {
        ConduitTranscript.Entry(host: "j", command: command, stdout: stdout, stderr: "", exit: 0)
    }

    /// Enacts over the transcript: the thrown error, nil on success, and the events.
    private static func enact(
        _ plan: Plan, over transcriptEntries: [ConduitTranscript.Entry]
    ) async -> (error: (any Error)?, events: [EnactmentEvent]) {
        let transports = Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript(entries: transcriptEntries))
        ) { _, _, _ in 0 }
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

    @Test("pre-existing destination entries under a merged directory release the delete — the subset rule")
    func preExistingDestinationEntriesRelease() async throws {
        // The gate used to demand exact equality, so a merge into a
        // directory holding other entries never deleted its source.
        // Every source byte is proven at the destination here; what
        // stood there before is the destination's own (2026-09-07).
        let plan = try Self.directoryMove()
        let source = ManifestFixture.directory("dir") + ManifestFixture.file("dir/x")
        let landed = source + ManifestFixture.file("dir/old")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.entry("cp -a /tank/a/dir /tank/b/"),
                Self.entry(MoveFixture.quarantine("j", "/tank/a", ["dir"], "t1")),
                Self.entry(
                    ManifestFixture.command(MoveFixture.directory("/tank/a", "t1"), ["dir"]),
                    stdout: source),
                Self.entry(ManifestFixture.command("/tank/b", ["dir"]), stdout: landed),
                Self.entry(MoveFixture.remove("/tank/a", "t1")),
            ])
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(outcome.events.last == .finished)
    }

    @Test("a source entry the merged destination lacks keeps the delete closed, and is named")
    func missingSourceEntryUnderMergeHoldsGate() async throws {
        // No rm entry in the transcript: a gate leak would surface as
        // UnrecordedCommand, not verificationFailed.
        let plan = try Self.directoryMove()
        let source =
            ManifestFixture.directory("dir") + ManifestFixture.file("dir/x") + ManifestFixture.file("dir/y")
        let landed = ManifestFixture.directory("dir") + ManifestFixture.file("dir/x") + ManifestFixture.file("dir/old")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.entry("cp -a /tank/a/dir /tank/b/"),
                Self.entry(MoveFixture.quarantine("j", "/tank/a", ["dir"], "t1")),
                Self.entry(
                    ManifestFixture.command(MoveFixture.directory("/tank/a", "t1"), ["dir"]),
                    stdout: source),
                Self.entry(ManifestFixture.command("/tank/b", ["dir"]), stdout: landed),
            ])
        guard case EnactmentError.verificationFailed(.manifests(let src, let dst))? = outcome.error else {
            Issue.record("expected verificationFailed, got \(String(describing: outcome.error))")
            return
        }
        #expect(src.firstUnmatched(in: dst) == "dir/y")
        #expect(
            !outcome.events.contains {
                guard case .stepBegan(2, _) = $0 else { return false }
                return true
            })
        // The frozen source is named, so the operator can reach it.
        #expect(
            outcome.events.contains {
                guard case .recovery(let note) = $0 else { return false }
                return note.kind == .retained
                    && note.detail.contains(MoveFixture.directory("/tank/a", "t1"))
            })
    }
}
