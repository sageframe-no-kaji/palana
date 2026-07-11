// The SwiftUI seam onto SwiftTerm's AppKit widget — the plan panel's
// terminal mode hosts one `LocalProcessTerminalView` at a time, full
// panel height, sized to the panel's own font scale.

import AppKit
import SwiftTerm
import SwiftUI

/// Wraps a `LocalProcessTerminalView` so SwiftUI can host it.
///
/// The view instance comes from `TerminalSessionStore` — this wrapper
/// never creates or destroys the session, only presents it. Switching
/// `view` (a focused-pane switch) swaps which live session is on screen;
/// the one that leaves keeps running underneath, untouched.
struct TerminalHostView: NSViewRepresentable {
    /// The live session to present — owned by `TerminalSessionStore`.
    let view: LocalProcessTerminalView
    /// The terminal's point size — follows the panel's `⌘+`/`⌘-` scale.
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Re-parenting the same instance under a new SwiftUI identity
        // (a pane switch) needs no extra wiring — the process and its
        // buffer live on the view itself, not in this representable.
        if nsView.font.pointSize != fontSize {
            nsView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }
}
