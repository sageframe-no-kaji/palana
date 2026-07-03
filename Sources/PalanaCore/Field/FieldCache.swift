// The field cache — memory of the last visit. One JSON file, human-
// readable, a convenience over re-derivable truth: corrupt or missing
// reads as empty, and deleting it is always safe. The Field rebuilds by
// discovering.

import Foundation

/// Loads and saves `field-cache.json`.
///
/// Not a system of record — deletable memory. No schema version: a shape
/// change reads as corrupt, corrupt reads as empty, and the next
/// discovery rewrites it.
public struct FieldCache: Sendable {
    /// Where the file lives — injectable for tests.
    public let url: URL

    /// A cache at the given location.
    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    /// `~/Library/Application Support/palana/field-cache.json`.
    public static var defaultURL: URL {
        let support =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return
            support
            .appendingPathComponent("palana")
            .appendingPathComponent("field-cache.json")
    }

    /// Reads the remembered facts — missing or corrupt is empty, by design.
    public func load() -> [String: HostFacts] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CacheFile.self, from: data))?.hosts ?? [:]
    }

    /// Writes the facts atomically — write-temp-rename via Foundation's
    /// `.atomic`, so a crash mid-write never leaves a torn file.
    public func save(_ hosts: [String: HostFacts]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(CacheFile(hosts: hosts))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// The file's shape — hosts keyed by alias.
    private struct CacheFile: Codable {
        var hosts: [String: HostFacts]
    }
}
