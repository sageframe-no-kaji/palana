// AddressRecoveryRoutingTests — conservative recovery from the pane's
// side. A typed address that does not exist as written may land on its
// one-character correction or on the nearest existing folder above it,
// and the pane says so in a notice that outlives the landing; one that
// nothing can recover is refused with the pane exactly where it was. The
// probe runs on the host the grammar chose — the filesystem for this Mac,
// the recording door for the remote host — and never anywhere else.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("address recovery — routed through the pane")
struct AddressRecoveryRoutingTests {
    private let host = AddressRig.host

    /// A temp directory holding `walk.md` and a file whose name ends in a
    /// period, so both the exact-wins and the corrected cases are real.
    private struct Vault {
        let root: URL
        let walk: URL
        let trailing: URL

        init() throws {
            root = try AddressRig.makeTemporaryDirectory()
            walk = root.appendingPathComponent("ho-05.1-walk.md")
            trailing = root.appendingPathComponent("draft.md.")
            try Data("walk".utf8).write(to: walk)
            try Data("draft".utf8).write(to: trailing)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Exact wins

    @Test("a local file whose name ends in a period is taken exactly and revealed, with no notice")
    func exactPunctuatedFileWins() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress(vault.trailing.path)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.host == Engine.localHost)
        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.state.cursor == Data("draft.md.".utf8), "the file itself is revealed, not draft.md")
        #expect(rig.pane.addressNotice == nil)
        #expect(rig.pane.lastError == nil)
    }

    // MARK: - One trailing prose character

    @Test("a copied Markdown path with one trailing period lands on the file and says what came off")
    func trailingPeriodCorrected() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress(vault.walk.path + ".")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.host == Engine.localHost)
        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.state.cursor == Data("ho-05.1-walk.md".utf8), "the corrected file is revealed")
        #expect(
            rig.pane.addressNotice
                == "trailing \".\" removed: \(vault.walk.path). is not there, \(vault.walk.path) is")
        #expect(rig.pane.lastError == nil)
        #expect(await rig.conduit.commands.isEmpty, "the pane's remote host was never asked")
    }

    @Test("two trailing periods are not both removed — the pane lands in the folder and names the miss")
    func onlyOnePeriodRemoved() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress(vault.walk.path + "..")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.state.selection.isEmpty, "nothing is revealed — the name as pasted is not there")
        #expect(
            rig.pane.addressNotice
                == "not found: ho-05.1-walk.md.. — landed at \(vault.root.path), the nearest folder that exists")
    }

    @Test("a corrected candidate that still does not exist is not taken — the folder is, with the miss named")
    func correctionMissLandsInFolder() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress(vault.root.path + "/gone.md,")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.addressNotice?.hasPrefix("not found: gone.md, — landed at") == true)
    }

    // MARK: - The longest existing directory

    @Test("a deep miss lands at the longest existing local folder, and the notice keeps the unresolved suffix")
    func longestLocalDirectoryRecovered() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }
        let deepest = vault.root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: deepest, withIntermediateDirectories: true)

        rig.pane.pointAddress(deepest.path + "/missing/deeper/file.md")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.host == Engine.localHost)
        #expect(rig.pane.state.path == deepest.path)
        #expect(
            rig.pane.addressNotice
                == "not found: missing/deeper/file.md — landed at \(deepest.path), the nearest folder that exists")
        #expect(await rig.conduit.commands.isEmpty)
    }

    @Test("the notice outlives its landing and clears on the next pointing")
    func noticeClearsOnNextPointing() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress(vault.root.path + "/missing")
        try await poll(message: "the pane did not land") { rig.pane.addressNotice != nil }
        #expect(rig.pane.state.path == vault.root.path)

        rig.pane.pointAddress(vault.root.path)
        try await poll(message: "the notice did not clear") { rig.pane.addressNotice == nil }
        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.status == .ready)
    }

    @Test("a miss whose only ancestor is / is refused — the pane does not move")
    func rootOnlyIsRefused() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let missing = "/nowhere-\(UUID().uuidString)/deeper/file.md."

        rig.pane.pointAddress(missing)
        try await poll(message: "the refusal never showed") { rig.pane.lastError != nil }

        #expect(rig.pane.lastError == "no such path on this Mac: \(missing) — nothing above it exists but /")
        #expect(rig.pane.state.host == host)
        #expect(rig.pane.state.path == "/srv")
        #expect(rig.pane.status == .unpointed, "no read was started")
        #expect(rig.pane.addressNotice == nil)
        #expect(rig.pane.isReading == false)
    }

    // MARK: - Clipboard wrappers reach recovery

    @Test(
        "wrapped pastes — quotes, newline, BOM, zero-width, file:// — come off first, and the trailing period after",
        arguments: [
            "\"{walk}.\"\n", "'{walk}.'", "\u{201C}{walk}.\u{201D}", "\u{FEFF}{walk}.\n", "\u{200B}{walk}.\u{200B}",
            "  {walk}.  \r\n", "file://{walk}.", "local:{walk}.",
        ])
    func wrappedPasteRecovers(template: String) async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress(template.replacingOccurrences(of: "{walk}", with: vault.walk.path))
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.host == Engine.localHost)
        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.state.cursor == Data("ho-05.1-walk.md".utf8))
        #expect(rig.pane.addressNotice?.hasPrefix("trailing \".\" removed") == true)
    }

    @Test("a mismatched outer quote is refused before any probe — no recovery rescues a parse refusal")
    func mismatchedQuoteRefused() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }

        rig.pane.pointAddress("\"" + vault.walk.path + ".")

        #expect(rig.pane.lastError == AddressParseError.unmatchedQuote.description)
        #expect(rig.pane.state.host == host)
        #expect(rig.pane.state.path == "/srv")
        #expect(rig.pane.isReading == false)
    }

    // MARK: - Hosts

    @Test("host:path recovers on that host only — every probe and the listing name it, nothing local is read")
    func namedHostRecoversOnItsHost() async throws {
        let (probeDeep, absent) = AddressRig.probe("/tank/missing/x", .absent)
        let (probeMid, absentMid) = AddressRig.probe("/tank/missing", .absent)
        let (probeTank, tank) = AddressRig.probe("/tank", .directory)
        let (listing, entries) = AddressRig.listing("/tank")
        let rig = try AddressRig(
            answers: [probeDeep: absent, probeMid: absentMid, probeTank: tank, listing: entries])
        defer { rig.tearDown() }

        rig.pane.pointAddress("koan:/tank/missing/x")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.host == host)
        #expect(rig.pane.state.path == "/tank")
        #expect(rig.pane.addressNotice == "not found: missing/x — landed at /tank, the nearest folder that exists")
        #expect(await rig.conduit.commands == [probeDeep, probeMid, probeTank, listing])
        #expect(await rig.conduit.hosts == [host, host, host, host])
    }

    @Test("a remote path that happens to exist on this Mac is never found here — the named host is the only host")
    func namedHostNeverFallsBackToLocal() async throws {
        let local = try AddressRig.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: local) }
        let components = local.path.split(separator: "/").map(String.init)
        var ancestors: [(String, RecordingConduit.Answer)] = []
        for depth in stride(from: components.count, through: 1, by: -1) {
            ancestors.append(AddressRig.probe("/" + components.prefix(depth).joined(separator: "/"), .absent))
        }
        let rig = try AddressRig(answers: AddressRig.answers(ancestors))
        defer { rig.tearDown() }

        rig.pane.pointAddress("koan:" + local.path)
        try await poll(message: "the refusal never showed") { rig.pane.lastError != nil }

        #expect(rig.pane.lastError == "no such path on koan: \(local.path) — nothing above it exists but /")
        #expect(rig.pane.state.host == nil, "the pane did not land on this Mac")
        #expect(rig.pane.status == .unpointed)
        #expect(await rig.conduit.hosts.allSatisfy { $0 == host })
    }

    @Test("a remote host that cannot be asked is a lookup failure — no other host is tried")
    func remoteLookupFailureIsRefused() async throws {
        let (probe, _) = AddressRig.probe("/tmp", .directory)
        let rig = try AddressRig(answers: [probe: .sshFailure("ssh: connect to host koan port 22: No route to host")])
        defer { rig.tearDown() }

        rig.pane.pointAddress("koan:/tmp")
        try await poll(message: "the refusal never showed") { rig.pane.lastError != nil }

        #expect(rig.pane.lastError?.hasPrefix("could not look up /tmp on koan:") == true)
        #expect(rig.pane.lastError?.contains("No route to host") == true)
        #expect(rig.pane.state.host == nil, "/tmp exists on this Mac, and the pane did not go there")
        #expect(rig.pane.status == .unpointed)
        #expect(rig.pane.isReading == false)
        #expect(await rig.conduit.commands == [probe], "one probe, then nothing")
    }

    @Test("a remote host that answers in the wrong words is a lookup failure, not a guess")
    func remoteProbeGarbageIsRefused() async throws {
        let (probe, _) = AddressRig.probe("/tank", .directory)
        let rig = try AddressRig(answers: [probe: .success("sh: test: not found\n")])
        defer { rig.tearDown() }

        rig.pane.pointAddress("koan:/tank")
        try await poll(message: "the refusal never showed") { rig.pane.lastError != nil }

        #expect(rig.pane.lastError == "could not look up /tank on koan: the listing did not parse — worth reporting")
        #expect(rig.pane.state.host == nil)
    }

    @Test("~ is expanded by the host that owns it before the probe runs — home itself is exact")
    func tildeExpandsBeforeTheProbe() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        rig.pane.pointAddress("~")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.host == Engine.localHost)
        #expect(rig.pane.state.path == home)
        #expect(rig.pane.addressNotice == nil)
        #expect(await rig.conduit.commands.isEmpty, "this Mac's home is not the remote host's business")
    }

    @Test("a miss under ~ recovers to the expanded home, and the notice names what was not there")
    func tildeMissRecoversToHome() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let missing = "nowhere-\(UUID().uuidString)/x.md"

        rig.pane.pointAddress("~/" + missing)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.path == home)
        #expect(rig.pane.addressNotice == "not found: \(missing) — landed at \(home), the nearest folder that exists")
    }

    // MARK: - No shell

    @Test("shell text in a local path is a literal name — corrected by one character, never evaluated")
    func shellTextIsLiteralLocally() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }
        let name = "$(id) `hostname` $HOME;x|y"
        try Data("literal".utf8).write(to: vault.root.appendingPathComponent(name))

        rig.pane.pointAddress(vault.root.path + "/" + name + ".")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        #expect(rig.pane.state.path == vault.root.path)
        #expect(rig.pane.state.cursor == Data(name.utf8), "the literally named file is revealed")
        #expect(rig.pane.addressNotice?.hasPrefix("trailing \".\" removed") == true)
    }

    @Test(
        "shell text in a remote path reaches the wire as a single-quoted literal in the probe",
        arguments: ["/tank/$(id)", "/tank/$HOME", "/tank/a;b", "/tank/a|b", "/tank/`id`", "/tank/a\\\\b"])
    func shellTextIsQuotedRemotely(path: String) async throws {
        let resolved = try TypedAddress.resolve("koan:" + path, currentHost: nil)
        let (probe, presence) = AddressRig.probe(resolved.path, .directory)
        let (listing, entries) = AddressRig.listing(resolved.path)
        let rig = try AddressRig(answers: [probe: presence, listing: entries])
        defer { rig.tearDown() }

        rig.pane.pointAddress("koan:" + path)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        let commands = await rig.conduit.commands
        #expect(commands == [probe, listing])
        #expect(commands.first?.contains("'" + resolved.path + "'") == true, "quoted, not bare: \(commands)")
    }

    // MARK: - One authority

    @Test("the sheet's preview and the pane's pointing come from the same recovery")
    func sheetAndPaneRecoverAlike() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let vault = try Vault()
        defer { vault.remove() }
        let requested = vault.walk.path + "."
        let resolved = try TypedAddress.resolve(requested, currentHost: host)

        let preview = await rig.pane.recover(resolved)
        rig.pane.pointAddress(requested)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }

        guard case .success(let recovery) = preview else {
            Issue.record("the preview refused: \(preview)")
            return
        }
        #expect(GoToBar.previewLine(for: recovery) == "this Mac · \(vault.walk.path) — \(recovery.notice ?? "")")
        #expect(rig.pane.addressNotice == recovery.notice)
        #expect(rig.pane.state.path == PaneModel.parentPath(of: recovery.destination.path))
    }
}
