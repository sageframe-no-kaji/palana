// The pane transitions — pure state moves the grammar dispatches into.
// Everything that can be wrong about navigation lives here, under the
// floor; the app's binding table stays declarative data. All moves
// operate over the displayed order, because that is the order the
// operator is looking at.

import Foundation

extension PaneState {
    /// Moves the cursor by a signed number of displayed rows, clamped.
    ///
    /// With no cursor yet, a downward move lands on the first row and
    /// an upward move on the last — the keyboard always gets footing.
    public mutating func moveCursor(by offset: Int) {
        let rows = sortedEntries()
        guard !rows.isEmpty else {
            cursor = nil
            return
        }
        guard let current = cursor, let index = rows.firstIndex(where: { $0.id == current }) else {
            cursor = offset >= 0 ? rows.first?.id : rows.last?.id
            return
        }
        let target = min(max(index + offset, 0), rows.count - 1)
        cursor = rows[target].id
    }

    /// Cursor to the first displayed row.
    public mutating func moveCursorToTop() {
        cursor = sortedEntries().first?.id
    }

    /// Cursor to the last displayed row.
    public mutating func moveCursorToBottom() {
        cursor = sortedEntries().last?.id
    }

    /// Toggles selection on the cursor entry, then advances one row.
    ///
    /// yazi's Space: mark and move on. No cursor, no effect.
    public mutating func toggleSelectionAtCursorAndAdvance() {
        guard let current = cursor else { return }
        if selection.contains(current) {
            selection.remove(current)
        } else {
            selection.insert(current)
        }
        moveCursor(by: 1)
    }

    /// Selects every displayed entry — hidden entries stay unselected.
    public mutating func selectAll() {
        selection = Set(sortedEntries().map(\.id))
    }

    /// Clears the selection.
    public mutating func clearSelection() {
        selection = []
    }

    /// Shows or hides dotfiles, then reconciles cursor and selection
    /// to the rows that remain displayed.
    public mutating func toggleHidden() {
        showHidden.toggle()
        reconcileToDisplayed()
    }

    /// Sets the sort key — the same key again flips direction.
    public mutating func setSort(key: SortKey) {
        if sort.key == key {
            sort.ascending.toggle()
        } else {
            sort = Sort(key: key)
        }
    }

    /// Replaces the entries after a read, keeping what survives.
    ///
    /// Selection intersects with the new identities. The cursor holds
    /// its entry if the entry is still displayed, otherwise lands on
    /// the first row — a fresh listing always leaves the keyboard
    /// standing somewhere.
    public mutating func replaceEntries(_ newEntries: [FileEntry]) {
        entries = newEntries
        let displayed = Set(sortedEntries().map(\.id))
        selection = selection.intersection(displayed)
        if let current = cursor, displayed.contains(current) { return }
        cursor = sortedEntries().first?.id
    }

    /// Prunes cursor and selection to the displayed rows.
    private mutating func reconcileToDisplayed() {
        let displayed = Set(sortedEntries().map(\.id))
        selection = selection.intersection(displayed)
        if let current = cursor, !displayed.contains(current) {
            cursor = sortedEntries().first?.id
        }
    }
}
