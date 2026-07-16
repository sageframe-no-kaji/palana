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
import UniformTypeIdentifiers

extension PaneView {
    /// The cursor row's own paint — moss wash, not the system accent.
    ///
    /// Doubles as the folder-drop target wash (ho-14): a folder row a valid
    /// drag hovers wears the same accent language, at the selection wash's
    /// weight (design system §7), so "this is where it lands" is unmistakable.
    func cursorWash(_ entry: FileEntry) -> some View {
        let opacity: Double
        if folderDropHoverID == entry.id {
            opacity = 0.10
        } else if model.state.cursor == entry.id {
            opacity = 0.18
        } else {
            opacity = 0
        }
        return RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent.opacity(opacity))
            .padding(.horizontal, -6)
    }

    /// Makes a directory row a drop target (ho-14): a pane-to-pane selection
    /// dropped here lands inside the folder, not in the pane's cwd.
    ///
    /// While a valid drag hovers, the row wears the accent wash; the wash clears
    /// on leave or drop. Non-directory rows return the content untouched, so
    /// they fall through to the pane-level drop. The row consumes the drop, so
    /// the pane handler does not also fire (Decision 4 — no double-plan).
    @ViewBuilder
    func folderDropTarget(_ entry: FileEntry, _ content: some View) -> some View {
        if entry.kind == .directory {
            content.onDrop(
                of: [.json, .fileURL],
                isTargeted: Binding(
                    get: { folderDropHoverID == entry.id },
                    set: { targeted in
                        folderDropHoverID = targeted ? entry.id : nil
                    }
                )
            ) { providers in
                folderDropHoverID = nil
                return handleFolderDrop(
                    providers: providers,
                    model: model,
                    folder: entry,
                    onSelectionOntoFolder: onDropSelectionOntoFolder,
                    onFinderOntoFolder: onFinderDropOntoFolder
                )
            }
        } else {
            content
        }
    }
}
