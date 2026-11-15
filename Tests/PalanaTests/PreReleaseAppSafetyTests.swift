// Pre-1.0 review (2026-11-15), app side — finding 3 (a cancelled watcher
// whose last reference is dropped at once leaked its descriptor) and
// finding 12 (a reorder that moved nothing still pushed an undo step).

import Foundation
import Testing

@testable import Palana

@Suite("pre-1.0 safety — watcher descriptors and favorites undo")
@MainActor
struct PreReleaseAppSafetyTests {
    /// The path a descriptor refers to, or nil once it is closed.
    private func path(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }

    @Test("a watcher cancelled and released at once still closes its descriptor")
    func cancelThenReleaseCloses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // F_GETPATH reports the real path (/private/var/…); URL's own
        // symlink resolution strips /private, so ask realpath(3).
        let watched = try #require(
            realpath(directory.path, nil).map { pointer in
                defer { free(pointer) }
                return String(cString: pointer)
            })

        var watcher: DirectoryWatcher? = DirectoryWatcher(path: watched) {}
        watcher?.start()
        let descriptor = try #require(await watcher?.watchedDescriptor())
        #expect(path(of: descriptor) == watched)

        // The pane's own sequence: cancel, then drop the only reference.
        watcher?.cancel()
        watcher = nil

        let deadline = Date().addingTimeInterval(5)
        while path(of: descriptor) == watched, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(path(of: descriptor) != watched, "the descriptor still watches the directory")
    }

    @Test("a reorder that moves nothing leaves no undo step behind")
    func noOpReorderPushesNoUndo() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-undo-\(UUID().uuidString)")
            .appendingPathComponent("favorites.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = FavoritesModel(url: url)
        model.add(host: "koan", path: "/a", scope: .host)
        model.add(host: "koan", path: "/b", scope: .host)

        model.move(id: "koan:/b", before: "koan:/a")
        #expect(model.all.map(\.id) == ["koan:/b", "koan:/a"])
        model.move(id: "koan:/b", by: -1)  // already first: nothing moves

        model.undo()
        #expect(model.all.map(\.id) == ["koan:/a", "koan:/b"], "⌘Z undid the real move")
    }
}
