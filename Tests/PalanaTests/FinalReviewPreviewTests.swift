// The 2026-11-18 final review's F10: a cancelled remote-binary preview
// that returns after a newer one finished must clean up only its own
// cache file — never the newer preview's.

import Foundation
import PalanaCore
import Testing

@testable import Palana

private final class Slot<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private func binary(_ name: String) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .file,
        size: 3,
        modified: Date(timeIntervalSince1970: 100),
        permissions: "644",
        owner: "op",
        group: "op")
}

@MainActor
@Suite("Final review F10 — superseded preview cleanup")
struct FinalReviewPreviewTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("a cancelled load that returns late deletes its own file and leaves the newer preview's")
    func lateCancelledLoadKeepsNewerPreview() async throws {
        let controller = PreviewController()
        // A's read hangs until released; every other read writes its file at once.
        let held = Slot<[String: CheckedContinuation<Bool, Never>]>([:])
        let written = Slot<[String: URL]>([:])
        controller.remoteFileReader = { _, path, url, _ in
            let name = (path as NSString).lastPathComponent
            try? Data([1, 2, 3]).write(to: url)
            written.value[name] = url
            if name.hasPrefix("held") {
                return await withCheckedContinuation { held.value[name] = $0 }
            }
            return true
        }
        defer { controller.clear() }

        controller.follow(entry: binary("held-a.png"), host: "nas", directory: "/p", isLocal: false, url: nil)
        try await waitUntil { held.value["held-a.png"] != nil }
        controller.follow(entry: binary("b.png"), host: "nas", directory: "/p", isLocal: false, url: nil)
        try await waitUntil {
            guard case .quickLook = controller.state else { return false }
            return true
        }
        let newer = try #require(written.value["b.png"])
        #expect(controller.state == .quickLook(binary("b.png"), newer))

        held.value["held-a.png"]?.resume(returning: false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(FileManager.default.fileExists(atPath: newer.path), "the newer preview's file survives")
        #expect(controller.state == .quickLook(binary("b.png"), newer))
        let stale = try #require(written.value["held-a.png"])
        #expect(!FileManager.default.fileExists(atPath: stale.path), "the superseded load removed its own file")

        // A third load supersedes B normally; B's file goes, C's stands.
        controller.follow(entry: binary("c.png"), host: "nas", directory: "/p", isLocal: false, url: nil)
        try await waitUntil { written.value["c.png"] != nil && controller.state != .quickLook(binary("b.png"), newer) }
        try await waitUntil {
            guard case .quickLook(let shown, _) = controller.state else { return false }
            return shown.name == "c.png"
        }
        let third = try #require(written.value["c.png"])
        #expect(!FileManager.default.fileExists(atPath: newer.path))
        #expect(FileManager.default.fileExists(atPath: third.path))
        controller.clear()
        #expect(!FileManager.default.fileExists(atPath: third.path))
    }
}
