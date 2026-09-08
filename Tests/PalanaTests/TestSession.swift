// TestSession — a whole PalanaSession over a throwaway world. The ssh
// config, the settings, the workbench snapshot, the favorites, the column
// visibility, the Field's cache, and the run record all live in one temp
// directory this rig makes and its caller removes; the only remote door
// is a RecordingConduit that answers what the test scripted and nothing
// else. Nothing built here reads the operator's ~/.ssh/config or
// Application Support, and nothing can reach a real host.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// A session whose every file lives in one temp directory and whose one
/// remote door records what it is asked.
@MainActor
struct TestSession {
    /// What stands where the ssh config should be.
    enum Config {
        /// A readable config with this text.
        case text(String)
        /// No file at all — the session treats it as an empty config.
        case absent
        /// A directory where the file should be — the read fails, the path exists.
        case unreadable
    }

    /// The one remote alias the default config names.
    static let host = "koan"
    /// The default config — one alias, nothing hidden.
    static let defaultConfig = "Host koan\n    HostName 192.0.2.1\n"

    /// The rig's world — remove it with ``tearDown()``.
    let directory: URL
    /// Where the ssh config stands (or fails to).
    let configURL: URL
    /// Where `persist()` writes the workbench and `start()` reads it.
    let sessionURL: URL
    /// The recording door the session's engine, field, and workbench share.
    let conduit: RecordingConduit
    /// The session under test.
    let session: PalanaSession

    /// A session over a fresh world.
    init(config: Config = .text(Self.defaultConfig), answers: [String: RecordingConduit.Answer] = [:]) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-session-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let state = directory.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config")
        switch config {
        case .text(let text):
            try Data(text.utf8).write(to: configURL)
        case .absent:
            break
        case .unreadable:
            try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: false)
        }
        let conduit = RecordingConduit(answers: answers)
        let sessionURL = state.appendingPathComponent("session.json")
        self.directory = directory
        self.configURL = configURL
        self.sessionURL = sessionURL
        self.conduit = conduit
        self.session = PalanaSession(
            sshConfigURL: configURL,
            configuration: SSHConfiguration(extraOptions: ["-F", configURL.path]),
            remote: conduit,
            settingsURL: state.appendingPathComponent("settings.json"),
            sessionURL: sessionURL,
            favoritesURL: state.appendingPathComponent("favorites.json"),
            columnsURL: state.appendingPathComponent("columns.json"),
            fieldCache: FieldCache(url: state.appendingPathComponent("field-cache.json")),
            operationLog: OperationLog(url: state.appendingPathComponent("operations.log")))
    }

    /// A fresh subdirectory inside the rig's world — somewhere a pane can
    /// point on this Mac without leaving the sandbox.
    func makeDirectory(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Rewrites the ssh config — an external edit, as the operator would make one.
    func writeConfig(_ text: String) throws {
        try Data(text.utf8).write(to: configURL)
    }

    /// Removes the world — call from a `defer` or a teardown block.
    nonisolated func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}
