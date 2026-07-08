// FavoritesList — the pure favorites logic: an ordered list of favorites
// with the add / remove / toggle / promote / query operations. The truth
// lives here in the core; the app's FavoritesModel is a thin @Observable
// shell that wraps this value and persists it, the way the session wraps
// SessionSnapshot.

import Foundation

/// The favorites, held as one insertion-ordered list across both scopes.
///
/// A location is favorited at most once — every operation keys on
/// `Favorite.id` (`host:path` after normalization). Scope is a property a
/// favorite carries, flipped in place by ``setScope(id:_:)``, not a second
/// entry. This type is pure: no persistence, no observation — those belong
/// to the surface that holds it.
public struct FavoritesList: Codable, Sendable, Equatable {
    /// Every favorite, insertion-ordered, both scopes.
    public private(set) var all: [Favorite]

    /// A favorites list, empty by default.
    public init(_ all: [Favorite] = []) {
        self.all = all
    }

    // MARK: - Queries

    /// True when `host:path` appears in any scope.
    public func isFavorited(host: String, path: String) -> Bool {
        let key = Favorite(host: host, path: path).id
        return all.contains { $0.id == key }
    }

    /// Global favorites, insertion-ordered.
    public var global: [Favorite] {
        all.filter { $0.scope == .global }
    }

    /// Host-bound favorites for the given host, insertion-ordered.
    public func hostBound(for host: String) -> [Favorite] {
        all.filter { $0.scope == .host && $0.host == host }
    }

    // MARK: - Mutations

    /// Removes the location if present (any scope); adds it host-bound if absent.
    public mutating func toggle(host: String, path: String) {
        let key = Favorite(host: host, path: path).id
        if let index = all.firstIndex(where: { $0.id == key }) {
            all.remove(at: index)
        } else {
            all.append(Favorite(host: host, path: path, scope: .host))
        }
    }

    /// Adds a favorite at the given scope.
    ///
    /// A no-op when the location is already favorited — scope is not updated
    /// here; use ``setScope(id:_:)`` to promote or demote an existing favorite.
    public mutating func add(host: String, path: String, scope: FavoriteScope) {
        let key = Favorite(host: host, path: path).id
        guard !all.contains(where: { $0.id == key }) else { return }
        all.append(Favorite(host: host, path: path, scope: scope))
    }

    /// Removes the favorite with the given id.
    public mutating func remove(id: String) {
        all.removeAll { $0.id == id }
    }

    /// Promotes or demotes by flipping a favorite's scope in place.
    public mutating func setScope(id: String, _ scope: FavoriteScope) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].scope = scope
    }
}
