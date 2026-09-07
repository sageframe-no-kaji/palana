// PalanaSession+Shell — ho-11's interactive terminal: the shell's view
// and keyboard as two separate facts, the ⌘` keyboard toggle, the
// plan-owns-the-panel rule, and the key-monitor stand-down while the
// shell holds the keyboard. Extracted from PalanaSession.swift to keep
// that file within the line-length budget, matching the +ZFS and
// +DragDrop convention.

import AppKit
import PalanaCore

/// ⌘`'s one decision, as a pure function of the session's facts.
///
/// The hands session of 2026-09-07 found ⌘` dead whenever a plan or a
/// result owned the panel — the round-9 'decline silently' rule. His
/// call: ⌘` always wins. The rule is written here, apart from the
/// session, so every combination of facts has a test.
enum ShellTogglePolicy {
    /// What ⌘` does.
    enum Action: Equatable {
        /// No pane points at a host — say so, change nothing.
        case refuseNoHost
        /// Shell mode on, panel up, keyboard to the shell. Nothing dismissed.
        case summon
        /// A settled operation owns the panel — dismiss it, then summon.
        case dismissThenSummon
        /// The shell is on screen with the keyboard — hand it to the panes.
        case release
    }

    /// The facts the decision reads.
    struct Situation: Equatable {
        var shellMode: Bool
        var shellFocused: Bool
        var panelShowing: Bool
        var phase: OperationModel.Phase
        var hasHost: Bool
    }

    /// Phases with work in flight — ⌘` never dismisses these.
    static func isRunning(_ phase: OperationModel.Phase) -> Bool {
        phase == .gathering || phase == .enacting
    }

    /// Whether the panel shows the shell under these facts — the one law.
    ///
    /// The plan owns the panel whenever a settled operation exists (naming,
    /// the plan, a result — until the operator dismisses it). Over a live
    /// run the shell shows only while it holds the keyboard: the moment the
    /// keyboard leaves (⌘`, a click, a failure) the transcript returns.
    static func shellShows(_ situation: Situation) -> Bool {
        guard situation.shellMode, situation.panelShowing, situation.hasHost else { return false }
        if situation.phase == .idle { return true }
        return isRunning(situation.phase) && situation.shellFocused
    }

    static func decide(_ situation: Situation) -> Action {
        guard situation.hasHost else { return .refuseNoHost }
        if shellShows(situation), situation.shellFocused { return .release }
        if situation.phase == .idle || isRunning(situation.phase) { return .summon }
        return .dismissThenSummon
    }
}

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

    /// The facts ⌘` and the visibility law read, gathered once.
    private var shellSituation: ShellTogglePolicy.Situation {
        ShellTogglePolicy.Situation(
            shellMode: shellMode,
            shellFocused: shellFocused,
            panelShowing: operation.panelShowing,
            phase: operation.phase,
            hasHost: shellHost != nil)
    }

    /// Whether the panel currently SHOWS the shell.
    ///
    /// `shellMode` is the operator's standing choice; this is that choice
    /// filtered through ``ShellTogglePolicy/shellShows(_:)``.
    var shellVisible: Bool {
        ShellTogglePolicy.shellShows(shellSituation)
    }

    /// ⌘` — the keyboard toggle (his ask: bring the shell in and out of
    /// focus without tearing the view down).
    ///
    /// Drives ``ShellTogglePolicy``. Shell on screen with the keyboard:
    /// hands the keyboard back to the panes, shell stays visible (dimmed
    /// edge) in the idle gap, the transcript returns over a live run. A
    /// settled operation owning the panel: dismissed, the shell summoned
    /// (supersedes round 9's silent decline — 'I should ALWAYS be able to
    /// shift to the shell'). A live run: the shell shows over it, nothing
    /// cancelled. No host: the note, nothing else.
    func toggleShellKeyboard() {
        switch ShellTogglePolicy.decide(shellSituation) {
        case .refuseNoHost:
            operation.appendToolError("point a pane at a host first")
        case .release:
            shellFocused = false
        case .dismissThenSummon:
            // The settled phases reset to idle here; the policy never
            // sends a running phase this way, so nothing live is stopped.
            operation.dismissOrCancel()
            summonShell()
        case .summon:
            summonShell()
        }
    }

    /// Shell mode on, panel up, keyboard to the shell.
    private func summonShell() {
        if !operation.panelShowing { operation.showPanel() }
        shellMode = true
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

    /// The directory a NEW session for `shellHost` opens in.
    ///
    /// The focused pane's resolved absolute path (his ask: the terminal
    /// opens where the pane stands, not in the remote home). Read only
    /// at first summon; an existing session is never moved.
    var shellDirectory: String {
        focusedPane.state.path
    }

    /// Pulls the keyboard off the shell on enactment failure.
    ///
    /// The view side follows: a failing operation makes `phase` settled
    /// and the shell yields the panel, so the transcript is showing. The
    /// keyboard must follow: the operator's next keys read the failure,
    /// not a hidden PTY.
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
            toggleShellKeyboard()
            return true
        }
        return token.hasPrefix("cmd-") && handleGlobalChord(token)
    }

    /// Hands the keyboard to the panes when a click lands off the shell.
    ///
    /// The pane's own focus callback fires only when the Table's selection
    /// changes — a click on the row already under the cursor, or on empty
    /// pane ground, moved AppKit's first responder off the terminal while
    /// `shellFocused` still said the shell had the keys, and the next verb
    /// went nowhere (his report: 'easy to get stuck right now'). The
    /// session reads the click before AppKit dispatches it and settles
    /// the flag: the click is what hands the keyboard back.
    func releaseShellKeyboardIfClickedAway(_ event: NSEvent) {
        guard shellVisible, shellFocused, let host = shellHost, terminalSessions.hasSession(for: host) else {
            return
        }
        // Guarded by hasSession above — this never starts a session.
        let terminal = terminalSessions.session(for: host, startingIn: shellDirectory)
        guard let window = event.window, window === terminal.window else { return }
        let hit = window.contentView?.hitTest(event.locationInWindow)
        if !Self.clickLandsOnShell(hit, terminal: terminal) {
            shellFocused = false
        }
    }

    /// Whether `hit` is the terminal view or sits inside it.
    static func clickLandsOnShell(_ hit: NSView?, terminal: NSView) -> Bool {
        var view = hit
        while let current = view {
            if current === terminal { return true }
            view = current.superview
        }
        return false
    }

    /// Installs the mouse-down monitor beside the key monitor.
    ///
    /// ho-11's keyboard flag must follow the mouse: a click anywhere but
    /// the shell hands the keyboard to the panes, so the next verb key
    /// reaches the pane's grammar instead of a PTY the operator has
    /// visibly left (hands session 2026-09-07). The event is never
    /// consumed — AppKit dispatches the click as it always did.
    func installClickMonitor() {
        guard clickMonitor == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated { self?.releaseShellKeyboardIfClickedAway(event) }
            return event
        }
    }
}
