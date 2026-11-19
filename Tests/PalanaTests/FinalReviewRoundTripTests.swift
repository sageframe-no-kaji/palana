// The 2026-11-18 final review's F09: after a successful send-back the
// record's conflict baseline must name the version that was sent, so the
// next save round-trips cleanly — while a remote writer after the landing,
// or a local edit during the transfer, still asks rather than sends.
//
// The center is driven through its seams: a quiet watcher, a delivery
// observer, and an injected remote reader standing in for the listing.

import Foundation
import PalanaCore
import Testing

@testable import Palana

private final class QuietWatcher: RoundTripWatching, @unchecked Sendable {
    func start() {}
    func cancel() {}
    func refreshBaseline(to sent: RoundTripWatcher.Snapshot) {}
}

private final class Holder<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private func remoteEntry(_ name: String, bytes: Int, at seconds: TimeInterval) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .file,
        size: Int64(bytes),
        modified: Date(timeIntervalSince1970: seconds),
        permissions: "644",
        owner: "op",
        group: "op")
}

private func digest(_ text: String) -> Data { RoundTrip.digest(of: Data(text.utf8)) }

/// A center whose remote is a mutable value: the test sets what stands
/// there, and every post-upload read returns it.
@MainActor
private struct SendBackRig {
    let center = RoundTripCenter { _, _ in QuietWatcher() }
    let delivered = Holder<[RoundTripRecord]>([])
    let free = Holder(true)
    /// What stands at the remote path now; nil content is absence.
    let remote = Holder<(entry: FileEntry, content: String)?>(nil)
    let reads = Holder(0)
    let record: RoundTripRecord

    init(original: String = "v0") throws {
        let directory = try RoundTripRecord.makeOpenDirectory()
        let url = directory.appendingPathComponent("edit.txt")
        try Data(original.utf8).write(to: url)
        let fetched = remoteEntry("edit.txt", bytes: original.utf8.count, at: 100)
        record = RoundTripRecord(
            host: "nas", remoteDirectory: "/srv", fetched: fetched, digest: digest(original), localURL: url)
        remote.value = (fetched, original)
        let delivered = delivered
        let free = free
        let remote = remote
        let reads = reads
        center.isPanelFree = { free.value }
        center.deliverUpload = { delivered.value.append($0) }
        center.readRemoteVersion = { _ in
            reads.value += 1
            guard let standing = remote.value else { return .init(entry: nil, digest: nil) }
            return .init(entry: standing.entry, digest: digest(standing.content))
        }
        center.register(record: record)
    }

    /// The operator saves `text` locally.
    func save(_ text: String) throws {
        try Data(text.utf8).write(to: record.localURL)
    }

    /// The send lands: the remote now holds `text`, with a new mtime.
    func land(_ text: String, at seconds: TimeInterval) {
        remote.value = (remoteEntry("edit.txt", bytes: text.utf8.count, at: seconds), text)
    }

    /// What the gather would rule for the most recent delivery.
    func checkLastDelivery() throws -> ConflictCheck {
        let offer = try #require(delivered.value.last)
        let standing = remote.value
        return RoundTrip.evaluate(
            record: offer, current: standing?.entry, currentDigest: standing.map { digest($0.content) })
    }

    func cleanUp() { try? FileManager.default.removeItem(at: record.localDirectory) }
}

@MainActor
@Suite("Final review F09 — successive send-backs")
struct FinalReviewSendBackBaselineTests {
    @Test("three successive saves each send cleanly against the version the previous one landed")
    func successiveSavesRoundTrip() async throws {
        let rig = try SendBackRig()
        defer { rig.cleanUp() }
        for (index, text) in ["first edit", "second", "third and longer"].enumerated() {
            try rig.save(text)
            rig.center.offerOrQueue(record: rig.record)
            #expect(try rig.checkLastDelivery() == .clean, "save \(index + 1) must not conflict with the last send")
            rig.land(text, at: 200 + Double(index))
            rig.center.uploadDidFinish()
            await rig.center.awaitBaselineSettled()
            let live = try #require(rig.center.liveRecord(id: rig.record.id))
            #expect(live.digest == digest(text))
            #expect(live.fetched.modified == Date(timeIntervalSince1970: 200 + Double(index)))
        }
        #expect(rig.delivered.value.count == 3)
        #expect(rig.reads.value == 3)
    }

    @Test("a remote writer after the landing is still a conflict on the next save")
    func remoteWriterAfterLandingConflicts() async throws {
        let rig = try SendBackRig()
        defer { rig.cleanUp() }
        try rig.save("mine")
        rig.center.offerOrQueue(record: rig.record)
        // Someone else writes between our landing and the post-upload read.
        rig.land("theirs", at: 300)
        rig.center.uploadDidFinish()
        await rig.center.awaitBaselineSettled()
        #expect(rig.center.liveRecord(id: rig.record.id)?.digest == digest("v0"), "no advance to unseen bytes")

        try rig.save("mine again")
        rig.center.offerOrQueue(record: rig.record)
        #expect(try rig.checkLastDelivery() != .clean)
    }

    @Test("a local edit during the transfer leaves the baseline, so the next save asks")
    func localEditDuringTransferAsks() async throws {
        let rig = try SendBackRig()
        defer { rig.cleanUp() }
        try rig.save("version A")
        rig.center.offerOrQueue(record: rig.record)  // hashed at delivery: version A
        // The transfer read a mixed version; the remote does not hold A.
        rig.land("version A, half of B", at: 400)
        rig.center.uploadDidFinish()
        await rig.center.awaitBaselineSettled()
        #expect(rig.center.liveRecord(id: rig.record.id)?.digest == digest("v0"))
    }

    @Test("a failed remote read leaves the baseline where it was")
    func failedReadLeavesBaseline() async throws {
        let rig = try SendBackRig()
        defer { rig.cleanUp() }
        rig.center.readRemoteVersion = { _ in nil }
        try rig.save("mine")
        rig.center.offerOrQueue(record: rig.record)
        rig.land("mine", at: 500)
        rig.center.uploadDidFinish()
        await rig.center.awaitBaselineSettled()
        #expect(rig.center.liveRecord(id: rig.record.id)?.digest == digest("v0"))
    }

    @Test("a save that arrives while the baseline settles waits, then carries the advanced baseline")
    func saveDuringSettlingWaits() async throws {
        let rig = try SendBackRig()
        defer { rig.cleanUp() }
        let gate = Holder<CheckedContinuation<Void, Never>?>(nil)
        let remote = rig.remote
        rig.center.readRemoteVersion = { _ in
            await withCheckedContinuation { gate.value = $0 }
            guard let standing = remote.value else { return nil }
            return .init(entry: standing.entry, digest: digest(standing.content))
        }
        try rig.save("first")
        rig.center.offerOrQueue(record: rig.record)
        rig.land("first", at: 600)
        rig.center.uploadDidFinish()
        while gate.value == nil { await Task.yield() }

        try rig.save("second")
        rig.center.offerOrQueue(record: rig.record)
        #expect(rig.delivered.value.count == 1, "no delivery against an unsettled baseline")
        #expect(rig.center.pendingRecordIDs == [rig.record.id])
        #expect(rig.center.drainOneIfFree() == false)

        gate.value?.resume()
        await rig.center.awaitBaselineSettled()
        rig.center.drainOneIfFree()
        #expect(rig.delivered.value.count == 2)
        #expect(try rig.checkLastDelivery() == .clean)
    }
}

// MARK: - F01: retirement keeps unconfirmed edits (owner ruling 2026-11-18)

@MainActor
@Suite("Final review F01 — retirement keeps unconfirmed edits")
struct FinalReviewRetirementTests {
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// A second open of the rig's remote file, in its own directory.
    private func reopen(_ rig: SendBackRig, content: String) throws -> RoundTripRecord {
        let directory = try RoundTripRecord.makeOpenDirectory()
        let url = directory.appendingPathComponent("edit.txt")
        try Data(content.utf8).write(to: url)
        return RoundTripRecord(
            host: rig.record.host,
            remoteDirectory: rig.record.remoteDirectory,
            fetched: rig.record.fetched,
            digest: digest(content),
            localURL: url)
    }

    @Test("a reopen while an edit waits in the queue keeps the old copy, names it, and drops the stale send")
    func reopenKeepsQueuedEdit() throws {
        let rig = try SendBackRig()
        let kept = Holder<[RoundTripRecord.ID]>([])
        rig.center.onRetainedCopy = { kept.value.append($0.id) }
        rig.free.value = false
        try rig.save("third")
        rig.center.offerOrQueue(record: rig.record)
        #expect(rig.center.pendingRecordIDs == [rig.record.id])

        let second = try reopen(rig, content: "v0")
        defer {
            rig.cleanUp()
            try? FileManager.default.removeItem(at: second.localDirectory)
        }
        rig.center.register(record: second)

        #expect(exists(rig.record.localURL), "the unsent edit survives the reopen")
        #expect(try String(contentsOf: rig.record.localURL, encoding: .utf8) == "third")
        #expect(kept.value == [rig.record.id])
        #expect(rig.center.pendingRecordIDs.isEmpty, "the superseded copy never sends on its own")
        #expect(rig.center.liveRecordIDs == [second.id])
    }

    @Test("a reopen of an unedited copy still deletes it")
    func reopenDeletesCleanCopy() throws {
        let rig = try SendBackRig()
        let kept = Holder(0)
        rig.center.onRetainedCopy = { _ in kept.value += 1 }
        let second = try reopen(rig, content: "v0")
        defer { try? FileManager.default.removeItem(at: second.localDirectory) }
        rig.center.register(record: second)
        #expect(!exists(rig.record.localDirectory))
        #expect(kept.value == 0)
    }

    @Test("an edit in flight when its record is retired is kept")
    func inFlightEditKept() throws {
        let rig = try SendBackRig()
        defer { rig.cleanUp() }
        try rig.save("sending")
        rig.center.offerOrQueue(record: rig.record)  // delivered, in flight
        rig.center.retire(id: rig.record.id)
        #expect(exists(rig.record.localURL))
        rig.center.uploadDidFinish()  // the late finish touches nothing retired
        #expect(rig.center.liveRecordCount == 0)
    }

    @Test("after a send-back is confirmed to land, retiring the copy deletes it")
    func confirmedEditDeleted() async throws {
        let rig = try SendBackRig()
        try rig.save("landed")
        rig.center.offerOrQueue(record: rig.record)
        rig.land("landed", at: 900)
        rig.center.uploadDidFinish()
        await rig.center.awaitBaselineSettled()
        rig.center.retire(id: rig.record.id)
        #expect(!exists(rig.record.localDirectory), "a confirmed edit is not unsent work")
    }

    @Test("the bounded cap keeps an evicted copy that holds an unconfirmed edit, and deletes clean ones")
    func capEvictionKeepsDirtyOldest() throws {
        let rig = try SendBackRig()
        try rig.save("never sent")
        var others: [RoundTripRecord] = []
        defer {
            rig.cleanUp()
            for record in others { try? FileManager.default.removeItem(at: record.localDirectory) }
        }
        for index in 0..<RoundTripCenter.maxRecords {
            let directory = try RoundTripRecord.makeOpenDirectory()
            let url = directory.appendingPathComponent("f\(index).txt")
            try Data("same".utf8).write(to: url)
            let record = RoundTripRecord(
                host: "nas",
                remoteDirectory: "/srv",
                fetched: remoteEntry("f\(index).txt", bytes: 4, at: 1),
                digest: digest("same"),
                localURL: url)
            others.append(record)
            rig.center.register(record: record)
        }
        #expect(!rig.center.liveRecordIDs.contains(rig.record.id))
        #expect(exists(rig.record.localURL), "the dirty oldest is evicted but kept")
        // One more open evicts a clean record, whose directory goes.
        let overflow = try reopen(rig, content: "v0")
        others.append(overflow)
        rig.center.register(record: overflow)
        #expect(!exists(others[0].localDirectory))
    }

    @Test("the session names a kept copy in the transcript")
    func sessionNamesKeptCopy() throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let directory = try RoundTripRecord.makeOpenDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("edit.txt")
        try Data("unsent".utf8).write(to: url)
        let record = RoundTripRecord(
            host: TestSession.host,
            remoteDirectory: "/srv",
            fetched: remoteEntry("edit.txt", bytes: 2, at: 1),
            digest: digest("v0"),
            localURL: url)
        rig.session.roundTripCenter.register(record: record)
        rig.session.roundTripCenter.retire(id: record.id)
        let lines = rig.session.operation.echo.lines.map(\.text)
        #expect(lines.contains { $0.hasPrefix("retained: local:\(url.path) — ") && $0.contains("never confirmed") })
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
