// A progressive local move through the same conduit used by the app.

import Foundation
import Testing

@testable import PalanaCore

@Suite("rsync move, live", .serialized)
struct RsyncMoveLiveTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-rsyncmv-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private var source: URL { root.appendingPathComponent("src") }
    private var destination: URL { root.appendingPathComponent("dst") }

    private func capability() throws -> HostCapability {
        let path = try #require(
            ["/usr/bin/rsync", "/opt/homebrew/bin/rsync"]
                .first { FileManager.default.isExecutableFile(atPath: $0) })
        let version =
            path == "/usr/bin/rsync"
            ? "openrsync: protocol version 29" : "rsync  version 3.4.1"
        return HostCapability(
            kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: version, rsyncPath: path)
    }

    private func entry(_ name: String, kind: FileEntry.Kind) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: 0,
            modified: Date(timeIntervalSince1970: 0),
            permissions: kind == .directory ? "755" : "644",
            owner: "op",
            group: "op")
    }

    private func plan(entries: [FileEntry]) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: entries,
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                token: "t1"),
            facts: PlanFacts(sourceCapability: try capability()))
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

    @Test("files land and emptied source directories are removed")
    func completeMove() async throws {
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("folder/inner"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("top".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("nested".utf8).write(to: source.appendingPathComponent("folder/inner/b.txt"))

        let move = try plan(entries: [entry("a.txt", kind: .file), entry("folder", kind: .directory)])
        let outcome = await enact(move)

        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(outcome.events.last == .finished)
        #expect(try Data(contentsOf: destination.appendingPathComponent("a.txt")) == Data("top".utf8))
        #expect(
            try Data(contentsOf: destination.appendingPathComponent("folder/inner/b.txt"))
                == Data("nested".utf8))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("a.txt").path))
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("folder").path))
    }

    @Test("a retained selected source is named and prevents success")
    func retainedSourceIsReported() async throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = source.appendingPathComponent("retained.txt")
        try Data("still here".utf8).write(to: retained)
        let command = PlanEngine.leftoverSourceReport(
            sources: [retained.path], host: PalanaCore.localHostName)
        let result = try await LocalConduit()
            .run(on: PalanaCore.localHostName, command)
            .collect()

        #expect(result.exitStatus != 0)
        #expect(result.stderrText.contains("palana-retained:"))
        let notes = RecoveryNote.notes(in: result.stderrText, host: PalanaCore.localHostName)
        #expect(notes.count == 1)
        #expect(notes[0].detail.contains(retained.path))
    }

    @Test("same-size same-time destination bytes cannot consume a different source")
    func contentComparisonPrecedesRemoval() async throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = source.appendingPathComponent("collision.txt")
        let destinationFile = destination.appendingPathComponent("collision.txt")
        try Data("AAAA".utf8).write(to: sourceFile)
        try Data("BBBB".utf8).write(to: destinationFile)
        let date = Date(timeIntervalSince1970: 1_577_840_460)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: sourceFile.path)
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: destinationFile.path)

        let move = try plan(entries: [entry("collision.txt", kind: .file)])
        let outcome = await enact(move)

        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(try Data(contentsOf: destinationFile) == Data("AAAA".utf8))
        #expect(!FileManager.default.fileExists(atPath: sourceFile.path))
    }
}
