// The pre-1.0 review's finding 8: a send-back's commit where the
// destination has no hard links — the link commit's refusal, and the
// rename commit the operator can choose after it.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Finding 8: send-back where hard links are missing

/// A send-back's commit program, run directly under `/bin/sh` in a
/// scratch destination, with `ln` replaced by a shell function — no
/// hard-link-less volume needed.
struct CommitScratch {
    let root: URL
    let name = "note.txt"
    var directory: URL { root.appendingPathComponent("remote") }
    var target: URL { directory.appendingPathComponent(name) }
    var stage: URL { directory.appendingPathComponent(RemoteVersionGuard.stagingName(token: "t1")) }
    var staged: URL { stage.appendingPathComponent(name) }
    var kept: URL { directory.appendingPathComponent(RemoteVersionGuard.displacedName(token: "t1")) }

    /// `ln` always fails, as on exFAT or an rclone mount.
    static let noLinks = #"ln() { echo "ln: Operation not supported" >&2; return 1; }"#
    /// The probe links; the promotion fails with the path still free.
    static let promotionFails = #"ln() { case "$3" in *.palana-link) command ln "$@" ;; *) return 1 ;; esac; }"#
    /// The probe links; another writer takes the path as promotion runs.
    static let promotionTaken =
        #"ln() { case "$3" in *.palana-link) command ln "$@" ;; *) printf theirs > "$3"; return 1 ;; esac; }"#

    init(remote: String?, edit: String = "mine") throws {
        root = try ProcessFixture.makeDirectory()
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try Data(edit.utf8).write(to: staged)
        if let remote { try Data(remote.utf8).write(to: target) }
    }

    func guardValue(expecting expected: String?) -> RemoteVersionGuard {
        RemoteVersionGuard(
            host: "nas",
            pathData: RemoteIdentity.pathData(directory: directory.path, name: Data(name.utf8)),
            expectedDigest: expected.map { RoundTrip.hex(RoundTrip.digest(of: Data($0.utf8))) },
            token: "t1")
    }

    /// Runs the program with `prelude` defined first; exit status and stderr.
    func commit(_ program: String, prelude: String = "") throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", prelude + "\n" + program]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    func commit(expecting expected: String?, prelude: String = "") throws -> (status: Int32, stderr: String) {
        try commit(
            guardValue(expecting: expected).commitProgram(directory: directory.path, name: name), prelude: prelude)
    }

    func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

@Suite("Review finding 8 — send-back without hard links")
struct SendBackWithoutHardLinksTests {
    @Test("no hard links: refused before anything is set aside; the remote version stands")
    func noLinksReplacing() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: "checked", prelude: CommitScratch.noLinks)
        #expect(result.status == RemoteVersionGuard.noHardLinkExitStatus)
        #expect(result.stderr.contains("palana-refused: nas:"))
        #expect(result.stderr.contains("a hard link could not be made here"))
        #expect(scratch.text(scratch.target) == "checked")
        #expect(!scratch.exists(scratch.kept))
        #expect(!scratch.exists(scratch.stage), "an early refusal clears staging; the Mac keeps the edit")
    }

    @Test("no hard links when the send creates the file: refused, nothing created")
    func noLinksCreating() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: nil, prelude: CommitScratch.noLinks)
        #expect(result.status == RemoteVersionGuard.noHardLinkExitStatus)
        #expect(!scratch.exists(scratch.target))
        #expect(!scratch.exists(scratch.stage))
    }

    @Test("promotion fails with the path free: mv restores the original; the edit is kept and named")
    func promotionFailsRestores() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: "checked", prelude: CommitScratch.promotionFails)
        #expect(result.status == 7)
        #expect(scratch.text(scratch.target) == "checked")
        #expect(!scratch.exists(scratch.kept))
        #expect(scratch.text(scratch.staged) == "mine")
        #expect(result.stderr.contains("palana-restored: nas:"))
        let notes = RecoveryNote.notes(in: result.stderr, host: "nas")
        #expect(
            notes.contains {
                $0.kind == .retained && $0.detail.hasPrefix("nas:\(scratch.staged.path) — ")
                    && $0.detail.hasSuffix("so your edit is kept here")
            })
    }

    @Test("another writer takes the path mid-commit: theirs stands, both other versions are kept and named")
    func promotionTakenKeepsBoth() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: "checked", prelude: CommitScratch.promotionTaken)
        #expect(result.status == 7)
        #expect(scratch.text(scratch.target) == "theirs")
        #expect(scratch.text(scratch.kept) == "checked")
        #expect(scratch.text(scratch.staged) == "mine")
        let retained = RecoveryNote.notes(in: result.stderr, host: "nas").filter { $0.kind == .retained }
        #expect(retained.contains { $0.detail.hasPrefix("nas:\(scratch.kept.path) — ") })
        #expect(retained.contains { $0.detail.hasPrefix("nas:\(scratch.staged.path) — ") })
    }

    @Test("where hard links work, the commit lands and leaves nothing behind")
    func linksWork() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: "checked")
        #expect(result.status == 0)
        #expect(scratch.text(scratch.target) == "mine")
        #expect(!scratch.exists(scratch.kept))
        #expect(!scratch.exists(scratch.stage))
    }
}

@Suite("Review finding 8 — the rename commit the operator can choose")
struct RenameCommitTests {
    private func renameProgram(_ scratch: CommitScratch, expecting expected: String?) -> String {
        var versionGuard = scratch.guardValue(expecting: expected)
        versionGuard.commitMode = .rename
        return versionGuard.commitProgram(directory: scratch.directory.path, name: scratch.name)
    }

    @Test("both commit programs parse under /bin/sh -n, replacing and creating")
    func programsParse() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        for expected in ["checked", nil] as [String?] {
            for program in [
                scratch.guardValue(expecting: expected).commitProgram(
                    directory: scratch.directory.path, name: scratch.name),
                renameProgram(scratch, expecting: expected),
            ] {
                #expect(try scratch.commit("set -n; " + program).status == 0)
            }
        }
    }

    @Test("no hard links, rename chosen: the edit replaces the checked version and nothing is left")
    func renameReplaces() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(
            renameProgram(scratch, expecting: "checked"), prelude: CommitScratch.noLinks)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(scratch.text(scratch.target) == "mine")
        #expect(!scratch.exists(scratch.kept))
        #expect(!scratch.exists(scratch.stage))
    }

    @Test("no hard links, rename chosen: a new file is created")
    func renameCreates() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(renameProgram(scratch, expecting: nil), prelude: CommitScratch.noLinks)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(scratch.text(scratch.target) == "mine")
        #expect(!scratch.exists(scratch.stage))
    }

    @Test("the rename commit still refuses a version that changed since the check")
    func renameStillProvesVersion() throws {
        let scratch = try CommitScratch(remote: "theirs")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(
            renameProgram(scratch, expecting: "checked"), prelude: CommitScratch.noLinks)
        #expect(result.status == 5)
        #expect(scratch.text(scratch.target) == "theirs")
    }

    @Test("a writer that lands after the rename is caught: theirs stands, the set-aside version is named")
    func writerAfterRename() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let lateWriter =
            #"mv() { command mv "$@"; s=$?; case "$3" in *palana-send-t1/*) printf theirs > "$4" ;; esac; return $s; }"#
        let result = try scratch.commit(
            renameProgram(scratch, expecting: "checked"), prelude: CommitScratch.noLinks + "\n" + lateWriter)
        #expect(result.status == 7)
        #expect(scratch.text(scratch.target) == "theirs")
        #expect(scratch.text(scratch.kept) == "checked")
        let retained = RecoveryNote.notes(in: result.stderr, host: "nas").filter { $0.kind == .retained }
        #expect(retained.contains { $0.detail.hasPrefix("nas:\(scratch.kept.path) — ") })
    }

    @Test("a directory that takes the name in the instant before the rename is named, with the edit inside it")
    func directorySwallows() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let racingDirectory =
            #"mv() { case "$3" in *palana-send-t1/*) mkdir "$4" ;; esac; command mv "$@"; }"#
        let result = try scratch.commit(
            renameProgram(scratch, expecting: nil), prelude: CommitScratch.noLinks + "\n" + racingDirectory)
        let nested = scratch.target.appendingPathComponent(scratch.name)
        #expect(result.status == 7)
        #expect(scratch.text(nested) == "mine")
        #expect(
            RecoveryNote.notes(in: result.stderr, host: "nas")
                .contains { $0.kind == .retained && $0.detail.hasPrefix("nas:\(nested.path) — ") })
    }

    @Test("a guard written before the mode existed decodes as a link commit")
    func oldGuardIsLink() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        var encoded = try JSONEncoder().encode(scratch.guardValue(expecting: nil))
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "commitMode")
        encoded = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RemoteVersionGuard.self, from: encoded)
        #expect(decoded.commitMode == nil)
        #expect(!decoded.renames)
    }
}

@Suite("Review finding 8 — the rename offer's plan", .serialized)
struct RenameCommittedPlanTests {
    private func sendBack(_ scratch: CommitScratch, mode: RemoteVersionGuard.CommitMode?) throws -> Plan {
        let edit = scratch.root.appendingPathComponent("edit")
        try FileManager.default.createDirectory(at: edit, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: edit.appendingPathComponent(scratch.name))
        // The scratch's own staging is for the program tests; a plan stages for itself.
        try? FileManager.default.removeItem(at: scratch.stage)
        var versionGuard = scratch.guardValue(expecting: "checked")
        versionGuard.host = PalanaCore.localHostName
        versionGuard.commitMode = mode
        return try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: PalanaCore.localHostName, directory: edit.path),
                entries: [remainderEntry(scratch.name)],
                destination: Locus(host: PalanaCore.localHostName, directory: scratch.directory.path),
                token: "t1",
                versionGuard: versionGuard),
            facts: PlanFacts())
    }

    @Test("renameCommitted is exactly what the engine composes for a rename guard")
    func matchesEngine() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let link = try sendBack(scratch, mode: nil)
        let offered = try #require(link.renameCommitted())
        #expect(offered == (try sendBack(scratch, mode: .rename)))
        #expect(offered.renameCommitted() == nil, "a rename plan offers nothing further")
        #expect(offered.steps.filter { $0.role != .promote } == link.steps.filter { $0.role != .promote })
    }

    @Test("a rename commit under a guard that names link is refused before anything runs")
    func mismatchRefused() async throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        var forged = try sendBack(scratch, mode: nil)
        let renamed = try #require(forged.renameCommitted())
        forged.steps = renamed.steps
        await #expect(throws: EnactmentError.self) {
            try await Transports(conduit: RecordedConduit(transcript: ConduitTranscript(entries: [])))
                .run(forged) { _ in }
        }
    }

    @Test("the offered plan runs through Transports and lands the edit")
    func offeredPlanRuns() async throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let offered = try #require(try sendBack(scratch, mode: nil).renameCommitted())
        try await Transports(conduit: LocalConduit()) { _, _, _ in 0 }.run(offered) { _ in }
        #expect(scratch.text(scratch.target) == "mine")
        #expect(!scratch.exists(scratch.kept))
        #expect(!scratch.exists(scratch.stage))
    }
}

/// Opt-in: a real directory with no hard links.
///
/// Named by `PALANA_NOLINK_DIR` — for example a scratch exFAT disk image
/// mounted with `hdiutil attach -nobrowse`. Skipped when unset.
@Suite("Review finding 8 — a real volume with no hard links", .serialized)
struct NoHardLinkVolumeTests {
    static let directory = ProcessInfo.processInfo.environment["PALANA_NOLINK_DIR"]

    @Test(
        "the link commit refuses with nothing replaced; the offered rename commit lands",
        .enabled(if: directory != nil))
    func realVolume() async throws {
        let base = URL(fileURLWithPath: try #require(Self.directory))
            .appendingPathComponent("palana-\(UUID().uuidString.prefix(8))")
        let edit = base.appendingPathComponent("edit")
        let remote = base.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: edit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("mine".utf8).write(to: edit.appendingPathComponent("note.txt"))
        try Data("checked".utf8).write(to: remote.appendingPathComponent("note.txt"))
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: PalanaCore.localHostName, directory: edit.path),
                entries: [remainderEntry("note.txt")],
                destination: Locus(host: PalanaCore.localHostName, directory: remote.path),
                token: "t1",
                versionGuard: RemoteVersionGuard(
                    host: PalanaCore.localHostName,
                    pathData: RemoteIdentity.pathData(directory: remote.path, name: Data("note.txt".utf8)),
                    expectedDigest: RoundTrip.hex(RoundTrip.digest(of: Data("checked".utf8))),
                    token: "t1")),
            facts: PlanFacts())
        let transports = Transports(conduit: LocalConduit()) { _, _, _ in 0 }
        await #expect {
            try await transports.run(plan) { _ in }
        } throws: { error in
            guard case EnactmentError.stepFailed(_, let status, _) = error else { return false }
            return status == RemoteVersionGuard.noHardLinkExitStatus
        }
        let target = remote.appendingPathComponent("note.txt")
        #expect(String(bytes: try Data(contentsOf: target), encoding: .utf8) == "checked")

        try await transports.run(try #require(plan.renameCommitted())) { _ in }
        #expect(String(bytes: try Data(contentsOf: target), encoding: .utf8) == "mine")
        #expect(try FileManager.default.contentsOfDirectory(atPath: remote.path) == ["note.txt"])
    }
}
