// The interactive terminal — one live shell per host, riding the same
// trust surface as every read and transfer. This is where ho-11's
// decisions live: the PTY is local, ssh carries it (decision 2), the
// operator's own `ssh <alias>` — the same binary, the same
// ~/.ssh/config, the same ControlMaster sockets the Conduit already
// maintains — so a session opens instantly beside a warm master.
// PalanaCore is never touched here: the Conduit's `run(on:_:)` contract
// is one command per exchange, and a PTY session is not that. The
// terminal goes THROUGH ssh beside the Conduit, not through it.

import Foundation
import PalanaCore
import SwiftTerm

/// Per-host `LocalProcessTerminalView` sessions, created lazily and kept
/// alive across mode exits — one session per host, until app quit.
///
/// The local host (`PalanaCore.localHostName`) runs the operator's own
/// login shell; every other host runs plain `ssh <alias>` with no `-F`
/// override, so the operator's real `~/.ssh/config` governs exactly as
/// it does in Terminal.app.
@MainActor
final class TerminalSessionStore {
    private var sessions: [String: LocalProcessTerminalView] = [:]

    /// The live session for `host`, creating and starting it on first summon.
    ///
    /// Later calls for the same host return the same view — the session
    /// survives mode exits, so re-summoning shows the same scrollback and
    /// the same running program.
    func session(for host: String) -> LocalProcessTerminalView {
        if let existing = sessions[host] { return existing }
        let view = LocalProcessTerminalView(frame: .zero)
        start(view, host: host)
        sessions[host] = view
        return view
    }

    /// True once a session for `host` has been summoned — the strip and
    /// the footer read this to say "same session" rather than "new".
    func hasSession(for host: String) -> Bool {
        sessions[host] != nil
    }

    /// Launches the host's process inside the view's pseudo-terminal.
    ///
    /// Local: the operator's login shell, read from `$SHELL` and falling
    /// back to `/bin/zsh`, launched with `-l` so it behaves as it would
    /// from Terminal.app. Remote: plain `ssh <alias>` — no `-F`, no
    /// extra options. The operator's own config is the only truth.
    private func start(_ view: LocalProcessTerminalView, host: String) {
        if host == PalanaCore.localHostName {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            view.startProcess(executable: shell, args: ["-l"])
        } else {
            view.startProcess(executable: "/usr/bin/ssh", args: [host])
        }
    }

    /// Tears down every session — the app-quit path only.
    ///
    /// A session mid-mode-exit is not torn down; only quitting ends it.
    func teardownAll() {
        for (_, view) in sessions {
            view.terminate()
        }
        sessions.removeAll()
    }
}
