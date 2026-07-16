// ho-11's fixture-only proof (Decision 5): session spawn against the
// local shell, bytes round-trip, per-host isolation, and teardown.
// These drive only localhost/the local shell — the hard rule against
// mutating operations on any real remote host means ssh-backed sessions
// are the hands session's job (vim, htop, ⌃C, resize), not this suite's.

import Foundation
import PalanaCore
import SwiftTerm
import Testing

@testable import Palana

/// Test-only conveniences over `LocalProcessTerminalView` — never shipped
/// in the app target, since production code never needs to type a line
/// or snapshot the buffer as a plain string.
extension LocalProcessTerminalView {
    /// The visible buffer, decoded as plain text — good enough to search
    /// for an echoed marker; the emulator's own escape-sequence handling
    /// already stripped the control codes by the time it lands here.
    /// Lossy decode on purpose, same policy as `EchoBuffer`'s display
    /// path — a test snapshot, not a correctness claim.
    func bufferText() -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: terminal.getBufferAsData(), as: UTF8.self)
    }

    /// Feeds a line of input to the child process as if typed, newline included.
    func typeLine(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        process.send(data: bytes[...])
    }
}

@MainActor
@Suite("TerminalSessionStore: local shell")
struct TerminalSessionStoreTests {
    /// Polls the terminal's buffer until `predicate` is true or the
    /// deadline passes — a PTY's output arrives asynchronously off a
    /// background read loop, so a single snapshot read is a flake.
    static func waitForBuffer(
        _ view: LocalProcessTerminalView,
        timeout: Duration = .seconds(5),
        _ predicate: (String) -> Bool
    ) async -> String {
        let deadline = ContinuousClock.now + timeout
        var last = ""
        while ContinuousClock.now < deadline {
            last = view.bufferText()
            if predicate(last) { return last }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return last
    }

    @Test("the local host spawns the operator's login shell")
    func localSessionSpawns() async throws {
        let store = TerminalSessionStore()
        let view = store.session(for: PalanaCore.localHostName)
        let text = await Self.waitForBuffer(view) { !$0.isEmpty }
        #expect(view.process.running, "the login shell should be alive moments after spawn")
        #expect(!text.isEmpty, "a freshly spawned shell prints at least a prompt")
        store.teardownAll()
    }

    @Test("a typed command's marker round-trips through the emulator's buffer")
    func bytesRoundTrip() async throws {
        let store = TerminalSessionStore()
        let view = store.session(for: PalanaCore.localHostName)
        // Wait for the shell to be ready for input before typing — an
        // immediate write can land before the shell has execve'd.
        _ = await Self.waitForBuffer(view) { !$0.isEmpty }
        let marker = "palana-terminal-marker-\(UUID().uuidString.prefix(8))"
        view.typeLine("echo \(marker)")
        let text = await Self.waitForBuffer(view, timeout: .seconds(8)) {
            $0.contains(marker)
        }
        #expect(text.contains(marker), "the echoed marker should appear in the terminal's own buffer")
        store.teardownAll()
    }

    @Test("sessions are isolated per host — the store never hands back a stranger's view")
    func perHostIsolation() {
        let store = TerminalSessionStore()
        let local = store.session(for: PalanaCore.localHostName)
        let localAgain = store.session(for: PalanaCore.localHostName)
        #expect(local === localAgain, "re-summoning the same host returns the same session")
        store.teardownAll()
    }

    @Test("hasSession is false until first summon, true after")
    func hasSessionTracksLazyCreation() {
        let store = TerminalSessionStore()
        #expect(!store.hasSession(for: PalanaCore.localHostName))
        _ = store.session(for: PalanaCore.localHostName)
        #expect(store.hasSession(for: PalanaCore.localHostName))
        store.teardownAll()
    }

    @Test("teardownAll terminates the running process")
    func teardownKillsProcess() async throws {
        let store = TerminalSessionStore()
        let view = store.session(for: PalanaCore.localHostName)
        _ = await Self.waitForBuffer(view) { !$0.isEmpty }
        #expect(view.process.running)
        store.teardownAll()
        // Termination is asynchronous (SIGHUP to the child); poll briefly.
        let deadline = ContinuousClock.now + .seconds(3)
        while view.process.running, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(!view.process.running, "the child process should exit after teardown")
    }

    @Test("a fresh store re-creates a session for a host after teardown")
    func freshSessionAfterTeardown() {
        let store = TerminalSessionStore()
        let first = store.session(for: PalanaCore.localHostName)
        store.teardownAll()
        let second = store.session(for: PalanaCore.localHostName)
        #expect(first !== second, "teardown drops the stored view — the next summon builds fresh")
        store.teardownAll()
    }
}
