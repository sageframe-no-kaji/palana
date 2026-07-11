// The natural-exit path — the operator types `exit` and the child ends
// on its own, no terminate() call. The hands session found a dead
// session left in the table: keystrokes kept writing into a closed
// (recyclable) descriptor and the app died silently. These tests pin
// the fix: the store notices the death, drops the session, fires the
// end signal, and a re-summon starts fresh.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class ShellNaturalExitTests: XCTestCase {
    /// Typing `exit` ends the session: dropped from the store, signal fired.
    func testChildExitDropsTheSessionAndSignals() async throws {
        let store = TerminalSessionStore()
        var endedHosts: [String] = []
        store.onSessionEnded = { endedHosts.append($0) }

        let view = store.session(for: PalanaCore.localHostName)
        // Let the shell come up before speaking to it.
        try await Task.sleep(for: .milliseconds(800))
        view.send(txt: "exit\n")

        // The exit lands asynchronously — poll up to ~5s for the drop.
        for _ in 0..<50 where store.hasSession(for: PalanaCore.localHostName) {
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertFalse(
            store.hasSession(for: PalanaCore.localHostName),
            "a session whose child ended must leave the store")
        XCTAssertEqual(endedHosts, [PalanaCore.localHostName])
    }

    /// A summon after the death starts a fresh session, not the corpse.
    func testResummonAfterExitSpawnsFresh() async throws {
        let store = TerminalSessionStore()
        let first = store.session(for: PalanaCore.localHostName)
        try await Task.sleep(for: .milliseconds(800))
        first.send(txt: "exit\n")
        for _ in 0..<50 where store.hasSession(for: PalanaCore.localHostName) {
            try await Task.sleep(for: .milliseconds(100))
        }

        let second = store.session(for: PalanaCore.localHostName)
        XCTAssertFalse(first === second, "the dead view must not be reissued")
        store.teardownAll()
    }
}
