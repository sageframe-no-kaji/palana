// The session's world (hands session 2026-09-08). PalanaSession.init()
// used to read the operator's ~/.ssh/config and Application Support and
// open a live SSHConduit — so every test that needed a session got one
// wired to real files and real hosts, and one intermediate run sent
// probes to a homelab machine. The session now takes its world as
// parameters. These tests pin the two guards — construction runs nothing
// through the door, and no test source opens a live one — and cover the
// session behaviour that was untestable while the world was fixed: the
// host list against a readable, absent, and unreadable config, the focus
// verbs, the pane swap, and the workbench persisting inside the rig.

import Foundation
import PalanaCore
import Testing

@testable import Palana

// MARK: - Structural guards

@MainActor
@Suite("The session's world — guards")
struct SessionWorldGuardTests {
    /// Building a session runs no command through the conduit.
    ///
    /// Every read waits for `start()` or a pointing; construction only
    /// reads files.
    @Test("construction runs nothing through the conduit")
    func constructionIsSilent() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }

        #expect(rig.session.hosts.isEmpty, "the host list waits for start()")
        #expect(await rig.conduit.commands.isEmpty)
        #expect(await rig.conduit.hosts.isEmpty)
    }

    /// The rig's files all sit inside its own directory — nothing lands in
    /// the operator's Application Support.
    @Test("the rig's world is one temp directory")
    func worldIsContained() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }

        rig.session.persist()

        #expect(rig.sessionURL.path.hasPrefix(rig.directory.path))
        #expect(FileManager.default.fileExists(atPath: rig.sessionURL.path))
    }

    /// No test source under `Tests/PalanaTests` constructs the live door.
    ///
    /// The needle is split so this file passes its own scan.
    @Test("no PalanaTests source opens a live ssh door")
    func noLiveDoorInTestSources() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let needle = "SSHConduit" + "("
        let sources = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(sources.count > 10, "the scan found the test sources")

        var offenders: [String] = []
        for source in sources where try String(contentsOf: source, encoding: .utf8).contains(needle) {
            offenders.append(source.lastPathComponent)
        }

        #expect(offenders.isEmpty, "a live ssh door in a test: \(offenders.sorted())")
    }
}

// MARK: - The host list

@MainActor
@Suite("The session's host list")
struct SessionHostListTests {
    /// A readable config lists this Mac first, then every alias not hidden.
    @Test("a readable config lists this Mac and the visible aliases")
    func readableConfig() throws {
        let config = """
            Host koan
                HostName 192.0.2.1
            Host jodo
                # palana: hide
                HostName 192.0.2.2
            Host chumon
                HostName 192.0.2.3

            """
        let rig = try TestSession(config: .text(config))
        defer { rig.tearDown() }

        rig.session.reloadHosts()

        #expect(rig.session.hosts == [Engine.localHost, "koan", "chumon"])
        #expect(rig.session.settings.configReadFailure == nil)
    }

    /// An external edit shows up on the next reload — the config is the
    /// only registry.
    @Test("an edited config is re-read on reload")
    func editedConfig() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        rig.session.reloadHosts()
        #expect(rig.session.hosts == [Engine.localHost, "koan"])

        try rig.writeConfig("Host koan\nHost mandala\n    HostName 192.0.2.4\n")
        rig.session.reloadHosts()

        #expect(rig.session.hosts == [Engine.localHost, "koan", "mandala"])
    }

    /// No config file: this Mac alone, and no diagnostic — absent is empty.
    @Test("an absent config lists only this Mac, without a diagnostic")
    func absentConfig() throws {
        let rig = try TestSession(config: .absent)
        defer { rig.tearDown() }

        rig.session.reloadHosts()

        #expect(rig.session.hosts == [Engine.localHost])
        #expect(rig.session.settings.configReadFailure == nil)
    }

    /// A config that exists but cannot be read: this Mac alone, and the
    /// settings model carries the typed failure the host menu shows.
    @Test("an unreadable config lists only this Mac and exposes the diagnostic")
    func unreadableConfig() throws {
        let rig = try TestSession(config: .unreadable)
        defer { rig.tearDown() }

        rig.session.reloadHosts()

        #expect(rig.session.hosts == [Engine.localHost])
        #expect(rig.session.settings.configReadFailure?.contains(rig.configURL.path) == true)
        guard case .unreadable(let path, _) = rig.session.settings.hostMenuDiagnostic.readFailure else {
            Issue.record("expected the typed unreadable failure")
            return
        }
        #expect(path == rig.configURL.path)
    }
}

// MARK: - Focus and the pane verbs

@MainActor
@Suite("The session's focus and pane verbs")
struct SessionPaneVerbTests {
    /// Focus starts left; a click on the right pane moves it and takes the
    /// keyboard back from any terminal.
    @Test("focusPane moves the keyboard and the focused pane follows")
    func focusPane() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        #expect(session.focusedSide == .left)
        #expect(session.focusedPane === session.left)
        #expect(session.otherPane === session.right)

        session.terminalFocused = true
        session.focusPane(.right)

        #expect(session.focusedSide == .right)
        #expect(session.focusedPane === session.right)
        #expect(session.otherPane === session.left)
        #expect(!session.terminalFocused)
    }

    /// The focus persists into the workbench file inside the rig.
    @Test("persist writes the focused side to the session file")
    func persistWritesFocus() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }

        rig.session.focusPane(.right)
        rig.session.persist()

        #expect(SessionStore.load(from: rig.sessionURL)?.focused == .right)
    }

    /// Two local pointings exchange places; both panes re-read and land.
    ///
    /// Local reads never touch the wire, and the door records nothing.
    @Test("swapPanes exchanges the two pointings")
    func swapPanes() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        let first = try rig.makeDirectory("first")
        let second = try rig.makeDirectory("second")
        session.left.point(host: Engine.localHost, path: first.path)
        session.right.point(host: Engine.localHost, path: second.path)
        try await poll(message: "both panes land") {
            session.left.state.path == first.path && session.right.state.path == second.path
        }

        session.swapPanes()

        try await poll(message: "the pointings exchange") {
            session.left.state.path == second.path && session.right.state.path == first.path
        }
        #expect(session.left.state.host == Engine.localHost)
        #expect(session.right.state.host == Engine.localHost)
        #expect(await rig.conduit.commands.isEmpty, "this Mac is read without the wire")
    }

    /// One pane unpointed: nothing moves — a swap needs two hosts.
    @Test("swapPanes with an unpointed pane is inert")
    func swapNeedsTwoHosts() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        session.left.state.host = "koan"
        session.left.state.path = "/srv"

        session.swapPanes()

        #expect(session.left.state.host == "koan")
        #expect(session.left.state.path == "/srv")
        #expect(session.right.state.host == nil)
    }

    /// Mirror points one side where the other stands.
    @Test("mirror copies a pointing across without a read on the wire")
    func mirror() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        let only = try rig.makeDirectory("only")
        session.left.point(host: Engine.localHost, path: only.path)
        try await poll(message: "the left pane lands") { session.left.state.path == only.path }

        session.mirror(to: .right)

        try await poll(message: "the right pane follows") { session.right.state.path == only.path }
        #expect(session.right.state.host == Engine.localHost)
    }
}
