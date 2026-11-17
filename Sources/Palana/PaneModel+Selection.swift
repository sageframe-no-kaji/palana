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

    /// Adopts the native table's selection without reinterpreting its modifiers.
    ///
    /// AppKit owns the range anchor, Command toggles, and the distinction
    /// between clicking a selected row and starting a drag of the cohort.
    /// A single selected row uses the cursor; several rows become marks.
    /// An empty selection clears the cursor too, so deselecting the last
    /// row cannot select it again through `tableSelection`'s fallback.
    func applyTableClick(_ newSelection: Set<FileEntry.ID>, clicked: FileEntry.ID? = nil) {
        state.selection = newSelection.count > 1 ? newSelection : []
        if let clicked, newSelection.contains(clicked) {
            state.cursor = clicked
        } else if let cursor = state.cursor, newSelection.contains(cursor) {
            return
        } else {
            state.cursor = rows.first { newSelection.contains($0.id) }?.id
        }
    }
}
