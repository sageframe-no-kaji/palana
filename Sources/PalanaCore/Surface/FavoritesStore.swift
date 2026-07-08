// The favorites store — reads and writes favorites.json beside
// session.json and settings.json in Application Support. Missing or
// corrupt reads as nil, never a throw. Writes are atomic.

import Foundation

/// Reads and writes the favorites file.
///
/// Mirrors `SessionStore` exactly: the same App Support path idiom,
/// the same silent-fail load, the same atomic pretty-printed save.
public enum FavoritesStore {
    /// The canonical location — `~/Library/Application Support/palana/favorites.json`.
    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("palana", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    /// Loads the favorites list, or nil when the file is absent or corrupt.
    ///
    /// A favorites file is never worth crashing over — a missing or
    /// unreadable file means an empty list, and the next save rewrites it.
    public static func load(from url: URL) -> [Favorite]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Favorite].self, from: data)
    }

    /// Writes the favorites list, creating the directory, atomically.
    ///
    /// - Parameters:
    ///   - favorites: The list to persist.
    ///   - url: The destination; the parent directory is created if absent.
    /// - Throws: Any `Error` from directory creation or the atomic file write.
    public static func save(_ favorites: [Favorite], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(favorites).write(to: url, options: .atomic)
    }
}
