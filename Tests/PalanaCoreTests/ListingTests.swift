// The Listing component over RecordedConduit playback — flavor dispatch
// and the read-failure taxonomy. The transcript is the network; the
// commands it carries pin the composed command text exactly.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Listing")
struct ListingTests {
    private static let gnuStdout = "notes.txt\0f\012\01700000000.5\0644\0op\0op\0\0"

    private static let bsdStdout =
        "Regular File\t12\t1700000000\t644\top\tstaff\n\0./notes.txt\0PALANA-LINKS\0"

    private static func transcript() -> ConduitTranscript {
        ConduitTranscript(entries: [
            .init(
                host: "gnu-host",
                command: Listing.command(for: "/srv", flavor: .gnu),
                stdout: Self.gnuStdout,
                stderr: "",
                exit: 0),
            .init(
                host: "mac-host",
                command: Listing.command(for: "/Users/op", flavor: .bsd),
                stdout: Self.bsdStdout,
                stderr: "",
                exit: 0),
            .init(
                host: "gnu-host",
                command: Listing.command(for: "/missing", flavor: .gnu),
                stdout: "",
                stderr: "sh: cd: /missing: No such file or directory",
                exit: 1),
            .init(
                host: "gnu-host",
                command: Listing.command(for: "/locked", flavor: .gnu),
                stdout: "",
                stderr: "sh: cd: /locked: Permission denied",
                exit: 1),
            .init(
                host: "gnu-host",
                command: Listing.command(for: "/srv/file.txt", flavor: .gnu),
                stdout: "",
                stderr: "sh: cd: /srv/file.txt: Not a directory",
                exit: 1),
            .init(
                host: "gnu-host",
                command: Listing.command(for: "/odd", flavor: .gnu),
                stdout: "",
                stderr: "find: something inscrutable",
                exit: 3),
        ])
    }

    private static func listing() -> Listing {
        Listing(conduit: RecordedConduit(transcript: transcript()))
    }

    @Test("GNU flavor dispatches the find -printf command and parses")
    func gnuDispatch() async throws {
        let entries = try await Self.listing().list(on: "gnu-host", path: "/srv", flavor: .gnu)
        #expect(entries.map(\.name) == ["notes.txt"])
        #expect(entries.first?.size == 12)
    }

    @Test("BSD flavor dispatches the stat record command and parses")
    func bsdDispatch() async throws {
        let entries = try await Self.listing().list(on: "mac-host", path: "/Users/op", flavor: .bsd)
        #expect(entries.map(\.name) == ["notes.txt"])
        #expect(entries.first?.group == "staff")
    }

    @Test("a missing directory classifies as directoryNotFound")
    func notFound() async {
        await #expect(throws: ListingError.directoryNotFound(path: "/missing")) {
            _ = try await Self.listing().list(on: "gnu-host", path: "/missing", flavor: .gnu)
        }
    }

    @Test("a refused directory classifies as permissionDenied")
    func denied() async {
        await #expect(throws: ListingError.permissionDenied(path: "/locked")) {
            _ = try await Self.listing().list(on: "gnu-host", path: "/locked", flavor: .gnu)
        }
    }

    @Test("a file path classifies as notADirectory")
    func notADirectory() async {
        await #expect(throws: ListingError.notADirectory(path: "/srv/file.txt")) {
            _ = try await Self.listing().list(on: "gnu-host", path: "/srv/file.txt", flavor: .gnu)
        }
    }

    @Test("an unrecognized failure stays typed with its stderr")
    func unrecognizedFailure() async {
        await #expect(
            throws: ListingError.listingFailed(exitStatus: 3, stderr: "find: something inscrutable")
        ) {
            _ = try await Self.listing().list(on: "gnu-host", path: "/odd", flavor: .gnu)
        }
    }
}
