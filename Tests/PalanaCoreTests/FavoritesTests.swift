// The favorites engine battery — value types, path normalization,
// Codable round-trips, scope raw-value pinning, and the store's
// silent-fail / atomic-save contract.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Favorites")
struct FavoritesTests {
    // MARK: - Helpers

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-favorites-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    // MARK: - Path normalization

    @Test("a trailing slash is stripped — /tank/media/ stores as /tank/media")
    func trailingSlashStripped() {
        let fav = Favorite(host: "koan", path: "/tank/media/")
        #expect(fav.path == "/tank/media")
    }

    @Test("the root path / keeps its slash")
    func rootPathUnchanged() {
        let fav = Favorite(host: "koan", path: "/")
        #expect(fav.path == "/")
    }

    @Test("a path with no trailing slash is stored unchanged")
    func noTrailingSlashUnchanged() {
        let fav = Favorite(host: "koan", path: "/tank/media")
        #expect(fav.path == "/tank/media")
    }

    @Test("id reflects the normalized path")
    func idReflectsNormalizedPath() {
        let fav = Favorite(host: "koan", path: "/tank/media/")
        #expect(fav.id == "koan:/tank/media")
    }

    @Test("root-path id is host:/")
    func rootPathId() {
        let fav = Favorite(host: PalanaCore.localHostName, path: "/")
        #expect(fav.id == "local:/")
    }

    // MARK: - FavoriteScope raw values

    @Test("FavoriteScope.host raw value is exactly \"host\"")
    func scopeHostRawValue() throws {
        let data = Data("\"host\"".utf8)
        let scope = try JSONDecoder().decode(FavoriteScope.self, from: data)
        #expect(scope == .host)
    }

    @Test("FavoriteScope.global raw value is exactly \"global\"")
    func scopeGlobalRawValue() throws {
        let data = Data("\"global\"".utf8)
        let scope = try JSONDecoder().decode(FavoriteScope.self, from: data)
        #expect(scope == .global)
    }

    @Test("FavoriteScope encodes to its raw string")
    func scopeEncodes() throws {
        let hostJSON = try JSONEncoder().encode(FavoriteScope.host)
        #expect(String(data: hostJSON, encoding: .utf8) == "\"host\"")

        let globalJSON = try JSONEncoder().encode(FavoriteScope.global)
        #expect(String(data: globalJSON, encoding: .utf8) == "\"global\"")
    }

    // MARK: - Codable round-trip

    @Test("a [Favorite] round-trips through JSON — both scopes, nil and non-nil labels")
    func arrayRoundTrip() throws {
        let favorites: [Favorite] = [
            Favorite(host: "koan", path: "/tank/media", scope: .host, label: "media pool"),
            Favorite(host: "jodo", path: "/rpool", scope: .global, label: nil),
            Favorite(host: PalanaCore.localHostName, path: "/Users/atm/projects", scope: .host),
            Favorite(host: "zencat", path: "/etc", scope: .global, label: "config"),
        ]
        let data = try JSONEncoder().encode(favorites)
        let decoded = try JSONDecoder().decode([Favorite].self, from: data)
        #expect(decoded == favorites)
    }

    @Test("a favorite with a nil label round-trips with label absent")
    func nilLabelRoundTrip() throws {
        let fav = Favorite(host: "koan", path: "/tank", scope: .host, label: nil)
        let data = try JSONEncoder().encode(fav)
        let decoded = try JSONDecoder().decode(Favorite.self, from: data)
        #expect(decoded == fav)
        #expect(decoded.label == nil)
    }

    @Test("a favorite with a non-nil label round-trips with label preserved")
    func nonNilLabelRoundTrip() throws {
        let fav = Favorite(host: "koan", path: "/tank", scope: .global, label: "tank")
        let data = try JSONEncoder().encode(fav)
        let decoded = try JSONDecoder().decode(Favorite.self, from: data)
        #expect(decoded == fav)
        #expect(decoded.label == "tank")
    }

    // MARK: - FavoritesStore: save / load contract

    @Test("save then load returns an equal array")
    func saveThenLoad() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let favorites: [Favorite] = [
            Favorite(host: "koan", path: "/tank/media", scope: .host),
            Favorite(host: "jodo", path: "/", scope: .global, label: "root"),
        ]
        try FavoritesStore.save(favorites, to: url)
        #expect(FavoritesStore.load(from: url) == favorites)
    }

    @Test("load from a non-existent URL returns nil")
    func loadAbsentReturnsNil() {
        #expect(FavoritesStore.load(from: makeTempURL()) == nil)
    }

    @Test("load from a URL with garbage bytes returns nil — silent-fail, no throw")
    func loadCorruptReturnsNil() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: url)
        #expect(FavoritesStore.load(from: url) == nil)
    }

    @Test("save creates the intermediate directory when absent")
    func saveCreatesDirectory() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        try FavoritesStore.save([], to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("save produces human-readable pretty-printed JSON")
    func savePrettyPrinted() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FavoritesStore.save([Favorite(host: "koan", path: "/tank")], to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\n"), "pretty-printed, per the data model's promise")
        #expect(text.contains("\"host\""), "host key appears in the output")
    }

    @Test("the default URL lands under Application Support/palana")
    func defaultLocation() {
        let url = FavoritesStore.defaultURL()
        #expect(url.lastPathComponent == "favorites.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "palana")
    }
}
