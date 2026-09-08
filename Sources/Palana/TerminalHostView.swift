// The SwiftUI seam onto SwiftTerm's AppKit widget — the plan panel's
// terminal mode hosts one `LocalProcessTerminalView` at a time, full
// panel height, sized to the panel's own font scale.

import AppKit
import SwiftTerm
import SwiftUI

/// Wraps a ``ShellTerminalView`` so SwiftUI can host it.
///
/// The view instance comes from `TerminalSessionStore` — this wrapper
/// never creates or destroys the session, only presents it. Switching
/// `view` (a focused-pane switch) swaps which live session is on screen;
/// the one that leaves keeps running underneath, untouched.
struct TerminalHostView: NSViewRepresentable {
    /// The live session to present — owned by `TerminalSessionStore`.
    let view: ShellTerminalView
    /// The terminal's point size — follows the panel's `⌘+`/`⌘-` scale.
    var fontSize: CGFloat = 13
    /// Whether the shell holds the keyboard — drives first responder and
    /// the caret's rest.
    var focused: Bool = true

    func makeNSView(context: Context) -> ShellTerminalView {
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.setCaretResting(!focused)
        return view
    }

    func updateNSView(_ nsView: ShellTerminalView, context: Context) {
        // Re-parenting the same instance under a new SwiftUI identity
        // (a pane switch) needs no extra wiring — the process and its
        // buffer live on the view itself, not in this representable.
        if nsView.font.pointSize != fontSize {
            nsView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        // The caret follows shellFocused — the session's flag is the
        // authority; first responder is its consequence, a turn behind.
        // Applied here, synchronously, so every path that flips the flag
        // (⌘`, a click off the shell, a failure resurfacing) rests or wakes
        // the caret on the same pass. Colors and a layer animation only —
        // no responder-chain mutation, so no reentrancy.
        nsView.setCaretResting(!focused)
        // First responder follows the session's shellFocused, deferred a
        // runloop turn — mutating the responder chain inside SwiftUI's
        // update pass is the reentrancy the styler taught us about. The
        // monitor consumes grammar keys either way; this keeps stray
        // unconsumed keys from leaking into an unfocused PTY.
        let wantsFocus = focused
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if wantsFocus, window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            } else if !wantsFocus, window.firstResponder === nsView {
                window.makeFirstResponder(nil)
            }
        }
    }
}
