// The manifest's two halves: the parser over hand-made records, and
// the command run live through LocalConduit against a temporary tree
// on this Mac — a real BSD userland resolving a real SHA-256 tool. The
// tree carries the hostile shapes: a name with a newline, a name with
// a space, a name starting with a hyphen, a dangling symlink, a fifo.

import Foundation
import Testing

@testable import PalanaCore

@Suite("TransferManifest parsing")
struct TransferManifestParseTests {
    private func parse(_ text: String) throws -> TransferManifest {
        try TransferManifest.parse(Data(text.utf8))
    }

    @Test("records parse into typed entries, sorted by name bytes")
    func parsesAndSorts() throws {
        let text =
            ManifestFixture.file("z.txt", size: 5)
            + ManifestFixture.symlink("link", target: "z.txt")
            + ManifestFixture.directory("dir with space")
            + ManifestFixture.record("o", name: "fifo")
            + ManifestFixture.file("dir with space/n\nl.txt", size: 3, digest: ManifestFixture.worldDigest)
        let manifest = try parse(text)
        #expect(
            manifest.entries.map(\.displayName) == [
                "dir with space", "dir with space/n\nl.txt", "fifo", "link", "z.txt",
            ])
        #expect(
            manifest.entries[4]
                == TransferManifest.Entry(
                    name: Data("z.txt".utf8), kind: .file, size: 5, digest: ManifestFixture.helloDigest))
        #expect(
            manifest.entries[3]
                == TransferManifest.Entry(
                    name: Data("link".utf8), kind: .symlink, linkTarget: Data("z.txt".utf8)))
        #expect(manifest.entries[0].kind == .directory)
        #expect(manifest.entries[2].kind == .other)
        #expect(manifest.entries[1].size == 3)
    }

    @Test("an empty manifest parses to no entries — the caller decides that is not evidence")
    func emptyParses() throws {
        #expect(try parse("").entries.isEmpty)
    }

    @Test("a truncated record — fields not a multiple of four — refuses")
    func truncatedRefuses() {
        #expect(throws: TransferManifest.ParseError.truncatedRecord) {
            try parse("f\u{0}5\u{0}\(ManifestFixture.helloDigest)\u{0}")
        }
        #expect(throws: TransferManifest.ParseError.truncatedRecord) {
            try parse("2\n")
        }
        // A record whose last field lacks its NUL.
        #expect(throws: TransferManifest.ParseError.truncatedRecord) {
            try parse("f\u{0}5\u{0}\(ManifestFixture.helloDigest)\u{0}a.txt")
        }
    }

    @Test("an unknown kind letter refuses")
    func unknownKindRefuses() {
        #expect(throws: TransferManifest.ParseError.unknownKind("x")) {
            try parse(ManifestFixture.record("x", name: "a"))
        }
        #expect(throws: TransferManifest.ParseError.unknownKind("")) {
            try parse(ManifestFixture.record("", name: "a"))
        }
    }

    @Test("a file with a malformed size or digest refuses — a masked failure's empty field is not a value")
    func malformedFieldsRefuse() {
        #expect(throws: TransferManifest.ParseError.malformedSize(name: "a")) {
            try parse(ManifestFixture.record("f", size: "", payload: ManifestFixture.helloDigest, name: "a"))
        }
        #expect(throws: TransferManifest.ParseError.malformedSize(name: "a")) {
            try parse(ManifestFixture.record("f", size: "-1", payload: ManifestFixture.helloDigest, name: "a"))
        }
        #expect(throws: TransferManifest.ParseError.malformedDigest(name: "a")) {
            try parse(ManifestFixture.record("f", size: "5", payload: "", name: "a"))
        }
        #expect(throws: TransferManifest.ParseError.malformedDigest(name: "a")) {
            try parse(ManifestFixture.record("f", size: "5", payload: "abc", name: "a"))
        }
        #expect(throws: TransferManifest.ParseError.malformedDigest(name: "a")) {
            try parse(
                ManifestFixture.record(
                    "f", size: "5", payload: ManifestFixture.helloDigest.uppercased(), name: "a"))
        }
    }

    @Test("a repeated name refuses")
    func duplicateRefuses() {
        #expect(throws: TransferManifest.ParseError.duplicateName("a")) {
            try parse(ManifestFixture.file("a") + ManifestFixture.file("a"))
        }
    }

    @Test("missingNames names the selected entries the manifest lacks")
    func missingNames() throws {
        let manifest = try parse(
            ManifestFixture.file("f1") + ManifestFixture.directory("d") + ManifestFixture.file("d/x"))
        #expect(manifest.missingNames(from: ["f1", "d"]).isEmpty)
        #expect(manifest.missingNames(from: ["f1", "f2", "d/x", "d"]) == ["f2"])
    }

    @Test("firstUnmatched is the subset rule — nil when identical, and nil over destination-only entries")
    func firstUnmatchedSubset() throws {
        let base = try parse(ManifestFixture.file("a") + ManifestFixture.file("b") + ManifestFixture.file("c"))
        #expect(base.firstUnmatched(in: base) == nil)
        // What already stood at a merged destination is not evidence
        // against the source; the source is evidence against it.
        let extra = try parse(
            ManifestFixture.file("a") + ManifestFixture.file("b") + ManifestFixture.file("bb")
                + ManifestFixture.file("c"))
        #expect(base.firstUnmatched(in: extra) == nil)
        #expect(extra.firstUnmatched(in: base) == "bb")
    }

    @Test("firstUnmatched names the first source entry the destination lacks, or carries differently")
    func firstUnmatchedNamesTheSourceEntry() throws {
        let base = try parse(ManifestFixture.file("a") + ManifestFixture.file("b") + ManifestFixture.file("c"))
        let shorter = try parse(ManifestFixture.file("a") + ManifestFixture.file("b"))
        #expect(base.firstUnmatched(in: shorter) == "c")
        #expect(shorter.firstUnmatched(in: base) == nil)
        let changed = try parse(
            ManifestFixture.file("a") + ManifestFixture.file("b", digest: ManifestFixture.worldDigest)
                + ManifestFixture.file("c"))
        #expect(base.firstUnmatched(in: changed) == "b")
        let resized = try parse(
            ManifestFixture.file("a") + ManifestFixture.file("b", size: 4) + ManifestFixture.file("c"))
        #expect(base.firstUnmatched(in: resized) == "b")
        let rekinded = try parse(
            ManifestFixture.file("a") + ManifestFixture.directory("b") + ManifestFixture.file("c"))
        #expect(base.firstUnmatched(in: rekinded) == "b")
        let linked = try parse(ManifestFixture.symlink("l", target: "a"))
        let relinked = try parse(ManifestFixture.symlink("l", target: "b"))
        #expect(linked.firstUnmatched(in: relinked) == "l")
        #expect(linked.firstUnmatched(in: linked) == nil)
    }

    @Test("the command names the directory, the selection, the tools, and the refusal — and no count")
    func commandShape() {
        let command = TransferManifest.command(directory: "/tank/a", names: ["f1", "with space", "-dash"])
        #expect(command.hasPrefix("cd /tank/a || exit 3; "))
        #expect(command.contains("for n in ./f1 './with space' ./-dash; do [ -e \"$n\" ] || [ -L \"$n\" ]"))
        #expect(command.contains("command -v sha256sum >/dev/null 2>&1; then PALANA_DG=sha256sum"))
        #expect(command.contains("then PALANA_DG='shasum -a 256'"))
        #expect(command.contains("then PALANA_DG='openssl dgst -sha256'"))
        #expect(command.contains("else echo 'no sha256 tool (tried sha256sum, shasum, openssl)' >&2; exit 3; fi"))
        #expect(command.contains("find ./f1 './with space' ./-dash -exec sh -c '"))
        #expect(command.hasSuffix("palana-manifest {} + || exit 3"))
        #expect(!command.contains("wc -l"))
        #expect(!command.contains("md5"))
        #expect(!command.contains("cksum"))
    }
}

@Suite("VerificationReport subset gate")
struct VerificationReportSubsetTests {
    private func manifest(_ text: String) throws -> TransferManifest {
        try TransferManifest.parse(Data(text.utf8))
    }

    private let source = ManifestFixture.directory("dir") + ManifestFixture.file("dir/x")

    @Test("destination-only entries pass — what stood in the merged directory is kept, not counted against")
    func destinationOnlyEntriesPass() throws {
        let landed = try manifest(source + ManifestFixture.file("dir/old") + ManifestFixture.directory("dir/sub"))
        let report = VerificationReport.manifests(source: try manifest(source), destination: landed)
        #expect(report.matched)
    }

    @Test("a source entry missing at the destination fails")
    func missingSourceEntryFails() throws {
        let landed = try manifest(ManifestFixture.directory("dir") + ManifestFixture.file("dir/old"))
        let report = VerificationReport.manifests(source: try manifest(source), destination: landed)
        #expect(!report.matched)
    }

    @Test("a source entry with different bytes at the destination fails")
    func differentBytesFail() throws {
        let landed = try manifest(
            ManifestFixture.directory("dir") + ManifestFixture.file("dir/x", digest: ManifestFixture.worldDigest)
                + ManifestFixture.file("dir/old"))
        let report = VerificationReport.manifests(source: try manifest(source), destination: landed)
        #expect(!report.matched)
    }

    @Test("a source file standing as a directory at the destination fails")
    func fileBecameDirectoryFails() throws {
        let landed = try manifest(
            ManifestFixture.directory("dir") + ManifestFixture.directory("dir/x") + ManifestFixture.file("dir/old"))
        let report = VerificationReport.manifests(source: try manifest(source), destination: landed)
        #expect(!report.matched)
    }

    @Test("an empty source manifest is still not a match, whatever the destination holds")
    func emptySourceNeverMatches() throws {
        let landed = try manifest(source)
        #expect(!VerificationReport.manifests(source: try manifest(""), destination: landed).matched)
        #expect(!VerificationReport.manifests(source: try manifest(""), destination: try manifest("")).matched)
    }
}

@Suite("TransferManifest live on this Mac", .serialized)
struct TransferManifestLiveTests {
    private static let helloDigest = ManifestFixture.helloDigest

    /// A fresh tree under the temporary directory, removed after the test.
    private struct Tree {
        let root: URL
        var source: String { root.appendingPathComponent("src").path }
        var destination: String { root.appendingPathComponent("dst").path }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-manifest-\(UUID().uuidString.prefix(8))", isDirectory: true)
            let src = root.appendingPathComponent("src")
            let nested = src.appendingPathComponent("dir with space/sub")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("dst"), withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: src.appendingPathComponent("a.txt"))
            try Data("x\ny".utf8).write(to: nested.appendingPathComponent("n\nl.txt"))
            try Data("dash".utf8).write(to: src.appendingPathComponent("-dash"))
            try FileManager.default.createSymbolicLink(
                atPath: src.appendingPathComponent("link").path, withDestinationPath: "a.txt")
            try FileManager.default.createSymbolicLink(
                atPath: src.appendingPathComponent("dir with space/dangle").path,
                withDestinationPath: "../zzz")
            #expect(mkfifo(src.appendingPathComponent("fifo").path, 0o644) == 0)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static let names = ["a.txt", "dir with space", "link", "fifo", "-dash"]

    private static func run(_ command: String) async throws -> CommandResult {
        try await LocalConduit().run(on: PalanaCore.localHostName, command).collect()
    }

    private static func manifest(_ directory: String, names: [String] = names) async throws -> TransferManifest {
        let result = try await run(TransferManifest.command(directory: directory, names: names))
        #expect(result.exitStatus == 0, Comment(rawValue: result.stderrText))
        return try TransferManifest.parse(result.stdout)
    }

    @Test("the command manifests a hostile tree exactly — kinds, sizes, digests, targets, names")
    func manifestsTheTree() async throws {
        let tree = try Tree()
        defer { tree.remove() }
        let manifest = try await Self.manifest(tree.source)
        let byName = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.displayName, $0) })
        #expect(
            Set(byName.keys) == [
                "-dash", "a.txt", "dir with space", "dir with space/dangle", "dir with space/sub",
                "dir with space/sub/n\nl.txt", "fifo", "link",
            ])
        #expect(
            byName["a.txt"]
                == TransferManifest.Entry(
                    name: Data("a.txt".utf8), kind: .file, size: 5, digest: Self.helloDigest))
        #expect(byName["dir with space/sub/n\nl.txt"]?.size == 3)
        #expect(byName["dir with space/sub/n\nl.txt"]?.digest?.count == 64)
        #expect(byName["link"]?.linkTarget == Data("a.txt".utf8))
        #expect(byName["dir with space/dangle"]?.linkTarget == Data("../zzz".utf8))
        #expect(byName["dir with space/dangle"]?.kind == .symlink)
        #expect(byName["fifo"]?.kind == .other)
        #expect(byName["dir with space"]?.kind == .directory)
        #expect(byName["-dash"]?.size == 4)
    }

    @Test("a faithful copy manifests identically; one changed byte at the same size does not")
    func copyAgreesUntilAByteChanges() async throws {
        let tree = try Tree()
        defer { tree.remove() }
        let copy = try await Self.run(
            "cp -R -P \(ShellQuote.quote(tree.source))/. \(ShellQuote.quote(tree.destination))/")
        #expect(copy.exitStatus == 0, Comment(rawValue: copy.stderrText))
        let before = try await Self.manifest(tree.source)
        let landed = try await Self.manifest(tree.destination)
        #expect(before == landed)
        #expect(before.firstUnmatched(in: landed) == nil)

        try Data("jello".utf8).write(
            to: URL(fileURLWithPath: tree.destination).appendingPathComponent("a.txt"))
        let tampered = try await Self.manifest(tree.destination)
        #expect(before != tampered)
        #expect(before.entries.count == tampered.entries.count)
        #expect(before.firstUnmatched(in: tampered) == "a.txt")
    }

    @Test("a selected name that is absent fails the command before it walks")
    func missingNameFails() async throws {
        let tree = try Tree()
        defer { tree.remove() }
        let result = try await Self.run(
            TransferManifest.command(directory: tree.source, names: ["a.txt", "nope"]))
        #expect(result.exitStatus == 3)
        #expect(result.stderrText.contains("missing: ./nope"))
        #expect(result.stdout.isEmpty)
    }

    @Test("an absent directory fails the command")
    func missingDirectoryFails() async throws {
        let tree = try Tree()
        defer { tree.remove() }
        let result = try await Self.run(
            TransferManifest.command(directory: tree.source + "/nowhere", names: ["a.txt"]))
        #expect(result.exitStatus == 3)
    }

    @Test("an unreadable file fails the command — no record, nonzero status", .enabled(if: geteuid() != 0))
    func unreadableFileFails() async throws {
        let tree = try Tree()
        defer { tree.remove() }
        let path = URL(fileURLWithPath: tree.source).appendingPathComponent("a.txt").path
        #expect(chmod(path, 0) == 0)
        defer { _ = chmod(path, 0o644) }
        let result = try await Self.run(
            TransferManifest.command(directory: tree.source, names: ["a.txt"]))
        #expect(result.exitStatus == 3)
        #expect(result.stderrText.contains("unreadable: a.txt"))
    }
}
