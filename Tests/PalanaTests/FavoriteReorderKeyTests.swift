// FavoriteReorderKeyTests — ⌥↑ / ⌥↓ reorder the favorite under the panel's
// cursor, the keyboard's half of the drag. The panel's key router is driven
// directly with built key events; no panel window is ever opened, and the
// session's world is the rig's temp directory.

import AppKit
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Favorites panel — ⌥ reorder keys")
struct FavoriteReorderKeyTests {
    private static func optionArrow(up: Bool) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: up ? 126 : 125))
    }

    /// A rig whose favorites are three host-bound directories on one host.
    private func rigWithThree() throws -> TestSession {
        let rig = try TestSession()
        for path in ["/a", "/b", "/c"] {
            rig.session.favorites.add(host: "koan", path: path, scope: .host)
        }
        return rig
    }

    private func paths(_ rig: TestSession) -> [String] {
        rig.session.favorites.all.map(\.path)
    }

    @Test("⌥↑ lifts the favorite under the cursor one place")
    func optionUpMoves() throws {
        let rig = try rigWithThree()
        defer { rig.tearDown() }
        rig.session.favoritesPanelModel.cursor = "fav:koan:/c"

        #expect(rig.session.handleFavoritesPanelKey(try Self.optionArrow(up: true)))

        #expect(paths(rig) == ["/a", "/c", "/b"])
    }

    @Test("⌥↓ drops it one place, and the ⌘ numbers follow")
    func optionDownMoves() throws {
        let rig = try rigWithThree()
        defer { rig.tearDown() }
        rig.session.favoritesPanelModel.cursor = "fav:koan:/a"

        #expect(rig.session.handleFavoritesPanelKey(try Self.optionArrow(up: false)))

        #expect(paths(rig) == ["/b", "/a", "/c"])
        #expect(FavoritesOutline.favorite(number: 1, in: rig.session.favorites.all)?.path == "/b")
    }

    @Test("⌥↑ on a header row is consumed and moves nothing")
    func headerRowInert() throws {
        let rig = try rigWithThree()
        defer { rig.tearDown() }
        rig.session.favoritesPanelModel.cursor = "hdr:koan"

        #expect(rig.session.handleFavoritesPanelKey(try Self.optionArrow(up: true)))

        #expect(paths(rig) == ["/a", "/b", "/c"])
    }

    @Test("a move is one undo step")
    func undoRestoresOrder() throws {
        let rig = try rigWithThree()
        defer { rig.tearDown() }
        rig.session.favoritesPanelModel.cursor = "fav:koan:/c"

        #expect(rig.session.handleFavoritesPanelKey(try Self.optionArrow(up: true)))
        rig.session.favorites.undo()

        #expect(paths(rig) == ["/a", "/b", "/c"])
    }
}
