// PaneDropTargetTests — what the AppKit drop surface reads off a drag
// pasteboard (pālana's selection first, then file URLs, else nothing), and
// which row turns a drop into a folder drop.

import AppKit
import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Pane drop target")
struct PaneDropTargetTests {
    private let selection = DraggedSelection(host: "koan", directory: "/srv", names: [Data("a".utf8)])

    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("palana-drop-test-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    private func entry(_ name: String, _ kind: FileEntry.Kind) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: 0,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "-",
            owner: "u",
            group: "g")
    }

    @Test("pālana's selection wins over the file URLs that ride with it")
    func selectionFirst() throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setData(try JSONEncoder().encode(selection), forType: .palanaPayload)
        item.setString(URL(fileURLWithPath: "/tmp/a").absoluteString, forType: .fileURL)
        pasteboard.writeObjects([item])
        #expect(PaneDropContent.read(from: pasteboard) == .selection(selection))
    }

    @Test("an internal drop does not request an outbound file representation")
    func internalDropDoesNotFetch() throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let provider = LazyDropData()
        let item = NSPasteboardItem()
        item.setData(try JSONEncoder().encode(selection), forType: .palanaPayload)
        item.setDataProvider(provider, forTypes: [.fileURL])
        pasteboard.writeObjects([item])
        #expect(PaneDropContent.read(from: pasteboard) == .selection(selection))
        #expect(provider.requests.isEmpty)
    }

    @Test("hover never loads payloads or changes drag images; release routes once")
    func hoverDoesNotRewriteDrag() async throws {
        let rig = try AddressRig()
        let directory = try AddressRig.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        rig.pane.point(host: Engine.localHost, path: directory.path)
        try await poll(message: "drop pane not ready") { rig.pane.status == .ready }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let provider = LazyDropData()
        provider.payload = try JSONEncoder().encode(selection)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.palanaPayload])
        pasteboard.writeObjects([item])
        let drag = DropInfo(pasteboard: pasteboard)
        let catcher = PaneDropTarget.Catcher(frame: .zero)
        catcher.model = rig.pane
        var deliveries: [PaneDropContent] = []
        var targeted = false
        catcher.onTargeted = { targeted = $0 }
        catcher.onDrop = { content, _, _ in deliveries.append(content) }
        #expect(catcher.draggingEntered(drag) == .copy)
        #expect(catcher.draggingUpdated(drag) == .copy)
        #expect(targeted)
        #expect(provider.requests.isEmpty)
        #expect(deliveries.isEmpty)
        #expect(catcher.performDragOperation(drag))
        catcher.draggingEnded(drag)
        #expect(!targeted)
        #expect(deliveries == [.selection(selection)])
        #expect(drag.imageAccesses == 0)
    }

    @Test("a Finder drop reads as its file URLs")
    func filesOnly() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.txt")]
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        #expect(PaneDropContent.read(from: pasteboard) == .files(urls))
    }

    @Test("unrelated JSON falls back to actual file URLs")
    func undecodableSelection() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setData(Data("nope".utf8), forType: .palanaPayload)
        pasteboard.writeObjects([item])
        #expect(PaneDropContent.read(from: pasteboard) == nil)
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/tmp/x")
        let withFile = NSPasteboardItem()
        withFile.setData(Data("nope".utf8), forType: .palanaPayload)
        withFile.setString(url.absoluteString, forType: .fileURL)
        pasteboard.writeObjects([withFile])
        #expect(PaneDropContent.read(from: pasteboard) == .files([url]))
    }

    @Test("a pasteboard with neither carries no drop")
    func nothing() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("just text", forType: .string)
        #expect(PaneDropContent.read(from: pasteboard) == nil)
        #expect(!PaneDropContent.accepts([.string]))
        #expect(PaneDropContent.accepts([.fileURL]))
        #expect(PaneDropContent.accepts([.palanaPayload]))
    }

    @Test("only a directory row is a folder drop; anything else is the pane")
    func folderRows() {
        let rows = [entry("media", .directory), entry("notes.txt", .file), entry("link", .symlink)]
        #expect(PaneDropTarget.folder(at: 0, in: rows) == rows[0])
        #expect(PaneDropTarget.folder(at: 1, in: rows) == nil)
        #expect(PaneDropTarget.folder(at: 2, in: rows) == nil)
        #expect(PaneDropTarget.folder(at: -1, in: rows) == nil)
        #expect(PaneDropTarget.folder(at: 3, in: rows) == nil)
    }

    @Test("the catcher lets every click through")
    func clicksPassThrough() {
        let catcher = PaneDropTarget.Catcher(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(catcher.hitTest(NSPoint(x: 50, y: 50)) == nil)
        #expect(catcher.registeredDraggedTypes.contains(.palanaPayload))
        #expect(catcher.registeredDraggedTypes.contains(.fileURL))
    }
}

/// A promised representation records every request made by the receiver.
private final class LazyDropData: NSObject, NSPasteboardItemDataProvider {
    var requests: [NSPasteboard.PasteboardType] = []
    var payload = Data()

    func pasteboard(
        _ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
    ) {
        requests.append(type)
        item.setData(payload, forType: type)
    }
}

/// A drag whose geometry methods record any attempt to alter its images.
@MainActor
private final class DropInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var imageAccesses = 0
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .move] }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default { didSet { imageAccesses += 1 } }
    var animatesToDestination = false { didSet { imageAccesses += 1 } }
    var numberOfValidItemsForDrop = 0 { didSet { imageAccesses += 1 } }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }

    func slideDraggedImage(to screenPoint: NSPoint) { imageAccesses += 1 }
    override nonisolated func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        imageAccesses += 1
    }
}
