// Native table selection must survive the bridge into pane operation subjects.
// AppKit owns mouse modifiers and range anchors; the pane owns the marks and cursor.

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

    @Test("a native single-row click clears previous marks and changes operation subjects")
    func plainClick() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("a")
        model.state.selection = [id("a"), id("c")]
        model.applyTableClick([id("d")], clicked: id("d"))
        #expect(model.state.selection.isEmpty)
        #expect(model.state.cursor == id("d"))
        #expect(model.operationSubjects.map(\.id) == [id("d")])
    }

    @Test("a native range may grow, shrink, or reverse without preserving old marks")
    func nativeRanges() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.applyTableClick([id("c")], clicked: id("c"))
        model.applyTableClick([id("c"), id("d"), id("e")], clicked: id("e"))
        #expect(model.operationSubjects.map(\.id) == [id("c"), id("d"), id("e")])
        model.applyTableClick([id("c"), id("d")], clicked: id("d"))
        #expect(model.operationSubjects.map(\.id) == [id("c"), id("d")])
        model.applyTableClick([id("a"), id("b"), id("c")], clicked: id("a"))
        #expect(model.operationSubjects.map(\.id) == [id("a"), id("b"), id("c")])
        #expect(model.state.cursor == id("a"))
    }

    @Test("native Command selection retains the first row and toggles nonadjacent rows")
    func noncontiguousSelection() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.applyTableClick([id("a")], clicked: id("a"))
        model.applyTableClick([id("a"), id("c")], clicked: id("c"))
        model.applyTableClick([id("a"), id("c"), id("e")], clicked: id("e"))
        #expect(model.operationSubjects.map(\.id) == [id("a"), id("c"), id("e")])
        model.applyTableClick([id("a"), id("e")], clicked: id("c"))
        #expect(model.operationSubjects.map(\.id) == [id("a"), id("e")])
        #expect(model.state.cursor == id("e"), "deselected c must not become the cursor highlight")
    }

    @Test("deselecting the last row clears both marks and the cursor fallback")
    func emptySelection() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("a")
        model.state.selection = [id("a")]
        model.applyTableClick([], clicked: id("a"))
        #expect(model.state.cursor == nil)
        #expect(model.tableSelection.isEmpty)
        #expect(model.operationSubjects.isEmpty)
    }

    @Test("a native drag that keeps its selected cohort does not collapse to the clicked row")
    func preserveDragCohort() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.selection = [id("a"), id("c"), id("e")]
        model.state.cursor = id("e")
        model.applyTableClick(model.tableSelection, clicked: id("c"))
        #expect(model.operationSubjects.map(\.id) == [id("a"), id("c"), id("e")])
        #expect(model.state.cursor == id("c"))
        // Mouse-up without a drag reports a single native selection.
        model.applyTableClick([id("c")], clicked: id("c"))
        #expect(model.operationSubjects.map(\.id) == [id("c")])
        #expect(model.state.selection.isEmpty)
    }

    @Test("without a clicked row, the cursor stays selected or follows display order")
    func missingClickedRow() async throws {
        let (rig, directory) = try await pane()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = rig.pane
        model.state.cursor = id("e")
        model.applyTableClick([id("b"), id("d")])
        #expect(model.state.cursor == id("b"))
        model.applyTableClick([id("a"), id("b"), id("d")])
        #expect(model.state.cursor == id("b"))
    }
}
