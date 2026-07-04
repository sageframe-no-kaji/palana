// The two listing parsers against synthetic streams — hostile bytes by
// construction. Recorded truth from real userlands replays in
// ListingCorpusTests; this battery owns the shapes fixtures can't
// conveniently produce.

import Foundation
import Testing

@testable import PalanaCore

@Suite("GNUListingParser")
struct GNUListingParserTests {
    private static func record(
        _ name: String,
        _ type: String,
        size: String = "0",
        mtime: String = "1700000000.5",
        perms: String = "644",
        owner: String = "op",
        group: String = "op",
        target: String = ""
    ) -> Data {
        let fields = [name, type, size, mtime, perms, owner, group, target]
        return Data((fields.joined(separator: "\0") + "\0").utf8)
    }

    @Test("records parse whole: kind, size, fractional mtime, ownership")
    func fullRecord() throws {
        let data = Self.record("notes.txt", "f", size: "1234", mtime: "1700000000.25")
        let entries = try GNUListingParser.parse(data)
        let entry = try #require(entries.first)
        #expect(entry.name == "notes.txt")
        #expect(entry.kind == .file)
        #expect(entry.size == 1234)
        #expect(entry.modified == Date(timeIntervalSince1970: 1_700_000_000.25))
        #expect(entry.permissions == "644")
        #expect(entry.owner == "op")
        #expect(entry.symlinkTarget == nil)
    }

    @Test("names and targets with newlines and tabs survive byte for byte")
    func hostileBytes() throws {
        let data =
            Self.record("new\nline", "f") + Self.record("has\ttab", "l", target: "tar\nget")
        let entries = try GNUListingParser.parse(data)
        #expect(entries.count == 2)
        #expect(entries.map(\.nameData).contains(Data("new\nline".utf8)))
        let link = try #require(entries.first { $0.kind == .symlink })
        #expect(link.symlinkTarget == Data("tar\nget".utf8))
    }

    @Test("kinds map: f, d, l, and the rest are other")
    func kindMapping() throws {
        let data =
            Self.record("a", "f") + Self.record("b", "d") + Self.record("c", "l", target: "a")
            + Self.record("d", "s")
        let kinds = try GNUListingParser.parse(data).map(\.kind)
        #expect(kinds == [.file, .directory, .symlink, .other])
    }

    @Test("entries return sorted by name bytes")
    func sortedContract() throws {
        let data = Self.record("zeta", "f") + Self.record("alpha", "f")
        #expect(try GNUListingParser.parse(data).map(\.name) == ["alpha", "zeta"])
    }

    @Test("an empty directory parses to no entries")
    func emptyDirectory() throws {
        #expect(try GNUListingParser.parse(Data()).isEmpty)
    }

    @Test("truncated or misaligned streams throw malformedListing")
    func malformedThrows() {
        #expect(throws: ListingError.malformedListing) {
            _ = try GNUListingParser.parse(Data("unterminated".utf8))
        }
        #expect(throws: ListingError.malformedListing) {
            _ = try GNUListingParser.parse(Data("only\0three\0fields\0".utf8))
        }
        #expect(throws: ListingError.malformedListing) {
            let bad = Self.record("x", "f", size: "not-a-number")
            _ = try GNUListingParser.parse(bad)
        }
    }

    @Test("the command embeds a quote-hostile path safely")
    func commandQuoting() {
        let command = GNUListingParser.command(for: "/srv/it's here")
        #expect(command.contains(#"'/srv/it'\''s here'"#))
        #expect(command.hasPrefix("cd "))
    }
}

@Suite("BSDListingParser")
struct BSDListingParserTests {
    private static func statLine(
        _ type: String,
        size: String = "0",
        mtime: String = "1700000000",
        perms: String = "644",
        owner: String = "op",
        group: String = "staff"
    ) -> String {
        [type, size, mtime, perms, owner, group].joined(separator: "\t") + "\n"
    }

    /// Builds the batch framing: stat lines, one NUL, the same count of
    /// NUL-terminated ./ names — repeated per batch, marker after.
    private static func stream(
        batches: [(lines: [String], names: [String])],
        links: [(String, String)] = []
    ) -> Data {
        var data = Data()
        for batch in batches {
            data += Data(batch.lines.joined().utf8)
            data += Data([0])
            for name in batch.names {
                data += Data("./\(name)\0".utf8)
            }
        }
        data += Data("PALANA-LINKS\0".utf8)
        for (name, target) in links {
            data += Data("./\(name)\0\(target)\0".utf8)
        }
        return data
    }

    @Test("a batch of stat lines pairs with its names by count")
    func fullRecord() throws {
        let data = Self.stream(batches: [
            (
                lines: [Self.statLine("Regular File", size: "42", mtime: "1700000001")],
                names: ["notes.txt"]
            )
        ])
        let entry = try #require(try BSDListingParser.parse(data).first)
        #expect(entry.name == "notes.txt")
        #expect(entry.kind == .file)
        #expect(entry.size == 42)
        #expect(entry.modified == Date(timeIntervalSince1970: 1_700_000_001))
        #expect(entry.group == "staff")
    }

    @Test("multiple batches concatenate — ARG_MAX splits are invisible")
    func multipleBatches() throws {
        let data = Self.stream(batches: [
            (
                lines: [Self.statLine("Regular File"), Self.statLine("Directory")],
                names: ["a.txt", "subdir"]
            ),
            (
                lines: [Self.statLine("Regular File", size: "7")],
                names: ["late.txt"]
            ),
        ])
        let entries = try BSDListingParser.parse(data)
        #expect(entries.map(\.name) == ["a.txt", "late.txt", "subdir"])
        #expect(entries.first { $0.name == "late.txt" }?.size == 7)
    }

    @Test("a name containing a newline survives — the NUL bounds it")
    func newlineInName() throws {
        let data = Self.stream(batches: [
            (
                lines: [Self.statLine("Regular File"), Self.statLine("Directory")],
                names: ["new\nline", "plain"]
            )
        ])
        let names = try BSDListingParser.parse(data).map(\.nameData)
        #expect(names.contains(Data("new\nline".utf8)))
    }

    @Test("symlink targets resolve from the keyed section")
    func linkTargets() throws {
        let data = Self.stream(
            batches: [
                (
                    lines: [Self.statLine("Symbolic Link", size: "5"), Self.statLine("Regular File")],
                    names: ["alink", "plain"]
                )
            ],
            links: [("alink", "plain")])
        let link = try #require(try BSDListingParser.parse(data).first { $0.kind == .symlink })
        #expect(link.symlinkTarget == Data("plain".utf8))
    }

    @Test("a file named like the marker cannot collide — names carry ./")
    func markerCollision() throws {
        let data = Self.stream(batches: [
            (lines: [Self.statLine("Regular File")], names: ["PALANA-LINKS"])
        ])
        let entries = try BSDListingParser.parse(data)
        #expect(entries.map(\.name) == ["PALANA-LINKS"])
    }

    @Test("kinds map from stat's type words")
    func kindMapping() throws {
        let data = Self.stream(batches: [
            (
                lines: [
                    Self.statLine("Regular File"), Self.statLine("Directory"),
                    Self.statLine("Symbolic Link"), Self.statLine("Socket"),
                ],
                names: ["a", "b", "c", "d"]
            )
        ])
        let kinds = try BSDListingParser.parse(data).map(\.kind)
        #expect(kinds == [.file, .directory, .symlink, .other])
    }

    @Test("an empty directory parses to no entries — marker only")
    func emptyDirectory() throws {
        #expect(try BSDListingParser.parse(Self.stream(batches: [])).isEmpty)
        #expect(try BSDListingParser.parse(Data()).isEmpty)
    }

    @Test("torn streams throw malformedListing")
    func malformedThrows() {
        #expect(throws: ListingError.malformedListing) {
            _ = try BSDListingParser.parse(Data("Regular File\t0\t170\t644\top\tstaff".utf8))
        }
        #expect(throws: ListingError.malformedListing) {
            _ = try BSDListingParser.parse(
                Data("Regular File\t0\t170\t644\top\tstaff\n\0./name-without-nul".utf8))
        }
        #expect(throws: ListingError.malformedListing) {
            let short = "Regular File\t0\n\0./x\0"
            _ = try BSDListingParser.parse(Data(short.utf8))
        }
    }

    @Test("a desynced batch is refused, never guessed at")
    func desyncedBatchThrows() {
        // Two stat lines, one name — the marker must not be eaten as
        // the second name.
        var data = Data(
            (Self.statLine("Regular File")
                + Self.statLine("Directory")).utf8)
        data += Data([0])
        data += Data("./only-one\0".utf8)
        data += Data("PALANA-LINKS\0".utf8)
        #expect(throws: ListingError.malformedListing) {
            _ = try BSDListingParser.parse(data)
        }
    }

    @Test("the command carries the marker, the batched stat, and the link loop")
    func commandShape() {
        let command = BSDListingParser.command(for: "/Users/op")
        #expect(command.contains("PALANA-LINKS"))
        #expect(command.contains("stat -f"))
        #expect(command.contains(#"-- "$@""#), "stat runs batched, not once per entry")
        #expect(command.contains("readlink -n"))
        #expect(command.hasPrefix("cd /Users/op"), "safe paths stay bare — plans read clean")
    }
}
