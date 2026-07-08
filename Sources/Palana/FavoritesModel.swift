// FavoritesModel — the @Observable surface over FavoritesList and its store.
// The logic lives in PalanaCore's FavoritesList; this shell adds observation
// and persistence: it loads favorites.json at init and writes it back on
// every mutation with a silent-fail write, matching SettingsModel's idiom.

import Foundation
import PalanaCore

/// The live favorites list — a thin shell wrapping the core ``FavoritesList``.
///
/// `@MainActor` because SwiftUI observes it; `@Observable` so every mutation
/// invalidates the views that read it. All list logic delegates to the pure
/// core value — this type only observes and persists.
@MainActor
@Observable
final class FavoritesModel {
    private var list: FavoritesList
    private let url: URL
    /// Undo snapshots — each entry is the full `.all` list before a mutation.
    ///
    /// Capped at 25. The oldest snapshot is dropped when the cap is hit.
    private var undoStack: [[Favorite]] = []

    /// Loads from `url` (missing or corrupt reads as an empty list).
    init(url: URL = FavoritesStore.defaultURL()) {
        self.url = url
        self.list = FavoritesList(FavoritesStore.load(from: url) ?? [])
    }

    // MARK: - Queries

    /// All favorites, insertion-ordered, both scopes.
    var all: [Favorite] { list.all }

    /// True when `host:path` appears in any scope.
    func isFavorited(host: String, path: String) -> Bool {
        list.isFavorited(host: host, path: path)
    }

    /// Global favorites, insertion-ordered.
    var global: [Favorite] { list.global }

    /// Host-bound favorites for the given host, insertion-ordered.
    func hostBound(for host: String) -> [Favorite] {
        list.hostBound(for: host)
    }

    // MARK: - Mutations

    /// Removes a favorite if present (any scope); adds it host-bound if absent.
    func toggle(host: String, path: String) {
        snapshot()
        list.toggle(host: host, path: path)
        persist()
    }

    /// Adds a favorite at the given scope (a no-op if already present).
    func add(host: String, path: String, scope: FavoriteScope) {
        snapshot()
        list.add(host: host, path: path, scope: scope)
        persist()
    }

    /// Removes the favorite with the given id.
    func remove(id: String) {
        snapshot()
        list.remove(id: id)
        persist()
    }

    /// Promotes or demotes a favorite by flipping its scope in place.
    func setScope(id: String, _ scope: FavoriteScope) {
        snapshot()
        list.setScope(id: id, scope)
        persist()
    }

    // MARK: - Undo

    /// Pops the last pre-mutation snapshot and restores it.
    ///
    /// A no-op when the stack is empty.
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        list = FavoritesList(previous)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        try? FavoritesStore.save(list.all, to: url)
    }

    /// Pushes the current list state onto the undo stack, trimming to 25 entries.
    private func snapshot() {
        if undoStack.count >= 25 { undoStack.removeFirst() }
        undoStack.append(list.all)
    }
}
