// The pane transitions — the grammar's state moves, pinned pure. The
// Surface dispatches intents into these; everything that can be wrong
// about navigation is provable here without a window. Hot moves take
// the displayed rows the way the caller passes them — computed once
// per display change, never per keystroke.

import Foundation
import Testing

@testable import PalanaCore

/// Entry builder for the transition batteries.
private func makeEntry(
    _ name: String, kind: FileEntry.Kind = .file, size: Int64 = 0, mtime: Double = 0
) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: mtime),
        permissions: "644",
        owner: "op",
        group: "op")
}

private func identity(_ name: String) -> Data {
    Data(name.utf8)
}

@Suite("Pane transitions — cursor")
struct PaneCursorTests {
    private static let entries = [
        makeEntry("alpha"),
        makeEntry("bravo"),
        makeEntry("charlie"),
        makeEntry("delta"),
    ]

    @Test("a downward move with no cursor lands on the first row")
    func footingDown() {
        var pane = PaneState(entries: Self.entries)
        pane.moveCursor(by: 1, in: pane.sortedEntries())
        #expect(pane.cursor == identity("alpha"))
    }

    @Test("an upward move with no cursor lands on the last row")
    func footingUp() {
        var pane = PaneState(entries: Self.entries)
        pane.moveCursor(by: -1, in: pane.sortedEntries())
        #expect(pane.cursor == identity("delta"))
    }

    @Test("moves clamp at both ends")
    func clamping() {
        var pane = PaneState(entries: Self.entries, cursor: identity("charlie"))
        pane.moveCursor(by: 100, in: pane.sortedEntries())
        #expect(pane.cursor == identity("delta"))
        pane.moveCursor(by: -100, in: pane.sortedEntries())
        #expect(pane.cursor == identity("alpha"))
    }

    @Test("moves walk the displayed order, not the arrival order")
    func displayedOrder() {
        var pane = PaneState(entries: [makeEntry("file10"), makeEntry("file2")])
        pane.moveCursor(by: 1, in: pane.sortedEntries())
        #expect(pane.cursor == identity("file2"), "Finder order puts file2 first")
        pane.moveCursor(by: 1, in: pane.sortedEntries())
        #expect(pane.cursor == identity("file10"))
    }

    @Test("top and bottom land on the displayed extremes")
    func topAndBottom() {
        var pane = PaneState(entries: Self.entries, cursor: identity("bravo"))
        pane.moveCursorToBottom(in: pane.sortedEntries())
        #expect(pane.cursor == identity("delta"))
        pane.moveCursorToTop(in: pane.sortedEntries())
        #expect(pane.cursor == identity("alpha"))
    }

    @Test("an empty pane keeps the cursor nil through every move")
    func emptyPane() {
        var pane = PaneState()
        pane.moveCursor(by: 1, in: pane.sortedEntries())
        #expect(pane.cursor == nil)
        pane.moveCursorToTop(in: pane.sortedEntries())
        #expect(pane.cursor == nil)
    }
}

@Suite("Pane transitions — selection")
struct PaneSelectionTests {
    private static let entries = [
        makeEntry("alpha"),
        makeEntry("bravo"),
        makeEntry(".hidden"),
    ]

    @Test("space toggles the cursor entry and advances")
    func toggleAndAdvance() {
        var pane = PaneState(entries: Self.entries, cursor: identity("alpha"))
        pane.toggleSelectionAtCursorAndAdvance(in: pane.sortedEntries())
        #expect(pane.selection == [identity("alpha")])
        #expect(pane.cursor == identity("bravo"))
        pane.moveCursor(by: -1, in: pane.sortedEntries())
        pane.toggleSelectionAtCursorAndAdvance(in: pane.sortedEntries())
        #expect(pane.selection.isEmpty, "the second toggle unmarks")
    }

    @Test("space with no cursor does nothing")
    func noCursorNoop() {
        var pane = PaneState(entries: Self.entries)
        pane.toggleSelectionAtCursorAndAdvance(in: pane.sortedEntries())
        #expect(pane.selection.isEmpty)
    }

    @Test("select all takes the displayed entries only")
    func selectAllDisplayed() {
        var pane = PaneState(entries: Self.entries)
        pane.selectAll(in: pane.sortedEntries())
        #expect(pane.selection == [identity("alpha"), identity("bravo")])
    }

    @Test("clear selection empties it")
    func clear() {
        var pane = PaneState(entries: Self.entries, selection: [identity("alpha")])
        pane.clearSelection()
        #expect(pane.selection.isEmpty)
    }
}

@Suite("Pane transitions — hidden, sort, replace")
struct PaneDisplayTests {
    private static let entries = [
        makeEntry("visible", size: 1, mtime: 10),
        makeEntry(".dotfile", size: 2, mtime: 20),
    ]

    @Test("dotfiles hide by default and toggle into view")
    func hiddenToggle() {
        var pane = PaneState(entries: Self.entries)
        #expect(pane.sortedEntries().map(\.name) == ["visible"])
        pane.toggleHidden()
        #expect(pane.sortedEntries().map(\.name) == [".dotfile", "visible"])
    }

    @Test("hiding prunes a hidden cursor and hidden selections")
    func hidingReconciles() {
        var pane = PaneState(entries: Self.entries, showHidden: true)
        pane.selectAll(in: pane.sortedEntries())
        pane.cursor = identity(".dotfile")
        pane.toggleHidden()
        #expect(pane.selection == [identity("visible")])
        #expect(pane.cursor == identity("visible"))
    }

    @Test("hidden judgment reads the bytes, not the face")
    func hiddenBytes() {
        #expect(makeEntry(".profile").isHidden)
        #expect(!makeEntry("readme").isHidden)
    }

    @Test("the same sort key again flips direction, a new key resets ascending")
    func sortFlip() {
        var pane = PaneState(entries: Self.entries)
        pane.setSort(key: .size)
        #expect(pane.sort == PaneState.Sort(key: .size, ascending: true))
        pane.setSort(key: .size)
        #expect(pane.sort == PaneState.Sort(key: .size, ascending: false))
        pane.setSort(key: .modified)
        #expect(pane.sort == PaneState.Sort(key: .modified, ascending: true))
    }

    @Test("replacing entries keeps a surviving cursor and prunes dead selections")
    func replaceKeepsSurvivors() {
        var pane = PaneState(
            entries: Self.entries,
            selection: [identity("visible")],
            cursor: identity("visible"))
        pane.replaceEntries([makeEntry("visible"), makeEntry("newcomer")])
        #expect(pane.cursor == identity("visible"))
        #expect(pane.selection == [identity("visible")])
    }

    @Test("replacing entries lands a dead cursor on the first row")
    func replaceRefoots() {
        var pane = PaneState(entries: Self.entries, cursor: identity("visible"))
        pane.replaceEntries([makeEntry("bravo"), makeEntry("alpha")])
        #expect(pane.cursor == identity("alpha"))
        #expect(pane.selection.isEmpty)
    }

    @Test("a fresh listing gives a nil cursor footing on the first row")
    func replaceFootsFreshPane() {
        var pane = PaneState()
        pane.replaceEntries([makeEntry("bravo"), makeEntry("alpha")])
        #expect(pane.cursor == identity("alpha"))
    }

    @Test("replacing with nothing clears the cursor")
    func replaceEmpty() {
        var pane = PaneState(entries: Self.entries, cursor: identity("visible"))
        pane.replaceEntries([])
        #expect(pane.cursor == nil)
    }
}
