// FavoritesNumberingTests — ⌘1–⌘9 reach the first nine favorites in the
// panel's display order. The number follows the list the operator sees,
// counts collapsed groups, and never caps how many favorites exist.

import Foundation
import Testing

@testable import PalanaCore

private func fav(host: String, path: String, scope: FavoriteScope = .host) -> Favorite {
    Favorite(host: host, path: path, scope: scope)
}

@Suite("FavoritesOutline numbering")
struct FavoritesNumberingTests {
    @Test("numbers follow display order — global first, then hosts by first appearance")
    func displayOrder() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "zencat", path: "/etc"),
            fav(host: "koan", path: "/srv", scope: .global),
            fav(host: "koan", path: "/home"),
        ]
        let numbered = FavoritesOutline.numbered(from: favs)
        #expect(numbered.map(\.id) == ["koan:/srv", "koan:/tank", "koan:/home", "zencat:/etc"])
    }

    @Test("only the first nine favorites carry a number")
    func capsAtNine() {
        let favs = (1...12).map { fav(host: "koan", path: "/d\($0)") }
        let numbered = FavoritesOutline.numbered(from: favs)
        #expect(numbered.count == FavoritesOutline.numberedCount)
        #expect(numbered.last?.path == "/d9")
    }

    @Test("a number names a favorite, and nothing outside 1…9 or past the end")
    func favoriteForNumber() {
        let favs = [fav(host: "koan", path: "/a"), fav(host: "koan", path: "/b")]
        #expect(FavoritesOutline.favorite(number: 1, in: favs)?.path == "/a")
        #expect(FavoritesOutline.favorite(number: 2, in: favs)?.path == "/b")
        #expect(FavoritesOutline.favorite(number: 3, in: favs) == nil)
        #expect(FavoritesOutline.favorite(number: 0, in: favs) == nil)
        #expect(FavoritesOutline.favorite(number: -1, in: favs) == nil)
    }

    @Test("the numbers map keys each numbered favorite's id to its number")
    func numbersMap() {
        let favs = (1...10).map { fav(host: "koan", path: "/d\($0)") }
        let numbers = FavoritesOutline.numbers(from: favs)
        #expect(numbers.count == 9)
        #expect(numbers["koan:/d1"] == 1)
        #expect(numbers["koan:/d9"] == 9)
        #expect(numbers["koan:/d10"] == nil)
    }

    @Test("a duplicated id keeps its first number instead of trapping")
    func duplicateIDs() {
        let favs = [fav(host: "koan", path: "/a"), fav(host: "koan", path: "/a")]
        #expect(FavoritesOutline.numbers(from: favs)["koan:/a"] == 1)
    }

    @Test("cmd-1 through cmd-9 name a number; every other token does not")
    func chordTokens() {
        for digit in 1...9 {
            #expect(FavoritesOutline.number(forChord: "cmd-\(digit)") == digit)
        }
        for token in ["cmd-0", "cmd-+1", "cmd-10", "cmd-shift-1", "ctrl-1", "1", "cmd-", "cmd-a"] {
            #expect(FavoritesOutline.number(forChord: token) == nil, "\(token)")
        }
    }
}
