// The contract models — FileEntry identity and display, PaneState
// ordering. ho-05 composes against selections and ho-07 renders this
// shape; the battery pins what they will lean on.

import Foundation
import Testing

@testable import PalanaCore

/// Shared entry builder for the model batteries.
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

@Suite("FileEntry")
struct FileEntryTests {
    @Test("identity is the name bytes")
    func identity() {
        #expect(makeEntry("notes.txt").id == Data("notes.txt".utf8))
    }

    @Test("undecodable name bytes still display, lossily, without dying")
    func lossyDisplay() {
        var bytes = Data("caf".utf8)
        bytes.append(contentsOf: [0xE9, 0x2E])  // Latin-1 é — not valid UTF-8
        var entry = makeEntry("")
        entry.nameData = bytes
        #expect(!entry.name.isEmpty)
        #expect(entry.nameData == bytes, "the truth is untouched by the face")
    }

    @Test("symlink target displays through the same lossy face")
    func targetDisplay() {
        var entry = makeEntry("alink", kind: .symlink)
        entry.symlinkTarget = Data("plain".utf8)
        #expect(entry.symlinkTargetName == "plain")
        #expect(makeEntry("plain").symlinkTargetName == nil)
    }
}

@Suite("PaneState")
struct PaneStateTests {
    private static let entries = [
        makeEntry("file10", size: 5, mtime: 30),
        makeEntry("file2", size: 20, mtime: 10),
        makeEntry("alpha", size: 5, mtime: 20),
    ]

    @Test("a fresh pane points nowhere, sorted by name ascending")
    func defaults() {
        let pane = PaneState()
        #expect(pane.host == nil)
        #expect(pane.path == "/")
        #expect(pane.entries.isEmpty)
        #expect(pane.sort == .byName)
    }

    @Test("name sort is Finder order: file2 before file10")
    func finderOrder() {
        let pane = PaneState(entries: Self.entries)
        #expect(pane.sortedEntries().map(\.name) == ["alpha", "file2", "file10"])
    }

    @Test("size sort orders by bytes, ties broken by name bytes")
    func sizeOrder() {
        var pane = PaneState(entries: Self.entries)
        pane.sort = PaneState.Sort(key: .size)
        #expect(pane.sortedEntries().map(\.name) == ["alpha", "file10", "file2"])
    }

    @Test("modified sort orders by time; descending flips whole")
    func modifiedOrder() {
        var pane = PaneState(entries: Self.entries)
        pane.sort = PaneState.Sort(key: .modified, ascending: false)
        #expect(pane.sortedEntries().map(\.name) == ["file10", "alpha", "file2"])
    }

    @Test("selection and cursor carry entry identities")
    func selectionByIdentity() {
        var pane = PaneState(entries: Self.entries)
        pane.selection = [Data("alpha".utf8)]
        pane.cursor = Data("file2".utf8)
        #expect(pane.selection.contains(Data("alpha".utf8)))
        #expect(pane.cursor == Data("file2".utf8))
    }
}
