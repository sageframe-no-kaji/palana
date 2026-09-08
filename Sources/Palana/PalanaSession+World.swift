// PalanaSession+World — the app's way into the session. The designated
// initializer takes the session's world as parameters (the ssh config,
// the state files, the remote door); this is the one caller that resolves
// them to the operator's machine and opens the live door. Tests never
// come through here — they build the world in a temp directory and hand
// in a recording conduit.
//
// PALANA_SSH_CONFIG points the whole stack at an alternate ssh config —
// the fixture's, during development. Unset, the operator's own
// ~/.ssh/config governs, exactly as it does in the terminal.

import Foundation
import PalanaCore

extension PalanaSession {
    /// The settings file's canonical location — beside `session.json`.
    static var defaultSettingsURL: URL {
        SessionStore.defaultURL().deletingLastPathComponent().appendingPathComponent("settings.json")
    }

    /// Builds the engine stack from the operator's ssh config, or from
    /// `PALANA_SSH_CONFIG` when the environment points elsewhere.
    ///
    /// Every file the session reads or writes resolves to the operator's
    /// own locations, and the remote door is the live ``SSHConduit`` — the
    /// one place in the process that opens it.
    convenience init() {
        let override = ProcessInfo.processInfo.environment["PALANA_SSH_CONFIG"]
        let configURL =
            override.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        let configuration = SSHConfiguration(extraOptions: override.map { ["-F", $0] } ?? [])
        self.init(
            sshConfigURL: configURL,
            configuration: configuration,
            remote: SSHConduit(configuration: configuration))
    }
}
