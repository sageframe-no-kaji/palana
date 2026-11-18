// DragFreezeRepro — a SwiftUI Table whose rows drag (TableRow.itemProvider)
// inside views that accept drops (.onDrop on the table and on each cell).
//
// Steps: launch, then with a TRACKPAD drag a row from one table to the other,
// or within the same table, a few times. On macOS 27.0.1 the window stops
// accepting clicks; the log shows
//   *** Canceling drag because exception was raised during a dragging session.
//   Exception: CALayerInvalidGeometry  CALayer position contains NaN: [nan nan]
// thrown from HIToolbox UpdateLayerPositions ← UnflockAnimationTimerCallback.
// Posted (CGEvent) mouse drags have not reproduced it.

import AppKit
import SwiftUI

struct Row: Identifiable, Hashable {
    let id: Int
    let url: URL
    var name: String { url.lastPathComponent }
}

@MainActor
func makeRows() -> [Row] {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("DragFreezeRepro", isDirectory: true)
    return (0..<20).map { index in
        let url = base.appendingPathComponent(String(format: "folder-%02d", index), isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Row(id: index, url: url)
    }
}

struct Pane: View {
    let rows: [Row]
    @State private var selection: Row.ID?
    @State private var targeted = false

    var body: some View {
        Table(of: Row.self, selection: $selection) {
            TableColumn("Name") { row in
                Text(row.name + "/")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onDrop(of: [.fileURL], isTargeted: nil) { _ in true }
            }
        } rows: {
            ForEach(rows) { row in
                TableRow(row).itemProvider { NSItemProvider(object: row.url as NSURL) }
            }
        }
        .overlay { if targeted { Color.accentColor.opacity(0.08).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { _ in true }
    }
}

struct ContentView: View {
    let rows = makeRows()
    var body: some View {
        HStack(spacing: 0) {
            Pane(rows: rows)
            Divider()
            Pane(rows: rows)
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

@main
struct DragFreezeReproApp: App {
    var body: some Scene {
        WindowGroup("DragFreezeRepro") { ContentView() }
    }
}
