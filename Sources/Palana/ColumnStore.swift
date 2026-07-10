// ColumnStore — column customization persistence for the pane table.
//
// SwiftUI's TableColumnCustomization<FileEntry> does not conform to Codable,
// so an own model persists visibility. The escape hatch named in AT-02:
// `ColumnVisibility` holds the set of hidden column IDs; widths are owned
// by the platform value and survive as long as the process lives. On relaunch
// the customization value starts at the platform default and we replay the
// hidden-column set from disk — widths reset on relaunch, which is acceptable
// per the spec's escape hatch boundary.
//
// One `ColumnStore` instance is shared across both panes so the operator's
// column choices apply everywhere — the session holds it, the panes bind to it.

import Foundation
import PalanaCore
import SwiftUI

// MARK: - Store functions

/// Reads and writes the column visibility file.
enum ColumnVisibilityStore {
    /// The canonical location — `~/Library/Application Support/palana/columns.json`.
    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("palana", isDirectory: true)
            .appendingPathComponent("columns.json")
    }

    /// Loads visibility, or nil when the file is absent or corrupt.
    static func load(from url: URL) -> ColumnVisibility? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ColumnVisibility.self, from: data)
    }

    /// Writes visibility to disk, creating the directory atomically.
    ///
    /// Silent-fail — a write error is recoverable on next save; the operator
    /// loses only column visibility changes since the last successful write.
    static func save(_ visibility: ColumnVisibility, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(visibility).write(to: url, options: .atomic)
        } catch {
            // Silent-fail: a columns file that fails to write is recoverable
            // on next save. The operator loses column visibility changes across
            // relaunches, not the session.
        }
    }
}

// MARK: - Observable column store

/// The live column customization — shared across both panes.
///
/// Holds the `TableColumnCustomization<FileEntry>` value the Table binds to.
/// On mutation the hidden-column set is extracted and persisted to `columns.json`
/// so visibility survives relaunch. Widths live only for the process lifetime
/// (the named escape hatch — ``TableColumnCustomization`` is not Codable).
@MainActor
@Observable
final class ColumnStore {
    /// The column customization value — bound directly into the Table.
    var customization: TableColumnCustomization<FileEntry>

    private let url: URL

    /// Loads from `url` (missing or corrupt reads as default visibility).
    init(url: URL = ColumnVisibilityStore.defaultURL()) {
        self.url = url
        let saved = ColumnVisibilityStore.load(from: url) ?? ColumnVisibility()
        var restored = TableColumnCustomization<FileEntry>()
        for id in saved.hiddenIDs {
            restored[visibility: .init(id)] = .hidden
        }
        self.customization = restored
    }

    // MARK: - Persistence

    /// Extracts the current hidden-column set and writes it to disk.
    ///
    /// Call this when the customization changes — on scene phase change
    /// (background / inactive) to match the session persistence idiom.
    func persist() {
        let hidden = Self.hiddenIDs(in: customization)
        ColumnVisibilityStore.save(ColumnVisibility(hiddenIDs: hidden), to: url)
    }

    // MARK: - Helpers

    /// Extracts the IDs of all hidden columns from a customization value.
    ///
    /// Iterates the known column IDs and checks each one's visibility.
    static func hiddenIDs(in customization: TableColumnCustomization<FileEntry>) -> [String] {
        PaneColumns.allIDs.filter { id in
            customization[visibility: .init(id)] == .hidden
        }
    }
}
