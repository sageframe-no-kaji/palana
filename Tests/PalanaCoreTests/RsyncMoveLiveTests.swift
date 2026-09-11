// The move as it actually runs, on this Mac, through the real rsync.
//
// The faithful case proves the whole shape: rsync removes each source
// file after confirming its copy, the sweep takes the emptied
// directories with rmdir alone, and the accounting step finds nothing
// left. The adversarial case changes a file while rsync is reading it
// and proves the operator is told: the bytes are at the destination,
// the source is still there, and the run does not report success.
//
// The transfer is throttled through the operator-flags seam the plan
// already has, so the window is wide and repeatable rather than raced.

import Foundation
import Testing

@testable import PalanaCore

@Suite("rsync move, live", .serialized)
struct RsyncMoveLiveTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-rsyncmv-\(UUID().uuidString.prefix(8))", isDirectory: true)

    private var source: URL { root.appendingPathComponent("src") }
    private var destination: URL { root.appendingPathComponent("dst") }

    /// This Mac's rsync, named absolutely so the plan and the process agree.
    private func capability() throws -> HostCapability {
        let path = try #require(
            ["/usr/bin/rsync", "/opt/homebrew/bin/rsync"]
                .first { FileManager.default.isExecutableFile(atPath: $0) })
        let version =
            path.hasSuffix("/usr/bin/rsync")
            ? "openrsync: protocol version 29" : "rsync  version 3.4.1"
        return HostCapability(
            kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: version, rsyncPath: path)
    }

    private func plan(entries: [FileEntry], throttleKBps: Int?) throws -> Plan {
        var facts = PlanFacts(sourceCapability: try capability())
        if let throttleKBps { facts.rsyncOperatorFlags = "--bwlimit=\(throttleKBps)" }
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: entries,
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path),
                token: "t1"),
            facts: facts)
    }

    private func listing() async throws -> [FileEntry] {
        try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: source.path, flavor: .bsd)
    }

    private func enact(_ plan: Plan) async -> (error: (any Error)?, events: [EnactmentEvent]) {
        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        var events: [EnactmentEvent] = []
        do {
            for try await event in transports.enact(plan) { events.append(event) }
            return (nil, events)
        } catch {
            return (error, events)
        }
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    @Test("a faithful move: every file lands, every source file goes, the tree is swept")
    func faithfulMove() async throws {
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("dir/inner"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: source.appendingPathComponent("a.txt"))
        try Data("nested".utf8).write(to: source.appendingPathComponent("dir/b.txt"))
        try Data("deeper".utf8).write(to: source.appendingPathComponent("dir/inner/c.txt"))

        let plan = try plan(entries: try await listing(), throttleKBps: nil)
        #expect(plan.steps.map(\.role) == [.copy, .cleanup, .verify])

        let outcome = await enact(plan)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(outcome.events.last == .finished)

        // Landed.
        #expect(try Data(contentsOf: destination.appendingPathComponent("a.txt")) == Data("hello".utf8))
        #expect(
            try Data(contentsOf: destination.appendingPathComponent("dir/inner/c.txt"))
                == Data("deeper".utf8))
        // Gone, directories included — swept bottom-up by rmdir alone.
        #expect(!exists("src/a.txt"))
        #expect(!exists("src/dir/inner"))
        #expect(!exists("src/dir"))
    }

    @Test("a file changed mid-transfer is kept, named, and the move does not claim success")
    func changedFileIsKeptAndReported() async throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = source.appendingPathComponent("payload.bin")
        try Data(count: 512 << 10).write(to: payload)

        // 100 KB/s over 512 KB is about five seconds of reading.
        let plan = try plan(entries: try await listing(), throttleKBps: 100)
        let meddler = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            if let handle = try? FileHandle(forUpdating: payload) {
                try? handle.seek(toOffset: 100)
                try? handle.write(contentsOf: Data("CHANGED-DURING-TRANSFER".utf8))
                try? handle.close()
            }
        }
        let outcome = await enact(plan)
        _ = await meddler.result

        // The run failed at the accounting step, not silently.
        guard case EnactmentError.stepFailed(let index, _, let stderrTail)? = outcome.error else {
            Issue.record("expected stepFailed, got \(String(describing: outcome.error))")
            return
        }
        #expect(index == 2, "the accounting step is the one that failed")
        #expect(stderrTail.contains("palana-retained:"))
        // The source is still there. rsync declined to remove what it
        // could not faithfully transfer, and nothing else deleted it.
        #expect(exists("src/payload.bin"))
        // And the operator was told in the transcript, not just in a status.
        #expect(
            outcome.events.contains {
                guard case .recovery(let note) = $0 else { return false }
                return note.kind == .retained && note.detail.contains("copied, not moved")
            })
    }
}
