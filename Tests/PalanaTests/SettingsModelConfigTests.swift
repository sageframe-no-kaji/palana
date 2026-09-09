// SettingsModel's config transaction and settings persistence, against
// temporary directories only — never the operator's ~/.ssh/config. Each
// case reproduces a failure the 2026-09-06 review named: a non-UTF-8 or
// unreadable config written back as empty, an external edit overwritten
// without a word, a single backup slot, a settings write that failed in
// silence.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// A throwaway directory holding `config` and `state/settings.json`.
private struct Sandbox {
    let directory: URL

    var configURL: URL { directory.appendingPathComponent("config") }
    var settingsURL: URL { directory.appendingPathComponent("state/settings.json") }

    init(configBytes: Data?) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let configBytes { try configBytes.write(to: configURL) }
    }

    @MainActor
    func model() -> SettingsModel {
        SettingsModel(
            configURL: configURL,
            settingsURL: settingsURL
        ) { url, accessor in
            accessor(url)
            return nil
        }
    }

    func configBytes() throws -> Data { try Data(contentsOf: configURL) }

    func configText() throws -> String {
        guard let text = String(data: try configBytes(), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    /// Every `config.palana-backup.*` beside the config, oldest first.
    func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("config.palana-backup.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func mode(of url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private let original = Data(
    "Host jodo\n    HostName 192.168.1.20 \r\n\nHost chumon\n    HostName 192.168.1.21\n".utf8)

// MARK: - Config transaction

@MainActor
@Suite("SettingsModel config transaction")
struct SettingsModelConfigTransactionTests {
    @Test("a file-coordination failure refuses the write before bytes change")
    func coordinationFailureRefuses() throws {
        let sandbox = try Sandbox(configBytes: original)
        defer { sandbox.tearDown() }
        let model = SettingsModel(
            configURL: sandbox.configURL,
            settingsURL: sandbox.settingsURL
        ) { _, _ in CocoaError(.fileWriteNoPermission) as NSError }

        let reason = model.addHost(HostBlock(alias: "mandala", hostName: "192.168.1.190"))
        #expect(reason?.contains("file coordination failed") == true)
        #expect(try sandbox.configBytes() == original)
        #expect(try sandbox.backups().isEmpty)
    }

    @Test("every write lands a versioned backup of the exact prior bytes and keeps the mode")
    func versionedBackups() throws {
        let sandbox = try Sandbox(configBytes: original)
        defer { sandbox.tearDown() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sandbox.configURL.path)
        let model = sandbox.model()
        var reloads = 0
        model.onConfigChanged = { reloads += 1 }

        #expect(model.addHost(HostBlock(alias: "mandala", hostName: "192.168.1.190")) == nil)
        let afterAdd = try sandbox.configBytes()
        #expect(model.removeHost(alias: "chumon") == nil)

        let backups = try sandbox.backups()
        // A prerequisite, not an expectation: indexing an array whose
        // count expectation merely recorded an issue aborted the whole
        // suite with an index-out-of-range trap instead of reporting
        // the file-coordination failure (2026-09-08 audit).
        try #require(backups.count == 2)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(try Data(contentsOf: backups[1]) == afterAdd)
        #expect(reloads == 2)
        #expect(try sandbox.mode(of: sandbox.configURL) == 0o600)
        for backup in backups {
            #expect(try sandbox.mode(of: backup) == 0o600)
        }
        #expect(SSHConfigParser.hosts(in: try sandbox.configText()) == ["jodo", "mandala"])
        #expect(model.configText == (try sandbox.configText()))
        #expect(model.includedFileNotice == nil)
    }

    @Test("an external edit after the read refuses the write and leaves the file as edited")
    func externalEditRefused() throws {
        let sandbox = try Sandbox(configBytes: original)
        defer { sandbox.tearDown() }
        let model = sandbox.model()
        let edited = original + Data("\nHost added-by-vim\n    HostName 10.0.0.9\n".utf8)
        try edited.write(to: sandbox.configURL)

        let reason = model.addHost(HostBlock(alias: "mandala", hostName: "192.168.1.190"))
        #expect(reason?.contains("changed on disk") == true)
        #expect(try sandbox.configBytes() == edited)
        #expect(try sandbox.backups().isEmpty)

        // After a refresh the edit is the baseline and the write goes through.
        model.refreshConfigText()
        #expect(model.addHost(HostBlock(alias: "mandala", hostName: "192.168.1.190")) == nil)
        #expect(
            SSHConfigParser.hosts(in: try sandbox.configText())
                == ["jodo", "chumon", "added-by-vim", "mandala"])
        let backups = try sandbox.backups()
        try #require(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == edited)
    }

    @Test("a hide toggle after an external edit is refused and the notice says why")
    func hideRefusedAfterExternalEdit() throws {
        let sandbox = try Sandbox(configBytes: original)
        defer { sandbox.tearDown() }
        let model = sandbox.model()
        let edited = Data("Host jodo\n    HostName 10.0.0.1\n".utf8)
        try edited.write(to: sandbox.configURL)

        model.setHidden(true, alias: "jodo")
        #expect(model.includedFileNotice?.contains("changed on disk") == true)
        #expect(try sandbox.configBytes() == edited)
        #expect(try sandbox.backups().isEmpty)
    }

    @Test("a non-UTF-8 config refuses every edit and stays byte-identical")
    func notUTF8() throws {
        let bytes = Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0x6A, 0xFF, 0x0A])
        let sandbox = try Sandbox(configBytes: bytes)
        defer { sandbox.tearDown() }
        let model = sandbox.model()

        #expect(model.configReadFailure?.contains("not UTF-8") == true)
        #expect(model.includedFileNotice?.contains("unreadable") == true)
        #expect(model.configText.isEmpty)
        #expect(model.allHostEntries.isEmpty)
        #expect(model.addHost(HostBlock(alias: "mandala", hostName: "x"))?.contains("unreadable") == true)
        #expect(model.removeHost(alias: "jodo")?.contains("unreadable") == true)
        model.setHidden(true, alias: "jodo")
        #expect(model.includedFileNotice?.contains("unreadable") == true)
        #expect(try sandbox.configBytes() == bytes)
        #expect(try sandbox.backups().isEmpty)
    }

    @Test("a config that cannot be read is a diagnostic, not an empty file")
    func unreadable() throws {
        let sandbox = try Sandbox(configBytes: nil)
        defer { sandbox.tearDown() }
        // A directory where the file should be — the read fails, the path exists.
        try FileManager.default.createDirectory(at: sandbox.configURL, withIntermediateDirectories: true)
        let model = sandbox.model()

        #expect(model.configReadFailure?.contains(sandbox.configURL.path) == true)
        #expect(model.addHost(HostBlock(alias: "mandala", hostName: "x"))?.contains("unreadable") == true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: sandbox.configURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("an absent config is created by the first add, private, with no backup to take")
    func absentConfig() throws {
        let sandbox = try Sandbox(configBytes: nil)
        defer { sandbox.tearDown() }
        let model = sandbox.model()

        #expect(model.configReadFailure == nil)
        #expect(model.allHostEntries.isEmpty)
        #expect(model.addHost(HostBlock(alias: "mandala", hostName: "x")) == nil)
        #expect(try sandbox.configText() == "Host mandala\n    HostName x")
        #expect(try sandbox.backups().isEmpty)
        #expect(try sandbox.mode(of: sandbox.configURL) == 0o600)
    }

    @Test("Host local in the config is refused, named, and kept out of the entries")
    func reservedInConfig() throws {
        let bytes = Data("Host local\n    HostName 127.0.0.1\nHost jodo\n".utf8)
        let sandbox = try Sandbox(configBytes: bytes)
        defer { sandbox.tearDown() }
        let model = sandbox.model()

        #expect(model.allHostEntries.map(\.alias) == ["jodo"])
        #expect(model.includedFileNotice?.contains("Host local is reserved") == true)
        #expect(model.addHost(HostBlock(alias: "local", hostName: "x"))?.contains("aliasReserved") == true)
        #expect(model.addHost(HostBlock(alias: "-x", hostName: "x"))?.contains("aliasOutsideGrammar") == true)
        #expect(try sandbox.configBytes() == bytes)
        #expect(try sandbox.backups().isEmpty)
    }

    @Test("the host menu diagnostic carries the typed read failure and the refused count")
    func hostMenuDiagnostic() throws {
        // A directory where the file should be — the read fails, the path exists.
        let unreadable = try Sandbox(configBytes: nil)
        defer { unreadable.tearDown() }
        try FileManager.default.createDirectory(at: unreadable.configURL, withIntermediateDirectories: true)
        let failing = unreadable.model()
        guard case .unreadable(let path, _) = failing.hostMenuDiagnostic.readFailure else {
            Issue.record("expected a typed read failure, got \(String(describing: failing.configReadError))")
            return
        }
        #expect(path == unreadable.configURL.path)
        #expect(failing.hostMenuDiagnostic.refusedAliasCount == 0)

        let refused = try Sandbox(configBytes: Data("Host local\nHost -x\nHost jodo\n".utf8))
        defer { refused.tearDown() }
        let refusing = refused.model()
        #expect(refusing.hostMenuDiagnostic == HostMenuDiagnostic(readFailure: nil, refusedAliasCount: 2))

        let clean = try Sandbox(configBytes: original)
        defer { clean.tearDown() }
        #expect(clean.model().hostMenuDiagnostic == .clear)
    }

    @Test("removing one alias from a shared line through the model keeps the other")
    func sharedAliasThroughModel() throws {
        let sandbox = try Sandbox(configBytes: Data("Host jodo alt\n    HostName x\n".utf8))
        defer { sandbox.tearDown() }
        let model = sandbox.model()

        #expect(model.removeHost(alias: "alt") == nil)
        #expect(try sandbox.configText() == "Host jodo\n    HostName x\n")
        #expect(model.removeHost(alias: "alt")?.contains("not found") == true)
    }

    @Test("a hide toggle for an alias in an included file writes nothing and says so")
    func includedFileNotice() throws {
        let bytes = Data("Host jodo\nInclude other\n".utf8)
        let sandbox = try Sandbox(configBytes: bytes)
        defer { sandbox.tearDown() }
        let model = sandbox.model()

        model.setHidden(true, alias: "github")
        #expect(model.includedFileNotice == "managed in an included file")
        #expect(try sandbox.configBytes() == bytes)
        #expect(try sandbox.backups().isEmpty)
        model.clearNotice()
        #expect(model.includedFileNotice == nil)

        model.setHidden(true, alias: "jodo")
        #expect(model.includedFileNotice == nil)
        #expect(model.allHostEntries.map(\.isHidden) == [true])
        #expect(try sandbox.configText() == "Host jodo\n    # palana: hide\nInclude other\n")
    }
}

// MARK: - Settings persistence

@MainActor
@Suite("SettingsModel settings persistence")
struct SettingsModelPersistenceTests {
    @Test("a settings write that fails is visible as unsaved, with the reason")
    func writeFailureVisible() throws {
        let sandbox = try Sandbox(configBytes: nil)
        defer { sandbox.tearDown() }
        // A regular file where the settings directory should be — neither
        // the directory nor the file can be created.
        try Data().write(to: sandbox.directory.appendingPathComponent("state"))
        let model = sandbox.model()
        #expect(model.settingsPersistence == .defaults)
        #expect(model.includedFileNotice == nil)

        model.rsyncFlags = "--dry-run"
        guard case .unsaved(let reason) = model.settingsPersistence else {
            Issue.record("expected unsaved, got \(model.settingsPersistence)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(model.rsyncFlags == "--dry-run")
        #expect(model.includedFileNotice?.contains("settings not saved") == true)
        #expect(!FileManager.default.fileExists(atPath: sandbox.settingsURL.path))
    }

    @Test("a settings write that lands is confirmed and comes back on the next load")
    func writeConfirmed() throws {
        let sandbox = try Sandbox(configBytes: nil)
        defer { sandbox.tearDown() }
        let model = sandbox.model()
        model.excludeDSStore = true
        #expect(model.settingsPersistence == .confirmed)
        #expect(FileManager.default.fileExists(atPath: sandbox.settingsURL.path))

        let again = sandbox.model()
        #expect(again.excludeDSStore)
        #expect(again.settingsPersistence == .confirmed)
        #expect(again.includedFileNotice == nil)
    }

    @Test("a settings file that will not decode shows defaults and says so")
    func undecodable() throws {
        let sandbox = try Sandbox(configBytes: nil)
        defer { sandbox.tearDown() }
        try FileManager.default.createDirectory(
            at: sandbox.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: sandbox.settingsURL)
        let model = sandbox.model()
        guard case .unsaved(let reason) = model.settingsPersistence else {
            Issue.record("expected unsaved, got \(model.settingsPersistence)")
            return
        }
        #expect(reason.contains("settings.json"))
        #expect(model.confirmDestroyTyped)
        #expect(model.includedFileNotice?.contains("settings not saved") == true)
    }
}
