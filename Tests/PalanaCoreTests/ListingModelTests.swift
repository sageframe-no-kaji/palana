// The contract models — FileEntry identity and display, PaneState
// ordering. ho-05 composes against selections and ho-07 renders this
// shape; the battery pins what they will lean on.

import Foundation
import Testing

@testable import PalanaCore

/// Shared entry builder for the model batteries.
private func makeEntry(
    _ name: String,
    kind: FileEntry.Kind = .file,
    size: Int64 = 0,
    mtime: Double = 0,
    created: Date? = nil,
    changed: Date? = nil,
    permissions: String = "644",
    owner: String = "op",
    group: String = "op"
) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: mtime),
        created: created,
        changed: changed,
        permissions: permissions,
        owner: owner,
        group: group)
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

// MARK: — New sort keys (ho-9.8)

/// Extracts the display name from a `FileEntry` for test assertions.
private func names(_ entries: [FileEntry]) -> [String] { entries.map(\.name) }

@Suite("PaneState new sort keys")
struct PaneStateNewSortKeyTests {
    // MARK: — Created

    @Test("created sort ascending, nils last")
    func createdAscending() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_001_000)
        let entries = [
            makeEntry("b", created: t2),
            makeEntry("a", created: nil),  // nil → last
            makeEntry("c", created: t1),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .created, ascending: true)
        #expect(names(pane.sortedEntries()) == ["c", "b", "a"])
    }

    @Test("created sort descending, nils still last")
    func createdDescending() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_001_000)
        let entries = [
            makeEntry("b", created: t2),
            makeEntry("a", created: nil),  // nil → still last when descending
            makeEntry("c", created: t1),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .created, ascending: false)
        // descending reverses the non-nil block: t2 > t1 → ["b", "c"], nil last
        #expect(names(pane.sortedEntries()) == ["b", "c", "a"])
    }

    @Test("created sort: two nils break tie on name bytes")
    func createdNilTie() {
        let entries = [makeEntry("z", created: nil), makeEntry("a", created: nil)]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .created, ascending: true)
        #expect(names(pane.sortedEntries()) == ["a", "z"])
    }

    // MARK: — Changed

    @Test("changed sort ascending, nils last")
    func changedAscending() {
        let t2 = Date(timeIntervalSince1970: 1_700_001_000)
        let t3 = Date(timeIntervalSince1970: 1_700_002_000)
        let entries = [
            makeEntry("b", changed: t3),
            makeEntry("a", changed: nil),
            makeEntry("c", changed: t2),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .changed, ascending: true)
        #expect(names(pane.sortedEntries()) == ["c", "b", "a"])
    }

    @Test("changed sort descending, nils still last")
    func changedDescending() {
        let t2 = Date(timeIntervalSince1970: 1_700_001_000)
        let t3 = Date(timeIntervalSince1970: 1_700_002_000)
        let entries = [
            makeEntry("b", changed: t3),
            makeEntry("a", changed: nil),
            makeEntry("c", changed: t2),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .changed, ascending: false)
        #expect(names(pane.sortedEntries()) == ["b", "c", "a"])
    }

    // MARK: — Permissions

    @Test("permissions sort ascending, ties on name bytes")
    func permissionsAscending() {
        let entries = [
            makeEntry("b", permissions: "755"),
            makeEntry("a", permissions: "644"),
            makeEntry("c", permissions: "644"),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .permissions, ascending: true)
        // "644" < "755"; tie between a and c breaks on name bytes
        #expect(names(pane.sortedEntries()) == ["a", "c", "b"])
    }

    @Test("permissions sort descending")
    func permissionsDescending() {
        let entries = [
            makeEntry("b", permissions: "755"),
            makeEntry("a", permissions: "644"),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .permissions, ascending: false)
        #expect(names(pane.sortedEntries()) == ["b", "a"])
    }

    // MARK: — Owner

    @Test("owner sort ascending, ties on name bytes")
    func ownerAscending() {
        let entries = [
            makeEntry("b", owner: "zach"),
            makeEntry("a", owner: "alice"),
            makeEntry("c", owner: "alice"),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .owner, ascending: true)
        #expect(names(pane.sortedEntries()) == ["a", "c", "b"])
    }

    @Test("owner sort descending")
    func ownerDescending() {
        let entries = [
            makeEntry("b", owner: "zach"),
            makeEntry("a", owner: "alice"),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .owner, ascending: false)
        #expect(names(pane.sortedEntries()) == ["b", "a"])
    }

    // MARK: — Group

    @Test("group sort ascending, ties on name bytes")
    func groupAscending() {
        let entries = [
            makeEntry("b", group: "wheel"),
            makeEntry("a", group: "admin"),
            makeEntry("c", group: "admin"),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .group, ascending: true)
        #expect(names(pane.sortedEntries()) == ["a", "c", "b"])
    }

    @Test("group sort descending")
    func groupDescending() {
        let entries = [
            makeEntry("b", group: "wheel"),
            makeEntry("a", group: "admin"),
        ]
        var pane = PaneState(entries: entries, showHidden: true)
        pane.sort = PaneState.Sort(key: .group, ascending: false)
        #expect(names(pane.sortedEntries()) == ["b", "a"])
    }
}

// MARK: — Backward-compatible decode (ho-9.8)

@Suite("FileEntry backward-compatible decode")
struct FileEntryBackwardCompatDecodeTests {
    /// A minimal pre-9.8 JSON shape: no `created`, no `changed` fields.
    ///
    /// Session and cache files written before ho-9.8 land on disk with
    /// this shape. Decoding must produce nil for both timestamps, not throw.
    @Test("pre-9.8 JSON without created/changed decodes to nil timestamps")
    func oldShapeDecodesNilTimestamps() throws {
        // Hand-written minimal fixture — intentionally omits created and changed.
        let json = """
            {
              "nameData": "\(Data("notes.txt".utf8).base64EncodedString())",
              "kind": "file",
              "size": 1024,
              "modified": 1700000000.0,
              "permissions": "644",
              "owner": "op",
              "group": "staff"
            }
            """
        let data = try #require(json.data(using: .utf8))
        let entry = try JSONDecoder().decode(FileEntry.self, from: data)
        #expect(entry.name == "notes.txt")
        #expect(entry.size == 1024)
        #expect(entry.created == nil, "old-shape JSON has no created field — must decode nil")
        #expect(entry.changed == nil, "old-shape JSON has no changed field — must decode nil")
    }

    @Test("current JSON with created and changed round-trips cleanly")
    func newShapeRoundTrips() throws {
        let original = makeEntry(
            "file.txt",
            created: Date(timeIntervalSince1970: 1_698_000_000),
            changed: Date(timeIntervalSince1970: 1_700_000_500))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileEntry.self, from: encoded)
        #expect(decoded.created == original.created)
        #expect(decoded.changed == original.changed)
    }
}
