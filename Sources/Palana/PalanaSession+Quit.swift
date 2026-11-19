// PalanaSession+Quit — what ⌘Q does while pālana is still working.
//
// Quitting mid-transfer asks: Keep Running, Quit When Finished, or Stop and
// Quit. "Quit When Finished" waits for the running transfer and every queued
// save to go back, then quits on its own. Anything that fails or is stopped
// on the way cancels the quit and pālana stays open, so the failure is on
// screen. "Stop and Quit" is the shutdown path (`closeDoors`).

import AppKit
import PalanaCore

/// The operator's answer to the quit prompt.
enum QuitChoice: Equatable {
    /// Stay open; any pending quit is cancelled.
    case keepRunning
    /// Quit once the running transfer and the queued saves are done.
    case quitWhenFinished
    /// Stop everything now and quit.
    case stopAndQuit
}

/// The session's quit state: the watch over a pending "Quit When Finished",
/// and how the app is asked to quit.
@MainActor
final class QuitState {
    /// Watches a pending "Quit When Finished" until the work ends.
    var watchTask: Task<Void, Never>?

    /// Asks the app to quit; tests count calls instead.
    ///
    /// Production schedules `terminate:` on the run loop rather than calling
    /// it here. This runs inside a main-actor task, and `terminate:` waits —
    /// in a nested event loop — for `applicationShouldTerminate`'s reply,
    /// which itself comes from a main-actor task. Called directly, the
    /// waiting task holds the main actor and the reply can never run: the
    /// app froze instead of quitting (hands check, 2026-11-19). From the run
    /// loop, terminate runs outside any task, as it does for ⌘Q.
    var requestTermination: @MainActor () -> Void = {
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }
}

extension PalanaSession {
    /// Whether ⌘Q must ask first: a plan is running, or saves are still on
    /// their way back to their servers.
    var quitNeedsConfirmation: Bool {
        operation.phase == .enacting || !roundTripCenter.isIdle
    }

    /// The prompt's explanation, naming what is still in progress.
    var quitPromptDetail: String {
        var parts: [String] = []
        if operation.phase == .enacting { parts.append("A transfer is running.") }
        let waiting = roundTripCenter.pendingCount
        if waiting > 0 {
            parts.append(
                "\(waiting) saved \(waiting == 1 ? "edit is" : "edits are") waiting to go back to the server.")
        }
        parts.append(
            "Quit When Finished waits for them, then quits. Stop and Quit stops now: an interrupted"
                + " transfer can leave partial files at the destination, and unsent edits stay in their"
                + " local copies.")
        return parts.joined(separator: " ")
    }

    /// Applies the operator's answer.
    ///
    /// - Returns: True when the app should quit now (Stop and Quit).
    @discardableResult
    func applyQuitChoice(_ choice: QuitChoice) -> Bool {
        switch choice {
        case .keepRunning:
            cancelPendingQuit(reason: nil)
            return false
        case .quitWhenFinished:
            beginQuitWhenFinished()
            return false
        case .stopAndQuit:
            quit.watchTask?.cancel()
            quit.watchTask = nil
            return true
        }
    }

    /// Holds new operator work and watches until everything in flight ends.
    private func beginQuitWhenFinished() {
        guard !operation.quitPending else { return }
        operation.quitPending = true
        operation.note("quitting when this finishes — ⌘Q again to stop now or stay open")
        quit.watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                if self.settleQuitWhenFinished() { return }
            }
        }
    }

    /// One look at the work a pending quit waits for.
    ///
    /// Returns true when the watch is over: everything finished and the
    /// app was asked to quit, or something failed or was stopped and the
    /// quit was cancelled. Exposed for tests, which pump it directly.
    @discardableResult
    func settleQuitWhenFinished() -> Bool {
        guard operation.quitPending else { return true }
        switch operation.phase {
        case .failed:
            cancelPendingQuit(reason: "something failed")
            return true
        case .cancelled:
            cancelPendingQuit(reason: "the run was stopped")
            return true
        case .enacting, .gathering, .ready, .naming:
            return false
        case .idle, .finished:
            guard roundTripCenter.isIdle else { return false }
            quit.watchTask = nil
            quit.requestTermination()
            return true
        }
    }

    /// Ends a pending quit and lets work start again.
    private func cancelPendingQuit(reason: String?) {
        quit.watchTask?.cancel()
        quit.watchTask = nil
        guard operation.quitPending else { return }
        operation.quitPending = false
        if let reason {
            operation.note("quit cancelled — \(reason), so pālana stays open")
            operation.panelShowing = true
        } else {
            operation.note("quit cancelled — pālana stays open")
        }
    }
}

/// The ⌘Q prompt while work is in progress.
@MainActor
enum QuitPrompt {
    /// Asks the operator.
    ///
    /// Keep Running is the default button (Return): the answer that changes
    /// nothing is the one a stray keypress gives.
    static func ask(detail: String) -> QuitChoice {
        let alert = NSAlert()
        alert.messageText = "pālana is still working"
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit When Finished")
        alert.addButton(withTitle: "Stop and Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepRunning
        case .alertSecondButtonReturn: return .quitWhenFinished
        default: return .stopAndQuit
        }
    }
}
