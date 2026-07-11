// PalanaSession+Shell — ho-11's interactive terminal: the shell's view
// and keyboard as two separate facts, the ⌘` keyboard toggle, the
// plan-owns-the-panel rule, and the key-monitor stand-down while the
// shell holds the keyboard. Extracted from PalanaSession.swift to keep
// that file within the line-length budget, matching the +ZFS and
// +DragDrop convention.

import AppKit
import PalanaCore

extension PalanaSession {
    /// Wires the store's end-of-session signal — called once from init.
    ///
    /// A shell that ends on its own (`exit`, a dropped connection) leaves
    /// shell mode if it was showing and says so in the transcript. The
    /// store has already dropped the dead session; the next ⌘` starts
    /// fresh.
    func wireShellLifecycle() {
        terminalSessions.onSessionEnded = { [weak self] host in
            guard let self else { return }
            if shellMode, shellHost == host {
                exitShellMode()
            }
            operation.note("shell on \(host) ended — ⌘` starts a new one")
        }
    }

    /// Whether the panel currently SHOWS the shell.
    ///
    /// The plan owns the panel whenever an operation exists (gather, plan,
    /// run, result — until the operator dismisses it); the shell shows
    /// only in the idle gaps. `shellMode` is the operator's standing
    /// choice; this is that choice filtered through the panel's one law.
    var shellVisible: Bool {
        shellMode && operation.phase == .idle
    }

    /// ⌘` — the keyboard toggle (his ask: bring the shell in and out of
    /// focus without tearing the view down).
    ///
    /// Not in shell mode yet: enters it, shell shown and focused. In
    /// shell mode with the keyboard: hands the keyboard back to the
    /// panes, shell stays visible (dimmed edge). In shell mode without
    /// the keyboard: focuses the shell again — unless the plan owns the
    /// panel, which is said out loud instead of silently ignored.
    func toggleShellKeyboard() {
        if !shellMode {
            guard focusedPane.state.host != nil else {
                operation.appendToolError("point a pane at a host first")
                return
            }
            if !operation.panelShowing { operation.showPanel() }
            shellMode = true
            shellFocused = true
            return
        }
        if shellFocused {
            shellFocused = false
            return
        }
        guard shellVisible else {
            operation.note("the plan owns the panel — esc dismisses it, then ⌘` returns the shell")
            return
        }
        shellFocused = true
    }

    /// Leaves shell mode entirely — the session-ended path.
    ///
    /// The session (if any) keeps running underneath; only the panel's
    /// view returns to the transcript.
    func exitShellMode() {
        shellMode = false
        shellFocused = false
    }

    /// The host whose session the panel shows in shell mode.
    ///
    /// The focused pane's host, live. Nil when no pane is pointed.
    var shellHost: String? {
        focusedPane.state.host
    }

    /// Pulls the keyboard off the shell on enactment failure.
    ///
    /// The view side is free — a failing operation makes `phase` non-idle
    /// and `shellVisible` false, so the transcript is already showing.
    /// The keyboard must follow: the operator's next keys read the
    /// failure, not a hidden PTY.
    func resurfaceTranscriptOnFailure() {
        shellFocused = false
    }

    /// The stand-down: while the shell holds the keyboard, every key
    /// belongs to the PTY except ⌘-chords (ho-9.7's law — ⌘Q, ⌘comma,
    /// the menus keep working). ⌘` hands the keyboard back.
    ///
    /// Esc itself is NOT caught here — it must reach SwiftTerm's keyDown
    /// unmolested, vim needs it. Returning false lets AppKit's normal
    /// responder chain carry the event to the terminal view, which is
    /// the key first responder while the shell holds the keyboard.
    func handleShellModeKey(_ event: NSEvent) -> Bool {
        guard let token = Grammar.token(for: event) else { return false }
        if token == "cmd-`" || token == "cmd-esc" {
            shellFocused = false
            return true
        }
        return token.hasPrefix("cmd-") && handleGlobalChord(token)
    }
}
