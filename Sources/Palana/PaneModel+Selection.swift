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

    /// ⌘- or ⌥-click: toggle one row in or out of the selection.
    func toggleSelection(_ id: FileEntry.ID) {
        if state.selection.contains(id) {
            state.selection.remove(id)
        } else {
            state.selection.insert(id)
        }
    }
}
