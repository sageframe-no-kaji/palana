// Actual SwiftUI pane tables: local file export and remote internal transfers.
// Offscreen; no pointer movement, native drag session, or live host operation.

import AppKit
import PalanaCore
import SwiftUI
import Testing

@testable import Palana

@MainActor
@Suite("Native table drag integration", .serialized)
struct TableDragIntegrationTests {
    @Test(arguments: [false, true])
    func productionPanes(markedGroup: Bool) async throws {
        _ = NSApplication.shared
        let local = try AddressRig()
        let remote = try AddressRig()
        let directory = try AddressRig.makeTemporaryDirectory()
        let settingsDirectory = try AddressRig.makeTemporaryDirectory()
        defer {
            local.tearDown()
            remote.tearDown()
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: settingsDirectory)
        }
        for name in ["a.txt", "b.txt", "c.txt"] {
            try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("folder"), withIntermediateDirectories: true)
        let columns = ColumnStore(url: settingsDirectory.appendingPathComponent("columns.json"))
        let favorites = FavoritesModel(url: settingsDirectory.appendingPathComponent("favorites.json"))
        let host = NSHostingView(
            rootView: HStack {
                pane(local.pane, columns: columns, favorites: favorites)
                pane(remote.pane, columns: columns, favorites: favorites)
            })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        local.pane.point(host: Engine.localHost, path: directory.path)
        remote.pane.point(host: Engine.localHost, path: directory.path)
        try await poll(message: "panes not ready") { local.pane.status == .ready && remote.pane.status == .ready }
        remote.pane.state.host = "fixture"
        if markedGroup {
            local.pane.state.selection = Set(local.pane.rows.map(\.id))
            remote.pane.state.selection = Set(remote.pane.rows.map(\.id))
        }
        host.layoutSubtreeIfNeeded()
        try await poll(message: "tables not loaded") {
            tables(host).count == 2 && tables(host).allSatisfy { $0.numberOfRows >= 3 }
        }
        try await Task.sleep(for: .milliseconds(500))
        for (index, table) in tables(host).enumerated() {
            for row in [0, 1] {
                try assertDrag(
                    table,
                    row: row,
                    model: index == 0 ? local.pane : remote.pane,
                    columns: columns,
                    favorites: favorites)
            }
        }
    }

    private func assertDrag(
        _ table: NSOutlineView, row: Int, model: PaneModel, columns: ColumnStore, favorites: FavoritesModel
    ) throws {
        let rect = table.rect(ofRow: row)
        for x in [50.0, 150.0, 300.0] {
            let canDrag = table.canDragRows(with: IndexSet(integer: row), at: NSPoint(x: rect.minX + x, y: rect.midY))
            #expect(canDrag)
        }
        let source = try #require(table.dataSource)
        let item = try #require(table.item(atRow: row))
        let writer = source.outlineView?(table, pasteboardWriterForItem: item)
        let board = NSPasteboard(name: .init("palana-native-drag-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        #expect(board.writeObjects([try #require(writer)]))
        let payload = try #require(PaneDropContent.read(from: board))
        #expect(
            payload
                == .selection(
                    DraggedSelection(
                        host: try #require(model.state.host),
                        directory: model.state.path,
                        names: model.state.selection.isEmpty ? [model.rows[row].nameData] : model.rows.map(\.nameData)))
        )
        #expect(PaneDropContent.accepts(board.types ?? []))
        if model.isLocalPane {
            #expect(board.types?.contains(.fileURL) == true)
        } else {
            #expect(board.types == [.palanaInternalSelection])
            #expect(!(writer is NSFilePromiseProvider))
            let provider = try #require(
                pane(model, columns: columns, favorites: favorites)
                    .rowProvider(for: model.rows[row], selectedNames: []))
            #expect(provider.registeredTypeIdentifiers == ["public.json"])
            #expect(!provider.hasItemConformingToTypeIdentifier("public.file-url"))
        }
    }

    private func pane(_ model: PaneModel, columns: ColumnStore, favorites: FavoritesModel) -> PaneView {
        PaneView(
            model: model,
            isFocused: true,
            hosts: [],
            hostMenuDiagnostic: .clear,
            onFocus: {},
            onEditConfig: {},
            onReloadHosts: {},
            onOperation: { _ in },
            fontScale: 1,
            favorites: favorites,
            columnStore: columns,
            onToggleFavorite: {},
            onChooseFavorite: { _ in },
            onStarEntry: { _ in },
            onDropSelection: { _, _ in },
            onDropSelectionOntoFolder: { _, _, _ in },
            onFinderDropOntoFolder: { _, _, _ in },
            onFinderDrop: { _, _ in },
            onDragOutNote: { _ in },
            onShowPanel: {},
            onBack: {},
            onForward: {},
            onZFSVerb: { _ in },
            zfsVerbs: [],
            previewState: .empty)
    }
    private func tables(_ view: NSView) -> [NSOutlineView] {
        if let table = view as? NSOutlineView { return [table] }
        return view.subviews.flatMap { tables($0) }
    }
}
