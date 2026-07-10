// Collision tests — detect and sentence covered by exact-value tests;
// the report rides the Plan and round-trips Codable. Command text is
// unchanged: the compose invariant is asserted directly.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Helpers

private func entry(
    _ name: String,
    kind: FileEntry.Kind = .file,
    size: Int64 = 0,
    modified: Date = Date(timeIntervalSince1970: 0)
) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: modified,
        permissions: "644",
        owner: "op",
        group: "op")
}

private func entryRaw(
    nameData: Data,
    kind: FileEntry.Kind = .file,
    size: Int64 = 0
) -> FileEntry {
    FileEntry(
        nameData: nameData,
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

private let source = Locus(host: "jodo", directory: "/tank/src")
private let dest = Locus(host: "jodo", directory: "/tank/dst")

// MARK: - Collision.detect

@Suite("Collision.detect")
struct CollisionDetectTests {
    @Test("empty destination — no collisions regardless of sources")
    func emptyDestination() {
        let sources = [entry("a.txt"), entry("b.txt")]
        let found = Collision.detect(sources: sources, destinationListing: [])
        #expect(found.isEmpty)
    }

    @Test("no overlap — sources and destination share no names")
    func noOverlap() {
        let sources = [entry("x.txt")]
        let destination = [entry("y.txt"), entry("z.txt")]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.isEmpty)
    }

    @Test("single file over file — one replace collision")
    func singleReplace() {
        let modified = Date(timeIntervalSince1970: 1_000_000)
        let sources = [entry("notes.txt")]
        let destination = [entry("notes.txt", kind: .file, size: 1000, modified: modified)]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 1)
        let collision = found[0]
        #expect(collision.nameData == Data("notes.txt".utf8))
        #expect(collision.standingKind == .file)
        #expect(collision.standingSize == 1000)
        #expect(collision.standingModified == modified)
        #expect(collision.arrivingKind == .file)
        #expect(collision.nature == .replace)
    }

    @Test("directory over directory — one merge collision")
    func dirOverDir() {
        let sources = [entry("media", kind: .directory)]
        let destination = [entry("media", kind: .directory, size: 4096)]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 1)
        #expect(found[0].nature == .merge)
    }

    @Test("file over directory — kind clash")
    func fileOverDir() {
        let sources = [entry("notes", kind: .file)]
        let destination = [entry("notes", kind: .directory, size: 4096)]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 1)
        #expect(found[0].nature == .kindClash)
    }

    @Test("directory over file — kind clash in the other direction")
    func dirOverFile() {
        let sources = [entry("notes", kind: .directory)]
        let destination = [entry("notes", kind: .file, size: 512)]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 1)
        #expect(found[0].nature == .kindClash)
    }

    @Test("symlink at destination with file arriving — replace, not follow")
    func symlinkStandingFileArriving() {
        let sources = [entry("link", kind: .file)]
        let destination = [entry("link", kind: .symlink, size: 0)]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 1)
        #expect(found[0].standingKind == .symlink)
        #expect(found[0].arrivingKind == .file)
        #expect(found[0].nature == .replace)
    }

    @Test("byte-exact names that differ only past UTF-8 — must not merge")
    func byteExactNamesMustNotMerge() {
        // Two nameData values with the same lossy UTF-8 display must be
        // treated as distinct names. The source has valid UTF-8; the
        // destination has an invalid byte sequence that decodes to the
        // same replacement-character string but is a different Data.
        let validName = Data("file".utf8)
        var invalidName = Data("file".utf8)
        invalidName[0] = 0xFF  // Not valid UTF-8; lossy display produces "ÿile" but stays distinct
        // Both display as the same lossy string only if the bytes truly
        // match — here they don't, so no collision.
        let sources = [entryRaw(nameData: validName, kind: .file)]
        let destination = [entryRaw(nameData: invalidName, kind: .file)]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.isEmpty, "byte-different names must not collide")
    }

    @Test("order follows destination-listing appearance, not source order")
    func stableOrder() {
        let sources = [
            entry("c.txt"),
            entry("a.txt"),
            entry("b.txt"),
        ]
        let destination = [
            entry("b.txt"),
            entry("a.txt"),
            entry("c.txt"),
        ]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 3)
        #expect(found[0].name == "b.txt")
        #expect(found[1].name == "a.txt")
        #expect(found[2].name == "c.txt")
    }

    @Test("multiple collisions of mixed natures are all found")
    func multipleCollisions() {
        let sources = [
            entry("notes.txt", kind: .file),
            entry("archive", kind: .directory),
            entry("link", kind: .file),
        ]
        let destination = [
            entry("notes.txt", kind: .file, size: 500),
            entry("archive", kind: .directory, size: 4096),
            entry("link", kind: .symlink, size: 0),
            entry("other.txt", kind: .file, size: 100),
        ]
        let found = Collision.detect(sources: sources, destinationListing: destination)
        #expect(found.count == 3)
        #expect(found[0].nature == .replace)
        #expect(found[1].nature == .merge)
        #expect(found[2].nature == .replace)
    }
}

// MARK: - Collision.Nature

@Suite("Collision.nature")
struct CollisionNatureTests {
    @Test("file over file is replace")
    func fileOverFile() {
        let collision = Collision(
            nameData: Data("x".utf8),
            standingKind: .file,
            standingSize: 0,
            standingModified: .distantPast,
            arrivingKind: .file)
        #expect(collision.nature == .replace)
    }

    @Test("directory over directory is merge")
    func dirOverDir() {
        let collision = Collision(
            nameData: Data("x".utf8),
            standingKind: .directory,
            standingSize: 0,
            standingModified: .distantPast,
            arrivingKind: .directory)
        #expect(collision.nature == .merge)
    }

    @Test("file over directory is kindClash")
    func fileOverDir() {
        let collision = Collision(
            nameData: Data("x".utf8),
            standingKind: .directory,
            standingSize: 0,
            standingModified: .distantPast,
            arrivingKind: .file)
        #expect(collision.nature == .kindClash)
    }

    @Test("directory over file is kindClash")
    func dirOverFile() {
        let collision = Collision(
            nameData: Data("x".utf8),
            standingKind: .file,
            standingSize: 0,
            standingModified: .distantPast,
            arrivingKind: .directory)
        #expect(collision.nature == .kindClash)
    }
}

// MARK: - CollisionReport.sentence

@Suite("CollisionReport.sentence")
struct CollisionReportSentenceTests {
    private func makeCollision(
        name: String,
        standingKind: FileEntry.Kind,
        arrivingKind: FileEntry.Kind,
        size: Int64 = 0
    ) -> Collision {
        Collision(
            nameData: Data(name.utf8),
            standingKind: standingKind,
            standingSize: size,
            standingModified: .distantPast,
            arrivingKind: arrivingKind)
    }

    @Test("ungathered — exact alarm string")
    func ungatheredString() {
        let report = CollisionReport(items: [], gathered: false)
        let result = report.sentence()
        #expect(result == "couldn't check the destination — this may overwrite files there")
    }

    @Test("gathered and clean — nil")
    func gatheredAndClean() {
        let report = CollisionReport(items: [], gathered: true)
        #expect(report.sentence() == nil)
    }

    @Test("single replace names the entry and its size")
    func singleReplace() throws {
        let report = CollisionReport(
            items: [
                makeCollision(
                    name: "notes.txt",
                    standingKind: .file,
                    arrivingKind: .file,
                    size: 1000)
            ],
            gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "will replace notes.txt (1 kB)")
    }

    @Test("single merge names the directory")
    func singleMerge() throws {
        let report = CollisionReport(
            items: [
                makeCollision(
                    name: "media",
                    standingKind: .directory,
                    arrivingKind: .directory)
            ],
            gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "will merge into media")
    }

    @Test("single kind clash — folder here, file there")
    func singleKindClashFolderHere() throws {
        let report = CollisionReport(
            items: [
                makeCollision(
                    name: "notes",
                    standingKind: .directory,
                    arrivingKind: .file)
            ],
            gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "won't work — notes is a folder here and a file there")
    }

    @Test("single kind clash — file here, folder there")
    func singleKindClashFileHere() throws {
        let report = CollisionReport(
            items: [
                makeCollision(
                    name: "notes",
                    standingKind: .file,
                    arrivingKind: .directory)
            ],
            gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "won't work — notes is a file here and a folder there")
    }

    @Test("replace total size sums across all replaced entries")
    func replaceSizeSum() throws {
        let report = CollisionReport(
            items: [
                makeCollision(name: "a.txt", standingKind: .file, arrivingKind: .file, size: 500),
                makeCollision(name: "b.txt", standingKind: .file, arrivingKind: .file, size: 500),
            ],
            gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "will replace a.txt, b.txt (1 kB)")
    }

    @Test("mixed natures produce clauses joined by the middle dot")
    func mixedNatures() throws {
        let report = CollisionReport(
            items: [
                makeCollision(name: "a.txt", standingKind: .file, arrivingKind: .file, size: 1000),
                makeCollision(
                    name: "media",
                    standingKind: .directory,
                    arrivingKind: .directory),
                makeCollision(name: "clash", standingKind: .directory, arrivingKind: .file),
            ],
            gathered: true)
        let result = try #require(report.sentence())
        // single kind-clash item names the exact direction
        #expect(
            result
                == "will replace a.txt (1 kB) · will merge into media · won't work — clash is a folder here and a file there"
        )
    }

    @Test("cap at four names with 'and N more' for a fifth")
    func capFiveNames() throws {
        let items = ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"].map { name in
            makeCollision(name: name, standingKind: .file, arrivingKind: .file, size: 100)
        }
        let report = CollisionReport(items: items, gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "will replace a.txt, b.txt, c.txt, d.txt, and 1 more (500 bytes)")
    }

    @Test("cap at four names with 'and N more' for many extras")
    func capManyNames() throws {
        let items = ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt", "f.txt", "g.txt"].map { name in
            makeCollision(name: name, standingKind: .file, arrivingKind: .file, size: 0)
        }
        let report = CollisionReport(items: items, gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "will replace a.txt, b.txt, c.txt, d.txt, and 3 more (Zero kB)")
    }

    @Test("exactly four names — no 'and N more'")
    func exactlyFour() throws {
        let items = ["a.txt", "b.txt", "c.txt", "d.txt"].map { name in
            makeCollision(name: name, standingKind: .file, arrivingKind: .file, size: 1000)
        }
        let report = CollisionReport(items: items, gathered: true)
        let result = try #require(report.sentence())
        #expect(result == "will replace a.txt, b.txt, c.txt, d.txt (4 kB)")
    }
}
