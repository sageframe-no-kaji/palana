// FavoritesReorderTests — the drag's half of the favorites order. A move
// stays inside one group: a cross-group target is refused, every other
// group keeps its slots, and the panel's section order cannot shift under
// a drag. ⌥↑/⌥↓ ride the same core move, one place at a time.

import Foundation
import Testing

@testable import PalanaCore

private func fav(host: String, path: String, scope: FavoriteScope = .host) -> Favorite {
    Favorite(host: host, path: path, scope: scope)
}

private func ids(_ list: FavoritesList) -> [String] {
    list.all.map(\.id)
}

@Suite("FavoritesList: move")
struct FavoritesReorderTests {
    private func koanList() -> FavoritesList {
        FavoritesList([
            fav(host: "koan", path: "/a"),
            fav(host: "koan", path: "/b"),
            fav(host: "koan", path: "/c"),
        ])
    }

    @Test("a favorite moves before another in its own group")
    func moveBefore() {
        var list = koanList()
        list.move(id: "koan:/c", before: "koan:/a")
        #expect(ids(list) == ["koan:/c", "koan:/a", "koan:/b"])
    }

    @Test("a nil target sends the favorite to the group's end")
    func moveToEnd() {
        var list = koanList()
        list.move(id: "koan:/a", before: nil)
        #expect(ids(list) == ["koan:/b", "koan:/c", "koan:/a"])
    }

    @Test("a move onto itself, or of an unknown id, changes nothing")
    func inertMoves() {
        var list = koanList()
        list.move(id: "koan:/b", before: "koan:/b")
        list.move(id: "koan:/missing", before: "koan:/a")
        #expect(ids(list) == ["koan:/a", "koan:/b", "koan:/c"])
    }

    @Test("a target in another group is refused")
    func crossGroupRefused() {
        var list = FavoritesList([
            fav(host: "koan", path: "/a"),
            fav(host: "zencat", path: "/x"),
            fav(host: "koan", path: "/b", scope: .global),
        ])
        list.move(id: "koan:/a", before: "zencat:/x")
        list.move(id: "koan:/a", before: "koan:/b")
        #expect(ids(list) == ["koan:/a", "zencat:/x", "koan:/b"], "scope and host both gate the move")
    }

    @Test("other groups keep their slots, so the panel's sections do not move")
    func groupOrderHolds() {
        var list = FavoritesList([
            fav(host: "koan", path: "/a"),
            fav(host: "zencat", path: "/x"),
            fav(host: "koan", path: "/b"),
            fav(host: "zencat", path: "/y"),
        ])
        list.move(id: "koan:/b", before: "koan:/a")

        #expect(ids(list) == ["koan:/b", "zencat:/x", "koan:/a", "zencat:/y"])
        let groups = FavoritesOutline.groups(from: list.all, collapsed: [])
        #expect(groups.map(\.key) == ["koan", "zencat"], "koan still leads")
        #expect(groups[0].favorites.map(\.path) == ["/b", "/a"])
        #expect(groups[1].favorites.map(\.path) == ["/x", "/y"], "the other group is untouched")
    }

    @Test("⌥↑ and ⌥↓ walk one place and stop at the group's ends")
    func moveByOffset() {
        var list = koanList()
        list.move(id: "koan:/c", by: -1)
        #expect(ids(list) == ["koan:/a", "koan:/c", "koan:/b"])

        list.move(id: "koan:/c", by: 1)
        #expect(ids(list) == ["koan:/a", "koan:/b", "koan:/c"])

        list.move(id: "koan:/a", by: -1)
        #expect(ids(list) == ["koan:/a", "koan:/b", "koan:/c"], "the first cannot rise")

        list.move(id: "koan:/c", by: 1)
        #expect(ids(list) == ["koan:/a", "koan:/b", "koan:/c"], "the last cannot fall")

        list.move(id: "koan:/a", by: 0)
        #expect(ids(list) == ["koan:/a", "koan:/b", "koan:/c"], "a zero offset is inert")
    }

    @Test("an offset past the end lands at the boundary")
    func offsetClamps() {
        var list = koanList()
        list.move(id: "koan:/a", by: 9)
        #expect(ids(list) == ["koan:/b", "koan:/c", "koan:/a"])

        list.move(id: "koan:/a", by: -9)
        #expect(ids(list) == ["koan:/a", "koan:/b", "koan:/c"])
    }

    @Test("the numbers follow the new order")
    func numbersFollow() {
        var list = koanList()
        list.move(id: "koan:/c", before: "koan:/a")
        #expect(FavoritesOutline.favorite(number: 1, in: list.all)?.path == "/c")
    }
}
