// Settings persistence and ssh config host visibility.
// The model serves two surfaces over one truth: the in-window
// SettingsCard and the Apple Settings scene. Config writes stay here —
// one backup, one atomic replace, one hosts reload via `onConfigChanged`.

import Foundation
import PalanaCore

/// Persisted settings and host-visibility control.
///
/// `rsyncFlags` survives the session in `settings.json` beside
/// `session.json`. Host visibility is computed from the live config
/// text — the config is the only registry — and written as a single
/// `# palana: hide` comment line via the AT-01 transform.
@MainActor
@Observable
final class SettingsModel {
    /// Extra rsync flags appended to every rsync command.
    ///
    /// Trimmed at use; an empty or whitespace-only string is absent.
    /// Persisted to `settings.json` on every assignment.
    var rsyncFlags: String = "" {
        didSet { persist() }
    }

    /// A one-line notice shown when a hide toggle targets an alias
    /// declared inside an included file and nothing is written.
    ///
    /// Cleared after a successful write or when the card closes.
    private(set) var includedFileNotice: String?

    /// All top-level aliases with their hidden status.
    ///
    /// Reads `configText`; SwiftUI re-renders automatically after any
    /// `setHidden` write because `configText` is a stored `@Observable`
    /// property.
    var allHostEntries: [(alias: String, isHidden: Bool)] {
        let all = SSHConfigParser.hosts(in: configText)
        let hidden = SSHConfigParser.hiddenHosts(in: configText)
        return all.map { alias in (alias: alias, isHidden: hidden.contains(alias)) }
    }

    /// Called after every successful config write — the session
    /// reloads its host list.
    var onConfigChanged: @MainActor () -> Void = {}

    /// The most recently read ssh config text.
    ///
    /// Updated by `setHidden` after every write and by
    /// `refreshConfigText`. SwiftUI views that read `allHostEntries`
    /// observe this property transitively.
    private(set) var configText: String = ""

    private let configURL: URL
    private let settingsURL: URL

    private struct Stored: Codable {
        var rsyncFlags: String
    }

    /// Initialises from the ssh config and the settings file URLs.
    ///
    /// `configURL` is the same URL the session uses — respects
    /// `PALANA_SSH_CONFIG` so tests and dev launches stay off the real
    /// file. `settingsURL` lives beside `session.json`.
    init(configURL: URL, settingsURL: URL) {
        self.configURL = configURL
        self.settingsURL = settingsURL
        configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        loadPersisted()
    }

    /// Re-reads the config file and updates `configText`.
    ///
    /// Call when the card becomes visible to pick up any external edits
    /// made since the last write.
    func refreshConfigText() {
        configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
    }

    /// Hides or shows `alias` by inserting or removing a `# palana: hide`
    /// marker in the config file.
    ///
    /// When the AT-01 transform returns nil, nothing is written:
    /// if the alias is absent from the top-level text (it lives in an
    /// `Include`'d file), `includedFileNotice` is set. On success: the
    /// previous text is preserved as `<config>.palana-backup`, the
    /// config is atomically replaced, `configText` is updated, and
    /// `onConfigChanged` fires.
    func setHidden(_ shouldHide: Bool, alias: String) {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let newText =
            shouldHide
            ? SSHConfigParser.hiding(alias: alias, in: text)
            : SSHConfigParser.showing(alias: alias, in: text)
        guard let newText else {
            let topLevel = SSHConfigParser.hosts(in: text)
            if !topLevel.contains(alias) {
                includedFileNotice = "managed in an included file"
            }
            return
        }
        includedFileNotice = nil
        // The backup must land before the config changes — a write
        // without a backup is a mutation the operator can't undo.
        let backupURL = configURL.appendingPathExtension("palana-backup")
        do {
            try text.write(to: backupURL, atomically: false, encoding: .utf8)
        } catch {
            includedFileNotice = "backup failed — config untouched: \(error.localizedDescription)"
            return
        }
        do {
            try newText.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            includedFileNotice = "write failed: \(error.localizedDescription)"
            return
        }
        configText = newText
        onConfigChanged()
    }

    /// Clears the included-file notice — call when the card is dismissed.
    func clearNotice() {
        includedFileNotice = nil
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        // didSet fires here but the resulting persist() is a harmless
        // round-trip — the same value goes straight back to disk.
        rsyncFlags = stored.rsyncFlags
    }

    private func persist() {
        let stored = Stored(rsyncFlags: rsyncFlags)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let dir = settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: settingsURL, options: .atomic)
    }
}
