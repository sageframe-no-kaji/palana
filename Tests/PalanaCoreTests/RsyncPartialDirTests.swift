// An interrupted rsync copy keeps its bytes in `.rsync-partial`, never
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
    private func plan(from source: URL, to destination: URL, slow: Bool, rsync: HostCapability) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: [
                    FileEntry(
                        nameData: Data("big.bin".utf8),
                        kind: .file,
                        size: 20_971_520,
                        modified: Date(),
                        permissions: "644",
                        owner: "op",
                        group: "op")
                ],
                destination: Locus(host: PalanaCore.localHostName, directory: destination.path)),
            facts: PlanFacts(
                sourceCapability: rsync,
                destinationCapability: rsync,
                rsyncOperatorFlags: slow ? "--bwlimit=2000" : nil))
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
        let slow = try plan(from: source, to: destination, slow: true, rsync: rsync)
        #expect(slow.steps.contains { $0.command.contains(PlanEngine.partialDirFlag) })

        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        let run = Task {
            for try await _ in transports.enact(slow) {}
        }
        try await Task.sleep(for: .milliseconds(1_500))
        run.cancel()
        _ = await run.result

        let finalName = destination.appendingPathComponent("big.bin")
        let kept = destination.appendingPathComponent(".rsync-partial/big.bin")
        // The stop waits for the shell rsync runs under; rsync's receiver
        // moves its temp file into the partial folder a moment later.
        await ProcessFixture.waitUntil(timeout: .seconds(3)) {
            FileManager.default.fileExists(atPath: kept.path)
        }
        #expect(!FileManager.default.fileExists(atPath: finalName.path), "no fragment under the real name")
        let keptSize = (try? FileManager.default.attributesOfItem(atPath: kept.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(keptSize > 0 && keptSize < bytes.count, "the received bytes wait in .rsync-partial")

        for try await _ in transports.enact(try plan(from: source, to: destination, slow: false, rsync: rsync)) {}
        #expect(try Data(contentsOf: finalName) == bytes, "the next run finishes the copy")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".rsync-partial").path))
    }
}
