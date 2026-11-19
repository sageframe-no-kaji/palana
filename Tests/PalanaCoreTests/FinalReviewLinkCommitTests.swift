// The 2026-11-18 final review's F04: the default hard-link send-back
// commit, with a directory taking the destination name in the instant
// before `ln`. `ln` given a directory links inside it and exits 0; the
// commit must not count that as the edit landing.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Final review F04 — link commit into a racing directory")
struct FinalReviewLinkCommitTests {
    /// The probe links normally; the promotion's `ln` finds a directory
    /// already standing at the destination name, then runs for real.
    static let racingDirectory =
        #"ln() { case "$3" in *.palana-link) command ln "$@" ;; *) mkdir -- "$3"; command ln "$@" ;; esac; }"#

    private func nested(_ scratch: CommitScratch) -> URL {
        scratch.target.appendingPathComponent(scratch.name)
    }

    private func retained(_ result: (status: Int32, stderr: String)) -> [String] {
        RecoveryNote.notes(in: result.stderr, host: "nas").filter { $0.kind == .retained }.map(\.detail)
    }

    @Test("replacing: refused, the checked version and the edit are both kept and named, nothing deleted")
    func replacingIntoRacingDirectory() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: "checked", prelude: Self.racingDirectory)
        #expect(result.status == 7, "a link inside a directory is not the edit landing")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: scratch.target.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(scratch.text(scratch.kept) == "checked", "the displaced original is not deleted")
        #expect(scratch.text(scratch.staged) == "mine", "the staged edit is not deleted")
        #expect(scratch.text(nested(scratch)) == "mine")
        let notes = retained(result)
        #expect(notes.contains { $0.hasPrefix("nas:\(scratch.kept.path) — ") })
        #expect(notes.contains { $0.hasPrefix("nas:\(scratch.staged.path) — ") })
        #expect(notes.contains { $0.hasPrefix("nas:\(nested(scratch).path) — ") && $0.contains("landed inside it") })
    }

    @Test("creating: refused, and the link that landed inside the directory is named")
    func creatingIntoRacingDirectory() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let result = try scratch.commit(expecting: nil, prelude: Self.racingDirectory)
        #expect(result.status == 7)
        #expect(result.stderr.contains("palana-refused: nas:"))
        #expect(scratch.text(nested(scratch)) == "mine")
        #expect(retained(result).contains { $0.hasPrefix("nas:\(nested(scratch).path) — ") })
    }

    @Test("a name already inside the racing directory is not claimed as this operation's")
    func foreignNestedNameIsNotNamed() throws {
        let scratch = try CommitScratch(remote: nil)
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        // The directory arrives already holding a file of the same name:
        // `ln` refuses, and nothing of theirs is called ours.
        let prelude =
            #"ln() { case "$3" in *.palana-link) command ln "$@" ;; *) mkdir -- "$3"; printf theirs > "$3/$3"; command ln "$@" ;; esac; }"#
        let result = try scratch.commit(expecting: nil, prelude: prelude)
        #expect(result.status == 7)
        #expect(scratch.text(nested(scratch)) == "theirs")
        #expect(!retained(result).contains { $0.hasPrefix("nas:\(nested(scratch).path) — ") })
    }

    @Test("successive link commits each land at the exact path and leave nothing behind")
    func successiveCommitsLand() throws {
        let scratch = try CommitScratch(remote: "checked")
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        let first = try scratch.commit(expecting: "checked")
        #expect(first.status == 0)
        #expect(scratch.text(scratch.target) == "mine")
        // The next save stages again under the same token, bound to what the first one sent.
        try FileManager.default.createDirectory(at: scratch.stage, withIntermediateDirectories: true)
        try Data("second".utf8).write(to: scratch.staged)
        let second = try scratch.commit(expecting: "mine")
        #expect(second.status == 0, "\(second.stderr)")
        #expect(scratch.text(scratch.target) == "second")
        #expect(!scratch.exists(scratch.kept))
        #expect(!scratch.exists(scratch.stage))
    }

    @Test("the link commit proves the landing with -ef, and refuses a shell that cannot, before setting aside")
    func programChecksSameFile() {
        let scratch = CommitNames(directory: "/srv", name: "note.txt", token: "t1")
        let program = RemoteVersionGuard(
            host: "nas", pathData: Data("/srv/note.txt".utf8), expectedDigest: "aa", token: "t1"
        ).commitProgram(directory: "/srv", name: "note.txt")
        #expect(program.contains("[ \(scratch.entry) -ef \(scratch.staged) ]"))
        #expect(program.contains("[ \(scratch.probe) -ef \(scratch.staged) ]"))
        let probe = program.range(of: "-ef \(scratch.staged) ] 2>/dev/null ||")
        let setAside = program.range(of: "mv -n -- \(scratch.entry) \(scratch.kept)")
        #expect(probe != nil && setAside != nil)
        if let probe, let setAside { #expect(probe.lowerBound < setAside.lowerBound) }
    }
}
