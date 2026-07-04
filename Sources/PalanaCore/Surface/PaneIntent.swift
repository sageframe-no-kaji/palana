// The pane vocabulary — what a keystroke means, named before any key
// is bound to it. The Surface's binding table maps keys to these; the
// pane transitions apply the state-only ones; the app performs the
// rest. Pruning the grammar edits the table, never this vocabulary.

/// One thing the operator can ask a pane to do.
///
/// Symbolic on purpose: paging intents carry no row counts because the
/// view owns its geometry — the pane model resolves a page into rows
/// at dispatch time.
public enum PaneIntent: String, CaseIterable, Sendable {
    /// Cursor one row down.
    case cursorDown
    /// Cursor one row up.
    case cursorUp
    /// Cursor half a page down.
    case cursorHalfPageDown
    /// Cursor half a page up.
    case cursorHalfPageUp
    /// Cursor a full page down.
    case cursorPageDown
    /// Cursor a full page up.
    case cursorPageUp
    /// Cursor to the first row.
    case cursorToTop
    /// Cursor to the last row.
    case cursorToBottom
    /// Toggle selection on the cursor entry, then advance one row.
    case toggleSelectionAndAdvance
    /// Select every displayed entry.
    case selectAll
    /// Clear the selection.
    case clearSelection
    /// Ascend to the parent directory.
    case ascend
    /// Descend into the directory under the cursor.
    case descend
    /// Show or hide dotfiles.
    case toggleHidden
    /// Sort by name — again flips direction.
    case sortByName
    /// Sort by size — again flips direction.
    case sortBySize
    /// Sort by modification time — again flips direction.
    case sortByModified
    /// Copy the cursor entry's full path to the clipboard.
    case copyPath
    /// Copy the pane's directory path to the clipboard.
    case copyDirectory
    /// Copy the cursor entry's filename to the clipboard.
    case copyFilename
    /// Copy the cursor entry's name without extension to the clipboard.
    case copyNameSansExtension
    /// Re-read the pane's directory — one listing command.
    case refresh
    /// Summon the go-to bar to point the pane.
    case goTo
    /// Move focus to the other pane.
    case switchPane
    /// Show the keyboard vocabulary.
    case help
    /// Compose a copy plan — this pane's subjects toward the other pane.
    case operationCopy
    /// Compose a move plan — this pane's subjects toward the other pane.
    case operationMove
    /// Compose a deletion plan for this pane's subjects.
    case operationDelete
}
