// PalanaSession+Preview — the preview pane's grammar and follow wiring (ho-16).
//
// `v` toggles preview on the focused pane; the pane then shows the OTHER pane's
// cursor. The follow is driven from the surface (which watches the source
// cursor) through `updatePreviewFollow`, which resolves the source file and
// hands it to the debounced `PreviewController`. The mode flag lives on the
// pane; nothing here touches the file cursor underneath.

import Foundation
import PalanaCore

extension PalanaSession {
    /// `v`: toggles preview mode on the focused pane.
    ///
    /// A second `v` (or Esc) exits. Entering preview leaves zfs mode if it was
    /// up — a pane holds one special mode at a time. On entry the follow fires
    /// once so the pane fills immediately, before the first cursor move.
    func togglePreviewMode() {
        let pane = focusedPane
        if pane.paneMode == .preview {
            pane.exitPreviewMode()
            previewController.clear()
            return
        }
        if pane.paneMode == .zfs { pane.exitZFSMode() }
        pane.enterPreviewMode()
        updatePreviewFollow()
    }

    /// Points the preview at the current opposite-pane cursor.
    ///
    /// Called on entry and whenever the source cursor moves (the surface
    /// watches it). Resolves the source pane — the one NOT in preview — and its
    /// cursor file, local URL and all, then hands it to the debounced loader.
    /// No pane in preview clears the loader.
    func updatePreviewFollow() {
        let source: PaneModel
        if left.paneMode == .preview {
            source = right
        } else if right.paneMode == .preview {
            source = left
        } else {
            previewController.clear()
            return
        }
        let entry = source.cursorEntry
        let host = source.state.host
        let isLocal = host == PalanaCore.localHostName
        var url: URL?
        if isLocal, let entry {
            url = URL(
                fileURLWithPath: PaneModel.childPath(of: source.state.path, name: entry.name))
        }
        previewController.follow(entry: entry, isLocal: isLocal, url: url)
    }

    /// A change-detection key for the preview follow — encodes which pane is
    /// previewing and where the source cursor sits, so the surface reloads only
    /// when one of those actually moves.
    var previewFollowKey: String {
        let source: PaneModel
        let side: String
        if left.paneMode == .preview {
            source = right
            side = "L"
        } else if right.paneMode == .preview {
            source = left
            side = "R"
        } else {
            return "none"
        }
        // base64 of the name bytes — a stable key without a lossy Data→String
        // conversion, so byte-distinct names never collide on the follow key.
        let cursor = source.cursorEntry.map { $0.nameData.base64EncodedString() } ?? "-"
        return "\(side)|\(source.state.host ?? "-")|\(source.state.path)|\(cursor)"
    }
}
