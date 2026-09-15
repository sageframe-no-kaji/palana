// FavoriteNumberChordTests — ⌘1–⌘9 open a numbered favorite in the focused
// pane, and ⇧⌘8 stars the current folder now that ⌘8 is a number. Panes
// point at directories inside the rig's temp world on this Mac, so nothing
// reaches the wire.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Numbered favorites — the ⌘ chords")
struct FavoriteNumberChordTests {
    /// ⌘2 reaches the second favorite in display order — Global before hosts.
    @Test("cmd-2 opens the second favorite in the focused pane")
    func opensInDisplayOrder() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        let hostBound = try rig.makeDirectory("host-bound")
        let global = try rig.makeDirectory("global")
        session.favorites.add(host: Engine.localHost, path: hostBound.path, scope: .host)
        session.favorites.add(host: Engine.localHost, path: global.path, scope: .global)

        #expect(session.handleGlobalChord("cmd-2"))

        try await poll(message: "the left pane lands on the host-bound favorite") {
            session.left.state.path == hostBound.path
        }
        #expect(session.right.state.host == nil)
        #expect(await rig.conduit.commands.isEmpty, "this Mac is read without the wire")
    }

    /// The number follows focus, not a fixed side.
    @Test("cmd-1 lands in the right pane when the right pane has focus")
    func followsFocus() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        let only = try rig.makeDirectory("only")
        session.favorites.add(host: Engine.localHost, path: only.path, scope: .host)
        session.focusPane(.right)

        #expect(session.handleGlobalChord("cmd-1"))

        try await poll(message: "the right pane lands") { session.right.state.path == only.path }
        #expect(session.left.state.host == nil)
    }

    /// An unassigned number is consumed and moves nothing.
    @Test("cmd-9 past the list's end is consumed and inert")
    func pastTheEnd() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session

        #expect(session.handleGlobalChord("cmd-9"))
        #expect(session.left.state.host == nil)
        #expect(session.right.state.host == nil)
    }

    /// ⇧⌘8 stars the focused pane's folder in both token spellings; ⌘8 no longer does.
    @Test("cmd-shift-* stars this folder, and cmd-8 is a number")
    func starMovesToShift() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        session.left.state.host = "koan"
        session.left.state.path = "/srv"

        #expect(session.handleGlobalChord("cmd-shift-*"))
        #expect(session.favorites.isFavorited(host: "koan", path: "/srv"))

        #expect(session.handleGlobalChord("cmd-shift-8"))
        #expect(!session.favorites.isFavorited(host: "koan", path: "/srv"), "a second star unstars")

        #expect(session.handleGlobalChord("cmd-8"), "⌘8 is favorite 8 now")
        #expect(session.favorites.all.isEmpty, "⌘8 stars nothing")
    }
}
