// PaneView+FolderDrop — the row wash and the folder-row drop target (ho-14),
// extracted from PaneView.swift to keep that file within the 500-line limit.
//
// A directory row becomes a drop target: a pane-to-pane selection dropped onto
// it lands inside the folder, not in the pane's cwd. While a valid drag hovers,
// the row wears the accent wash — the same "this is where it lands" language as
// the cursor row. The pure destination/refusal logic lives in PalanaCore's
// DropDecision.decideOntoFolder; this file is only the SwiftUI wiring.

import PalanaCore
import SwiftUI

extension PaneView {
    /// The cursor row's own paint — moss wash, not the system accent.
    ///
    /// Doubles as the folder-drop target (ho-14): a folder row a valid drag
    /// hovers is lit like the pane wash — a stronger fill and accent rules
    /// along its top and bottom edges. Every column's cell draws this, so
    /// the light runs the whole row.
    func cursorWash(_ entry: FileEntry) -> some View {
        let dropTarget = folderDropHoverID == entry.id
        let opacity: Double
        if dropTarget {
            opacity = 0.16
        } else if model.state.cursor == entry.id {
            opacity = 0.18
        } else {
            opacity = 0
        }
        return Rectangle()
            .fill(Theme.accent.opacity(opacity))
            .overlay(alignment: .top) { dropEdge(dropTarget) }
            .overlay(alignment: .bottom) { dropEdge(dropTarget) }
            .padding(.horizontal, -6)
    }

    /// One accent rule along a drop-target row's edge.
    private func dropEdge(_ visible: Bool) -> some View {
        Rectangle()
            .fill(Theme.accent)
            .frame(height: visible ? 2 : 0)
    }

    /// The folder row a drag would drop into, if any.
    var hoveredFolder: FileEntry? {
        folderDropHoverID.flatMap { id in model.rows.first { $0.id == id } }
    }

    /// Routes one native drop through the same pane or folder plan entry point.
    func receivePaneDrop(_ content: PaneDropContent, folder: FileEntry?, moveHeld: Bool) {
        switch (content, folder) {
        case (.selection(let selection), .some(let folder)):
            onDropSelectionOntoFolder(selection, folder, moveHeld)
        case (.selection(let selection), nil):
            onDropSelection(selection, moveHeld)
        case (.files(let urls), .some(let folder)):
            onFinderDropOntoFolder(urls, folder, moveHeld)
        case (.files(let urls), nil):
            onFinderDrop(urls, moveHeld)
        }
    }
}
