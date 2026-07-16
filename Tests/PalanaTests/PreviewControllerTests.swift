// PreviewControllerTests — the preview pane's app-layer behavior (ho-16): the
// pane mode toggle and the PreviewController's load branches — remote → the
// local-only card, a local directory → info-only, a local text file → text
// (capped), a local binary → quick-look — plus the debounce's last-wins
// cancellation. The pure routing/sniff/cap live in PalanaCore's
// PreviewRouterTests; this is the mode flag and the debounced local read.

import Foundation
import PalanaCore
import Testing

@testable import Palana

// MARK: - Pane mode toggle

@MainActor
@Suite("PaneModel preview mode")
struct PaneModelPreviewModeTests {
    private func makePane() -> PaneModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let field = Field(conduit: recorded, hosts: ["h"], cache: FieldCache())
        let engine = Engine(
            conduit: SSHConduit(configuration: SSHConfiguration()),
            field: field,
            listing: Listing(conduit: recorded))
        return PaneModel(engine: engine)
    }

    @Test("enter sets preview mode; exit restores files")
    func toggle() {
        let pane = makePane()
        #expect(pane.paneMode == .files)
        pane.enterPreviewMode()
        #expect(pane.paneMode == .preview)
        pane.exitPreviewMode()
        #expect(pane.paneMode == .files)
    }

    @Test("entering and leaving preview never disturbs the file cursor or path")
    func fileStatePreserved() {
        let pane = makePane()
        pane.state.host = "koan"
        pane.state.path = "/tank/media"
        pane.state.cursor = Data("movie.mkv".utf8)
        pane.enterPreviewMode()
        pane.exitPreviewMode()
        #expect(pane.state.host == "koan")
        #expect(pane.state.path == "/tank/media")
        #expect(pane.state.cursor == Data("movie.mkv".utf8))
    }
}

// MARK: - PreviewController

@MainActor
@Suite("PreviewController — debounced local load")
struct PreviewControllerTests {
    private func entry(_ name: String, size: Int64 = 0, kind: FileEntry.Kind = .file) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: size,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "me",
            group: "staff")
    }

    /// Writes bytes to a fresh temp file and returns its URL.
    private func tempFile(_ bytes: Data, ext: String = "") throws -> URL {
        let name = "palana-preview-\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    /// Polls until the controller settles on a terminal (non-empty, non-loading)
    /// state, or a timeout — the debounce plus the read is well under this.
    private func settle(_ controller: PreviewController) async {
        for _ in 0..<300 {
            switch controller.state {
            case .empty, .loading:
                try? await Task.sleep(for: .milliseconds(10))
            default:
                return
            }
        }
    }

    /// Follows a LOCAL file at `url` (host/dir are unused on the local path).
    private func followLocal(_ controller: PreviewController, _ file: FileEntry, url: URL?) {
        controller.follow(
            entry: file, host: "local", directory: "/tmp", isLocal: true, url: url)
    }

    @Test("a nil cursor clears to empty immediately")
    func nilClearsToEmpty() {
        let controller = PreviewController()
        controller.follow(entry: nil, host: "local", directory: "/", isLocal: true, url: nil)
        #expect(controller.state == .empty)
    }

    @Test("a remote file with no reader wired → the local-only card")
    func remoteNoReaderIsLocalOnly() async {
        let controller = PreviewController()  // remoteReader stays nil
        let file = entry("notes.md")
        controller.follow(
            entry: file, host: "koan", directory: "/tank", isLocal: false, url: nil)
        await settle(controller)
        #expect(controller.state == .remote(file))
    }

    @Test("a remote text file with a reader → text over the wire")
    func remoteTextReads() async {
        let controller = PreviewController()
        controller.remoteReader = { _, _, _ in Data("remote: true\nkey: val\n".utf8) }
        let file = entry("config.yaml")
        controller.follow(
            entry: file, host: "koan", directory: "/etc", isLocal: false, url: nil)
        await settle(controller)
        guard case .text(let resolvedEntry, let preview) = controller.state else {
            Issue.record("expected .text, got \(controller.state)")
            return
        }
        #expect(resolvedEntry == file)
        #expect(preview.text == "remote: true\nkey: val\n")
    }

    @Test("a small remote image is fetched to a cache and quick-looked (ho-18)")
    func remoteBinaryFetches() async throws {
        let controller = PreviewController()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])  // PNG-ish
        controller.remoteFileReader = { _, _ in bytes }
        let file = entry("photo.png", size: 2000)
        controller.follow(entry: file, host: "koan", directory: "/pics", isLocal: false, url: nil)
        await settle(controller)
        guard case .quickLook(let resolvedEntry, let url) = controller.state else {
            Issue.record("expected .quickLook, got \(controller.state)")
            return
        }
        #expect(resolvedEntry == file)
        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == bytes)
        controller.clear()  // evicts the cache
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a remote image over the cap is never fetched — the local-only card")
    func remoteBinaryOverCapNotFetched() async {
        let controller = PreviewController()
        var readerCalled = false
        controller.remoteFileReader = { _, _ in
            readerCalled = true
            return Data([0x89])
        }
        let big = Int64(PreviewRouter.remoteBinaryCap) + 1
        let file = entry("huge.tiff", size: big)
        controller.follow(entry: file, host: "koan", directory: "/pics", isLocal: false, url: nil)
        await settle(controller)
        #expect(controller.state == .remote(file))
        #expect(!readerCalled, "an over-cap remote binary must not be read over the wire")
    }

    @Test("a remote binary with no binary reader wired → the local-only card")
    func remoteBinaryNoReader() async {
        let controller = PreviewController()  // remoteFileReader stays nil
        let file = entry("photo.png", size: 2000)
        controller.follow(entry: file, host: "koan", directory: "/pics", isLocal: false, url: nil)
        await settle(controller)
        #expect(controller.state == .remote(file))
    }

    @Test("a local directory resolves to info-only")
    func localDirectoryInfoOnly() async {
        let controller = PreviewController()
        followLocal(controller, entry("src", kind: .directory), url: URL(fileURLWithPath: "/tmp/src"))
        await settle(controller)
        #expect(controller.state == .infoOnly(entry("src", kind: .directory)))
    }

    @Test("a local text file resolves to text with its content")
    func localTextFile() async throws {
        let controller = PreviewController()
        let url = try tempFile(Data("hello preview\n".utf8), ext: "md")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = entry("notes.md")
        followLocal(controller, file, url: url)
        await settle(controller)
        guard case .text(let resolvedEntry, let preview) = controller.state else {
            Issue.record("expected .text, got \(controller.state)")
            return
        }
        #expect(resolvedEntry == file)
        #expect(preview.text == "hello preview\n")
        #expect(!preview.truncated)
    }

    @Test("a local text file past the cap resolves to truncated text")
    func localTextFileTruncates() async throws {
        let controller = PreviewController()
        let big = Data(repeating: UInt8(ascii: "x"), count: PreviewRouter.textCap + 500)
        let url = try tempFile(big, ext: "log")
        defer { try? FileManager.default.removeItem(at: url) }
        followLocal(controller, entry("huge.log"), url: url)
        await settle(controller)
        guard case .text(_, let preview) = controller.state else {
            Issue.record("expected .text, got \(controller.state)")
            return
        }
        #expect(preview.truncated)
        #expect(preview.text.count == PreviewRouter.textCap)
    }

    @Test("a local binary file resolves to quick-look")
    func localBinaryFile() async throws {
        let controller = PreviewController()
        let url = try tempFile(Data([0x00, 0x01, 0x02, 0xFF]))  // NUL → binary
        defer { try? FileManager.default.removeItem(at: url) }
        let file = entry("blob")  // extensionless → sniff decides
        followLocal(controller, file, url: url)
        await settle(controller)
        guard case .quickLook(let resolvedEntry, let resolved) = controller.state else {
            Issue.record("expected .quickLook, got \(controller.state)")
            return
        }
        #expect(resolvedEntry == file)
        #expect(resolved == url)
    }

    @Test("the debounce is last-wins — a rapid second follow cancels the first")
    func debounceLastWins() async {
        let controller = PreviewController()
        controller.follow(
            entry: entry("first.md"), host: "koan", directory: "/a", isLocal: false, url: nil)
        // Immediately supersede before the debounce elapses.
        let second = entry("second.md")
        controller.follow(
            entry: second, host: "koan", directory: "/a", isLocal: false, url: nil)
        await settle(controller)
        #expect(controller.state == .remote(second))
    }

    @Test("clear cancels and returns to empty")
    func clearResets() async throws {
        let controller = PreviewController()
        let url = try tempFile(Data("x".utf8), ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        followLocal(controller, entry("x.txt"), url: url)
        controller.clear()
        #expect(controller.state == .empty)
    }
}
