// FavoritesOutline — a pure builder that groups a flat favorites list into
// disclosure sections for the favorites column panel. No persistence, no
// observation: given favorites and a collapsed set, it returns the groups.
// The fold state lives in the app target's FavoritesPanelModel; this stays
// in core so it can be unit-tested without the app.

import Foundation

/// Pure grouping logic for the favorites column panel.
///
/// Given a flat ``FavoritesList/all`` array and a set of collapsed group keys,
/// `groups(from:collapsed:)` returns the display-ready sections in their
/// canonical order: the Global group first (when any `.global` favorites
/// exist), then one group per distinct host among the `.host`-scoped entries,
/// in first-appearance order. Empty groups are omitted.
public enum FavoritesOutline {
    // MARK: - Group

    /// One disclosure section in the favorites column.
    ///
    /// `key` is `"global"` for the cross-machine bookmark bar, or the host's
    /// ssh alias for a host-bound section. `expanded` reflects whether the
    /// section is open (`!collapsed.contains(key)`).
    public struct Group: Sendable, Equatable, Identifiable {
        /// The section's stable identity: `"global"` or a host alias.
        public let key: String

        /// The display title: `"Global"` or the host alias.
        public let title: String

        /// True for the cross-machine bookmark bar, false for host-bound sections.
        public let isGlobal: Bool

        /// The favorites in this section, insertion-ordered.
        public let favorites: [Favorite]

        /// Whether the section is open.
        ///
        /// Derived from the `collapsed` set passed to ``groups(from:collapsed:)``:
        /// `true` when `collapsed` does not contain `key`.
        public let expanded: Bool

        /// The stable identifier — equal to `key`.
        public var id: String { key }
    }

    // MARK: - Builder

    /// Builds the display-ready groups for the favorites column.
    ///
    /// Ordering:
    /// 1. The Global group — all `.global` favorites, insertion-ordered —
    ///    appears first, but **only** when at least one global favorite exists.
    /// 2. One group per distinct host among the `.host`-scoped favorites, in
    ///    first-appearance order, each carrying that host's entries in insertion
    ///    order.
    ///
    /// A group whose `key` is in `collapsed` has `expanded == false`. Empty
    /// groups (after filtering) are omitted from the result.
    ///
    /// - Parameters:
    ///   - favorites: The flat, insertion-ordered favorites list.
    ///   - collapsed: Keys of sections the operator has closed.
    /// - Returns: The non-empty groups in canonical display order.
    public static func groups(from favorites: [Favorite], collapsed: Set<String>) -> [Group] {
        var result: [Group] = []

        // Global section — first, only when non-empty.
        let globals = favorites.filter { $0.scope == .global }
        if !globals.isEmpty {
            result.append(
                Group(
                    key: "global",
                    title: "Global",
                    isGlobal: true,
                    favorites: globals,
                    expanded: !collapsed.contains("global")))
        }

        // Per-host sections — first-appearance order.
        var seenHosts: [String] = []
        for fav in favorites where fav.scope == .host {
            if !seenHosts.contains(fav.host) {
                seenHosts.append(fav.host)
            }
        }
        for host in seenHosts {
            let hostFavs = favorites.filter { $0.scope == .host && $0.host == host }
            guard !hostFavs.isEmpty else { continue }
            result.append(
                Group(
                    key: host,
                    title: host,
                    isGlobal: false,
                    favorites: hostFavs,
                    expanded: !collapsed.contains(host)))
        }

        return result
    }
}
