// Settings persistence and ssh config host visibility.
// The model serves two surfaces over one truth: the in-window
// SettingsCard and the Apple Settings scene. Config writes stay here —
// one backup, one atomic replace, one hosts reload via `onConfigChanged`.

import Foundation
import PalanaCore

// MARK: - Stored (file-private persistence shape)

/// The on-disk representation of persisted settings.
///
/// Declared at file scope to avoid a two-level nesting with `CodingKeys`.
/// `excludeDSStore` and `excludeAppleDouble` are decoded with
/// `decodeIfPresent` so that old `settings.json` files without these
/// keys read false — upgrades from pre-exclude builds are lossless.
private struct SettingsStored: Codable {
    var rsyncFlags: String
    var excludeDSStore: Bool
    var excludeAppleDouble: Bool

    enum CodingKeys: String, CodingKey {
        case rsyncFlags
        case excludeDSStore
        case excludeAppleDouble
    }

    // Custom decoder — missing keys in old settings.json read false.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rsyncFlags = try container.decode(String.self, forKey: .rsyncFlags)
        excludeDSStore =
            (try? container.decodeIfPresent(Bool.self, forKey: .excludeDSStore)) ?? false
        excludeAppleDouble =
            (try? container.decodeIfPresent(Bool.self, forKey: .excludeAppleDouble)) ?? false
    }

    init(rsyncFlags: String, excludeDSStore: Bool, excludeAppleDouble: Bool) {
        self.rsyncFlags = rsyncFlags
        self.excludeDSStore = excludeDSStore
        self.excludeAppleDouble = excludeAppleDouble
    }
}

// MARK: - SettingsModel

/// Persisted settings and host-visibility control.
///
/// `rsyncFlags`, `excludeDSStore`, and `excludeAppleDouble` survive the
/// session in `settings.json` beside `session.json`. Host visibility is
/// computed from the live config text — the config is the only registry
/// — and written as a single `# palana: hide` comment line via the
/// AT-01 transform.
@MainActor
@Observable
final class SettingsModel {
    /// Extra rsync flags appended to every rsync command (free-form field).
    ///
    /// Trimmed at use; an empty or whitespace-only string is absent.
    /// Persisted to `settings.json` on every assignment.
    var rsyncFlags: String = "" {
        didSet { persist() }
    }

    /// When true, `--exclude .DS_Store` is prepended to every rsync command.
    ///
    /// Persisted to `settings.json` on every assignment.
    var excludeDSStore: Bool = false {
        didSet { persist() }
    }

    /// When true, `--exclude '._*'` is prepended to every rsync command.
    ///
    /// Covers AppleDouble resource-fork sidecar files. Persisted to
    /// `settings.json` on every assignment.
    var excludeAppleDouble: Bool = false {
        didSet { persist() }
    }

    /// The composed rsync flags for every operation.
    ///
    /// `--exclude .DS_Store` when `excludeDSStore` is on;
    /// `--exclude '._*'` when `excludeAppleDouble` is on; then the
    /// trimmed free-form field. Nil when all three sources are empty —
    /// the caller treats nil as absent.
    var effectiveRsyncFlags: String? {
        var parts: [String] = []
        if excludeDSStore { parts.append("--exclude .DS_Store") }
        if excludeAppleDouble { parts.append("--exclude '._*'") }
        let free = rsyncFlags.trimmingCharacters(in: .whitespaces)
        if !free.isEmpty { parts.append(free) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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

    // MARK: - Add and remove

    /// Appends a validated ``HostBlock`` to the config and reloads.
    ///
    /// Mirrors the backup-then-write-then-reload path in ``setHidden(_:alias:)``.
    /// Returns `nil` on success, or a short reason string when no write happened:
    /// - "alias already exists" — ``SSHConfigParser.adding`` refused a duplicate.
    /// - "backup failed" / "write failed" — filesystem trouble; config untouched.
    ///
    /// The caller is responsible for running ``HostBlock/validate()`` before
    /// calling this — composing an invalid block is refused by the surface, not here.
    @discardableResult
    func addHost(_ block: HostBlock) -> String? {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        guard let newText = SSHConfigParser.adding(block, to: text) else {
            return "alias already exists — choose a different alias or remove the existing one first"
        }
        return commitWrite(from: text, to: newText)
    }

    /// Strips the named alias's ``Host`` block from the config and reloads.
    ///
    /// Same backup-then-write-then-reload path as ``setHidden(_:alias:)`` and
    /// ``addHost(_:)``. Returns `nil` on success, or a short reason string when
    /// no write happened:
    /// - "alias not found" — the alias isn't in the top-level config text.
    /// - "backup failed" / "write failed" — filesystem trouble; config untouched.
    @discardableResult
    func removeHost(alias: String) -> String? {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        guard let newText = SSHConfigParser.removing(alias: alias, from: text) else {
            return "alias not found in the top-level config"
        }
        return commitWrite(from: text, to: newText)
    }

    /// Backs up, writes atomically, updates ``configText``, and fires ``onConfigChanged``.
    ///
    /// Returns `nil` on success or a short reason string on failure so the surface can
    /// surface it — config is untouched on any error.
    private func commitWrite(from original: String, to newText: String) -> String? {
        let backupURL = configURL.appendingPathExtension("palana-backup")
        do {
            try original.write(to: backupURL, atomically: false, encoding: .utf8)
        } catch {
            return "backup failed — config untouched: \(error.localizedDescription)"
        }
        do {
            try newText.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            return "write failed: \(error.localizedDescription)"
        }
        configText = newText
        onConfigChanged()
        return nil
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let stored = try? JSONDecoder().decode(SettingsStored.self, from: data)
        else { return }
        // didSet fires on each assignment but the resulting persist()
        // calls are harmless round-trips — the same values go straight
        // back to disk.
        rsyncFlags = stored.rsyncFlags
        excludeDSStore = stored.excludeDSStore
        excludeAppleDouble = stored.excludeAppleDouble
    }

    private func persist() {
        let stored = SettingsStored(
            rsyncFlags: rsyncFlags,
            excludeDSStore: excludeDSStore,
            excludeAppleDouble: excludeAppleDouble)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let dir = settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: settingsURL, options: .atomic)
    }
}
