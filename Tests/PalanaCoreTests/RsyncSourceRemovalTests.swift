// The proof that `--remove-source-files` may be composed at all.
//
// A move built on that flag is only safe if rsync itself refuses to
// remove a source file that changed while it was being read. That is a
// property of the rsync on the host, not of anything pālana composes,
// so it is established here against every rsync binary this machine
// carries, live, with a real file changed mid-transfer.
//
// The window is made wide and repeatable with --bwlimit rather than by
// racing a large file: the transfer is throttled to a known rate, and
// the change lands well inside it.
//
// Recorded difference, and the reason the engine reports leftovers
// instead of trusting exit status: rsync 3.x refuses and exits 23,
// while openrsync refuses and exits 0.

import Foundation
import Testing

@testable import PalanaCore

@Suite("rsync source removal, live", .serialized)
struct RsyncSourceRemovalTests {
    /// Every rsync this machine carries, by absolute path.
    static func availableBinaries() -> [String] {
        ["/usr/bin/rsync", "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync"]
            .filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-rsyncmove-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("dst"), withIntermediateDirectories: true)
        return root
    }

    private struct Outcome {
        var exitStatus: Int32
        var output: String
        var sourceSurvives: Bool
    }

    /// Runs one rsync move, optionally changing the source mid-transfer.
    private func move(
        binary: String, root: URL, throttleKBps: Int?, changeAfter: Duration?
    ) async throws -> Outcome {
        let source = root.appendingPathComponent("src/payload.bin")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var arguments = ["-a"]
        if let throttleKBps { arguments.append("--bwlimit=\(throttleKBps)") }
        arguments += ["--remove-source-files", source.path, root.appendingPathComponent("dst").path + "/"]
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        if let changeAfter {
            try await Task.sleep(for: changeAfter)
            if let handle = try? FileHandle(forUpdating: source) {
                try? handle.seek(toOffset: 100)
                try handle.write(contentsOf: Data("CHANGED-DURING-TRANSFER".utf8))
                try? handle.close()
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(
            exitStatus: process.terminationStatus,
            output: String(bytes: data, encoding: .utf8) ?? "",
            sourceSurvives: FileManager.default.fileExists(atPath: source.path))
    }

    @Test("every rsync here refuses to remove a source that changed during the transfer")
    func changedSourceIsNeverRemoved() async throws {
        let binaries = Self.availableBinaries()
        try #require(!binaries.isEmpty, "no rsync on this machine")
        for binary in binaries {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            // 512 KB throttled to 100 KB/s is about five seconds of reading.
            try Data(count: 512 << 10)
                .write(to: root.appendingPathComponent("src/payload.bin"))

            let outcome = try await move(
                binary: binary, root: root, throttleKBps: 100, changeAfter: .milliseconds(1200))

            let unsafe = Comment(
                rawValue: "\(binary) removed a source it had not faithfully transferred — "
                    + "--remove-source-files must not be composed for this binary")
            #expect(outcome.sourceSurvives, unsafe)
            // The refusal is always spoken, even where the status is 0.
            let silent = Comment(
                rawValue: "\(binary) refused silently and exited 0 — the leftover check is the only signal")
            #expect(outcome.exitStatus != 0 || !outcome.output.isEmpty, silent)
        }
    }

    @Test("an unchanged source is removed — the flag does what the move needs")
    func unchangedSourceIsRemoved() async throws {
        for binary in Self.availableBinaries() {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            try Data("steady bytes".utf8)
                .write(to: root.appendingPathComponent("src/payload.bin"))

            let outcome = try await move(
                binary: binary, root: root, throttleKBps: nil, changeAfter: nil)

            #expect(outcome.exitStatus == 0, Comment(rawValue: "\(binary): \(outcome.output)"))
            #expect(
                !outcome.sourceSurvives,
                Comment(rawValue: "\(binary) left the source behind"))
            #expect(
                FileManager.default.contents(
                    atPath: root.appendingPathComponent("dst/payload.bin").path)
                    == Data("steady bytes".utf8))
        }
    }
}
