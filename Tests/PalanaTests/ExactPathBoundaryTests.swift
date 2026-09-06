// The exact-path boundary at the Surface — a pane's actions compose a
// path only from a name whose bytes a String carries exactly. Two rows
// whose names display alike but differ in bytes are refused rather than
// collapsed onto one path; a remote open's ceiling is the bytes streamed,
// not the size the listing claimed. Fakes only: a byte-level conduit
// stands in for the wire, never a host.

import Foundation
import PalanaCore
import Testing

@testable import Palana

// MARK: - A conduit that speaks bytes

/// A command the byte conduit has no answer for.
private struct ByteConduitMiss: Error { let command: String }

/// Answers commands with raw bytes and streams one command in chunks.
///
/// Listings are replayed from `responses`, keyed by the exact command, so
/// a name that is not UTF-8 reaches the parser as the bytes it is. The
/// `streamed` command yields its chunk `count` times, exits 0, and records
/// whether the reader terminated it.
private actor ByteConduit: Conduit {
    struct Streamed {
        var command: String
        var chunk: Data
        var count: Int
    }

    private let responses: [String: Data]
    private let streamed: Streamed?
    private(set) var commands: [String] = []
    private(set) var terminated = false

    init(responses: [String: Data], streamed: Streamed? = nil) {
        self.responses = responses
        self.streamed = streamed
    }

    private func markTerminated() { terminated = true }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        commands.append(command)
        if let streamed, streamed.command == command {
            let stdout = AsyncStream<Data> { continuation in
                for _ in 0..<streamed.count { continuation.yield(streamed.chunk) }
                continuation.finish()
            }
            return RunningCommand(
                stdout: stdout,
                stderr: AsyncStream { $0.finish() },
                exitStatus: { 0 },
                terminate: { _ in Task { await self.markTerminated() } })
        }
        guard let data = responses[command] else { throw ByteConduitMiss(command: command) }
        return RunningCommand(replayingStdout: data, stderr: Data(), exitStatus: 0)
    }

    func close(host: String) async {}
    func closeAll() async {}
}

/// A box the injected closures can write to across the `@Sendable` boundary.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// One GNU find record — nine NUL-terminated fields, the name as raw bytes.
private func gnuRecord(name: [UInt8], type: String = "f", size: Int = 10) -> Data {
    var record = Data(name)
    record.append(0)
    for field in [type, "\(size)", "1000000.0", "1000000.0", "644", "op", "op", ""] {
        record.append(contentsOf: field.utf8)
        record.append(0)
    }
    return record
}

/// A `FileEntry` for a remote file with the given bytes as its name.
private func fileEntry(_ bytes: [UInt8], size: Int64 = 10) -> FileEntry {
    FileEntry(
        nameData: Data(bytes),
        kind: .file,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

// MARK: - The pane

@MainActor
@Suite("PaneModel — actions refuse names no path carries exactly")
struct PaneExactPathTests {
    private let host = "koan"
    private let lossyA: [UInt8] = [0x61, 0xFF]
    private let lossyB: [UInt8] = [0x61, 0xFE]

    private struct Rig {
        let conduit: ByteConduit
        let pane: PaneModel
        let opened: Box<[URL]>
        let registered: Box<RoundTripRecord?>
        let cacheURL: URL
    }

    /// A pane pointed at `/dir` on a GNU host whose listing is `records`.
    private func makeRig(records: [Data], streamed: ByteConduit.Streamed? = nil) async throws -> Rig {
        var listing = Data()
        for record in records { listing.append(record) }
        let conduit = ByteConduit(
            responses: [Listing.command(for: "/dir", flavor: .gnu): listing],
            streamed: streamed)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-exact-cache-\(UUID().uuidString).json")
        let cache = FieldCache(url: cacheURL)
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: nil)
        try cache.save([host: HostFacts(capability: Dated(value: capability, discoveredAt: Date()))])
        let field = Field(conduit: conduit, hosts: [host], cache: cache)
        let engine = Engine(
            conduit: SSHConduit(configuration: SSHConfiguration()),
            field: field,
            listing: Listing(conduit: conduit))
        let pane = PaneModel(engine: engine)
        let opened = Box<[URL]>([])
        let registered = Box<RoundTripRecord?>(nil)
        pane.openHandler = { opened.value.append($0) }
        pane.onRoundTripRegistered = { registered.value = $0 }
        pane.point(host: host, path: "/dir")
        try await poll(message: "pane did not become ready at /dir") {
            pane.status == .ready && pane.state.path == "/dir"
        }
        return Rig(conduit: conduit, pane: pane, opened: opened, registered: registered, cacheURL: cacheURL)
    }

    @Test("two lossy twins list as two rows; opening one is refused, and no cat is ever composed")
    func openRefusesLossyTwin() async throws {
        let rig = try await makeRig(records: [gnuRecord(name: lossyA), gnuRecord(name: lossyB)])
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        #expect(rig.pane.rows.count == 2)
        #expect(rig.pane.rows.map(\.name) == ["a\u{FFFD}", "a\u{FFFD}"], "one display for two names")
        #expect(Set(rig.pane.rows.map(\.id)).count == 2, "two identities")

        rig.pane.state.cursor = Data(lossyA)
        rig.pane.apply(.descendOrOpen)
        try await Task.sleep(for: .milliseconds(50))

        #expect(rig.pane.lastError == PaneModel.unrepresentableNameRefusal)
        #expect(rig.opened.value.isEmpty, "nothing was handed to the system")
        #expect(rig.registered.value == nil, "no round-trip record was initiated")
        let commands = await rig.conduit.commands
        #expect(!commands.contains { $0.hasPrefix("cat ") }, "no read was composed from a lossy name")
    }

    @Test("descending into a directory whose name no path carries is refused in place")
    func navigationRefusesLossyDirectory() async throws {
        let rig = try await makeRig(records: [gnuRecord(name: lossyA, type: "d")])
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        let before = await rig.conduit.commands.count

        rig.pane.state.cursor = Data(lossyA)
        rig.pane.apply(.descend)
        try await Task.sleep(for: .milliseconds(50))

        #expect(rig.pane.lastError == PaneModel.unrepresentableNameRefusal)
        #expect(rig.pane.state.path == "/dir", "the pane stays where it was")
        #expect(await rig.conduit.commands.count == before, "no listing was composed for a lossy path")
    }

    @Test("copy path refuses a lossy name rather than pasting a replacement-character path")
    func copyPathRefusesLossyName() async throws {
        let rig = try await makeRig(records: [gnuRecord(name: lossyA)])
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }

        rig.pane.state.cursor = Data(lossyA)
        rig.pane.apply(.copyPath)

        #expect(rig.pane.lastError == PaneModel.unrepresentableNameRefusal)
    }

    @Test("a stale small size followed by oversized content is refused mid-stream, command terminated")
    func staleSizeThenOversizeStream() async throws {
        let name = Array("grown.bin".utf8)
        let readCommand = Listing.readFileCommand(for: "/dir/grown.bin")
        let rig = try await makeRig(
            records: [gnuRecord(name: name, size: 10)],
            streamed: .init(command: readCommand, chunk: Data(repeating: 0x5A, count: 512), count: 3))
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        rig.pane.openByteCeiling = 1024

        rig.pane.state.cursor = Data(name)
        rig.pane.apply(.descendOrOpen)
        try await poll(message: "the open never reported") { rig.pane.lastError != nil }

        #expect(rig.pane.lastError?.contains("too large to open here") == true)
        #expect(rig.opened.value.isEmpty, "an oversize copy is never handed to the system")
        #expect(rig.registered.value == nil, "no round-trip record for a refused open")
        #expect(await rig.conduit.terminated, "the read's command was terminated at the ceiling")
        #expect(!openCopyExists(named: "grown.bin"), "the per-open directory was taken back")
    }

    @Test("a file under the ceiling streams to its copy with the digest a whole read would give")
    func openStreamsUnderCeiling() async throws {
        let name = Array("small.bin".utf8)
        let chunk = Data(repeating: 0x5A, count: 256)
        let readCommand = Listing.readFileCommand(for: "/dir/small.bin")
        let rig = try await makeRig(
            records: [gnuRecord(name: name, size: 512)],
            streamed: .init(command: readCommand, chunk: chunk, count: 2))
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        rig.pane.openByteCeiling = 1024

        rig.pane.state.cursor = Data(name)
        rig.pane.apply(.descendOrOpen)
        try await poll(message: "the open never registered") { rig.registered.value != nil }

        let record = try #require(rig.registered.value)
        defer { try? FileManager.default.removeItem(at: record.localDirectory) }
        #expect(rig.opened.value == [record.localURL])
        #expect(try Data(contentsOf: record.localURL) == chunk + chunk)
        #expect(record.digest == RoundTrip.digest(of: chunk + chunk))
        #expect(record.localURL.lastPathComponent == "small.bin")
    }

    @Test("exactChildPath joins only an exact name")
    func exactChildPath() {
        #expect(PaneModel.exactChildPath(of: "/dir", entry: fileEntry(lossyA)) == nil)
        #expect(PaneModel.exactChildPath(of: "/dir", entry: fileEntry(Array("x.txt".utf8))) == "/dir/x.txt")
        #expect(PaneModel.exactChildPath(of: "/", entry: fileEntry(Array("x.txt".utf8))) == "/x.txt")
    }

    /// True when any per-open directory under the round-trip root holds a
    /// copy by this name — keyed on the name, since other suites open their
    /// own files under the same root at the same time.
    private func openCopyExists(named name: String) -> Bool {
        let root = RoundTripRecord.openRoot
        let children = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return children.contains { child in
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(child).appendingPathComponent(name).path)
        }
    }

    /// Bounded main-actor poll — records an issue on timeout rather than hanging.
    private func poll(
        timeout: TimeInterval = 5,
        message: String,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("\(message)")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

// MARK: - The preview

@MainActor
@Suite("PreviewController — the boundary and the bounded binary fetch")
struct PreviewExactPathTests {
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

    @Test("a remote entry whose name no path carries is never read — the card shows unread")
    func remoteLossyNameNeverRead() async {
        let controller = PreviewController()
        let textCalled = Box(false)
        let binaryCalled = Box(false)
        controller.remoteReader = { _, _, _ in
            textCalled.value = true
            return Data("text".utf8)
        }
        controller.remoteFileReader = { _, _, _, _ in
            binaryCalled.value = true
            return true
        }
        let lossy = fileEntry([0x61, 0xFF])
        controller.follow(entry: lossy, host: "koan", directory: "/dir", isLocal: false, url: nil)
        await settle(controller)
        #expect(controller.state == .remote(lossy))
        #expect(!textCalled.value, "no head read from a lossy name")
        #expect(!binaryCalled.value, "no fetch from a lossy name")
    }

    @Test("a binary fetch refused by its ceiling leaves no cache file and shows the card")
    func binaryOversizeEvictsCache() async throws {
        let controller = PreviewController()
        let destination = Box<URL?>(nil)
        let limit = Box(0)
        controller.remoteFileReader = { _, _, url, cap in
            destination.value = url
            limit.value = cap
            try? Data(repeating: 1, count: 16).write(to: url)  // a partial write, then refusal
            return false
        }
        let file = fileEntry(Array("photo.png".utf8), size: 2000)
        controller.follow(entry: file, host: "koan", directory: "/pics", isLocal: false, url: nil)
        await settle(controller)
        #expect(controller.state == .remote(file))
        #expect(limit.value == PreviewRouter.remoteBinaryCap, "the fetch carries the binary cap")
        let url = try #require(destination.value)
        #expect(!FileManager.default.fileExists(atPath: url.path), "the partial cache file was evicted")
    }
}
