// The 2026-11-18 final review's F02 (owner ruling: ask the filesystem).
// On storage that resolves names case- or normalization-insensitively,
// an arriving name the byte compare missed can still land on a standing
// entry. The destination is asked, and a hit is disclosed as the
// collision it is. This Mac's temporary directory is the live witness;
// each case first proves the volume it runs on folds names.

import Foundation
import Testing

@testable import PalanaCore

private func entry(_ name: String, kind: FileEntry.Kind = .file, size: Int64 = 3) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: 1_000),
        permissions: "644",
        owner: "op",
        group: "op")
}

@Suite("Final review F02 — collisions the destination resolves")
struct FinalReviewCollisionTests {
    private let listing = Listing(conduit: LocalConduit())

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-f02-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a case variant resolves on this volume and becomes a disclosed replace of the listed spelling")
    func caseVariantIsCollision() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("old".utf8).write(to: directory.appendingPathComponent("report.txt"))
        try #require(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("REPORT.TXT").path),
            "this witness needs a case-insensitive temporary volume")
        let standing = [entry("report.txt")]
        let arriving = [entry("Report.txt"), entry("new.txt")]
        #expect(Collision.detect(sources: arriving, destinationListing: standing).isEmpty, "the byte compare misses it")

        let arrivals = Collision.unmatched(sources: arriving, destinationListing: standing)
        let hits = try await listing.resolving(
            names: arrivals.compactMap(\.exactName), in: directory.path, on: PalanaCore.localHostName)
        #expect(hits == [0])
        let collisions = try #require(
            Collision.resolved(arrivals: arrivals, hits: hits, destinationListing: standing))
        #expect(collisions.map(\.name) == ["report.txt"])
        #expect(collisions.first?.nature == .replace)
        #expect(CollisionReport(items: collisions, gathered: true).sentence() == "will replace report.txt (3 bytes)")
    }

    @Test("a normalization variant resolves too, and a kind clash under a case variant is refused")
    func normalizationAndKindClash() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let composed = "caf\u{E9}"  // é as one scalar
        let decomposed = "cafe\u{301}"  // e + combining acute
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(composed), withIntermediateDirectories: true)
        try #require(FileManager.default.fileExists(atPath: directory.appendingPathComponent(decomposed).path))
        let standing = [entry(composed, kind: .directory)]
        let arrivals = [entry(decomposed.uppercased(), kind: .file)]
        let hits = try await listing.resolving(
            names: arrivals.compactMap(\.exactName), in: directory.path, on: PalanaCore.localHostName)
        let collisions = try #require(
            Collision.resolved(arrivals: arrivals, hits: hits, destinationListing: standing))
        #expect(collisions.first?.nature == .kindClash)
        #expect(CollisionReport(items: collisions, gathered: true).hasKindClash)
    }

    @Test("a hit that names no single listed entry makes the facts unknown, not clean")
    func ambiguousHitIsUnknown() {
        let arrivals = [entry("Report.txt")]
        #expect(Collision.resolved(arrivals: arrivals, hits: [0], destinationListing: []) == nil)
        let twins = [entry("report.txt"), entry("REPORT.txt")]
        #expect(Collision.resolved(arrivals: arrivals, hits: [0], destinationListing: twins) == nil)
        #expect(Collision.resolved(arrivals: arrivals, hits: [], destinationListing: twins)?.isEmpty == true)
    }

    @Test("names the destination does not resolve stay byte-exact: no hits, no collisions")
    func absentNamesStayClean() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = (0..<450).map { "new-\($0) 'quoted'.txt" }
        try Data().write(to: directory.appendingPathComponent(names[401]))
        let hits = try await listing.resolving(names: names, in: directory.path, on: PalanaCore.localHostName)
        #expect(hits == [401], "batches keep their positions across the command-line bound")
    }

    @Test("an unreadable answer or an unenterable directory throws, so the gather says unknown")
    func probeFailuresThrow() async throws {
        #expect(Listing.resolutionAnswer("1\n3\n", count: 2) == nil)
        #expect(Listing.resolutionAnswer("x\n", count: 2) == nil)
        #expect(Listing.resolutionAnswer("", count: 2)?.isEmpty == true)
        await #expect(throws: ListingError.self) {
            try await listing.resolving(
                names: ["a"], in: "/nonexistent/palana-f02", on: PalanaCore.localHostName)
        }
    }
}
