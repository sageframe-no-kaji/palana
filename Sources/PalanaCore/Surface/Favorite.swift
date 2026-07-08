// A favorite — a named location (host + path) the operator reaches often.
// Two scopes: host-bound favorites appear in one host's context; global
// favorites are the cross-machine bookmark bar. One store, both scopes.

import Foundation

/// A bookmarked location — a host and a path the operator reaches often.
///
/// A favorite is a concrete location, never a template. `id` is `host:path`
/// after normalization: a trailing slash on path is stripped except at root,
/// so `koan:/tank/media` and `koan:/tank/media/` are one favorite. Scope
/// is a property you flip, not a second entry.
public struct Favorite: Codable, Identifiable, Sendable, Equatable {
    /// The host's ssh alias, or `PalanaCore.localHostName` for this Mac.
    public let host: String

    /// The directory path on that host, normalized (no trailing slash except root).
    public let path: String

    /// Whether this favorite belongs to one host or to every host.
    public var scope: FavoriteScope

    /// A display name; nil means show `host:path`.
    public var label: String?

    /// The stable identity — `host:path` after normalization.
    public var id: String { "\(host):\(path)" }

    /// A bookmarked location.
    ///
    /// - Parameters:
    ///   - host: The ssh alias or `PalanaCore.localHostName`.
    ///   - path: The directory path; a trailing slash is stripped except at root.
    ///   - scope: `.host` (default) or `.global`.
    ///   - label: Optional display name; nil shows `host:path`.
    public init(host: String, path: String, scope: FavoriteScope = .host, label: String? = nil) {
        self.host = host
        self.path = Self.normalizePath(path)
        self.scope = scope
        self.label = label
    }

    /// Strips a trailing slash unless the path is exactly `/`.
    private static func normalizePath(_ path: String) -> String {
        guard path != "/" else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// The visibility scope of a favorite.
///
/// A host-bound favorite surfaces in that host's context only. A global
/// favorite is the cross-machine bookmark bar — always visible, always
/// jumpable, and re-pointing the pane's host when followed.
public enum FavoriteScope: String, Codable, Sendable {
    /// Belongs to one host; shown only in that host's context.
    case host

    /// The bookmark bar — jumpable from any host, re-pointing on the way.
    case global
}
