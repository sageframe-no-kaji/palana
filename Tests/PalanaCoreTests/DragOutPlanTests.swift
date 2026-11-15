// DragOutPlan — every branch of a drag leaving a pane: local entries are
// paths, remote regular files are downloads with their size, and remote
// folders, links, specials, oversize files, unlisted and unrepresentable
// names refuse with a line the transcript can show.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Drag-out plan")
struct DragOutPlanTests {
    private let local = PalanaCore.localHostName

    private func entry(_ name: String, _ kind: FileEntry.Kind, size: Int64 = 0) -> FileEntry {
        entry(bytes: Data(name.utf8), kind, size: size)
    }

    private func entry(bytes: Data, _ kind: FileEntry.Kind, size: Int64 = 0) -> FileEntry {
        let epoch = Date(timeIntervalSince1970: 0)
        return FileEntry(
            nameData: bytes,
            kind: kind,
            size: size,
            modified: epoch,
            permissions: "-rw-r--r--",
            owner: "u",
            group: "g")
    }

    private func name(_ text: String) -> Data { Data(text.utf8) }

    /// The plan for `names` (as text) dragged out of `host:directory`.
    private func plan(_ host: String, _ directory: String, _ names: [String], _ entries: [FileEntry]) -> [DragOutItem] {
        DragOutPlan.items(host: host, directory: directory, names: names.map(name), entries: entries)
    }

    @Test("a local multi-selection gives one local file per entry, in order")
    func localSelection() {
        let entries = [entry("a.txt", .file), entry("b", .directory), entry("c.png", .file, size: 9)]
        let items = plan(local, "/Users/me/Docs", ["a.txt", "b", "c.png"], entries)
        let expected: [DragOutItem] = [
            .localFile(path: "/Users/me/Docs/a.txt"),
            .localFile(path: "/Users/me/Docs/b"),
            .localFile(path: "/Users/me/Docs/c.png"),
        ]
        #expect(items == expected)
    }

    @Test("a local symlink is a local file — the receiver decides")
    func localLink() {
        #expect(plan(local, "/", ["l"], [entry("l", .symlink)]) == [.localFile(path: "/l")])
    }

    @Test("a remote regular file is a download carrying its size")
    func remoteFile() {
        let items = plan("koan", "/srv/", ["song.flac"], [entry("song.flac", .file, size: 31_337)])
        #expect(items == [.remoteFile(host: "koan", path: "/srv/song.flac", size: 31_337)])
    }

    @Test("a remote folder refuses, naming the place")
    func remoteFolder() {
        let reason = DragOutRefusal.remoteFolder(location: "koan:/srv/media")
        let items = plan("koan", "/srv", ["media"], [entry("media", .directory)])
        #expect(items == [.refused(name: "media", reason: reason)])
        let line = "koan:/srv/media is a folder — drag out files, or copy it to a local pane first"
        #expect(reason.line(name: "media") == line)
    }

    @Test("a remote symlink refuses — a folder behind it cannot be told from a file")
    func remoteLink() {
        let reason = DragOutRefusal.remoteLink(location: "koan:/srv/current")
        let items = plan("koan", "/srv", ["current"], [entry("current", .symlink)])
        #expect(items == [.refused(name: "current", reason: reason)])
        #expect(reason.line(name: "current").contains("is a link"))
    }

    @Test("a remote device or pipe refuses")
    func remoteSpecial() {
        let reason = DragOutRefusal.remoteSpecial(location: "koan:/dev/null")
        let items = plan("koan", "/dev", ["null"], [entry("null", .other)])
        #expect(items == [.refused(name: "null", reason: reason)])
        #expect(reason.line(name: "null").contains("not a regular"))
    }

    @Test("a remote file over the drag ceiling refuses; one at the ceiling downloads")
    func remoteCeiling() {
        let limit = DragOutPlan.remoteCeiling
        let entries = [entry("big.iso", .file, size: limit + 1), entry("edge.iso", .file, size: limit)]
        let reason = DragOutRefusal.tooLarge(location: "koan:/v/big.iso", limit: limit)
        let expected: [DragOutItem] = [
            .refused(name: "big.iso", reason: reason),
            .remoteFile(host: "koan", path: "/v/edge.iso", size: limit),
        ]
        #expect(plan("koan", "/v", ["big.iso", "edge.iso"], entries) == expected)
        #expect(reason.line(name: "big.iso").hasPrefix("koan:/v/big.iso is larger than"))
    }

    @Test("a name that is not UTF-8 refuses, locally and remotely")
    func unrepresentable() {
        let bad = Data([0x66, 0xFF, 0x6F])
        let badEntry = entry(bytes: bad, .file, size: 1)
        for host in [local, "koan"] {
            let items = DragOutPlan.items(host: host, directory: "/x", names: [bad], entries: [badEntry])
            #expect(items == [.refused(name: badEntry.name, reason: .unrepresentableName)])
        }
        #expect(DragOutRefusal.unrepresentableName.line(name: "f?o").contains("not valid UTF-8"))
    }

    @Test("a name gone from the listing refuses")
    func notListed() {
        #expect(plan("koan", "/x", ["gone"], []) == [.refused(name: "gone", reason: .notListed)])
        #expect(DragOutRefusal.notListed.line(name: "gone").contains("no longer listed"))
    }

    @Test("a mixed remote drag keeps its files and refuses only the folder")
    func mixedRemote() {
        let entries = [entry("a.txt", .file, size: 3), entry("media", .directory)]
        let expected: [DragOutItem] = [
            .remoteFile(host: "koan", path: "/srv/a.txt", size: 3),
            .refused(name: "media", reason: .remoteFolder(location: "koan:/srv/media")),
        ]
        #expect(plan("koan", "/srv", ["a.txt", "media"], entries) == expected)
    }

    @Test("a dragged row inside the selection carries the whole selection")
    func draggedInsideSelection() {
        let selected = [name("a"), name("b"), name("c")]
        #expect(DragOutPlan.names(dragged: name("b"), selectedInOrder: selected) == selected)
    }

    @Test("a dragged row outside the selection carries that row only")
    func draggedOutsideSelection() {
        let selected = [name("a"), name("b")]
        #expect(DragOutPlan.names(dragged: name("z"), selectedInOrder: selected) == [name("z")])
        #expect(DragOutPlan.names(dragged: name("z"), selectedInOrder: []) == [name("z")])
    }
}
