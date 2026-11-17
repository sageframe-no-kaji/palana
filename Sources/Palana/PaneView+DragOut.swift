// PaneView+DragOut — what a row hands the table when it is dragged: its
// item provider (the pane-to-pane payload plus drag-out representations) and
// the pasteboard writer pālana substitutes for SwiftUI's (TableRowWriters).
// Extracted from PaneView.swift for the line budget.

import AppKit
import PalanaCore
import SwiftUI
import os

extension PaneModel {
    /// Any pointed pane can transfer a selection to another pane.
    var permitsRowDrag: Bool { state.host != nil }
}

extension PaneView {
    /// One row's drag provider: the pane-to-pane payload, and what the row
    /// delivers outside pālana (``DragOutPlan``).
    func rowProvider(for entry: FileEntry, selectedNames: [Data]) -> NSItemProvider? {
        guard model.permitsRowDrag else { return nil }
        let payload = dragPayload(for: entry, selectedNames: selectedNames)
        // Remote rows advertise only the process-local selection, never a file.
        guard model.isLocalPane else { return Palana.itemProvider(for: payload) }
        let (outbound, remote) = dragOut(for: entry)
        // Qualify the global to resolve the name collision with the
        // .itemProvider(_:) modifier method on TableRow.
        return Palana.itemProvider(for: payload, outbound: outbound, remote: remote)
    }

    /// The pasteboard writer for the table's row `row`, written up front
    /// (``rowPasteboardWriter``), or nil to keep SwiftUI's.
    func rowWriter(_ row: Int) -> (any NSPasteboardWriting)? {
        guard model.permitsRowDrag, model.rows.indices.contains(row) else { return nil }
        let entry = model.rows[row]
        let selectedNames = model.rows.filter { model.state.selection.contains($0.id) }.map(\.nameData)
        let payload = dragPayload(for: entry, selectedNames: selectedNames)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        guard model.isLocalPane else { return internalRowPasteboardWriter(payload: data) }
        let (outbound, remote) = dragOut(for: entry)
        guard let outbound else { return nil }
        Self.dragLog.info(
            "row writer for \(entry.name, privacy: .public): \(String(describing: outbound), privacy: .public)")
        return rowPasteboardWriter(for: outbound, payload: data, remote: remote)
    }

    static let dragLog = Logger(subsystem: "net.sageframe.palana", category: "dragout")

    /// What a row delivers outside pālana, and the remote reader it needs.
    func dragOut(for entry: FileEntry) -> (DragOutItem?, RemoteDragSupport?) {
        let host = model.state.host ?? PalanaCore.localHostName
        let outbound = DragOutPlan.items(
            host: host, directory: model.state.path, names: [entry.nameData], entries: [entry]
        ).first
        let note = onDragOutNote
        let remote =
            host == PalanaCore.localHostName
            ? nil
            : RemoteDragSupport(listing: model.listing(for: host)) { line in
                Task { @MainActor in note(line) }
            }
        return (outbound, remote)
    }
}
