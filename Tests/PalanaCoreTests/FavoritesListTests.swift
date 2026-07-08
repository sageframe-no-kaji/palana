// FavoritesList battery — the pure add / remove / toggle / promote / query
// logic the app's FavoritesModel is a thin shell over. Exercising the real
// core type, not a reference copy: a bug in FavoritesList fails here.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - isFavorited

@Suite("FavoritesList: isFavorited")
struct FavoritesListIsFavoritedTests {
    @Test("isFavorited returns false for an empty list")
    func emptyList() {
        let list = FavoritesList()
        #expect(!list.isFavorited(host: "koan", path: "/tank"))
    }

    @Test("isFavorited returns true after add (host-bound)")
    func afterAddHostBound() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        #expect(list.isFavorited(host: "koan", path: "/tank"))
    }

    @Test("isFavorited returns true after add (global)")
    func afterAddGlobal() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .global)
        #expect(list.isFavorited(host: "koan", path: "/tank"))
    }

    @Test("isFavorited normalizes a trailing slash")
    func trailingSlash() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank/media", scope: .host)
        #expect(list.isFavorited(host: "koan", path: "/tank/media/"))
    }

    @Test("isFavorited returns false after remove")
    func afterRemove() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.remove(id: "koan:/tank")
        #expect(!list.isFavorited(host: "koan", path: "/tank"))
    }
}

// MARK: - toggle

@Suite("FavoritesList: toggle")
struct FavoritesListToggleTests {
    @Test("toggle adds a host-bound favorite when absent")
    func addsWhenAbsent() {
        var list = FavoritesList()
        list.toggle(host: "koan", path: "/tank")
        #expect(list.isFavorited(host: "koan", path: "/tank"))
        #expect(list.all.first?.scope == .host)
    }

    @Test("toggle removes a host-bound favorite when present")
    func removesWhenPresent() {
        var list = FavoritesList()
        list.toggle(host: "koan", path: "/tank")
        list.toggle(host: "koan", path: "/tank")
        #expect(!list.isFavorited(host: "koan", path: "/tank"))
        #expect(list.all.isEmpty)
    }

    @Test("toggle removes a global favorite — any scope")
    func removesGlobal() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .global)
        list.toggle(host: "koan", path: "/tank")
        #expect(!list.isFavorited(host: "koan", path: "/tank"))
    }

    @Test("toggle normalizes a trailing slash when removing")
    func removesNormalized() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank/media", scope: .host)
        list.toggle(host: "koan", path: "/tank/media/")
        #expect(list.all.isEmpty)
    }
}

// MARK: - add

@Suite("FavoritesList: add")
struct FavoritesListAddTests {
    @Test("add is a no-op when the location is already present")
    func noOpWhenPresent() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.add(host: "koan", path: "/tank", scope: .global)
        #expect(list.all.count == 1)
        #expect(list.all.first?.scope == .host)
    }

    @Test("add appends in insertion order")
    func insertionOrder() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.add(host: "jodo", path: "/", scope: .global)
        #expect(list.all[0].host == "koan")
        #expect(list.all[1].host == "jodo")
    }
}

// MARK: - remove

@Suite("FavoritesList: remove")
struct FavoritesListRemoveTests {
    @Test("remove by id removes only that entry")
    func byId() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.add(host: "jodo", path: "/", scope: .global)
        list.remove(id: "koan:/tank")
        #expect(list.all.count == 1)
        #expect(list.all.first?.host == "jodo")
    }

    @Test("remove with an unknown id is a no-op")
    func unknownId() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.remove(id: "koan:/does-not-exist")
        #expect(list.all.count == 1)
    }
}

// MARK: - setScope (promote / demote)

@Suite("FavoritesList: setScope")
struct FavoritesListSetScopeTests {
    @Test("setScope promotes host-bound to global")
    func promotes() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.setScope(id: "koan:/tank", .global)
        #expect(list.all.first?.scope == .global)
    }

    @Test("setScope demotes global to host-bound")
    func demotes() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .global)
        list.setScope(id: "koan:/tank", .host)
        #expect(list.all.first?.scope == .host)
    }

    @Test("setScope with an unknown id is a no-op")
    func unknownId() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.setScope(id: "missing:/x", .global)
        #expect(list.all.first?.scope == .host)
    }
}

// MARK: - Slices (global / hostBound)

@Suite("FavoritesList: slices")
struct FavoritesListSliceTests {
    @Test("global returns only global-scoped favorites")
    func globalOnly() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.add(host: "jodo", path: "/", scope: .global)
        list.add(host: PalanaCore.localHostName, path: "/Users/atm", scope: .global)
        #expect(list.global.count == 2)
        #expect(list.global.allSatisfy { $0.scope == .global })
    }

    @Test("hostBound returns only the named host's host-scoped favorites")
    func hostBoundForHost() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.add(host: "koan", path: "/var", scope: .host)
        list.add(host: "jodo", path: "/", scope: .host)
        let entries = list.hostBound(for: "koan")
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.host == "koan" })
    }

    @Test("hostBound excludes global favorites for that host")
    func hostBoundExcludesGlobal() {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .global)
        list.add(host: "koan", path: "/var", scope: .host)
        let entries = list.hostBound(for: "koan")
        #expect(entries.count == 1)
        #expect(entries.first?.path == "/var")
    }

    @Test("both slices are empty when the list is empty")
    func emptySlices() {
        let list = FavoritesList()
        #expect(list.global.isEmpty)
        #expect(list.hostBound(for: "koan").isEmpty)
    }
}

// MARK: - Codable round-trip

@Suite("FavoritesList: Codable")
struct FavoritesListCodableTests {
    @Test("a FavoritesList round-trips through JSON preserving order and scope")
    func roundTrip() throws {
        var list = FavoritesList()
        list.add(host: "koan", path: "/tank", scope: .host)
        list.add(host: "jodo", path: "/", scope: .global)
        list.setScope(id: "koan:/tank", .global)
        let data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode(FavoritesList.self, from: data)
        #expect(decoded == list)
    }
}
