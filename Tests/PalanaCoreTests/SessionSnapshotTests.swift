// The session store — the workbench memory, round-tripped against
// temp directories. Absent and corrupt files mean a fresh start,
// never a crash.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SessionSnapshot")
struct SessionSnapshotTests {
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-session-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    @Test("a snapshot round-trips through the store")
    func roundTrip() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = SessionSnapshot(
            left: SessionSnapshot.Pane(
                host: "jodo",
                path: "/tank/sage",
                sort: PaneState.Sort(key: .size),
                showHidden: true),
            right: SessionSnapshot.Pane(host: "koan", path: "/rpool"),
            focused: .right)
        try SessionStore.save(snapshot, to: url)
        #expect(SessionStore.load(from: url) == snapshot)
    }

    @Test("an absent file loads as nil")
    func absentFile() {
        #expect(SessionStore.load(from: makeTempURL()) == nil)
    }

    @Test("a corrupt file loads as nil, never a crash")
    func corruptFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: url)
        #expect(SessionStore.load(from: url) == nil)
    }

    @Test("the pane snapshot takes the rememberable part of a live pane")
    func fromPaneState() {
        var state = PaneState(host: "jodo", path: "/tank")
        state.setSort(key: .modified)
        state.toggleHidden()
        let pane = SessionSnapshot.Pane(of: state)
        #expect(pane.host == "jodo")
        #expect(pane.path == "/tank")
        #expect(pane.sort == PaneState.Sort(key: .modified, ascending: true))
        #expect(pane.showHidden)
    }

    @Test("saving writes human-readable JSON")
    func humanReadable() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SessionStore.save(SessionSnapshot(), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"left\""))
        #expect(text.contains("\n"), "pretty-printed, per the data model's promise")
    }

    @Test("the default URL lands under Application Support/palana")
    func defaultLocation() {
        let url = SessionStore.defaultURL()
        #expect(url.lastPathComponent == "session.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "palana")
    }
}
