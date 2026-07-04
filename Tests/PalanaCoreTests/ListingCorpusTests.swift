// The recorded listing corpus replayed — the container's GNU stream and
// Darwin's BSD stream, committed, parsing in every environment. If a
// parser change breaks against these transcripts, it broke against
// reality.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Listing corpus replay")
struct ListingCorpusTests {
    private static let corpusDirectory = "/tmp/palana-listing-corpus"

    private static func listing(from corpus: String, flavor: UserlandFlavor) throws -> [FileEntry] {
        let transcript = try ConduitTranscript(
            contentsOf: SSHFixture.repoRoot.appendingPathComponent(
                "Tests/PalanaCoreTests/Fixtures/\(corpus)"))
        let command = Listing.command(for: corpusDirectory, flavor: flavor)
        let entry = try #require(
            transcript.entries.first { $0.command == command },
            "corpus lacks the pinned listing command — recapture with PALANA_RECORD_FIXTURES=1")
        return switch flavor {
        case .gnu: try GNUListingParser.parse(Data(entry.stdout.utf8))
        case .bsd: try BSDListingParser.parse(Data(entry.stdout.utf8))
        }
    }

    @Test("the container's recorded GNU stream parses whole")
    func containerListing() throws {
        let entries = try Self.listing(from: "listing-container.json", flavor: .gnu)
        try assertRecordedHostileListing(entries)
    }

    @Test("Darwin's recorded BSD stream parses whole")
    func darwinListing() throws {
        let entries = try Self.listing(from: "listing-darwin.json", flavor: .bsd)
        try assertRecordedHostileListing(entries)
    }

    /// The recorded directories were built by the shared hostile setup —
    /// same names, same shapes, both userlands.
    private func assertRecordedHostileListing(_ entries: [FileEntry]) throws {
        #expect(entries.count == 11)
        let names = Set(entries.map(\.name))
        #expect(names.contains("new\nline"), "newline name survived recording and replay")
        #expect(names.contains("end\n"), "trailing-newline name survived")
        #expect(names.contains("café"), "UTF-8 name survived")
        #expect(names.contains("PALANA-LINKS"), "marker-shaped name cannot collide")

        let alink = try #require(entries.first { $0.name == "alink" })
        #expect(alink.kind == .symlink)
        #expect(alink.symlinkTarget == Data("plain".utf8))

        let subdir = try #require(entries.first { $0.name == "subdir" })
        #expect(subdir.kind == .directory)

        let sized = try #require(entries.first { $0.name == "sized" })
        #expect(sized.size == 1)
    }
}
