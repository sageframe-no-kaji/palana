// FavoritesOutlineTests — a full battery for FavoritesOutline.groups(from:collapsed:).
// Every rule in the spec is exercised against the real public API, not a copy.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Helpers

private func fav(host: String, path: String, scope: FavoriteScope = .host) -> Favorite {
    Favorite(host: host, path: path, scope: scope)
}

// MARK: - FavoritesOutlineTests

@Suite("FavoritesOutline")
struct FavoritesOutlineTests {
    // MARK: Empty input

    @Test("empty input produces no groups")
    func emptyInput() {
        let groups = FavoritesOutline.groups(from: [], collapsed: [])
        #expect(groups.isEmpty)
    }

    // MARK: Global group ordering

    @Test("global group appears first when global favorites exist")
    func globalGroupFirst() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "koan", path: "/tank/media"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(groups.count == 2)
        #expect(groups[0].isGlobal)
        #expect(groups[0].key == "global")
        #expect(!groups[1].isGlobal)
    }

    @Test("global group absent when no global favorites")
    func globalGroupAbsent() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "zencat", path: "/etc"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(!groups.contains { $0.isGlobal })
    }

    // MARK: Global group content

    @Test("global group title is 'Global'")
    func globalGroupTitle() {
        let favs = [fav(host: "koan", path: "/", scope: .global)]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(groups[0].title == "Global")
    }

    @Test("global group contains only global-scoped favorites")
    func globalGroupContainsOnlyGlobals() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "koan", path: "/home"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        let globalGroup = groups.first { $0.isGlobal }
        #expect(globalGroup?.favorites.count == 1)
        #expect(globalGroup?.favorites.first?.path == "/tank")
    }

    @Test("a global favorite does NOT appear in its host's group")
    func globalFavoriteNotInHostGroup() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "koan", path: "/home"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        let hostGroup = groups.first { $0.key == "koan" }
        let paths = hostGroup?.favorites.map(\.path) ?? []
        #expect(!paths.contains("/tank"))
        #expect(paths.contains("/home"))
    }

    // MARK: Per-host groups

    @Test("per-host groups appear in first-appearance order")
    func perHostFirstAppearanceOrder() {
        let favs: [Favorite] = [
            fav(host: "zencat", path: "/etc"),
            fav(host: "koan", path: "/tank"),
            fav(host: "mandala", path: "/data"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        let keys = groups.map(\.key)
        #expect(keys == ["zencat", "koan", "mandala"])
    }

    @Test("host-bound favorites appear under their host's group")
    func hostBoundFavoritesUnderHost() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "koan", path: "/tank/media"),
            fav(host: "zencat", path: "/etc"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        let koanGroup = groups.first { $0.key == "koan" }
        #expect(koanGroup?.favorites.count == 2)
        let zenGroup = groups.first { $0.key == "zencat" }
        #expect(zenGroup?.favorites.count == 1)
    }

    @Test("host-bound favorites insertion order is preserved within a group")
    func insertionOrderPreserved() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/z"),
            fav(host: "koan", path: "/a"),
            fav(host: "koan", path: "/m"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        let paths = groups.first?.favorites.map(\.path) ?? []
        #expect(paths == ["/z", "/a", "/m"])
    }

    // MARK: Collapsed / expanded state

    @Test("group is expanded when its key is not in collapsed set")
    func groupExpandedByDefault() {
        let favs = [fav(host: "koan", path: "/")]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(groups.first?.expanded == true)
    }

    @Test("group is closed when its key is in collapsed set")
    func groupClosedWhenCollapsed() {
        let favs = [fav(host: "koan", path: "/")]
        let groups = FavoritesOutline.groups(from: favs, collapsed: ["koan"])
        #expect(groups.first?.expanded == false)
    }

    @Test("collapsed applies to global group by key 'global'")
    func globalGroupCollapsed() {
        let favs = [fav(host: "koan", path: "/", scope: .global)]
        let groups = FavoritesOutline.groups(from: favs, collapsed: ["global"])
        #expect(groups.first?.expanded == false)
    }

    @Test("collapsed set may include only some groups")
    func partialCollapse() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/", scope: .global),
            fav(host: "zencat", path: "/etc"),
            fav(host: "mandala", path: "/data"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: ["global", "zencat"])
        let globalGroup = groups.first { $0.key == "global" }
        let zenGroup = groups.first { $0.key == "zencat" }
        let mandalaGroup = groups.first { $0.key == "mandala" }
        #expect(globalGroup?.expanded == false)
        #expect(zenGroup?.expanded == false)
        #expect(mandalaGroup?.expanded == true)
    }

    // MARK: Group identity

    @Test("group id equals key")
    func groupIdEqualsKey() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/", scope: .global),
            fav(host: "koan", path: "/tank"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(groups[0].id == groups[0].key)
        #expect(groups[1].id == groups[1].key)
    }

    // MARK: Mixed scopes

    @Test("mixed global and host-bound favorites produce correct groups")
    func mixedScopes() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "zencat", path: "/etc"),
            fav(host: "koan", path: "/home"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        // Global first, then hosts in first-appearance order.
        #expect(groups[0].key == "global")
        #expect(groups[1].key == "zencat")
        #expect(groups[2].key == "koan")
    }

    // MARK: Only-global favorites

    @Test("only global favorites — one global group, no host groups")
    func onlyGlobalFavorites() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "zencat", path: "/etc", scope: .global),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(groups.count == 1)
        #expect(groups[0].isGlobal)
        #expect(groups[0].favorites.count == 2)
    }

    // MARK: Only-host favorites

    @Test("only host-bound favorites — no global group")
    func onlyHostFavorites() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "zencat", path: "/etc"),
        ]
        let groups = FavoritesOutline.groups(from: favs, collapsed: [])
        #expect(!groups.contains { $0.isGlobal })
        #expect(groups.count == 2)
    }
}

// MARK: - FavoritesOutlineFlatRowsTests

@Suite("FavoritesOutline.flatRows")
struct FavoritesOutlineFlatRowsTests {
    // MARK: Empty input

    @Test("empty favorites produce no rows")
    func emptyInput() {
        let rows = FavoritesOutline.flatRows(from: [], collapsed: [])
        #expect(rows.isEmpty)
    }

    // MARK: Row structure

    @Test("header row appears for each group")
    func headerRowsPresent() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "zencat", path: "/etc"),
        ]
        let rows = FavoritesOutline.flatRows(from: favs, collapsed: [])
        let headerCount = rows.filter {
            if case .header = $0 { return true }
            return false
        }.count
        #expect(headerCount == 2)
    }

    @Test("favorite rows appear under their group when expanded")
    func favoriteRowsUnderGroup() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "koan", path: "/home"),
        ]
        let rows = FavoritesOutline.flatRows(from: favs, collapsed: [])
        // Expect: header for koan, then two favorites.
        #expect(rows.count == 3)
        if case .header(let key) = rows[0] { #expect(key == "koan") }
        if case .favorite(let fav1) = rows[1] { #expect(fav1.path == "/tank") }
        if case .favorite(let fav2) = rows[2] { #expect(fav2.path == "/home") }
    }

    @Test("favorites are hidden under a collapsed group")
    func favoritesHiddenWhenCollapsed() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank"),
            fav(host: "koan", path: "/home"),
        ]
        let rows = FavoritesOutline.flatRows(from: favs, collapsed: ["koan"])
        // Only the header survives; favorites are tucked away.
        #expect(rows.count == 1)
        if case .header(let key) = rows[0] { #expect(key == "koan") }
    }

    @Test("global header appears first when global favorites exist")
    func globalHeaderFirst() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "koan", path: "/home"),
        ]
        let rows = FavoritesOutline.flatRows(from: favs, collapsed: [])
        if case .header(let key) = rows[0] { #expect(key == "global") }
    }

    // MARK: cursorID

    @Test("header cursorID is 'hdr:<key>'")
    func headerCursorID() {
        let row = FavoritesOutline.Row.header(groupKey: "koan")
        #expect(row.cursorID == "hdr:koan")
    }

    @Test("favorite cursorID is 'fav:<host>:<path>'")
    func favoriteCursorID() {
        let entry = fav(host: "koan", path: "/tank")
        let row = FavoritesOutline.Row.favorite(entry)
        #expect(row.cursorID == "fav:koan:/tank")
    }

    @Test("global group header cursorID is 'hdr:global'")
    func globalHeaderCursorID() {
        let row = FavoritesOutline.Row.header(groupKey: "global")
        #expect(row.cursorID == "hdr:global")
    }

    // MARK: Mixed

    @Test("mixed scopes produce correct row ordering")
    func mixedScopesRows() {
        let favs: [Favorite] = [
            fav(host: "koan", path: "/tank", scope: .global),
            fav(host: "zencat", path: "/etc"),
        ]
        let rows = FavoritesOutline.flatRows(from: favs, collapsed: [])
        // global header, global fav, zencat header, zencat fav
        #expect(rows.count == 4)
        if case .header(let key0) = rows[0] { #expect(key0 == "global") }
        if case .favorite(let fav1) = rows[1] { #expect(fav1.path == "/tank") }
        if case .header(let key2) = rows[2] { #expect(key2 == "zencat") }
        if case .favorite(let fav3) = rows[3] { #expect(fav3.path == "/etc") }
    }
}
