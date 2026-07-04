// The pane transitions — pure state moves the grammar dispatches into.
// Everything that can be wrong about navigation lives here, under the
// floor; the app's binding table stays declarative data.
//
// The hot moves — cursor and selection, fired per keystroke — take the
// displayed rows as a parameter instead of re-deriving them: sorting
// 5,000 names with localizedStandardCompare on every keypress would
// eat the ho-01 cadence. The caller computes rows once per display
// change and passes them back in. The cold moves — hidden, sort,
// replace — re-derive internally, because they are the display change.

import Foundation

extension PaneState {
    /// Moves the cursor by a signed number of rows, clamped.
    ///
    /// With no cursor yet, a downward move lands on the first row and
    /// an upward move on the last — the keyboard always gets footing.
    public mutating func moveCursor(by offset: Int, in rows: [FileEntry]) {
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

    /// Cursor to the first row.
    public mutating func moveCursorToTop(in rows: [FileEntry]) {
        cursor = rows.first?.id
    }

    /// Cursor to the last row.
    public mutating func moveCursorToBottom(in rows: [FileEntry]) {
        cursor = rows.last?.id
    }

    /// Toggles selection on the cursor entry, then advances one row.
    ///
    /// yazi's Space: mark and move on. No cursor, no effect.
    public mutating func toggleSelectionAtCursorAndAdvance(in rows: [FileEntry]) {
        guard let current = cursor else { return }
        if selection.contains(current) {
            selection.remove(current)
        } else {
            selection.insert(current)
        }
        moveCursor(by: 1, in: rows)
    }

    /// Selects every displayed entry — hidden entries stay unselected.
    public mutating func selectAll(in rows: [FileEntry]) {
        selection = Set(rows.map(\.id))
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
        reconcileToDisplayed(refootDeadCursor: true)
    }

    /// Prunes cursor and selection to the displayed rows.
    private mutating func reconcileToDisplayed(refootDeadCursor: Bool = false) {
        let rows = sortedEntries()
        let displayed = Set(rows.map(\.id))
        selection = selection.intersection(displayed)
        if let current = cursor, displayed.contains(current) { return }
        if cursor != nil || refootDeadCursor {
            cursor = rows.first?.id
        }
    }
}
