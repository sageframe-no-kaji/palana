// DragOutProviderTests — the remote half of a drag out of a pane, driven
// against a scripted conduit (never a live SSHConduit): the bytes land at
// the delivered URL, progress reaches the byte count, a cancel stops the
// download and leaves no file, a failed fetch leaves no file. Plus each
// row's item provider: the pane-to-pane payload, a local file's URL and
// file, a remote file downloaded on request, a refusal that names itself.

import AppKit
import Foundation
import PalanaCore
import Testing
import UniformTypeIdentifiers

@testable import Palana

// MARK: - A conduit that streams one file

/// What the scripted command has done — the test reads it back.
private actor StreamLog {
    private(set) var terminated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var exit: Int32?

    func terminate() {
        terminated = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func waitForTerminate() async {
        guard !terminated else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ status: Int32) {
        exit = status
        for waiter in exitWaiters { waiter.resume(returning: status) }
        exitWaiters.removeAll()
    }

    func exitStatus() async -> Int32 {
        if let exit { return exit }
        return await withCheckedContinuation { exitWaiters.append($0) }
    }
}

/// Answers every command with one scripted stream.
private struct FileConduit: Conduit {
    enum Script {
        /// Yields the chunks and exits 0.
        case bytes([Data])
        /// Writes stderr and exits with the status.
        case failure(stderr: String, status: Int32)
        /// Yields one chunk, then holds the stream until terminated.
        case stall(Data)
    }

    let script: Script
    let log = StreamLog()

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        let log = log
        let script = script
        let (stdout, out) = AsyncStream<Data>.makeStream()
        let (stderr, err) = AsyncStream<Data>.makeStream()
        Task {
            switch script {
            case .bytes(let chunks):
                for chunk in chunks { out.yield(chunk) }
                out.finish()
                err.finish()
                await log.finish(0)
            case .failure(let message, let status):
                err.yield(Data(message.utf8))
                out.finish()
                err.finish()
                await log.finish(status)
            case .stall(let chunk):
                out.yield(chunk)
                await log.waitForTerminate()
                out.finish()
                err.finish()
                await log.finish(143)
            }
        }
        return RunningCommand(
            stdout: stdout,
            stderr: stderr,
            exitStatus: { await log.exitStatus() },
            terminate: { _ in Task { await log.terminate() } })
    }

    func close(host: String) async {}
    func closeAll() async {}
}

/// Collects transcript lines from any thread.
private final class Lines: @unchecked Sendable {
    // @unchecked: every access holds the lock.
    private let lock = NSLock()
    private var stored: [String] = []

    func append(_ line: String) {
        lock.withLock { stored.append(line) }
    }

    var all: [String] { lock.withLock { stored } }
}

// MARK: - Helpers

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dragout-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func fetch(_ conduit: FileConduit, size: Int64, root: URL) -> RemoteDragFetch {
    RemoteDragFetch(listing: Listing(conduit: conduit), host: "koan", path: "/srv/song.flac", size: size, root: root)
}

/// Starts `fetch` and waits for its completion.
private func run(_ fetch: RemoteDragFetch) async throws -> (Result<URL, any Error>, Progress) {
    var progress: Progress?
    let result = await withCheckedContinuation { (done: CheckedContinuation<Result<URL, any Error>, Never>) in
        progress = fetch.start { done.resume(returning: $0) }
    }
    return (result, try #require(progress))
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

// MARK: - The download

@Suite("Drag-out remote download")
struct DragOutProviderTests {
    private let chunks = [Data("hello, ".utf8), Data("drop".utf8)]

    @Test("the bytes land at the delivered URL and progress reaches the byte count")
    func bytesLand() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let download = fetch(FileConduit(script: .bytes(chunks)), size: 11, root: root)
        let (result, progress) = try await run(download)
        let url = try result.get()
        #expect(try Data(contentsOf: url) == Data("hello, drop".utf8))
        #expect(url.lastPathComponent == "song.flac")
        #expect(url.deletingLastPathComponent() == download.directory)
        #expect(progress.completedUnitCount == 11)
        #expect(progress.totalUnitCount == 11)
        download.cleanUp()
        #expect(!exists(download.directory))
    }

    @Test("a fetch failure delivers the error and leaves no file")
    func failureLeavesNothing() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let conduit = FileConduit(script: .failure(stderr: "cat: /srv/song.flac: Permission denied", status: 1))
        let download = fetch(conduit, size: 11, root: root)
        let (result, _) = try await run(download)
        #expect(throws: (any Error).self) { try result.get() }
        #expect(!exists(download.directory))
    }

    @Test("cancelling stops the fetch, delivers an error and leaves no file")
    func cancelStops() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let conduit = FileConduit(script: .stall(Data("partial".utf8)))
        let download = fetch(conduit, size: 1_000, root: root)
        let result = await withCheckedContinuation { (done: CheckedContinuation<Result<URL, any Error>, Never>) in
            let progress = download.start { done.resume(returning: $0) }
            Task {
                // Let the first chunk reach the disk, then cancel mid-stream.
                try? await Task.sleep(for: .milliseconds(150))
                progress.cancel()
            }
        }
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!exists(download.directory))
        #expect(await conduit.log.terminated, "the remote command must be stopped")
    }

    @Test("the promise delegate moves the bytes into place and reports both lines")
    func deliverPlacesFile() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let download = fetch(FileConduit(script: .bytes(chunks)), size: 11, root: root)
        let lines = Lines()
        let delegate = RemoteDropDelegate(fetch: download) { lines.append($0) }
        let target = root.appendingPathComponent("dropped.flac")
        let error = await withCheckedContinuation { (done: CheckedContinuation<(any Error)?, Never>) in
            _ = delegate.deliver(to: target) { done.resume(returning: $0) }
        }
        #expect(error == nil)
        #expect(try Data(contentsOf: target) == Data("hello, drop".utf8))
        #expect(!exists(download.directory), "the temp directory goes once the file is placed")
        #expect(
            lines.all == ["downloading koan:/srv/song.flac for a drop…", "koan:/srv/song.flac delivered to the drop"])
    }

    @Test("a failed delivery places nothing and names the failure")
    @MainActor
    func deliverFailure() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let conduit = FileConduit(script: .failure(stderr: "cat: nope: No such file or directory", status: 1))
        let download = fetch(conduit, size: 11, root: root)
        let lines = Lines()
        let delegate = RemoteDropDelegate(fetch: download) { lines.append($0) }
        let target = root.appendingPathComponent("dropped.flac")
        let error = await withCheckedContinuation { (done: CheckedContinuation<(any Error)?, Never>) in
            _ = delegate.deliver(to: target) { done.resume(returning: $0) }
        }
        #expect(error != nil)
        #expect(!exists(target))
        #expect(lines.all.last?.hasPrefix("koan:/srv/song.flac — download failed") == true)
        #expect(delegate.filePromiseProvider(NSFilePromiseProvider(), fileNameForType: "public.data") == "song.flac")
    }

    @Test("leftover drag directories are swept, others are kept")
    func sweep() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = root.appendingPathComponent(RemoteDragFetch.directoryPrefix + "old")
        let other = root.appendingPathComponent("keep-me")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        RemoteDragFetch.sweep(root: root)
        #expect(!exists(stale))
        #expect(exists(other))
    }

    @Test("the drag timeout covers the 1 GiB ceiling at 1 MiB/s")
    func ceilings() {
        #expect(RemoteDragFetch.ceiling == 1 << 30)
        #expect(RemoteDragFetch.timeout == .seconds(1024))
    }
}

// MARK: - The row providers

/// Loads one file representation and reads the bytes inside the completion,
/// while the file still exists.
@MainActor
private func loadFile(_ provider: NSItemProvider, type: String) async -> (Data?, (any Error)?) {
    await withCheckedContinuation { (done: CheckedContinuation<(Data?, (any Error)?), Never>) in
        _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            done.resume(returning: (url.flatMap { try? Data(contentsOf: $0) }, error))
        }
    }
}

@MainActor
@Suite("Drag-out row providers")
struct DragOutRowProviderTests {
    private let selection = DraggedSelection(host: "koan", directory: "/srv", names: [Data("song.flac".utf8)])

    private func support(_ conduit: FileConduit, _ lines: Lines) -> RemoteDragSupport {
        RemoteDragSupport(listing: Listing(conduit: conduit)) { lines.append($0) }
    }

    @Test("every row carries the pane-to-pane payload, for pālana only")
    func payload() async throws {
        let provider = try #require(itemProvider(for: selection))
        #expect(provider.registeredTypeIdentifiers == [UTType.json.identifier])
        let data = await withCheckedContinuation { (done: CheckedContinuation<Data?, Never>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
                done.resume(returning: data)
            }
        }
        #expect(try JSONDecoder().decode(DraggedSelection.self, from: try #require(data)) == selection)
    }

    @Test("a remote file downloads when the receiver asks, and the transcript says so")
    func remoteDownloads() async throws {
        let lines = Lines()
        let conduit = FileConduit(script: .bytes([Data("hello, ".utf8), Data("drop".utf8)]))
        let item = DragOutItem.remoteFile(host: "koan", path: "/srv/song.flac", size: 11)
        let provider = try #require(itemProvider(for: selection, outbound: item, remote: support(conduit, lines)))
        #expect(provider.suggestedName == "song.flac")
        let type = UTType(filenameExtension: "flac")?.identifier ?? UTType.data.identifier
        #expect(provider.hasItemConformingToTypeIdentifier(type))
        let (data, error) = await loadFile(provider, type: type)
        #expect(error == nil)
        #expect(data == Data("hello, drop".utf8))
        try await poll(message: "the delivered line never came") { lines.all.count == 2 }
        #expect(
            lines.all == ["downloading koan:/srv/song.flac for a drop…", "koan:/srv/song.flac delivered to the drop"])
    }

    @Test("a failed download delivers an error and names it")
    func remoteFails() async throws {
        let lines = Lines()
        let conduit = FileConduit(script: .failure(stderr: "cat: /srv/song.flac: No such file or directory", status: 1))
        let item = DragOutItem.remoteFile(host: "koan", path: "/srv/song.flac", size: 11)
        let provider = try #require(itemProvider(for: selection, outbound: item, remote: support(conduit, lines)))
        let type = UTType(filenameExtension: "flac")?.identifier ?? UTType.data.identifier
        let (data, error) = await loadFile(provider, type: type)
        #expect(data == nil)
        #expect(error != nil)
        try await poll(message: "the failure line never came") { lines.all.count == 2 }
        #expect(lines.all.last?.hasPrefix("koan:/srv/song.flac — download failed") == true)
    }

    @Test("a refused remote folder answers an outside receiver with the reason")
    func refusal() async throws {
        let lines = Lines()
        let reason = DragOutRefusal.remoteFolder(location: "koan:/srv/media")
        let item = DragOutItem.refused(name: "media", reason: reason)
        let provider = try #require(
            itemProvider(for: selection, outbound: item, remote: support(FileConduit(script: .bytes([])), lines)))
        let (data, error) = await loadFile(provider, type: UTType.data.identifier)
        #expect(data == nil)
        // NSItemProvider hands the receiver its own error; the transcript
        // line is the operator's word on why.
        #expect(error != nil)
        #expect(lines.all == [reason.line(name: "media")])
        #expect(DragOutRefused(message: "x").errorDescription == "x")
    }

    @Test("a local file carries its URL and the file itself")
    func localFile() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.txt")
        try Data("local".utf8).write(to: file)
        let provider = try #require(itemProvider(for: selection, outbound: .localFile(path: file.path)))
        #expect(provider.suggestedName == "notes.txt")
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        let (data, error) = await loadFile(provider, type: UTType.plainText.identifier)
        #expect(error == nil)
        #expect(data == Data("local".utf8))
    }

    @Test("a local folder is offered as a folder")
    func localFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = try #require(itemProvider(for: selection, outbound: .localFile(path: root.path)))
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier))
    }

    @Test("a file's type comes from its extension, plain data when unknown")
    func fileTypes() {
        #expect(dragOutFileType(for: "/a/b.txt") == UTType.plainText.identifier)
        #expect(dragOutFileType(for: "/a/b.zzqx") == UTType.data.identifier)
        #expect(dragOutFileType(for: "/a/Makefile") == UTType.data.identifier)
    }
}

// MARK: - The row writers

@MainActor
@Suite("Drag-out row writers")
struct DragOutRowWriterTests {
    private let payload = Data("{\"selection\":1}".utf8)
    private let listing = Listing(conduit: FileConduit(script: .bytes([])))

    @Test("a local entry's writer carries its file URL and the payload, up front")
    func local() throws {
        let writer = rowPasteboardWriter(for: .localFile(path: "/tmp/a b.txt"), payload: payload, remote: nil)
        let item = try #require(writer as? NSPasteboardItem)
        #expect(item.string(forType: .fileURL) == "file:///tmp/a%20b.txt")
        #expect(item.string(forType: .URL) == "file:///tmp/a%20b.txt")
        #expect(item.data(forType: .palanaPayload) == payload)
    }

    @Test("a remote file's writer is a promise typed by its extension, carrying the payload")
    func remote() throws {
        let support = RemoteDragSupport(listing: listing) { _ in }
        let item = DragOutItem.remoteFile(host: "koan", path: "/srv/shot.png", size: 9)
        let promise = try #require(
            rowPasteboardWriter(for: item, payload: payload, remote: support) as? RemoteFilePromise)
        #expect(promise.fileType == UTType.png.identifier)
        #expect(promise.selectionPayload == payload)
        #expect(promise.keeper != nil)
        let board = NSPasteboard(name: NSPasteboard.Name("palana-writer-test-\(UUID().uuidString)"))
        #expect(promise.writableTypes(for: board).contains(.palanaPayload))
        #expect(promise.pasteboardPropertyList(forType: .palanaPayload) as? Data == payload)
        board.releaseGlobally()
    }

    @Test("a refused entry, or a remote one without a reader, keeps SwiftUI's writer")
    func none() {
        let refused = DragOutItem.refused(name: "media", reason: .remoteFolder(location: "koan:/srv/media"))
        #expect(rowPasteboardWriter(for: refused, payload: payload, remote: nil) == nil)
        let remote = DragOutItem.remoteFile(host: "koan", path: "/srv/a.txt", size: 1)
        #expect(rowPasteboardWriter(for: remote, payload: payload, remote: nil) == nil)
    }
}
