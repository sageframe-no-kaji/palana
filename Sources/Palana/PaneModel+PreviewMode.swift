// PaneModel+PreviewMode — the pane's preview mode (ho-16). A pane in preview
// renders no listing of its own; it shows the file the *other* pane's cursor is
// on. Like zfs mode, entering and leaving only flips `paneMode` — the file
// cursor and path underneath are never touched, so the file view is restored on
// exit simply by never having disturbed it. The follow wiring and the load live
// in PreviewController; this file is only the mode flag.

import Foundation

extension PaneModel {
    /// Enters preview mode on this pane.
    ///
    /// The file cursor and path are untouched; only `paneMode` changes. The
    /// surface drives what the preview shows from the opposite pane's cursor.
    func enterPreviewMode() {
        paneMode = .preview
    }

    /// Leaves preview mode, restoring the file view exactly as it stood.
    ///
    /// `state` was never touched while previewing, so flipping the flag back is
    /// the whole operation.
    func exitPreviewMode() {
        paneMode = .files
    }
}
