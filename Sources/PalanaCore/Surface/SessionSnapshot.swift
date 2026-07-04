// The session snapshot — the workbench as it was left. Pane hosts,
// paths, sort, hidden toggles, and which pane holds focus, in one
// human-readable JSON file. Entries are never persisted: the panes
// re-point and re-list from live truth, because the hosts are the
// system of record and this file is a memory of the last visit.

import Foundation

/// Where the panes were left, for the next open.
public struct SessionSnapshot: Codable, Sendable, Equatable {
    /// Which pane holds focus.
    public enum Side: String, Codable, Sendable {
        /// The left pane.
        case left
        /// The right pane.
        case right
    }

    /// One pane's remembered pointing — no entries, no cursor.
    public struct Pane: Codable, Sendable, Equatable {
        /// The host the pane pointed at. nil when it pointed nowhere.
        public var host: String?
        /// The directory path on that host.
        public var path: String
        /// The sort order in force.
        public var sort: PaneState.Sort
        /// Whether dotfiles were showing.
        public var showHidden: Bool

        /// A remembered pointing.
        public init(
            host: String? = nil,
            path: String = "/",
            sort: PaneState.Sort = .byName,
            showHidden: Bool = false
        ) {
            self.host = host
            self.path = path
            self.sort = sort
            self.showHidden = showHidden
        }

        /// The rememberable part of a live pane.
        public init(of state: PaneState) {
            self.init(
                host: state.host,
                path: state.path,
                sort: state.sort,
                showHidden: state.showHidden)
        }
    }

    /// The left pane's pointing.
    public var left: Pane
    /// The right pane's pointing.
    public var right: Pane
    /// The focused side.
    public var focused: Side

    /// A snapshot of both panes and the focus.
    public init(left: Pane = Pane(), right: Pane = Pane(), focused: Side = .left) {
        self.left = left
        self.right = right
        self.focused = focused
    }
}

/// Reads and writes the session file.
public enum SessionStore {
    /// The canonical location — `~/Library/Application Support/palana/session.json`.
    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("palana", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    /// Loads a snapshot, or nil when the file is absent or corrupt.
    ///
    /// A session is never worth crashing over — an unreadable file
    /// means a fresh workbench, and the next save rewrites it.
    public static func load(from url: URL) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    /// Writes a snapshot, creating the directory, atomically.
    public static func save(_ snapshot: SessionSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
