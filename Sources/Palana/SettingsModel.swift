// Settings persistence and ssh config host visibility.
// The model serves two surfaces over one truth: the in-window
// SettingsCard and the Apple Settings scene. Config writes stay here —
// one transaction: the file must still be the bytes the operator saw, a
// versioned backup of those exact bytes lands first, then an atomic
// replace, then one hosts reload via `onConfigChanged`. A config that
// cannot be read refuses every edit and says so.

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
    var askBeforeSendingBack: Bool
    var confirmDestroyTyped: Bool

    enum CodingKeys: String, CodingKey {
        case rsyncFlags
        case excludeDSStore
        case excludeAppleDouble
        case askBeforeSendingBack
        case confirmDestroyTyped
    }

    // Custom decoder — missing keys in old settings.json read their default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rsyncFlags = try container.decode(String.self, forKey: .rsyncFlags)
        excludeDSStore =
            (try? container.decodeIfPresent(Bool.self, forKey: .excludeDSStore)) ?? false
        excludeAppleDouble =
            (try? container.decodeIfPresent(Bool.self, forKey: .excludeAppleDouble)) ?? false
        // The key changed name when the default flipped (save is save,
        // 2026-07-10) — old files carry autoSendRoundTrips, which is
        // deliberately ignored so everyone lands on the new default.
        askBeforeSendingBack =
            (try? container.decodeIfPresent(Bool.self, forKey: .askBeforeSendingBack)) ?? false
        // Missing key reads TRUE — the typed confirmation is the default.
        confirmDestroyTyped =
            (try? container.decodeIfPresent(Bool.self, forKey: .confirmDestroyTyped)) ?? true
    }

    init(
        rsyncFlags: String,
        excludeDSStore: Bool,
        excludeAppleDouble: Bool,
        askBeforeSendingBack: Bool,
        confirmDestroyTyped: Bool
    ) {
        self.rsyncFlags = rsyncFlags
        self.excludeDSStore = excludeDSStore
        self.excludeAppleDouble = excludeAppleDouble
        self.askBeforeSendingBack = askBeforeSendingBack
        self.confirmDestroyTyped = confirmDestroyTyped
    }
}

// MARK: - State shapes

/// Where the settings values stand relative to `settings.json`.
enum SettingsPersistence: Equatable {
    /// Built-in defaults; nothing has been loaded or written this session.
    case defaults
    /// The values in memory are the values on disk.
    case confirmed
    /// The values in memory could not be written — they revert at restart.
    case unsaved(reason: String)
}

/// The ssh config as the model last read it, or why it could not.
enum SSHConfigState: Equatable {
    /// Read and decoded; edits transform this document's text.
    case loaded(SSHConfigDocument)
    /// Could not be read or decoded; every edit is refused.
    case unreadable(SSHConfigReadError)
}

/// What a config transaction did.
enum SSHConfigTransaction: Equatable {
    /// The file was replaced and `onConfigChanged` fired.
    case written
    /// The transform had nothing to change; nothing was written.
    case unchanged
    /// Nothing was written, for the named reason.
    case refused(String)
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

    /// When true, every round-trip upload waits for the operator's Enter.
    ///
    /// Off by default — save is save: a saved edit goes back to the server
    /// with one transcript line. A conflict (the remote file changed since
    /// the fetch) always asks, regardless of this setting. Persisted to
    /// `settings.json` on every assignment.
    var askBeforeSendingBack: Bool = false {
        didSet { persist() }
    }

    /// When true, zfs destroy's gather demands the word `destroy` typed
    /// into the field before the plan composes.
    ///
    /// On by default — the most destructive verb reads your intent in
    /// letters, not in a second Enter. Persisted to `settings.json` on
    /// every assignment.
    var confirmDestroyTyped: Bool = true {
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

    /// Whether the settings values shown are the values on disk.
    ///
    /// `.unsaved` means the interface reflects a change that will revert
    /// at restart — the card shows the reason through `includedFileNotice`.
    private(set) var settingsPersistence: SettingsPersistence = .defaults

    /// The one-line notice the card renders under the host list.
    ///
    /// A transient notice — a hide toggle that targeted an alias declared
    /// in an included file, or a refused write — takes precedence; it is
    /// cleared after a successful write or when the card closes. Behind
    /// it stand the diagnostics that hold as long as their cause does: an
    /// unreadable config, aliases the parser refused, settings that could
    /// not be saved.
    var includedFileNotice: String? {
        transientNotice ?? standingNotice
    }

    /// All top-level aliases with their hidden status.
    ///
    /// Reads `configText`; SwiftUI re-renders automatically after any
    /// `setHidden` write because `configState` is a stored `@Observable`
    /// property. The reserved `local` and tokens outside the alias grammar
    /// never appear here — `includedFileNotice` names them instead.
    var allHostEntries: [(alias: String, isHidden: Bool)] {
        let all = SSHConfigParser.hosts(in: configText)
        let hidden = SSHConfigParser.hiddenHosts(in: configText)
        return all.map { alias in (alias: alias, isHidden: hidden.contains(alias)) }
    }

    /// Called after every successful config write — the session
    /// reloads its host list.
    var onConfigChanged: @MainActor () -> Void = {}

    /// The ssh config as last read, or why it could not be.
    ///
    /// Updated by every successful write and by `refreshConfigText`.
    private(set) var configState: SSHConfigState

    /// The most recently read ssh config text; empty when unreadable.
    ///
    /// An unreadable config is not an empty one — `configReadFailure`
    /// says so, `allHostEntries` is empty, and every edit is refused.
    /// SwiftUI views that read `allHostEntries` observe this transitively.
    var configText: String {
        if case .loaded(let document) = configState { return document.text }
        return ""
    }

    /// Why the config could not be read, or `nil` when it was.
    var configReadFailure: String? {
        if case .unreadable(let error) = configState { return Self.describe(error) }
        return nil
    }

    /// The typed reason the config could not be read, or `nil` when it was.
    var configReadError: SSHConfigReadError? {
        if case .unreadable(let error) = configState { return error }
        return nil
    }

    /// What the pane's host menu says under its list.
    ///
    /// The typed read failure and the count of refused aliases — the same
    /// refusals `includedFileNotice` names one by one, so the menu's
    /// "see settings" lands on a card that agrees with it.
    var hostMenuDiagnostic: HostMenuDiagnostic {
        HostMenuDiagnostic(
            readFailure: configReadError,
            refusedAliasCount: SSHConfigParser.excludedAliases(in: configText).count)
    }

    private var transientNotice: String?
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
        self.configState = Self.readConfig(at: configURL)
        loadPersisted()
    }

    /// Re-reads the config file and updates `configState`.
    ///
    /// Call when the card becomes visible to pick up any external edits
    /// made since the last write — and after a refused write, so the next
    /// edit transforms what is on disk now.
    func refreshConfigText() {
        configState = Self.readConfig(at: configURL)
    }

    /// Hides or shows `alias` by inserting or removing a `# palana: hide`
    /// marker in the config file.
    ///
    /// When the AT-01 transform returns nil, nothing is written:
    /// if the alias is absent from the top-level text (it lives in an
    /// `Include`'d file), `includedFileNotice` is set. On success the
    /// transaction has preserved the previous bytes as a versioned backup,
    /// atomically replaced the config, updated `configState`, and fired
    /// `onConfigChanged`.
    func setHidden(_ shouldHide: Bool, alias: String) {
        let result = transact { text in
            shouldHide
                ? SSHConfigParser.hiding(alias: alias, in: text)
                : SSHConfigParser.showing(alias: alias, in: text)
        }
        switch result {
        case .written:
            transientNotice = nil
        case .unchanged:
            if !SSHConfigParser.hosts(in: configText).contains(alias) {
                transientNotice = "managed in an included file"
            }
        case .refused(let reason):
            transientNotice = reason
        }
    }

    /// Clears the transient notice — call when the card is dismissed.
    ///
    /// Standing diagnostics stay until their cause is gone.
    func clearNotice() {
        transientNotice = nil
    }

    // MARK: - Add and remove

    /// Appends a validated ``HostBlock`` to the config and reloads.
    ///
    /// Same transaction as ``setHidden(_:alias:)``. Returns `nil` on success,
    /// or a short reason string when no write happened:
    /// - the block fails ``HostBlock/validate()`` — the surface validates
    ///   first, but the reserved `local` is refused here too;
    /// - "alias already exists" — ``SSHConfigParser.adding`` refused a duplicate;
    /// - the config is unreadable, changed on disk, or the backup or
    ///   write failed — config untouched.
    @discardableResult
    func addHost(_ block: HostBlock) -> String? {
        let errors = block.validate()
        guard errors.isEmpty else {
            return "refused — the block is not valid: \(errors)"
        }
        let result = transact { SSHConfigParser.adding(block, to: $0) }
        switch result {
        case .written: return nil
        case .unchanged: return "alias already exists — choose a different alias or remove the existing one first"
        case .refused(let reason): return reason
        }
    }

    /// Removes the named alias from the config and reloads.
    ///
    /// An alias that shares its `Host` line with others loses only its own
    /// token; the block goes only when it was the line's last name. Same
    /// transaction as ``setHidden(_:alias:)`` and ``addHost(_:)``. Returns
    /// `nil` on success, or a short reason string when no write happened:
    /// - "alias not found" — the alias isn't in the top-level config text.
    /// - the config is unreadable, changed on disk, or the backup or
    ///   write failed — config untouched.
    @discardableResult
    func removeHost(alias: String) -> String? {
        let result = transact { SSHConfigParser.removing(alias: alias, from: $0) }
        switch result {
        case .written: return nil
        case .unchanged: return "alias not found in the top-level config"
        case .refused(let reason): return reason
        }
    }

    // MARK: - The config transaction

    /// Applies `transform` to the config as last read and replaces the file.
    ///
    /// Fails closed at every step: an unreadable config, a transform with
    /// nothing to do, a file whose bytes no longer match the ones the
    /// transform saw, a backup that did not land, a replace that did not
    /// complete — each is a refusal with nothing written. The compare and
    /// the replace run inside one `NSFileCoordinator` write, so an editor
    /// that coordinates cannot slip between them. One that does not (vim,
    /// a shell redirect) is caught by the compare when it wrote before, and
    /// beaten only by a write that lands in the instant between the compare
    /// and the rename — the platform offers no lock that closes that.
    private func transact(_ transform: (String) -> String?) -> SSHConfigTransaction {
        let baseline: SSHConfigDocument
        switch configState {
        case .loaded(let document):
            baseline = document
        case .unreadable(let error):
            return .refused("ssh config unreadable — nothing written: \(Self.describe(error))")
        }
        guard let newText = transform(baseline.text) else { return .unchanged }
        let replacement = SSHConfigDocument(text: newText, posixPermissions: baseline.posixPermissions ?? 0o600)

        var outcome = SSHConfigTransaction.refused("file coordination did not run — nothing written")
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: configURL, options: .forReplacing, error: &coordinationError
        ) { url in
            outcome = Self.replace(at: url, expecting: baseline, with: replacement)
        }
        if let coordinationError {
            return .refused("file coordination failed — nothing written: \(coordinationError.localizedDescription)")
        }
        if outcome == .written {
            configState = .loaded(replacement)
            onConfigChanged()
        }
        return outcome
    }

    /// The write half of the transaction, inside the coordinated scope.
    private static func replace(
        at url: URL, expecting baseline: SSHConfigDocument, with replacement: SSHConfigDocument
    ) -> SSHConfigTransaction {
        let current: SSHConfigDocument
        do {
            current = try SSHConfigDocument.read(at: url)
        } catch {
            return .refused("ssh config unreadable — nothing written: \(describe(error))")
        }
        guard current.bytes == baseline.bytes, current.exists == baseline.exists else {
            return .refused(
                "ssh config changed on disk since it was read — nothing written; reload hosts and try again")
        }
        // The backup must land before the config changes — a write
        // without a backup is a mutation the operator can't undo.
        if baseline.exists {
            do {
                try writeVersionedBackup(of: baseline, beside: url)
            } catch {
                return .refused("backup failed — config untouched: \(error.localizedDescription)")
            }
        }
        do {
            try atomicallyReplace(url, with: replacement)
        } catch {
            return .refused("write failed — config untouched: \(error.localizedDescription)")
        }
        return .written
    }

    /// Writes `document.bytes` to a fresh `<config>.palana-backup.<stamp>`
    /// beside the config — never over an earlier backup.
    private static func writeVersionedBackup(of document: SSHConfigDocument, beside url: URL) throws {
        let stamp = backupStampFormatter.string(from: Date())
        let base = url.lastPathComponent + ".palana-backup." + stamp
        let directory = url.deletingLastPathComponent()
        for attempt in 0..<1000 {
            let name = attempt == 0 ? base : "\(base)-\(attempt)"
            let backupURL = directory.appendingPathComponent(name)
            do {
                try document.bytes.write(to: backupURL, options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: document.posixPermissions ?? 0o600], ofItemAtPath: backupURL.path)
            return
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Writes `document` to a temporary file beside `url`, gives it the
    /// config's mode, and renames it into place — one atomic step.
    private static func atomicallyReplace(_ url: URL, with document: SSHConfigDocument) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).palana-\(UUID().uuidString).tmp")
        try document.bytes.write(to: temporary, options: .withoutOverwriting)
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: document.posixPermissions ?? 0o600], ofItemAtPath: temporary.path)
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static let backupStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    // MARK: - Diagnostics

    private static func readConfig(at url: URL) -> SSHConfigState {
        do {
            return .loaded(try SSHConfigDocument.read(at: url))
        } catch {
            return .unreadable(error)
        }
    }

    private static func describe(_ error: SSHConfigReadError) -> String {
        switch error {
        case .unreadable(let path, let reason): "\(path): \(reason)"
        case .notUTF8(let path): "\(path) is not UTF-8 text"
        }
    }

    private var standingNotice: String? {
        var lines: [String] = []
        if let configReadFailure {
            lines.append("ssh config unreadable — hosts and edits unavailable: \(configReadFailure)")
        }
        for excluded in SSHConfigParser.excludedAliases(in: configText) {
            switch excluded.reason {
            case .reserved:
                lines.append(
                    "Host \(excluded.token) is reserved for this Mac and is ignored — rename it in the config")
            case .outsideGrammar:
                lines.append("Host \(excluded.token) is not listed — aliases use \(SSHConfigParser.aliasGrammar)")
            }
        }
        if case .unsaved(let reason) = settingsPersistence {
            lines.append("settings not saved — the values shown revert at restart: \(reason)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: settingsURL) else { return }
        let stored: SettingsStored
        do {
            stored = try JSONDecoder().decode(SettingsStored.self, from: data)
        } catch {
            settingsPersistence = .unsaved(
                reason: "settings.json could not be read, showing defaults: \(error.localizedDescription)")
            return
        }
        // didSet fires on each assignment but the resulting persist()
        // calls are harmless round-trips — the same values go straight
        // back to disk.
        rsyncFlags = stored.rsyncFlags
        excludeDSStore = stored.excludeDSStore
        excludeAppleDouble = stored.excludeAppleDouble
        askBeforeSendingBack = stored.askBeforeSendingBack
        confirmDestroyTyped = stored.confirmDestroyTyped
    }

    private func persist() {
        let stored = SettingsStored(
            rsyncFlags: rsyncFlags,
            excludeDSStore: excludeDSStore,
            excludeAppleDouble: excludeAppleDouble,
            askBeforeSendingBack: askBeforeSendingBack,
            confirmDestroyTyped: confirmDestroyTyped)
        do {
            let data = try JSONEncoder().encode(stored)
            let dir = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: settingsURL, options: .atomic)
            settingsPersistence = .confirmed
        } catch {
            settingsPersistence = .unsaved(reason: error.localizedDescription)
        }
    }
}
