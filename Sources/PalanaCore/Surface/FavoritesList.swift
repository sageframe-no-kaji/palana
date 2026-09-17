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

    /// Moves a favorite to sit before `target`, or last when `target` is nil.
    ///
    /// Reordering happens **within one group only** — the favorite's own
    /// scope and host. A target in another group is refused, so a drag can
    /// never promote, demote, or change hosts; those stay with
    /// ``setScope(id:_:)``. The group's slots in `all` are rewritten in
    /// place, so every other group keeps its position and the panel's
    /// section order never moves under a drag.
    ///
    /// - Parameters:
    ///   - id: The favorite being moved.
    ///   - target: The favorite it should precede; nil sends it to the group's end.
    public mutating func move(id: String, before target: String?) {
        guard id != target, let moved = all.first(where: { $0.id == id }) else { return }
        let slots = all.indices.filter { all[$0].scope == moved.scope && all[$0].host == moved.host }
        var members = slots.map { all[$0] }
        // A target outside this group is refused — the drag lands nowhere.
        if let target, !members.contains(where: { $0.id == target }) { return }
        guard let from = members.firstIndex(where: { $0.id == id }) else { return }
        members.remove(at: from)
        let insertion = target.flatMap { id in members.firstIndex { $0.id == id } } ?? members.count
        members.insert(moved, at: insertion)
        for (slot, favorite) in zip(slots, members) {
            all[slot] = favorite
        }
    }

    /// Moves a favorite one place up (-1) or down (+1) within its own group.
    ///
    /// Clamped at the group's ends: the first favorite cannot move up, the
    /// last cannot move down. Any other offset than ±1 walks that many
    /// places and stops at the boundary.
    public mutating func move(id: String, by offset: Int) {
        guard offset != 0, let moved = all.first(where: { $0.id == id }) else { return }
        let members = all.filter { $0.scope == moved.scope && $0.host == moved.host }
        guard let from = members.firstIndex(where: { $0.id == id }) else { return }
        let destination = max(0, min(members.count - 1, from + offset))
        guard destination != from else { return }
        // Moving down lands *before* the favorite past the destination.
        let target =
            destination + 1 < members.count && destination > from
            ? members[destination + 1].id
            : (destination > from ? nil : members[destination].id)
        move(id: id, before: target)
    }

    /// Sets or clears a favorite's display label in place.
    ///
    /// The text is trimmed; nil, empty, or whitespace-only clears the label and
    /// returns the favorite to path display. No uniqueness rule — `host:path`
    /// is the identity, the label is display.
    public mutating func setLabel(id: String, label: String?) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        all[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
