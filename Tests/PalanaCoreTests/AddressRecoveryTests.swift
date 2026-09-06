// AddressRecoveryTests — the conservative recovery policy behind every
// typed address, over a fake host that records each path it is asked
// about. The order is fixed: the exact path wins even when it ends in
// punctuation; one trailing prose character may come off, only when what
// remains exists; then the longest existing directory ancestor, with the
// unresolved remainder carried along; `/` is never a recovery. Every
// outcome names what it did, and the host is never anyone but the one the
// grammar chose.

import Foundation
import Testing

@testable import PalanaCore

/// A host that knows a few directories and files, and remembers every
/// path it was asked about — in order, so a test can pin the probe count.
private actor FakeHost {
    private let directories: Set<String>
    private let files: Set<String>
    private let failure: (any Error)?
    private(set) var asked: [String] = []

    init(directories: Set<String> = [], files: Set<String> = [], failure: (any Error)? = nil) {
        self.directories = directories.union(["/"])
        self.files = files
        self.failure = failure
    }

    func answer(_ path: String) throws -> PathPresence {
        asked.append(path)
        if let failure { throw failure }
        if directories.contains(path) { return .directory }
        if files.contains(path) { return .file }
        return .absent
    }

    /// The probe recovery is handed.
    var probe: PathProbe {
        { path in try await self.answer(path) }
    }
}

private struct HostDown: Error, CustomStringConvertible {
    var description: String { "ssh: connect to host koan port 22: No route to host" }
}

/// A door that answers scripted commands and remembers the hosts asked.
private actor ScriptedDoor: Conduit {
    private let answers: [String: (String, Int32)]
    private(set) var hosts: [String] = []

    init(answers: [String: (String, Int32)]) {
        self.answers = answers
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        hosts.append(host)
        let (stdout, status) = answers[command] ?? ("", 1)
        return RunningCommand(replayingStdout: Data(stdout.utf8), stderr: Data(), exitStatus: status)
    }

    func close(host: String) async {}
    func closeAll() async {}
}

private func koan(_ path: String) -> ResolvedAddress {
    ResolvedAddress(host: "koan", path: path)
}

@Suite("AddressRecovery: the order and the outcomes")
struct AddressRecoveryTests {
    // MARK: - Exact wins

    @Test(
        "an existing path that ends in punctuation is taken exactly, with one probe and no correction",
        arguments: ["/notes/todo.", "/notes/draft,", "/notes/why?", "/notes/said;", "/notes/\"quoted\"", "/notes/end’"])
    func exactPathWinsEvenWithTrailingPunctuation(path: String) async throws {
        let host = FakeHost(files: [path])
        let recovery = try await AddressRecovery.recover(koan(path), probe: host.probe)
        #expect(recovery == .exact(koan(path)))
        #expect(recovery.isCorrected == false)
        #expect(recovery.notice == nil)
        #expect(await host.asked == [path], "one probe, and nothing else was tried")
    }

    @Test("an existing directory is exact whether or not the path ends in a slash")
    func exactDirectory() async throws {
        let host = FakeHost(directories: ["/tank/media"])
        #expect(
            try await AddressRecovery.recover(koan("/tank/media"), probe: host.probe) == .exact(koan("/tank/media")))
        #expect(try await AddressRecovery.recover(koan("/"), probe: host.probe) == .exact(koan("/")))
    }

    // MARK: - One trailing prose character

    @Test("a copied Markdown path with one accidental trailing period resolves to the file")
    func oneTrailingPeriodCorrected() async throws {
        let host = FakeHost(directories: ["/vault"], files: ["/vault/ho-05.1-walk.md"])
        let recovery = try await AddressRecovery.recover(koan("/vault/ho-05.1-walk.md."), probe: host.probe)
        #expect(
            recovery
                == .punctuationCorrected(
                    koan("/vault/ho-05.1-walk.md"), requested: "/vault/ho-05.1-walk.md.", removed: "."))
        #expect(recovery.destination == koan("/vault/ho-05.1-walk.md"))
        #expect(recovery.requestedPath == "/vault/ho-05.1-walk.md.")
        #expect(recovery.isCorrected)
        #expect(
            recovery.notice
                == "found ho-05.1-walk.md — the pasted address ended in an extra \".\"")
        #expect(await host.asked == ["/vault/ho-05.1-walk.md.", "/vault/ho-05.1-walk.md"])
    }

    @Test(
        "every character in the prose set comes off once; nothing outside it ever does",
        arguments: AddressRecovery.terminalProse.sorted() + ["-", "_", "~", "a", " "])
    func terminalProseSet(character: Character) async throws {
        let requested = "/vault/walk.md" + String(character)
        let host = FakeHost(directories: ["/vault"], files: ["/vault/walk.md"])
        let recovery = try await AddressRecovery.recover(koan(requested), probe: host.probe)
        if AddressRecovery.terminalProse.contains(character) {
            #expect(recovery == .punctuationCorrected(koan("/vault/walk.md"), requested: requested, removed: character))
        } else {
            #expect(
                recovery
                    == .ancestorRecovered(
                        koan("/vault"), requested: requested, unresolved: "walk.md" + String(character)))
            #expect(await host.asked == [requested, "/vault"], "no correction was tried for \(character)")
        }
    }

    @Test("with two trailing periods only one may come off, and the rest is an ancestor landing")
    func onlyOneCharacterRemoved() async throws {
        let host = FakeHost(directories: ["/vault"], files: ["/vault/ho-05.1-walk.md"])
        let recovery = try await AddressRecovery.recover(koan("/vault/ho-05.1-walk.md.."), probe: host.probe)
        #expect(
            recovery
                == .ancestorRecovered(
                    koan("/vault"), requested: "/vault/ho-05.1-walk.md..", unresolved: "ho-05.1-walk.md.."))
        #expect(
            await host.asked == ["/vault/ho-05.1-walk.md..", "/vault/ho-05.1-walk.md.", "/vault"],
            "exactly one character was tried, never two")
    }

    @Test("a corrected candidate that still does not exist is not taken — the ancestor is")
    func correctionMissFallsToAncestor() async throws {
        let host = FakeHost(directories: ["/vault"])
        let recovery = try await AddressRecovery.recover(koan("/vault/gone.md."), probe: host.probe)
        #expect(recovery == .ancestorRecovered(koan("/vault"), requested: "/vault/gone.md.", unresolved: "gone.md."))
        #expect(recovery.notice == "gone.md. is not here — stopped at /vault, the deepest folder that exists")
        #expect(await host.asked == ["/vault/gone.md.", "/vault/gone.md", "/vault"])
    }

    // MARK: - The longest existing directory

    @Test("recovery lands at the longest existing directory, probing each ancestor once, nearest first")
    func longestAncestorWins() async throws {
        let host = FakeHost(directories: ["/a", "/a/b"])
        let recovery = try await AddressRecovery.recover(koan("/a/b/missing/deeper/file.md"), probe: host.probe)
        #expect(
            recovery
                == .ancestorRecovered(
                    koan("/a/b"), requested: "/a/b/missing/deeper/file.md", unresolved: "missing/deeper/file.md"))
        #expect(
            await host.asked == ["/a/b/missing/deeper/file.md", "/a/b/missing/deeper", "/a/b/missing", "/a/b"],
            "one probe per component, stopping at the first directory")
    }

    @Test(
        "the unresolved suffix is the requested remainder exactly — punctuation, trailing slash and all",
        arguments: [
            ("/a/b/missing/file.md;", "missing/file.md;"),
            ("/a/b/missing/", "missing"),
            ("/a/b/missing/dir/", "missing/dir"),
            ("/a/b/x y/z.md", "x y/z.md"),
        ])
    func unresolvedSuffixPreserved(requested: String, unresolved: String) async throws {
        let host = FakeHost(directories: ["/a", "/a/b"])
        let recovery = try await AddressRecovery.recover(koan(requested), probe: host.probe)
        #expect(recovery == .ancestorRecovered(koan("/a/b"), requested: requested, unresolved: unresolved))
        #expect(recovery.notice?.contains(unresolved) == true, "the notice shows what was not found")
    }

    @Test("an ancestor that is a file is not a landing — the walk continues to its directory")
    func fileAncestorIsNotADirectory() async throws {
        let host = FakeHost(directories: ["/a", "/a/b"], files: ["/a/b/file.txt"])
        let recovery = try await AddressRecovery.recover(koan("/a/b/file.txt/extra"), probe: host.probe)
        #expect(
            recovery == .ancestorRecovered(koan("/a/b"), requested: "/a/b/file.txt/extra", unresolved: "file.txt/extra")
        )
    }

    @Test(
        "a walk that reaches only / fails, and the failure names the host and path",
        arguments: ["/nowhere/x", "/nowhere", "/nowhere/deep/er.md."])
    func rootIsNotRecovery(requested: String) async throws {
        let host = FakeHost(directories: ["/tank"])
        await #expect(throws: AddressRecoveryError.notFound(koan(requested))) {
            try await AddressRecovery.recover(koan(requested), probe: host.probe)
        }
        let asked = await host.asked
        #expect(!asked.contains("/"), "/ is never even asked about: \(asked)")
        #expect(
            AddressRecoveryError.notFound(koan(requested)).description
                == "no such path on koan: \(requested) — nothing above it exists but /")
    }

    // MARK: - The host is the grammar's host

    @Test("every outcome keeps the requested host and its current-pane mark")
    func hostIsNeverChanged() async throws {
        let host = FakeHost(directories: ["/a"], files: ["/a/f"])
        let current = ResolvedAddress(host: "koan", path: "/a/f.", usesCurrentHost: true)
        let corrected = try await AddressRecovery.recover(current, probe: host.probe)
        #expect(corrected.destination == ResolvedAddress(host: "koan", path: "/a/f", usesCurrentHost: true))
        let deep = ResolvedAddress(host: "koan", path: "/a/x/y", usesCurrentHost: true)
        let recovered = try await AddressRecovery.recover(deep, probe: host.probe)
        #expect(recovered.destination == ResolvedAddress(host: "koan", path: "/a", usesCurrentHost: true))
        let local = ResolvedAddress(host: PalanaCore.localHostName, path: "/a/x")
        let localRecovery = try await AddressRecovery.recover(local, probe: host.probe)
        #expect(localRecovery.destination.host == PalanaCore.localHostName)
        #expect(AddressRecoveryError.notFound(local).description.hasPrefix("no such path on this Mac:"))
    }

    @Test("a host that cannot be asked is a lookup failure at the first probe — nothing else is tried")
    func lookupFailureIsTyped() async throws {
        let host = FakeHost(directories: ["/tank"], failure: HostDown())
        let address = koan("/tank/media")
        await #expect(throws: AddressRecoveryError.lookupFailed(address, reason: HostDown().description)) {
            try await AddressRecovery.recover(address, probe: host.probe)
        }
        #expect(await host.asked == ["/tank/media"])
        #expect(
            AddressRecoveryError.lookupFailed(address, reason: "no route").description
                == "could not look up /tank/media on koan: no route")
    }

    // MARK: - The wire shape

    @Test(
        "the probe command carries shell text as a quoted literal — nothing is evaluated",
        arguments: [
            "/tank/$(id)", "/tank/$HOME", "/tank/a;b", "/tank/a|b", "/tank/a\\b", "/tank/My Folder", "/tank/`id`",
        ])
    func probeCommandQuotesShellText(path: String) {
        let command = Listing.presenceCommand(for: path)
        let quoted = "'" + path + "'"
        #expect(
            command
                == "if test -d \(quoted); then echo directory; elif test -e \(quoted); then echo file; else echo absent; fi"
        )
    }

    @Test("a shell-inert path rides bare, as the listing's does")
    func probeCommandBarePath() {
        #expect(
            Listing.presenceCommand(for: "/tank/media")
                == "if test -d /tank/media; then echo directory; elif test -e /tank/media; then echo file; else echo absent; fi"
        )
    }

    @Test("the probe's three words parse, and anything else is no answer")
    func probeAnswerParses() {
        #expect(Listing.presenceAnswer("directory\n") == .directory)
        #expect(Listing.presenceAnswer("file\n") == .file)
        #expect(Listing.presenceAnswer("absent") == .absent)
        #expect(Listing.presenceAnswer("") == nil)
        #expect(Listing.presenceAnswer("sh: test: not found") == nil)
    }

    @Test("the listing's probe is one round trip on the named host, typed on failure")
    func listingPresence() async throws {
        let command = Listing.presenceCommand(for: "/tank")
        let answers: [String: (String, Int32)] = [command: ("directory\n", 0)]
        let door = ScriptedDoor(answers: answers)
        let listing = Listing(conduit: door)
        #expect(try await listing.presence(on: "koan", path: "/tank") == .directory)
        #expect(await door.hosts == ["koan"])
        let garbled = Listing(conduit: ScriptedDoor(answers: [command: ("sh: test: not found\n", 0)]))
        await #expect(throws: ListingError.malformedListing) { try await garbled.presence(on: "koan", path: "/tank") }
        let failed = Listing(conduit: ScriptedDoor(answers: [command: ("", 127)]))
        await #expect(throws: ListingError.listingFailed(exitStatus: 127, stderr: "")) {
            try await failed.presence(on: "koan", path: "/tank")
        }
    }

    // MARK: - Path arithmetic

    @Test("the parent walk and the remainder are plain POSIX arithmetic")
    func pathArithmetic() {
        #expect(AddressRecovery.parent(of: "/a/b/c") == "/a/b")
        #expect(AddressRecovery.parent(of: "/a/b/c//") == "/a/b")
        #expect(AddressRecovery.parent(of: "/a") == "/")
        #expect(AddressRecovery.parent(of: "/") == "/")
        #expect(AddressRecovery.remainder(of: "/a/b/c/d", below: "/a/b") == "c/d")
        #expect(AddressRecovery.remainder(of: "/a/b/c/", below: "/a/b") == "c")
        #expect(
            AddressRecovery.remainder(of: "/a/b", below: "/x") == "/a/b", "an ancestor that is not one is left whole")
    }
}
