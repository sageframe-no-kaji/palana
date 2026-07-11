// PalanaSession+Shell — ho-11's interactive terminal: entering and
// leaving shell mode, the key-monitor stand-down while the shell holds
// the panel, and the failure law that pulls the transcript back over an
// open shell. Extracted from PalanaSession.swift to keep that file
// within the line-length budget, matching the +ZFS and +DragDrop
// convention.

import AppKit
import PalanaCore

extension PalanaSession {
    /// Wires the store's end-of-session signal — called once from init.
    ///
    /// A shell that ends on its own (`exit`, a dropped connection) leaves
    /// shell mode if it was showing and says so in the transcript. The
    /// store has already dropped the dead session; the next `t` starts
    /// fresh.
    func wireShellLifecycle() {
        terminalSessions.onSessionEnded = { [weak self] host in
            guard let self else { return }
            if shellMode, shellHost == host {
                exitShellMode()
            }
            operation.note("shell on \(host) ended — t starts a new one")
        }
    }

    /// `t` while the terminal strip holds focus — summons the panel if
    /// needed and swaps the transcript for the focused pane's live shell.
    ///
    /// No-op with no pane pointed anywhere: a shell needs a host. Switching
    /// the focused pane afterward switches which host's session shows
    /// (`shellHost` tracks the pointing live), so this only needs to arm
    /// the mode once.
    func enterShellMode() {
        guard focusedPane.state.host != nil else {
            operation.appendToolError("point a pane at a host first")
            return
        }
        if !operation.panelShowing { operation.showPanel() }
        shellMode = true
    }

    /// ⌘Esc — leaves shell mode.
    ///
    /// The session underneath keeps running; only the panel's view
    /// changes back to the transcript. The panel itself stays open
    /// (Esc's ordinary hide is a separate keystroke).
    func exitShellMode() {
        shellMode = false
    }

    /// The host whose session the panel shows in shell mode.
    ///
    /// The focused pane's host, live. Nil when no pane is pointed.
    var shellHost: String? {
        focusedPane.state.host
    }

    /// Forces the transcript back over an open shell on enactment failure.
    ///
    /// ho-11's failure law holds regardless of mode. Called from the
    /// `OperationModel.onFinished`-adjacent failure paths via the
    /// session, since the model has no reach into `shellMode`.
    func resurfaceTranscriptOnFailure() {
        shellMode = false
    }

    /// The stand-down: while the shell holds the panel, every key belongs
    /// to the PTY except ⌘-chords and ⌘Esc (ho-9.7's law — ⌘Q, ⌘comma,
    /// the menus keep working).
    ///
    /// Esc itself is NOT caught here — it must reach SwiftTerm's keyDown
    /// unmolested, vim needs it. Returning false lets AppKit's normal
    /// responder chain carry the event to the terminal view, which is
    /// the key first responder while shell mode shows.
    func handleShellModeKey(_ event: NSEvent) -> Bool {
        guard let token = Grammar.token(for: event) else { return false }
        if token == "cmd-esc" {
            exitShellMode()
            return true
        }
        return token.hasPrefix("cmd-") && handleGlobalChord(token)
    }
}
