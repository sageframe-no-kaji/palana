// RowDragGateTests — a remote pane must yield no drag writer, including
// SwiftUI's fallback writer, before the native drag session can begin.

import AppKit
import Testing

@testable import Palana

@MainActor
@Suite("Row drag source gate", .serialized)
struct RowDragGateTests {
    @Test("remote and unpointed panes cannot invoke either writer")
    func blocksRemote() throws {
        let model = try AddressRig().pane
        let table = NSOutlineView()
        let source = GateSource()
        table.dataSource = source
        var customCalls = 0
        RowWriterHook.install(
            on: table,
            isEnabled: { model.permitsRowDrag },
            hook: { _ in
                customCalls += 1
                return NSPasteboardItem()
            })
        for host: String? in [nil, "koan", "localhost", "fixture"] {
            model.state.host = host
            #expect(writer(source, table) == nil)
        }
        #expect(customCalls == 0)
        #expect(source.calls == 0, "nil must not fall back to SwiftUI's remote writer")
    }

    @Test("a reused table follows host changes without retaining local drag permission")
    func switchesHosts() throws {
        let model = try AddressRig().pane
        let table = NSOutlineView()
        let source = GateSource()
        table.dataSource = source
        let item = NSPasteboardItem()
        RowWriterHook.install(on: table, isEnabled: { model.permitsRowDrag }, hook: { _ in item })
        model.state.host = Engine.localHost
        #expect((writer(source, table) as? NSPasteboardItem) === item)
        model.state.host = "koan"
        #expect(writer(source, table) == nil)
        model.state.host = Engine.localHost
        #expect((writer(source, table) as? NSPasteboardItem) === item)
        #expect(source.calls == 0)
    }

    @Test("local fallback and unrelated tables retain their original writer")
    func preservesFallback() throws {
        let model = try AddressRig().pane
        let hooked = NSOutlineView()
        let other = NSOutlineView()
        let source = GateSource()
        hooked.dataSource = source
        other.dataSource = source
        RowWriterHook.install(on: hooked, isEnabled: { model.permitsRowDrag }, hook: { _ in nil })
        model.state.host = Engine.localHost
        #expect((writer(source, hooked) as? NSPasteboardItem) === source.item)
        model.state.host = "koan"
        #expect(writer(source, hooked) == nil)
        #expect((writer(source, other) as? NSPasteboardItem) === source.item)
        #expect(source.calls == 2)
    }
}

@MainActor
private func writer(_ source: any NSOutlineViewDataSource, _ table: NSOutlineView) -> (any NSPasteboardWriting)? {
    source.outlineView?(table, pasteboardWriterForItem: "row")
}

@MainActor
private final class GateSource: NSObject, NSOutlineViewDataSource {
    var calls = 0
    let item = NSPasteboardItem()

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        calls += 1
        return self.item
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { 0 }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { "unused" }
    func outlineView(
        _ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?
    ) -> Any? { nil }
}
