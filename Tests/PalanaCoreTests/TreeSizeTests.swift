// Recursive size facts — command pinned, parser pinned, the engine's
// consumption proven pure. The completeness flag is the point: a
// refused subtree must never disappear into a clean-looking number.

import Foundation
import Testing

@testable import PalanaCore

@Suite("TreeSize")
struct TreeSizeTests {
    @Test("the GNU command walks with -printf and sums with awk")
    func gnuCommand() {
        let command = TreeSize.command(for: ["/srv/data"], flavor: .gnu)
        #expect(command.contains("find /srv/data -type f -printf '%s\\n' 2>&1"))
        #expect(command.contains("awk"))
        #expect(command.contains(#"printf "%.0f %d\n""#))
    }

    @Test("the BSD command walks with stat -f %z")
    func bsdCommand() {
        let command = TreeSize.command(for: ["/Users/op/docs"], flavor: .bsd)
        #expect(command.contains("find /Users/op/docs -type f -exec stat -f %z {} + 2>&1"))
    }

    @Test("hostile paths ride quoted")
    func quoting() {
        let command = TreeSize.command(for: ["/srv/two words"], flavor: .gnu)
        #expect(command.contains("'/srv/two words'"))
    }

    @Test("several paths join into one round trip, in order")
    func severalPaths() throws {
        let command = TreeSize.command(for: ["/a", "/b", "/c"], flavor: .gnu)
        #expect(command.components(separatedBy: "find /").count == 4, "three walks")
        let first = try #require(command.range(of: "find /a"))
        let second = try #require(command.range(of: "find /b"))
        let third = try #require(command.range(of: "find /c"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(second.lowerBound < third.lowerBound)
    }

    @Test("parse reads one fact per line, flag decoded")
    func parses() throws {
        let facts = try TreeSize.parse("41300000000 0\n12288 1\n", expecting: 2)
        #expect(facts[0] == RecursiveSize(bytes: 41_300_000_000, complete: true))
        #expect(facts[1] == RecursiveSize(bytes: 12288, complete: false))
    }

    @Test("an empty tree sums to zero, complete")
    func emptyTree() throws {
        let facts = try TreeSize.parse("0 0\n", expecting: 1)
        #expect(facts == [RecursiveSize(bytes: 0, complete: true)])
    }

    @Test("a short answer refuses to parse — count is the contract")
    func shortAnswer() {
        #expect(throws: ListingError.malformedListing) {
            try TreeSize.parse("100 0\n", expecting: 2)
        }
    }

    @Test("garbage refuses to parse")
    func garbage() {
        #expect(throws: ListingError.malformedListing) {
            try TreeSize.parse("not a number 0\n", expecting: 1)
        }
    }

    @Test("treeSizes runs one command and returns facts in path order")
    func overTheDoor() async throws {
        let paths = ["/srv/a", "/srv/b"]
        let transcript = ConduitTranscript(entries: [
            .init(
                host: "gnu-host",
                command: TreeSize.command(for: paths, flavor: .gnu),
                stdout: "512 0\n2048 1\n",
                stderr: "",
                exit: 0)
        ])
        let listing = Listing(conduit: RecordedConduit(transcript: transcript))
        let facts = try await listing.treeSizes(on: "gnu-host", paths: paths, flavor: .gnu)
        #expect(facts[0].bytes == 512)
        #expect(facts[1].complete == false)
    }

    @Test("no paths means no round trip and no facts")
    func noPaths() async throws {
        let listing = Listing(conduit: RecordedConduit(transcript: ConduitTranscript(entries: [])))
        let facts = try await listing.treeSizes(on: "x", paths: [], flavor: .gnu)
        #expect(facts.isEmpty)
    }
}

@Suite("Plan totalSize — recursive truth")
struct PlanTotalSizeTests {
    private static func makeEntry(_ name: String, kind: FileEntry.Kind, size: Int64) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: size,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "755",
            owner: "op",
            group: "op")
    }

    private static let file = makeEntry("notes.txt", kind: .file, size: 1000)
    private static let tree = makeEntry("archive", kind: .directory, size: 4096)

    private func makePlan(facts: PlanFacts) throws -> Plan {
        let request = PlanRequest(
            operation: .copy,
            source: Locus(host: "jodo", directory: "/tank/src"),
            entries: [Self.file, Self.tree],
            destination: Locus(host: "jodo", directory: "/tank/dst"))
        return try PlanEngine.plan(request, facts: facts)
    }

    @Test("a gathered directory counts its whole contents")
    func recursiveTotal() throws {
        let facts = PlanFacts(recursiveSizes: [
            Self.tree.id: RecursiveSize(bytes: 41_300_000_000, complete: true)
        ])
        let plan = try makePlan(facts: facts)
        #expect(plan.totalSize == 41_300_001_000)
        #expect(plan.totalSizeComplete)
    }

    @Test("an ungathered directory counts at inode size and marks the floor")
    func ungatheredFloor() throws {
        let plan = try makePlan(facts: PlanFacts())
        #expect(plan.totalSize == 5096)
        #expect(!plan.totalSizeComplete)
    }

    @Test("a refused walk marks the total incomplete")
    func refusedWalk() throws {
        let facts = PlanFacts(recursiveSizes: [
            Self.tree.id: RecursiveSize(bytes: 9000, complete: false)
        ])
        let plan = try makePlan(facts: facts)
        #expect(plan.totalSize == 10000)
        #expect(!plan.totalSizeComplete)
    }

    @Test("files alone need no facts and stay complete")
    func filesOnly() throws {
        let request = PlanRequest(
            operation: .copy,
            source: Locus(host: "jodo", directory: "/tank/src"),
            entries: [Self.file],
            destination: Locus(host: "jodo", directory: "/tank/dst"))
        let plan = try PlanEngine.plan(request, facts: PlanFacts())
        #expect(plan.totalSize == 1000)
        #expect(plan.totalSizeComplete)
    }
}
