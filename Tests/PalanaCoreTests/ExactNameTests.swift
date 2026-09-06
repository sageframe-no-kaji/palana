// The exact-name boundary — bytes are identity, and a String names an
// entry only when its UTF-8 is those bytes exactly. Two names that
// display alike but differ in bytes must never collapse into one path,
// and a name no string carries is refused, never guessed at.

import Foundation
import Testing

@testable import PalanaCore

@Suite("FileEntry.exactName")
struct ExactNameTests {
    private func entry(_ bytes: [UInt8], kind: FileEntry.Kind = .file) -> FileEntry {
        FileEntry(
            nameData: Data(bytes),
            kind: kind,
            size: 1,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    @Test("valid UTF-8 round-trips to the same bytes")
    func validRoundTrips() {
        let file = entry(Array("naïve café.txt".utf8))
        #expect(file.exactName == "naïve café.txt")
        #expect(file.isNameRepresentable)
        #expect(file.exactName.map { Data($0.utf8) } == file.nameData)
    }

    @Test("bytes that are not UTF-8 have no exact name — only a display face")
    func invalidHasNoExactName() {
        let file = entry([0x61, 0xFF])
        #expect(file.exactName == nil)
        #expect(!file.isNameRepresentable)
        #expect(file.name == "a\u{FFFD}", "the display face still renders")
    }

    @Test("two byte-distinct names with one lossy display stay distinct — and neither is addressable")
    func lossyTwinsStayDistinct() {
        let first = entry([0x61, 0xFF])
        let second = entry([0x61, 0xFE])
        #expect(first.name == second.name, "the display collapses them")
        #expect(first.id != second.id, "the identity does not")
        #expect(first.exactName == nil)
        #expect(second.exactName == nil)
    }

    @Test("a leading byte-order mark is part of the name, not decoration to strip")
    func byteOrderMarkSurvives() {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("marked.txt".utf8)
        let file = entry(bytes)
        // Representable only if the round trip keeps every byte — a decoder
        // that swallowed the mark would name a different file.
        if let exact = file.exactName {
            #expect(Data(exact.utf8) == Data(bytes))
        }
    }

    @Test("the plan engine refuses an entry no command can name")
    func engineRefuses() {
        let twin = entry([0x61, 0xFF])
        #expect(throws: PlanError.unrepresentableName(twin.nameData)) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .delete,
                    source: Locus(host: "jodo", directory: "/tank"),
                    entries: [twin]),
                facts: PlanFacts())
        }
    }
}
