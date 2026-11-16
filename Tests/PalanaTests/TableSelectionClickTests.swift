// TableSelectionClickTests — the table is told pālana's marks (or the cursor
// alone), and a click it reports comes back in pālana's manners: a plain
// click moves the cursor and keeps the marks, ⇧ extends from the cursor,
// ⌘/⌥ toggles the clicked row, a click on empty space drops the cursor.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Table selection clicks")
struct TableSelectionClickTests {
    private func id(_ name: String) -> Data { Data(name.utf8) }

    /// A pane standing ready on a temp folder holding a … e.
    private func pane() async throws -> (AddressRig, URL) {
        let rig = try AddressRig()
        let directory = try AddressRig.makeTemporaryDirectory()
        for name in ["a", "b", "c", "d", "e"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        rig.pane.point(host: Engine.localHost, path: directory.path)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready && rig.pane.rows.count == 5 }
        return (rig, directory)
    }

    @Test("the table sees the marks, or the cursor alone")
    func tableSelection() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("b")
        model.state.selection = []
        #expect(model.tableSelection == [id("b")])
        model.state.selection = [id("a"), id("c")]
        #expect(model.tableSelection == [id("a"), id("c")])
        model.state.cursor = nil
        model.state.selection = []
        #expect(model.tableSelection.isEmpty)
    }

    @Test("a plain click moves the cursor and keeps the marks")
    func plainClick() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("a")
        model.state.selection = [id("a"), id("c")]
        model.applyTableClick([id("d")], shift: false, toggle: false)
        #expect(model.state.cursor == id("d"))
        #expect(model.state.selection == [id("a"), id("c")])
    }

    @Test("a click on empty space drops the cursor")
    func emptyClick() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("a")
        model.applyTableClick([], shift: false, toggle: false)
        #expect(model.state.cursor == nil)
    }

    @Test("⇧-click extends the marks from the cursor, whichever way")
    func shiftClick() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("b")
        model.state.selection = []
        model.applyTableClick([id("b"), id("c"), id("d")], shift: true, toggle: false)
        #expect(model.state.selection == [id("b"), id("c"), id("d")])
        #expect(model.state.cursor == id("d"))

        model.state.selection = []
        model.state.cursor = id("d")
        model.applyTableClick([id("a"), id("b"), id("c"), id("d")], shift: true, toggle: false)
        #expect(model.state.selection == [id("a"), id("b"), id("c"), id("d")])
        #expect(model.state.cursor == id("a"))

        model.applyTableClick([], shift: true, toggle: false)
        #expect(model.state.cursor == id("a"), "an empty report changes nothing")

        // Marks present: the table extends from its anchor (a marked row),
        // and the clicked row is the end that was not selected before.
        model.state.selection = [id("c"), id("e")]
        model.state.cursor = id("a")
        model.applyTableClick([id("b"), id("c"), id("d"), id("e")], shift: true, toggle: false)
        #expect(model.state.cursor == id("b"))
        #expect(model.state.selection == [id("a"), id("b"), id("c"), id("e")])
    }

    @Test("⌘/⌥-click toggles the clicked row in and out")
    func toggleClick() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("a")
        model.state.selection = []
        model.applyTableClick([id("a"), id("c")], shift: false, toggle: true)
        #expect(model.state.selection == [id("c")])
        #expect(model.state.cursor == id("c"))

        model.state.selection = [id("a"), id("c")]
        model.applyTableClick([id("a")], shift: false, toggle: true)
        #expect(model.state.selection == [id("a")])
        #expect(model.state.cursor == id("c"))

        model.applyTableClick([id("a"), id("b"), id("e")], shift: false, toggle: true)
        #expect(model.state.selection == [id("a")], "more than one change is not a toggle click")
    }

    @Test("⇧-click on a marked row unmarks the run from the cursor to it")
    func shiftUnmarks() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.selection = [id("a"), id("b"), id("c"), id("d")]
        model.state.cursor = id("d")
        model.applyTableClick([id("b")], clicked: id("b"), shift: true, toggle: false)
        #expect(model.state.selection == [id("a")])
        #expect(model.state.cursor == id("b"))
        // With no cursor, only the clicked row comes off.
        model.state.selection = [id("a"), id("c")]
        model.state.cursor = nil
        model.applyTableClick([], clicked: id("c"), shift: true, toggle: false)
        #expect(model.state.selection == [id("a")])
    }

    @Test("the clicked row, when the table says, decides every kind of click")
    func clickedRowDecides() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.selection = [id("a"), id("c")]
        model.state.cursor = id("a")
        model.applyTableClick([id("a"), id("c")], clicked: id("e"), shift: false, toggle: false)
        #expect(model.state.cursor == id("e"))
        #expect(model.state.selection == [id("a"), id("c")])
        model.applyTableClick([id("a")], clicked: id("c"), shift: false, toggle: true)
        #expect(model.state.selection == [id("a")])
        #expect(model.state.cursor == id("c"))
        model.applyTableClick([id("a"), id("b"), id("c")], clicked: id("c"), shift: true, toggle: false)
        #expect(model.state.selection == [id("a"), id("c")], "c is unmarked, so ⇧ marks the run c…c")
    }
}
