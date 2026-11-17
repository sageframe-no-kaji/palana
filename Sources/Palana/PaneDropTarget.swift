// PaneDropTarget — a pane's drop surface, in AppKit.
//
// SwiftUI's drop targets (.onDrop) rewrite a drag's items the moment a drag
// enters them: they set the formation and move the item frames. On macOS 27,
// when that lands inside the drag's opening animation, HIToolbox can compute a
// NaN layer position (CALayerInvalidGeometry in UnflockAnimationTimerCallback),
// AppKit cancels the drag, and the window stops taking clicks (issue #4). A
// drag that starts on a pane begins over that pane's own drop target, so
// every drag was exposed.
//
// This view is the pane's only drop target. It is registered for pālana's
// selection payload and file URLs, lets every click through (hitTest is nil),
// and never touches the drag's items — it reads the pasteboard, works out the
// folder row under the pointer from the table itself, and hands the drop to
// the same four routes the SwiftUI targets used. The decisions and plans
// behind those routes are unchanged.

import AppKit
import PalanaCore
import SwiftUI
import os

/// What a drop on a pane carries.
enum PaneDropContent: Equatable {
    /// pālana's own selection, from a pane.
    case selection(DraggedSelection)
    /// Files from Finder or another app.
    case files([URL])

    /// Reads the drop off a drag pasteboard.
    static func read(from pasteboard: NSPasteboard) -> Self? {
        let selectionData = pasteboard.pasteboardItems?.lazy.compactMap {
            $0.data(forType: .palanaInternalSelection) ?? $0.data(forType: .palanaPayload)
        }.first
        // An internal drop must never ask an outbound file promise for bytes.
        if let selectionData, let payload = try? JSONDecoder().decode(DraggedSelection.self, from: selectionData) {
            return .selection(payload)
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        return urls.isEmpty ? nil : .files(urls)
    }

    /// Whether a pasteboard could carry a pane drop at all.
    static func accepts(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(.palanaInternalSelection) || types.contains(.palanaPayload) || types.contains(.fileURL)
    }
}

/// The pane's AppKit drop surface.
struct PaneDropTarget: NSViewRepresentable {
    /// The pane receiving drops.
    let model: PaneModel
    /// The native table whose rows define folder targets.
    let tableRef: TableRef
    /// Whether a drop would land on the pane itself (drives the drop wash).
    let onTargeted: @MainActor (Bool) -> Void
    /// The folder row a drop would land in, if any (drives the row wash).
    let onFolderHover: @MainActor (FileEntry.ID?) -> Void
    /// A drop: what it carries, the folder it landed on (nil for the pane),
    /// and whether ⌘ was held.
    let onDrop: @MainActor (PaneDropContent, FileEntry?, Bool) -> Void

    func makeNSView(context: Context) -> Catcher {
        let catcher = Catcher(frame: .zero)
        update(catcher)
        return catcher
    }

    func updateNSView(_ nsView: Catcher, context: Context) {
        update(nsView)
    }

    private func update(_ catcher: Catcher) {
        catcher.model = model
        catcher.tableRef = tableRef
        catcher.onTargeted = onTargeted
        catcher.onFolderHover = onFolderHover
        catcher.onDrop = onDrop
    }

    /// The directory entry at `row`, or nil — a drop there lands inside it.
    ///
    /// - Parameters:
    ///   - row: The table row under the pointer (-1 for none).
    ///   - rows: The pane's rows, in table order.
    /// - Returns: The folder, when the row is a directory.
    static func folder(at row: Int, in rows: [FileEntry]) -> FileEntry? {
        guard rows.indices.contains(row), rows[row].kind == .directory else { return nil }
        return rows[row]
    }

    /// The registered view.
    ///
    /// Transparent to clicks; a drag destination only.
    final class Catcher: NSView {
        var model: PaneModel?
        var tableRef: TableRef?
        private static let logger = Logger(subsystem: "net.sageframe.palana", category: "dragdrop")
        var onTargeted: (@MainActor (Bool) -> Void)?
        var onFolderHover: (@MainActor (FileEntry.ID?) -> Void)?
        var onDrop: (@MainActor (PaneDropContent, FileEntry?, Bool) -> Void)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.palanaInternalSelection, .palanaPayload, .fileURL])
        }

        @available(*, unavailable, message: "built in code only")
        required init?(coder: NSCoder) {
            nil
        }

        /// Clicks, scrolls and drags that start here belong to the views
        /// beneath; drag routing still finds this registered view.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            track(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            track(sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            clear()
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            clear()
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            let folder = folder(under: sender)
            clear()
            guard isReady, let content = PaneDropContent.read(from: sender.draggingPasteboard) else { return false }
            // Copy is the default; ⌘ escalates to a move — the plan is the gate.
            onDrop?(content, folder, NSEvent.modifierFlags.contains(.command))
            Self.logger.info("pane drop accepted: session \(sender.draggingSequenceNumber), folder \(folder != nil)")
            return true
        }

        private var isReady: Bool {
            guard let model else { return false }
            return model.status == .ready && model.state.host != nil
        }

        private func track(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let types = sender.draggingPasteboard.types ?? []
            guard isReady, PaneDropContent.accepts(types) else {
                clear()
                return []
            }
            let folder = folder(under: sender)
            onFolderHover?(folder?.id)
            onTargeted?(folder == nil)
            let wantsMove = NSEvent.modifierFlags.contains(.command)
            return wantsMove && sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
        }

        private func clear() {
            onFolderHover?(nil)
            onTargeted?(false)
        }

        /// The folder row under the drag, read from the pane's table.
        private func folder(under sender: any NSDraggingInfo) -> FileEntry? {
            guard let model, let table = tableRef?.table, table.window === window else { return nil }
            let point = table.convert(sender.draggingLocation, from: nil)
            return PaneDropTarget.folder(at: table.row(at: point), in: model.rows)
        }
    }
}
