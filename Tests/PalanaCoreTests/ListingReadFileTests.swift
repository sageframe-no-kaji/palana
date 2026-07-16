// The file-read verb — bytes through the door, failures typed. The
// transcript pins the composed command so the Surface's open verb
// never drifts from what the record says it runs.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Listing.readFile")
struct ListingReadFileTests {
    private static func transcript() -> ConduitTranscript {
        ConduitTranscript(entries: [
            .init(
                host: "gnu-host",
                command: Listing.readFileCommand(for: "/srv/notes.txt"),
                stdout: "hello, field\n",
                stderr: "",
                exit: 0),
            .init(
                host: "gnu-host",
                command: Listing.readFileCommand(for: "/srv/missing.txt"),
                stdout: "",
                stderr: "cat: /srv/missing.txt: No such file or directory",
                exit: 1),
            .init(
                host: "gnu-host",
                command: Listing.readFileCommand(for: "/srv/locked.txt"),
                stdout: "",
                stderr: "cat: /srv/locked.txt: Permission denied",
                exit: 1),
        ])
    }

    private func makeListing() -> Listing {
        Listing(conduit: RecordedConduit(transcript: Self.transcript()))
    }

    @Test("bytes come back exactly")
    func readsBytes() async throws {
        let data = try await makeListing().readFile(on: "gnu-host", path: "/srv/notes.txt")
        #expect(data == Data("hello, field\n".utf8))
    }

    @Test("a missing file types as directoryNotFound's sibling truth")
    func missingFile() async {
        await #expect(throws: ListingError.directoryNotFound(path: "/srv/missing.txt")) {
            try await self.makeListing().readFile(on: "gnu-host", path: "/srv/missing.txt")
        }
    }

    @Test("a refused file types as permissionDenied")
    func lockedFile() async {
        await #expect(throws: ListingError.permissionDenied(path: "/srv/locked.txt")) {
            try await self.makeListing().readFile(on: "gnu-host", path: "/srv/locked.txt")
        }
    }

    @Test("the command quotes the path — hostile names survive")
    func quoting() {
        let command = Listing.readFileCommand(for: "/srv/a name'with quote")
        #expect(command.hasPrefix("cat "))
        #expect(command.contains("a name'\\''with quote"))
    }

    @Test("the capped head command uses head -c and quotes hostile paths (ho-16 review)")
    func headCommand() {
        #expect(
            Listing.readFileHeadCommand(for: "/srv/big.log", limit: 262_145)
                == "head -c 262145 /srv/big.log")
        let hostile = Listing.readFileHeadCommand(for: "/srv/a name'x", limit: 10)
        #expect(hostile.hasPrefix("head -c 10 "))
        #expect(hostile.contains("a name'\\''x"))
    }
}
