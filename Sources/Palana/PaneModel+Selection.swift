// PaneModel+Selection — the cursor and the selection as the verbs and the
// mouse see them: the entry under the cursor, what an operation acts on,
// and the two click gestures that grow or toggle the selection. Pure
// state moves over the pane's rows; split from PaneModel.swift for the
// type-body-length budget, the same move as PaneModel+Path.

import PalanaCore

extension PaneModel {
    /// The entry under the cursor, if any.
    var cursorEntry: FileEntry? {
        guard let cursor = state.cursor else { return nil }
        return rows.first { $0.id == cursor }
    }

    /// What an operation verb acts on.
    ///
    /// The selection when it exists, the cursor entry otherwise — the
    /// clipboard-verb precedent.
    var operationSubjects: [FileEntry] {
        if state.selection.isEmpty {
            return [cursorEntry].compactMap { $0 }
        }
        return rows.filter { state.selection.contains($0.id) }
    }

    /// Shift-click: select the run from the cursor to the clicked row,
    /// inclusive — Finder's manners over yazi's marks.
    func extendSelection(to id: FileEntry.ID) {
        guard
            let anchor = state.cursor,
            let from = rows.firstIndex(where: { $0.id == anchor }),
            let to = rows.firstIndex(where: { $0.id == id })
        else {
            state.selection.insert(id)
            return
        }
        for row in rows[min(from, to)...max(from, to)] {
            state.selection.insert(row.id)
        }
    }

    /// The rows the table is told are selected: the marks, or the cursor
    /// alone when nothing is marked.
    ///
    /// The table drags its selected rows natively, so a drag that starts on
    /// a marked row carries every marked row out of the pane; a drag on any
    /// other row carries that row.
    var tableSelection: Set<FileEntry.ID> {
        if !state.selection.isEmpty { return state.selection }
        return state.cursor.map { [$0] } ?? []
    }

    /// Applies a click the table reports as its new selection, in pālana's
    /// manners: a plain click moves the cursor and leaves the marks; ⇧
    /// extends the marks from the cursor; ⌘ or ⌥ toggles the clicked row.
    ///
    /// The table works out its own new selection; this reads which row was
    /// clicked from it and hands the click to pālana's selection.
    ///
    /// - Parameters:
    ///   - newSelection: The table's selection after the click.
    ///   - shift: Whether ⇧ was held.
    ///   - toggle: Whether ⌘ or ⌥ was held.
    func applyTableClick(_ newSelection: Set<FileEntry.ID>, shift: Bool, toggle: Bool) {
        if shift {
            // The table extends from its own anchor; the clicked row is the
            // end of that run farthest from the cursor.
            let indices = rows.indices.filter { newSelection.contains(rows[$0].id) }
            guard let low = indices.first, let high = indices.last else { return }
            let cursorIndex = state.cursor.flatMap { cursor in rows.firstIndex { $0.id == cursor } } ?? low
            let clicked = abs(high - cursorIndex) >= abs(low - cursorIndex) ? rows[high].id : rows[low].id
            extendSelection(to: clicked)
            state.cursor = clicked
        } else if toggle {
            let changed = tableSelection.symmetricDifference(newSelection)
            guard changed.count == 1, let clicked = changed.first else { return }
            toggleSelection(clicked)
            state.cursor = clicked
        } else if newSelection.count <= 1 {
            // A plain click on a row, or on empty space (no cursor).
            state.cursor = newSelection.first
        }
    }

    /// ⌘- or ⌥-click: toggle one row in or out of the selection.
    func toggleSelection(_ id: FileEntry.ID) {
        if state.selection.contains(id) {
            state.selection.remove(id)
        } else {
            state.selection.insert(id)
        }
    }
}
