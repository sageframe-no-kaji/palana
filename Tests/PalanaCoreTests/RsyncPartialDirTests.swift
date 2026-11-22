// An interrupted rsync copy keeps its bytes in `.palana-partial`, never
// under the file's own name, and the next run of the same copy finishes
// it. Live on this Mac, through Transports, with the rsync on PATH.

import Foundation
import Testing

@testable import PalanaCore

/// The two rsyncs a Mac runs: the system openrsync (the floor) and, where
/// installed, Homebrew's rsync 3.
private let rsyncs: [HostCapability] =
    [HostCapability(kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "openrsync: protocol version 29")]
    + (FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/rsync")
        ? [
            HostCapability(
                kernel: "Darwin",
                flavor: .bsd,
                zfs: nil,
                rsync: "rsync  version 3.4.1  protocol version 32",
                rsyncPath: "/opt/homebrew/bin/rsync")
        ] : [])

@Suite("rsync partial dir — a stopped copy never poses as the finished file", .serialized)
struct RsyncPartialDirTests {
    private func plan(
        from source: URL,
        to destination: URL,
        name: String = "big.bin",
        kind: FileEntry.Kind = .file,
        flags: String?,
        rsync: HostCapability
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: [
                    FileEntry(
                        nameData: Data(name.utf8),
                        kind: kind,
                        size: 20_971_520,
                        modified: Date(),
                        permissions: "644",
                        owner: "op",
                        group: "op")
                ],
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path)),
            facts: PlanFacts(sourceCapability: rsync, destinationCapability: rsync, rsyncOperatorFlags: flags))
    }

    /// Runs a plan to the end; returns its standard output.
    private func output(of plan: Plan) async throws -> String {
        var text = ""
        for try await event in Transports(conduit: LocalConduit()) { _, _, _ in 0 }.enact(plan) {
            if case .outputChunk(_, .stdout, let data) = event { text += String(bytes: data, encoding: .utf8) ?? "" }
        }
        return text
    }

    /// The bytes rsync's `--stats` says it reused from the destination's
    /// basis: "Matched data: 2,424,224 bytes" (rsync 3) or
    /// "Matched data: 4062184 B" (openrsync).
    private func matchedBytes(_ stats: String) -> Int {
        guard let line = stats.split(separator: "\n").first(where: { $0.contains("Matched data:") }) else { return 0 }
        let digits = line.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "," }.filter(\.isNumber)
        return Int(String(digits)) ?? 0
    }

    @Test(
        "stopped mid-copy: no file under the real name; run again: complete, and the partial folder is gone",
        arguments: rsyncs)
    func stoppedThenResumed(rsync: HostCapability) async throws {
        let root = try ProcessFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src")
        let destination = root.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bytes = Data((0..<20_971_520).map { _ in UInt8.random(in: 0...255) })
        try bytes.write(to: source.appendingPathComponent("big.bin"))
        let slow = try plan(from: source, to: destination, flags: "--bwlimit=2000", rsync: rsync)
        #expect(slow.steps.contains { $0.command.contains(PlanEngine.partialDirFlag) })

        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        let run = Task {
            for try await _ in transports.enact(slow) {}
        }
        try await Task.sleep(for: .milliseconds(1_500))
        run.cancel()
        _ = await run.result

        let finalName = destination.appendingPathComponent("big.bin")
        let kept = destination.appendingPathComponent(".palana-partial/big.bin")
        // The stop waits for the shell rsync runs under; rsync's receiver
        // moves its temp file into the partial folder a moment later.
        await ProcessFixture.waitUntil(timeout: .seconds(3)) {
            FileManager.default.fileExists(atPath: kept.path)
        }
        #expect(!FileManager.default.fileExists(atPath: finalName.path), "no fragment under the real name")
        let keptSize = (try? FileManager.default.attributesOfItem(atPath: kept.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(keptSize > 0 && keptSize < bytes.count, "the received bytes wait in .palana-partial")

        // The next run reuses the saved bytes rather than resending them —
        // a final file that matches proves only that it finished (review Q04).
        let stats = try await output(of: try plan(from: source, to: destination, flags: "--stats", rsync: rsync))
        #expect(matchedBytes(stats) > 0, "the resumed copy reused what was saved: \(stats)")
        #expect(try Data(contentsOf: finalName) == bytes, "the next run finishes the copy")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".palana-partial").path))
    }

    @Test(
        "a selected folder copies whole, a .rsync-partial inside it included; only .palana-partial is pālana's own",
        arguments: rsyncs)
    func selectedFoldersCopyWhole(rsync: HostCapability) async throws {
        let root = try ProcessFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src")
        let destination = root.appendingPathComponent("dst")
        let tree = source.appendingPathComponent("tree")
        for folder in ["", ".rsync-partial", ".palana-partial"] {
            try FileManager.default.createDirectory(
                at: tree.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("ordinary".utf8).write(to: tree.appendingPathComponent("ordinary.txt"))
        try Data("theirs".utf8).write(to: tree.appendingPathComponent(".rsync-partial/kept.txt"))
        try Data("ours".utf8).write(to: tree.appendingPathComponent(".palana-partial/x"))

        _ = try await output(
            of: try plan(from: source, to: destination, name: "tree", kind: .directory, flags: nil, rsync: rsync))
        let landed = destination.appendingPathComponent("tree")
        #expect(FileManager.default.fileExists(atPath: landed.appendingPathComponent("ordinary.txt").path))
        #expect(
            FileManager.default.fileExists(atPath: landed.appendingPathComponent(".rsync-partial/kept.txt").path),
            "a folder that merely looks like a cache is the operator's data")
        #expect(
            !FileManager.default.fileExists(atPath: landed.appendingPathComponent(".palana-partial/x").path),
            "the reserved name is skipped, as the plan and the README say")
    }
}

@Suite("rsync operator flags — interrupted-copy handling stays pālana's (review Q06)")
struct InterruptedCopyFlagTests {
    @Test(
        "flags that would put a fragment under the real name, or stop resume, are refused on a copy",
        arguments: [
            "--partial-dir=.", "--partial", "--no-partial", "--inplace", "--append", "--append-verify",
            "--delay-updates", "--whole-file", "--no-whole-file", "-P", "-avP", "-W", "--bwlimit=1000 --partial-dir=.",
            "--inpl", "--PARTIAL",
            "--no-secluded-args --remote-option=--partial-dir=.", "--no-secluded-args -M--partial-dir=.",
            "-M --partial-dir=.", "-vM--inplace", "--remote-o=--append",
        ])
    func refused(flags: String) {
        #expect(throws: PlanError.rsyncFlagsControlInterruptedCopies) {
            try PlanEngine.validateRsyncOperatorFlags(flags, copying: true)
        }
    }

    @Test(
        "ordinary refinements still pass, -p (permissions) and value-taking short options included",
        arguments: [
            "--bwlimit=1000", "-p", "-avz", "--progress", "--info=stats2", "--exclude=cache/", "--delete",
            "-T/tmp/Work", "-B8192", "-avT/tmp/MW", "--no-secluded-args",
        ])
    func allowed(flags: String) throws {
        try PlanEngine.validateRsyncOperatorFlags(flags, copying: true)
    }

    @Test("a move drops operator flags, so they are not refused there")
    func movesUnaffected() throws {
        try PlanEngine.validateRsyncOperatorFlags("--append", copying: false)
    }
}
