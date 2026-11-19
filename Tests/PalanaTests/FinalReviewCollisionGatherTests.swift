// The 2026-11-18 final review's F02 at the gather: a copy onto a
// case-insensitive destination discloses the file it will replace, and
// a destination that cannot be asked is reported unknown.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Final review F02 — the gather discloses resolved collisions")
struct FinalReviewCollisionGatherTests {
    private func operation() -> OperationModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let engine = Engine(
            conduit: recorded,
            field: Field(conduit: recorded, hosts: [], cache: FieldCache()),
            listing: Listing(conduit: recorded))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        return OperationModel(
            engine: engine,
            configuration: SSHConfiguration(),
            settings: settings,
            log: OperationLog(url: FileManager.default.temporaryDirectory.appendingPathComponent("palana-f02.log")))
    }

    private func file(_ name: String) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: .file,
            size: 3,
            modified: Date(timeIntervalSince1970: 1_000),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    @Test("Report.txt onto report.txt: the plan names the replace; a later, different name is clean")
    func caseVariantDisclosedThenClean() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-f02-gather-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("old".utf8).write(to: directory.appendingPathComponent("report.txt"))
        try #require(FileManager.default.fileExists(atPath: directory.appendingPathComponent("REPORT.txt").path))
        let model = operation()
        let destination = Locus(host: PalanaCore.localHostName, directory: directory.path)

        var facts = PlanFacts()
        await model.gatherCollisions(destination: destination, subjects: [file("Report.txt")], into: &facts)
        let found = try #require(facts.collisions)
        #expect(found.map(\.name) == ["report.txt"])
        #expect(model.echo.lines.contains { $0.text == "1 file already exists at destination" })

        var second = PlanFacts()
        await model.gatherCollisions(destination: destination, subjects: [file("other.txt")], into: &second)
        #expect(second.collisions?.isEmpty == true)
    }

    @Test("a destination that cannot be asked leaves the facts unknown and says so")
    func unaskableDestinationIsUnknown() async {
        let model = operation()
        var facts = PlanFacts()
        await model.gatherCollisions(
            destination: Locus(host: PalanaCore.localHostName, directory: "/nonexistent/palana-f02"),
            subjects: [file("a.txt")],
            into: &facts)
        #expect(facts.collisions == nil)
        #expect(model.echo.lines.contains { $0.text.hasPrefix("couldn't check the destination") })
    }
}
