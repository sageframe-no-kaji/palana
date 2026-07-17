// PalanaSession+Preview — the preview pane's grammar and follow wiring (ho-16,
// reshaped in review).
//
// `v` puts the RIGHT pane into preview and follows the LEFT pane's cursor; the
// keyboard is forced to the left and locked there (there is nothing to click on
// the right). `v` or Esc exits the whole viewer. The mode flag lives on the
// right pane; the left pane's file cursor underneath is never touched.

import Foundation
import PalanaCore

extension PalanaSession {
    /// True while the viewer is engaged — the right pane previews and the left
    /// is locked as the driver.
    var previewActive: Bool { right.paneMode == .preview }

    /// `v`: engages or exits the viewer.
    ///
    /// Engage → the right pane previews the left pane's cursor, focus snaps to
    /// the left and locks there. A second `v` (or Esc) exits and unlocks. The
    /// left pane keeps whatever it was showing; only the right pane's mode flag
    /// moves.
    func togglePreviewMode() {
        if previewActive {
            exitPreview()
            return
        }
        if right.paneMode == .zfs { right.exitZFSMode() }
        right.enterPreviewMode()
        focusedSide = .left
        updatePreviewFollow()
    }

    /// Exits the viewer: the right pane returns to files, focus unlocks.
    func exitPreview() {
        right.exitPreviewMode()
        previewController.clear()
    }

    /// Honors a focus request from a click, enforcing the viewer lock.
    ///
    /// While previewing, the keyboard is pinned to the left — a click on the
    /// right pane (which shows no rows) never steals focus.
    func focusPane(_ side: SessionSnapshot.Side) {
        if previewActive, side == .right { return }
        focusedSide = side
        // Clicking a pane reclaims the keyboard for it. After an operation's
        // terminal or the interactive shell has taken the keyboard, a click
        // that only moved `focusedSide` left the keys still aimed at the
        // terminal — the pane looked focused but didn't answer keys, and Tab
        // (which routes through the grammar) was the only way back (his report).
        terminalFocused = false
        shellFocused = false
    }

    /// Points the preview at the current LEFT-pane cursor.
    ///
    /// Called on engage and whenever the left cursor moves (the surface watches
    /// it). Resolves the left pane's cursor file — local URL or remote address —
    /// and hands it to the debounced loader.
    func updatePreviewFollow() {
        guard previewActive else {
            previewController.clear()
            return
        }
        let source = left
        let entry = source.cursorEntry
        let host = source.state.host
        let isLocal = host == PalanaCore.localHostName
        var url: URL?
        if isLocal, let entry {
            url = URL(
                fileURLWithPath: PaneModel.childPath(of: source.state.path, name: entry.name))
        }
        previewController.follow(
            entry: entry,
            host: host,
            directory: source.state.path,
            isLocal: isLocal,
            url: url)
    }

    /// A change-detection key for the preview follow — encodes the left cursor's
    /// address, so the surface reloads only when it actually moves.
    var previewFollowKey: String {
        guard previewActive else { return "none" }
        // base64 of the name bytes — a stable key without a lossy Data→String
        // conversion, so byte-distinct names never collide on the follow key.
        let cursor = left.cursorEntry.map { $0.nameData.base64EncodedString() } ?? "-"
        return "\(left.state.host ?? "-")|\(left.state.path)|\(cursor)"
    }
}
