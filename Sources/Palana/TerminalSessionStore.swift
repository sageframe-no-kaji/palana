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

/// The process a fresh terminal session launches — decided from the host,
/// the summoning pane's directory, and the app's environment, with no
/// PTY in sight so the decision can be pinned by plain tests.
///
/// Local: the operator's login shell (`$SHELL`, falling back to
/// `/bin/zsh`) launched with `-l` and the pane's directory as the
/// process's working directory. Remote: `ssh -t <alias> -- <command>`
/// where the command changes into the pane's directory and replaces
/// itself with the login shell — no `-F`, no extra options, so the
/// operator's own `~/.ssh/config` governs exactly as it does in
/// Terminal.app.
struct TerminalLaunch: Equatable, Sendable {
    /// The binary to spawn inside the pseudo-terminal.
    let executable: String
    /// Its arguments, exactly as handed to `execve`.
    let args: [String]
    /// The local process's working directory; nil leaves it wherever the
    /// app happens to be (the remote case — the directory rides inside
    /// the ssh command instead).
    let currentDirectory: String?

    /// The remote half: `cd` into the directory, then become the login shell.
    ///
    /// The directory is quoted with the engine's own armor so
    /// spaces and quotes survive the remote shell. The `sh -c` hop is
    /// what makes the `$SHELL` fallback portable — `${SHELL:-sh}` is
    /// POSIX, and a login shell that is fish would refuse it bare.
    static func remoteCommand(directory: String) -> String {
        "cd \(ShellQuote.quote(directory)) && exec sh -c 'exec \"${SHELL:-sh}\" -l'"
    }

    /// Decides the launch for `host` starting in `directory`.
    ///
    /// `environment` is the app's own — passed in rather than read so a
    /// test can pin the `$SHELL` reading without touching the process.
    static func plan(host: String, directory: String, environment: [String: String]) -> Self {
        if host == PalanaCore.localHostName {
            let shell = environment["SHELL"] ?? "/bin/zsh"
            return Self(executable: shell, args: ["-l"], currentDirectory: directory)
        }
        return Self(
            executable: "/usr/bin/ssh",
            args: ["-t", host, "--", remoteCommand(directory: directory)],
            currentDirectory: nil
        )
    }
}

/// Per-host `LocalProcessTerminalView` sessions, created lazily and kept
/// alive across mode exits — one session per host, until app quit.
///
/// The local host (`PalanaCore.localHostName`) runs the operator's own
/// login shell; every other host runs `ssh <alias>` with no `-F`
/// override, so the operator's real `~/.ssh/config` governs exactly as
/// it does in Terminal.app. Either way the session opens in the
/// directory the summoning pane stands in — see ``TerminalLaunch``.
@MainActor
final class TerminalSessionStore: NSObject {
    private var sessions: [String: LocalProcessTerminalView] = [:]

    /// The launch each live session was started with, keyed by host.
    ///
    /// Recorded once at creation and never rewritten: a re-summon from a
    /// different directory returns the existing session untouched, so
    /// the recorded launch is proof the second directory never reached
    /// a running shell.
    private(set) var launches: [String: TerminalLaunch] = [:]

    /// Fired when a session's child process ends on its own — the operator
    /// typed `exit`, the connection dropped, the shell died.
    ///
    /// The dead session is already removed when this fires; the next
    /// summon spawns fresh. The session wires this to leave shell mode
    /// and say so in the transcript. A dead session left in the panel is
    /// how the natural-exit crash happened: keystrokes kept writing into
    /// a closed (and recyclable) descriptor.
    var onSessionEnded: (String) -> Void = { _ in }

    /// The live session for `host`, creating and starting it on first
    /// summon in `directory` — the summoning pane's resolved absolute path.
    ///
    /// Later calls for the same host return the same view whatever
    /// directory they name — the session survives mode exits, so
    /// re-summoning shows the same scrollback and the same running
    /// program, and nothing is ever typed into a running shell to move
    /// it. A session whose process ENDED is removed by the termination
    /// delegate, so a summon after `exit` starts anew, in the directory
    /// the pane stands in then.
    func session(for host: String, startingIn directory: String) -> LocalProcessTerminalView {
        if let existing = sessions[host] { return existing }
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = self
        let launch = TerminalLaunch.plan(
            host: host, directory: directory, environment: ProcessInfo.processInfo.environment)
        view.startProcess(
            executable: launch.executable, args: launch.args, currentDirectory: launch.currentDirectory)
        sessions[host] = view
        launches[host] = launch
        return view
    }

    /// True once a session for `host` has been summoned — the strip and
    /// the footer read this to say "same session" rather than "new".
    func hasSession(for host: String) -> Bool {
        sessions[host] != nil
    }

    /// Tears down every session — the app-quit path only.
    ///
    /// A session mid-mode-exit is not torn down; only quitting ends it.
    func teardownAll() {
        for (_, view) in sessions {
            view.terminate()
        }
        sessions.removeAll()
        launches.removeAll()
    }
}

// MARK: - LocalProcessTerminalViewDelegate

/// The store hears its sessions' lifecycle. Only termination matters:
/// a session whose child ended must leave the table immediately, or the
/// panel keeps feeding keystrokes to a closed descriptor (the
/// natural-exit crash — a recycled fd turns that into SIGPIPE).
///
/// SwiftTerm delivers these on the main queue (`LocalProcess`'s default);
/// the protocol itself is nonisolated, so each method hops explicitly.
extension TerminalSessionStore: LocalProcessTerminalViewDelegate {
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            guard let host = sessions.first(where: { $0.value === source })?.key else { return }
            sessions.removeValue(forKey: host)
            launches.removeValue(forKey: host)
            onSessionEnded(host)
        }
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // The view manages its own PTY winsize; nothing to relay.
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // The panel's header names the host; shell titles are not surfaced.
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // OSC 7 tracking is a future nicety (point-a-pane-here); unused today.
    }
}
