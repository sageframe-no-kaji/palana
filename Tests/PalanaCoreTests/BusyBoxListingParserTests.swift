// The BusyBox listing path, pinned against zencat-shaped lines — the
// recon's `ls -lane`, numeric ids, full dates, symlink arrows, and the
// refusal contract: a line the shape can't own kills the listing
// loudly, never a silently wrong row.

import Foundation
import Testing

@testable import PalanaCore

@Suite("BusyBoxListingParser")
struct BusyBoxListingParserTests {
    private static let stream = """
        total 24
        drwxr-xr-x   12 0        0             4096 Fri Jul  4 10:23:11 2026 .
        drwxr-xr-x    3 0        0             4096 Thu Jul  3 09:00:00 2026 ..
        -rw-r--r--    1 0        0             1024 Fri Jul  4 10:23:11 2026 config.ini
        drwxr-xr-x    2 1000     1000          4096 Wed Jan  1 00:00:01 2025 www
        lrwxrwxrwx    1 0        0               11 Fri Jul  4 10:23:11 2026 etc -> tmp/etc
        -rw-r--r--    1 0        0                5 Fri Jul  4 10:23:11 2026 with space.txt
        -rwxr-xr-x    1 0        0            88888 Fri Jul  4 10:23:11 2026 .hidden
        """

    @Test("zencat-shaped lines parse whole, dot and dotdot dropped")
    func fullStream() throws {
        let entries = try BusyBoxListingParser.parse(Self.stream)
        #expect(entries.map(\.name) == [".hidden", "config.ini", "etc", "with space.txt", "www"])
    }

    @Test("kinds, numeric ids, and sizes carry through")
    func fields() throws {
        let entries = try BusyBoxListingParser.parse(Self.stream)
        let www = try #require(entries.first { $0.name == "www" })
        #expect(www.kind == .directory)
        #expect(www.owner == "1000")
        #expect(www.group == "1000")
        let config = try #require(entries.first { $0.name == "config.ini" })
        #expect(config.kind == .file)
        #expect(config.size == 1024)
        #expect(config.permissions == "rw-r--r--")
    }

    @Test("symlink targets split at the first arrow")
    func symlinks() throws {
        let entries = try BusyBoxListingParser.parse(Self.stream)
        let link = try #require(entries.first { $0.name == "etc" })
        #expect(link.kind == .symlink)
        #expect(link.symlinkTarget == Data("tmp/etc".utf8))
    }

    @Test("the full date reads to the second")
    func dates() throws {
        let entries = try BusyBoxListingParser.parse(Self.stream)
        let www = try #require(entries.first { $0.name == "www" })
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = utc.dateComponents([.year, .second], from: www.modified)
        #expect(parts.year == 2025)
        #expect(parts.second == 1)
    }

    @Test("names keep their spaces")
    func spacedNames() throws {
        let entries = try BusyBoxListingParser.parse(Self.stream)
        #expect(entries.contains { $0.name == "with space.txt" })
    }

    @Test("a line the shape cannot own refuses the listing loudly")
    func malformedRefuses() {
        #expect(throws: ListingError.malformedListing) {
            _ = try BusyBoxListingParser.parse("garbage that is not ls output")
        }
    }

    @Test("an empty directory is just the two dots — no entries")
    func emptyDirectory() throws {
        let stream = """
            total 8
            drwxr-xr-x    2 0        0             4096 Fri Jul  4 10:23:11 2026 .
            drwxr-xr-x    3 0        0             4096 Fri Jul  4 10:23:11 2026 ..
            """
        #expect(try BusyBoxListingParser.parse(stream).isEmpty)
    }

    @Test("the command is cd and the date-precision ladder, one round trip")
    func commandShape() {
        let command = BusyBoxListingParser.command(for: "/etc")
        #expect(command.hasPrefix("cd /etc && "))
        #expect(command.contains("ls -lane 2>/dev/null || ls -lan --full-time 2>/dev/null || ls -lan"))
        #expect(Listing.command(for: "/etc", flavor: .busybox) == command)
    }

    @Test("Alpine's --full-time shape parses with its real timezone")
    func fullTimeShape() throws {
        let stream = """
            total 16
            drwxr-xr-x    3 0        0             4096 2026-07-04 17:20:37 +0000 .
            -rw-r--r--    1 0        0                5 2026-07-04 17:20:37 +0000 a file.txt
            lrwxrwxrwx    1 0        0               10 2026-07-04 17:20:37 +0000 alink -> a file.txt
            drwxr-xr-x    2 0        0             4096 2026-07-04 17:20:37 +0000 sub dir
            """
        let entries = try BusyBoxListingParser.parse(stream)
        #expect(entries.map(\.name) == ["a file.txt", "alink", "sub dir"])
        let link = try #require(entries.first { $0.kind == .symlink })
        #expect(link.symlinkTarget == Data("a file.txt".utf8))
        let file = try #require(entries.first { $0.name == "a file.txt" })
        #expect(file.modified == Date(timeIntervalSince1970: 1_783_185_637))
    }

    @Test("the short-date floor parses, year or clock")
    func shortDateShape() throws {
        let stream = """
            -rw-r--r--    1 0        0              512 Jul  4 13:20 recent.txt
            -rw-r--r--    1 0        0              512 Jan  2 2025 old.txt
            """
        let entries = try BusyBoxListingParser.parse(stream)
        #expect(entries.count == 2)
        let old = try #require(entries.first { $0.name == "old.txt" })
        let year = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(identifier: "UTC") ?? .current, from: old.modified).year
        #expect(year == 2025)
    }

    @Test("treeSizes answers no facts for BusyBox — the floor stays named")
    func treeSizesNoFacts() async throws {
        let listing = Listing(conduit: RecordedConduit(transcript: ConduitTranscript(entries: [])))
        let sizes = try await listing.treeSizes(on: "zencat", paths: ["/www"], flavor: .busybox)
        #expect(sizes.isEmpty)
    }

    @Test("the probe tells BusyBox apart from BSD")
    func probeParsesBusyBox() throws {
        let stdout = """
            palana:kernel:Linux
            palana:flavor:BusyBox
            palana:zfs:
            palana:rsync:
            """
        let capability = try CapabilityProbe.parse(stdout)
        #expect(capability.flavor == .busybox)
        #expect(capability.rsync == nil)
        #expect(CapabilityProbe.command.contains("busybox true"))
    }
}
