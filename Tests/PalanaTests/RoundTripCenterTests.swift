// RoundTripCenterTests — the app-side lifecycle of round-trip records: the
// keyed pending queue (distinct saves keep their place, repeats coalesce),
// deduplication of repeated opens, bounded eviction, explicit retirement
// with watcher and temp-directory cleanup, and the exact-record baseline
// refresh that an ordinary copy or a sibling record never disturbs. Plus
// the pane-side proof that a navigation during a fetch cannot change the
// directory a round-trip record names.
//
// The center is driven through injected seams — a spy watcher, a panel-free
// toggle, and a delivery observer — so every case is deterministic with no
// wall-clock waits on the poll timer.

import Foundation
import PalanaCore
import Testing

@testable import Palana

// MARK: - Spy watcher

/// A stand-in ``RoundTripWatching`` that records lifecycle calls.
private final class SpyWatcher: RoundTripWatching, @unchecked Sendable {
    let record: RoundTripRecord
    let onChange: @Sendable () -> Void
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var refreshCount = 0

    init(record: RoundTripRecord, onChange: @escaping @Sendable () -> Void) {
        self.record = record
        self.onChange = onChange
    }

    func start() { started = true }
    func cancel() { cancelled = true }
    func refreshBaseline(to sent: RoundTripWatcher.Snapshot) { refreshCount += 1 }
}

// MARK: - Test rig

/// A box the injected closures can write to across the `@Sendable` boundary.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@MainActor
private struct Rig {
    let center: RoundTripCenter
    let deliveries: Box<[RoundTripRecord.ID]>
    let free: Box<Bool>
    let spies: Box<[RoundTripRecord.ID: SpyWatcher]>

    init() {
        let deliveries = Box<[RoundTripRecord.ID]>([])
        let free = Box(true)
        let spies = Box<[RoundTripRecord.ID: SpyWatcher]>([:])
        let center = RoundTripCenter { record, onChange in
            let spy = SpyWatcher(record: record, onChange: onChange)
            spies.value[record.id] = spy
            return spy
        }
        center.isPanelFree = { free.value }
        center.deliverUpload = { record in deliveries.value.append(record.id) }
        self.center = center
        self.deliveries = deliveries
        self.free = free
        self.spies = spies
    }
}

/// Builds a ``FileEntry`` for a local file with the given name and byte count.
private func fileEntry(named name: String, bytes: Int) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .file,
        size: Int64(bytes),
        modified: Date(),
        permissions: "644",
        owner: "op",
        group: "op")
}

/// Builds a record on a real per-open directory holding a file with `content`.
///
/// Real directory so retirement can prove the deletion and so
/// `RoundTripWatcher.snapshot` returns a non-nil snapshot for the offer.
private func makeLiveRecord(
    host: String = "koan",
    dir: String = "/tank",
    name: String,
    content: String = "x"
) throws -> RoundTripRecord {
    let directory = try RoundTripRecord.makeOpenDirectory()
    let fileURL = directory.appendingPathComponent(name)
    try Data(content.utf8).write(to: fileURL)
    return RoundTripRecord(
        host: host,
        remoteDirectory: dir,
        fetched: fileEntry(named: name, bytes: content.utf8.count),
        digest: RoundTrip.digest(of: Data(content.utf8)),
        localURL: fileURL)
}

// MARK: - Keyed queue

@MainActor
@Suite("RoundTripCenter — the keyed pending queue")
struct RoundTripCenterQueueTests {
    @Test("two distinct files saved while busy both queue, in order — neither replaces the other")
    func distinctSavesBothSurvive() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(name: "a.txt")
        let recordB = try makeLiveRecord(name: "b.txt")
        defer {
            try? FileManager.default.removeItem(at: recordA.localDirectory)
            try? FileManager.default.removeItem(at: recordB.localDirectory)
        }
        rig.center.register(record: recordA)
        rig.center.register(record: recordB)

        rig.free.value = false
        rig.center.offerOrQueue(record: recordA)
        rig.center.offerOrQueue(record: recordB)

        #expect(rig.center.pendingRecordIDs == [recordA.id, recordB.id])
        #expect(rig.deliveries.value.isEmpty)

        rig.free.value = true
        rig.center.drainOneIfFree()
        rig.center.drainOneIfFree()
        #expect(rig.deliveries.value == [recordA.id, recordB.id])
        #expect(rig.center.pendingRecordIDs.isEmpty)
    }

    @Test("repeated saves of one record coalesce to a single queued offer")
    func repeatedSavesCoalesce() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(name: "a.txt")
        defer { try? FileManager.default.removeItem(at: recordA.localDirectory) }
        rig.center.register(record: recordA)

        rig.free.value = false
        rig.center.offerOrQueue(record: recordA)
        rig.center.offerOrQueue(record: recordA)
        rig.center.offerOrQueue(record: recordA)
        #expect(rig.center.pendingRecordIDs == [recordA.id])
    }

    @Test("a coalesced repeat keeps its position — it does not jump the queue")
    func coalesceKeepsPosition() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(name: "a.txt")
        let recordB = try makeLiveRecord(name: "b.txt")
        defer {
            try? FileManager.default.removeItem(at: recordA.localDirectory)
            try? FileManager.default.removeItem(at: recordB.localDirectory)
        }
        rig.center.register(record: recordA)
        rig.center.register(record: recordB)

        rig.free.value = false
        rig.center.offerOrQueue(record: recordA)
        rig.center.offerOrQueue(record: recordB)
        rig.center.offerOrQueue(record: recordA)  // repeat of A while B waits behind it
        #expect(rig.center.pendingRecordIDs == [recordA.id, recordB.id])
    }
}

// MARK: - Exact baseline refresh

@MainActor
@Suite("RoundTripCenter — exact-record baseline refresh")
struct RoundTripCenterRefreshTests {
    @Test("finishing an upload refreshes only that record; a sibling in the same directory is untouched")
    func refreshTargetsOneRecord() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(dir: "/tank", name: "a.txt")
        let recordB = try makeLiveRecord(dir: "/tank", name: "b.txt")  // same directory, sibling
        defer {
            try? FileManager.default.removeItem(at: recordA.localDirectory)
            try? FileManager.default.removeItem(at: recordB.localDirectory)
        }
        rig.center.register(record: recordA)
        rig.center.register(record: recordB)

        rig.center.offerOrQueue(record: recordA)  // free → delivered, A is in flight
        #expect(rig.deliveries.value == [recordA.id])

        rig.center.uploadDidFinish()
        #expect(rig.spies.value[recordA.id]?.refreshCount == 1)
        #expect(rig.spies.value[recordB.id]?.refreshCount == 0, "a sibling record must not be refreshed")
    }

    @Test("an ordinary copy — no upload in flight — refreshes nothing")
    func ordinaryCopyRefreshesNothing() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(name: "a.txt")
        defer { try? FileManager.default.removeItem(at: recordA.localDirectory) }
        rig.center.register(record: recordA)

        // No offerOrQueue → nothing in flight. A finished ordinary copy calls this.
        rig.center.uploadDidFinish()
        #expect(rig.spies.value[recordA.id]?.refreshCount == 0)
    }

    @Test("a save queued during an upload survives the upload's finish")
    func queuedSaveSurvivesFinish() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(name: "a.txt")
        defer { try? FileManager.default.removeItem(at: recordA.localDirectory) }
        rig.center.register(record: recordA)

        rig.center.offerOrQueue(record: recordA)  // delivered, in flight
        rig.free.value = false
        rig.center.offerOrQueue(record: recordA)  // a fresh save arrives mid-upload → queued
        #expect(rig.center.pendingRecordIDs == [recordA.id])

        rig.center.uploadDidFinish()  // finish must not drop the queued save
        #expect(rig.center.pendingRecordIDs == [recordA.id])
    }
}

// MARK: - Dedup, eviction, retirement

@MainActor
@Suite("RoundTripCenter — record lifecycle")
struct RoundTripCenterLifecycleTests {
    @Test("re-opening the same remote file retires the earlier record")
    func repeatedOpenDeduplicates() throws {
        let rig = Rig()
        let first = try makeLiveRecord(dir: "/tank", name: "same.txt")
        rig.center.register(record: first)
        // A second open of the same remote file (same host + path), distinct id.
        let secondDirectory = try makeLiveRecord(dir: "/tank", name: "same.txt")
        let second = RoundTripRecord(
            host: first.host,
            remoteDirectory: first.remoteDirectory,
            fetched: first.fetched,
            digest: first.digest,
            localURL: secondDirectory.localURL)
        defer {
            try? FileManager.default.removeItem(at: first.localDirectory)
            try? FileManager.default.removeItem(at: second.localDirectory)
        }
        rig.center.register(record: second)

        #expect(rig.center.liveRecordCount == 1)
        #expect(rig.center.liveRecordIDs == [second.id])
        #expect(rig.spies.value[first.id]?.cancelled == true, "the earlier open's watcher must be cancelled")
    }

    @Test("registering past the bounded cap retires the oldest record")
    func boundedEviction() throws {
        let rig = Rig()
        var records: [RoundTripRecord] = []
        for index in 0..<RoundTripCenter.maxRecords {
            let record = try makeLiveRecord(dir: "/tank", name: "f\(index).txt")
            records.append(record)
            rig.center.register(record: record)
        }
        #expect(rig.center.liveRecordCount == RoundTripCenter.maxRecords)

        let overflow = try makeLiveRecord(dir: "/tank", name: "overflow.txt")
        records.append(overflow)
        rig.center.register(record: overflow)
        defer { for record in records { try? FileManager.default.removeItem(at: record.localDirectory) } }

        #expect(rig.center.liveRecordCount == RoundTripCenter.maxRecords)
        #expect(rig.spies.value[records[0].id]?.cancelled == true, "the oldest must be evicted")
        #expect(!rig.center.liveRecordIDs.contains(records[0].id))
        #expect(rig.center.liveRecordIDs.contains(overflow.id))
    }

    @Test("retirement cancels the watcher, drops queue state, and deletes the per-open directory")
    func retirementCleansUp() throws {
        let rig = Rig()
        let recordA = try makeLiveRecord(name: "a.txt")
        rig.center.register(record: recordA)
        rig.free.value = false
        rig.center.offerOrQueue(record: recordA)
        #expect(rig.center.pendingRecordIDs == [recordA.id])
        #expect(FileManager.default.fileExists(atPath: recordA.localDirectory.path))

        rig.center.retire(id: recordA.id)

        #expect(rig.spies.value[recordA.id]?.cancelled == true)
        #expect(rig.center.liveRecordCount == 0)
        #expect(rig.center.pendingRecordIDs.isEmpty, "a retired record's queued offers are dropped")
        #expect(
            !FileManager.default.fileExists(atPath: recordA.localDirectory.path),
            "the per-open temporary directory must be deleted")
    }

    @Test("retirement only deletes directories under the palana-open root")
    func retirementGuardsDeletion() throws {
        // A record whose local URL is NOT under palana-open must never have its
        // parent directory deleted by retirement.
        let stray = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-stray-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        let fileURL = stray.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: stray) }

        let record = RoundTripRecord(
            host: "koan",
            remoteDirectory: "/tank",
            fetched: fileEntry(named: "keep.txt", bytes: 4),
            digest: Data(),
            localURL: fileURL)

        let rig = Rig()
        rig.center.register(record: record)
        rig.center.retire(id: record.id)

        #expect(
            FileManager.default.fileExists(atPath: stray.path),
            "a directory outside palana-open must be left alone")
    }
}

// MARK: - Pane: identity captured before the fetch

/// A command the gated conduit's transcript does not carry.
private struct GatedConduitMiss: Error { let command: String }

/// A conduit that answers listings from a transcript and suspends the read.
///
/// The file read suspends until the test releases it, so a navigation can be
/// interleaved between an open's start and its completion.
private actor GatedConduit: Conduit {
    private let transcript: ConduitTranscript
    private let readCommand: String
    private let readBytes: Data
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(transcript: ConduitTranscript, readCommand: String, readBytes: Data) {
        self.transcript = transcript
        self.readCommand = readCommand
        self.readBytes = readBytes
    }

    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        if command == readCommand {
            if !released {
                await withCheckedContinuation { waiters.append($0) }
            }
            return RunningCommand(replayingStdout: readBytes, stderr: Data(), exitStatus: 0)
        }
        guard
            let entry = transcript.entries.first(where: { $0.host == host && $0.command == command })
        else { throw GatedConduitMiss(command: command) }
        return RunningCommand(
            replayingStdout: Data(entry.stdout.utf8),
            stderr: Data(entry.stderr.utf8),
            exitStatus: entry.exit)
    }

    func close(host: String) async {}
    func closeAll() async {}
}

@MainActor
@Suite("PaneModel — round-trip identity is captured before the fetch")
struct PaneModelRoundTripIdentityTests {
    /// One GNU find record for a single file, NUL-delimited (9 fields).
    private func gnuEntry(name: String) -> String {
        let nul = "\u{0}"
        let fields = [name, "f", "10", "1000000.0", "1000000.0", "644", "op", "op", ""]
        return fields.map { $0 + nul }.joined()
    }

    @Test("navigating during the download does not change the record's directory")
    func navigationDuringFetchKeepsOpenDirectory() async throws {
        let host = "koan"
        let readCommand = Listing.readFileCommand(for: "/dirA/notes.txt")
        let transcript = ConduitTranscript(entries: [
            .init(
                host: host,
                command: Listing.command(for: "/dirA", flavor: .gnu),
                stdout: gnuEntry(name: "notes.txt"),
                stderr: "",
                exit: 0),
            .init(
                host: host,
                command: Listing.command(for: "/dirB", flavor: .gnu),
                stdout: "",
                stderr: "",
                exit: 0),
        ])
        let gated = GatedConduit(
            transcript: transcript, readCommand: readCommand, readBytes: Data("fetched bytes".utf8))

        // Seed the host's capability so the pane resolves the flavor without the wire.
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-rt-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cache = FieldCache(url: cacheURL)
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: nil)
        try cache.save([host: HostFacts(capability: Dated(value: capability, discoveredAt: Date()))])

        let field = Field(conduit: gated, hosts: [host], cache: cache)
        let engine = Engine(
            conduit: gated,
            field: field,
            listing: Listing(conduit: gated))
        let pane = PaneModel(engine: engine)
        pane.openHandler = { _ in }  // never launch a real editor

        let captured = Box<RoundTripRecord?>(nil)
        pane.onRoundTripRegistered = { record in captured.value = record }

        // Point at /dirA and wait for it to be ready with the file listed.
        pane.point(host: host, path: "/dirA")
        try await poll(message: "pane did not become ready at /dirA") {
            pane.state.path == "/dirA" && pane.rows.contains { $0.name == "notes.txt" }
        }

        // Open the file — the fetch suspends inside GatedConduit.
        pane.state.cursor = Data("notes.txt".utf8)
        pane.apply(.descendOrOpen)

        // Navigate away while the download is in flight.
        pane.point(host: host, path: "/dirB")
        try await poll(message: "pane did not navigate to /dirB during the fetch") {
            pane.state.path == "/dirB"
        }

        // Release the fetch; the record must still name /dirA.
        await gated.release()
        try await poll(message: "round-trip record was never registered") { captured.value != nil }

        let record = try #require(captured.value)
        #expect(
            record.remoteDirectory == "/dirA",
            "the record must name where the file was opened, not the new location")
        #expect(record.host == host)
        #expect(record.remotePath == "/dirA/notes.txt")
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
