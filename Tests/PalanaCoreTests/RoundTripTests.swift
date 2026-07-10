// RoundTrip battery — real temp files, all on FileManager.default.temporaryDirectory.
// Each test owns its own UUID directory; deferred cleanup runs in every case.
// Async cases use swift-testing confirmation or a polling await with a hard
// timeout — never an unbounded wait. The debounce interval is injected at
// a few milliseconds so the suite stays fast.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Helpers

private let debounce: TimeInterval = 0.05  // 50 ms — fast enough for tests, slow enough for CI

/// Builds a ``FileEntry`` for a local file by reading its attributes.
private func entryForLocalFile(at url: URL) throws -> FileEntry {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = attrs[.size] as? Int64 ?? 0
    let mtime = attrs[.modificationDate] as? Date ?? Date.distantPast
    return FileEntry(
        nameData: Data(url.lastPathComponent.utf8),
        kind: .file,
        size: size,
        modified: mtime,
        permissions: "644",
        owner: "op",
        group: "op")
}

/// Writes `content` to `url`, then returns a ``FileEntry`` reflecting the
/// new on-disk state.
@discardableResult
private func write(_ content: String, to url: URL) throws -> FileEntry {
    try Data(content.utf8).write(to: url)
    return try entryForLocalFile(at: url)
}

/// Builds a ``RoundTripRecord`` pointing at `fileURL` inside `dirURL`.
private func makeRecord(host: String = "koan", dir: String = "/tank", fileURL: URL) -> RoundTripRecord {
    RoundTripRecord(
        host: host,
        remoteDirectory: dir,
        fetched: FileEntry(
            nameData: Data(fileURL.lastPathComponent.utf8),
            kind: .file,
            size: 0,
            modified: Date.distantPast,
            permissions: "644",
            owner: "op",
            group: "op"),
        localURL: fileURL)
}

/// Creates a temp directory and a file inside it.
///
/// Returns (dirURL, fileURL). Caller is responsible for calling
/// `try? FileManager.default.removeItem(at: dirURL)`.
private func makeWorkDir() throws -> (dirURL: URL, fileURL: URL) {
    let dirURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("palana-roundtrip-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let fileURL = dirURL.appendingPathComponent("edit.txt")
    try Data("original".utf8).write(to: fileURL)
    return (dirURL, fileURL)
}

/// Awaits `condition` with a hard timeout, polling every 10 ms.
///
/// Records an `Issue` (not a throw) if the timeout expires before the
/// condition becomes true, so the test still completes cleanly.
private func awaitCondition(
    timeout: TimeInterval = 5.0,
    message: String = "condition timed out",
    condition: @escaping @Sendable () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            Issue.record("\(message)")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
    }
}

// MARK: - RoundTripRecord

@Suite("RoundTripRecord")
struct RoundTripRecordTests {
    @Test("displayName is host space remoteDir/filename")
    func displayName() {
        let record = RoundTripRecord(
            host: "koan",
            remoteDirectory: "/tank/data",
            fetched: FileEntry(
                nameData: Data("notes.txt".utf8),
                kind: .file,
                size: 0,
                modified: .distantPast,
                permissions: "644",
                owner: "op",
                group: "op"),
            localURL: URL(fileURLWithPath: "/tmp/a/notes.txt"))
        #expect(record.displayName == "koan /tank/data/notes.txt")
    }

    @Test("Equatable — same fields compare equal")
    func equatable() {
        let entry = FileEntry(
            nameData: Data("x".utf8),
            kind: .file,
            size: 42,
            modified: .distantPast,
            permissions: "644",
            owner: "op",
            group: "op")
        let url = URL(fileURLWithPath: "/tmp/a/x")
        let lhs = RoundTripRecord(host: "jodo", remoteDirectory: "/rpool", fetched: entry, localURL: url)
        let rhs = RoundTripRecord(host: "jodo", remoteDirectory: "/rpool", fetched: entry, localURL: url)
        #expect(lhs == rhs)
    }

    @Test("Equatable — different host compares unequal")
    func equatableDifferentHost() {
        let entry = FileEntry(
            nameData: Data("x".utf8),
            kind: .file,
            size: 0,
            modified: .distantPast,
            permissions: "644",
            owner: "op",
            group: "op")
        let url = URL(fileURLWithPath: "/tmp/a/x")
        let lhs = RoundTripRecord(host: "koan", remoteDirectory: "/rpool", fetched: entry, localURL: url)
        let rhs = RoundTripRecord(host: "jodo", remoteDirectory: "/rpool", fetched: entry, localURL: url)
        #expect(lhs != rhs)
    }
}

// MARK: - RoundTripWatcher

@Suite("RoundTripWatcher")
struct RoundTripWatcherTests {
    // MARK: In-place write fires callback

    @Test("in-place write fires the callback")
    func inPlaceWriteFiresCallback() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let fired = LockProtected(value: false)

        let watcher = RoundTripWatcher(record: record, debounceInterval: debounce) {
            fired.withLock { $0 = true }
        }
        watcher.start()

        // Give the source a moment to arm.
        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        // Overwrite the file in place (no rename, no atomic replace).
        try Data("changed content".utf8).write(to: fileURL)

        try await awaitCondition(message: "in-place write did not fire callback") {
            fired.withLock { $0 }
        }
        watcher.cancel()
    }

    // MARK: Atomic-replace save fires callback

    @Test("atomic-replace save fires the callback — the case that justifies the directory watch")
    func atomicReplaceFiresCallback() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let fired = LockProtected(value: false)

        let watcher = RoundTripWatcher(record: record, debounceInterval: debounce) {
            fired.withLock { $0 = true }
        }
        watcher.start()

        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        // Atomic replace: write to a sibling temp file, then rename over the target.
        let tmp = dirURL.appendingPathComponent("edit.txt.tmp-\(UUID().uuidString)")
        try Data("atomically replaced content".utf8).write(to: tmp)
        // replaceItemAt performs an atomic rename, closing the original fd.
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)

        try await awaitCondition(message: "atomic-replace save did not fire callback") {
            fired.withLock { $0 }
        }
        watcher.cancel()
    }

    // MARK: Debounce coalesces a burst

    @Test("a burst of writes inside the debounce window fires the callback exactly once")
    func burstCoalescesToOneCallback() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let count = LockProtected(value: 0)

        // This test's OWN debounce is a generous full second — a loaded CI
        // runner spaced 50ms-window writes wider than the window and saw
        // three callbacks (run 29071523768). With back-to-back writes and a
        // one-second window, only a >1s stall between two in-process writes
        // could split the burst.
        let burstDebounce: TimeInterval = 1.0
        let watcher = RoundTripWatcher(record: record, debounceInterval: burstDebounce) {
            count.withLock { $0 += 1 }
        }
        watcher.start()

        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        // Fire five back-to-back in-place writes — no inter-write sleep.
        // The size changes so each event passes the stat-compare gate; the
        // debounce should coalesce them.
        for index in 1...5 {
            try Data("burst \(index)".utf8).write(to: fileURL)
        }

        // Wait for the debounce to settle and one callback to fire.
        try await awaitCondition(message: "burst did not produce a callback") {
            count.withLock { $0 >= 1 }
        }

        // Hold half a window more to confirm no second callback fires.
        try await Task.sleep(nanoseconds: 500_000_000)

        let finalCount = count.withLock { $0 }
        #expect(finalCount == 1, "burst should coalesce to exactly one callback, got \(finalCount)")
        watcher.cancel()
    }

    // MARK: Non-change event does not fire callback

    @Test("a directory event with no stat difference does not fire — touch via sibling create/remove")
    func nonChangeDoesNotFire() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let fired = LockProtected(value: false)

        let watcher = RoundTripWatcher(record: record, debounceInterval: debounce) {
            fired.withLock { $0 = true }
        }
        watcher.start()

        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        // Touch the directory by creating and immediately removing a sibling file.
        // The watched file's size and mtime are unchanged.
        let sibling = dirURL.appendingPathComponent("unrelated-\(UUID().uuidString).txt")
        try Data("sibling".utf8).write(to: sibling)
        try FileManager.default.removeItem(at: sibling)

        // Wait longer than the debounce to confirm nothing fires.
        let waitNs = UInt64(debounce * 4 * 1_000_000_000)
        try await Task.sleep(nanoseconds: waitNs)

        // Access the fileURL to suppress "unused variable" warnings
        _ = fileURL

        let didFire = fired.withLock { $0 }
        #expect(!didFire, "sibling create/remove must not fire the change callback")
        watcher.cancel()
    }

    // MARK: Baseline refresh

    @Test("after refreshBaseline an identical stat fires nothing; a subsequent real edit fires")
    func baselineRefresh() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let count = LockProtected(value: 0)

        let watcher = RoundTripWatcher(record: record, debounceInterval: debounce) {
            count.withLock { $0 += 1 }
        }
        watcher.start()

        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        // Edit the file so the stat changes, wait for callback.
        try Data("first edit".utf8).write(to: fileURL)
        try await awaitCondition(message: "first edit callback not received") {
            count.withLock { $0 >= 1 }
        }

        // Refresh the baseline so the watcher considers the current stat "known".
        watcher.refreshBaseline()

        // Wait a moment for the refresh to propagate (it runs on the watcher's queue).
        let waitNs = UInt64(debounce * 3 * 1_000_000_000)
        try await Task.sleep(nanoseconds: waitNs)

        let countAfterRefresh = count.withLock { $0 }

        // Now make a second real edit — a different size, so stat changes again.
        try Data("second edit with more content to ensure size differs".utf8).write(to: fileURL)
        try await awaitCondition(message: "second edit callback not received") {
            count.withLock { $0 >= countAfterRefresh + 1 }
        }

        let finalCount = count.withLock { $0 }
        #expect(finalCount == countAfterRefresh + 1, "exactly one more callback after the second edit")
        watcher.cancel()
    }

    // MARK: Cancel stops delivery

    @Test("cancel stops callback delivery")
    func cancelStopsDelivery() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let count = LockProtected(value: 0)

        let watcher = RoundTripWatcher(record: record, debounceInterval: debounce) {
            count.withLock { $0 += 1 }
        }
        watcher.start()

        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        // Cancel before any edit.
        watcher.cancel()

        // Wait for the cancel to propagate through the dispatch queue.
        try await Task.sleep(nanoseconds: 150_000_000)  // 150 ms — enough for cancel to propagate

        // Write after cancel — must not fire.
        try Data("post-cancel edit".utf8).write(to: fileURL)

        // Wait longer than the debounce to confirm nothing arrives.
        let waitNs = UInt64(debounce * 4 * 1_000_000_000)
        try await Task.sleep(nanoseconds: waitNs)

        let finalCount = count.withLock { $0 }
        #expect(finalCount == 0, "no callbacks after cancel; got \(finalCount)")
    }

    // MARK: Double-cancel is safe

    @Test("double-cancel does not crash or produce spurious callbacks")
    func doubleCancelIsSafe() async throws {
        let (dirURL, fileURL) = try makeWorkDir()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let record = makeRecord(fileURL: fileURL)
        let watcher = RoundTripWatcher(record: record, debounceInterval: debounce) {}
        watcher.start()

        try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms — enough for source to arm under load

        watcher.cancel()
        watcher.cancel()  // must not crash

        // Access fileURL to suppress unused warning
        _ = fileURL
    }
}

// MARK: - RoundTrip.changedSinceFetch

@Suite("RoundTrip.changedSinceFetch")
struct ChangedSinceFetchTests {
    private func entry(size: Int64 = 0, mtime: Date = .distantPast, permissions: String = "644") -> FileEntry {
        FileEntry(
            nameData: Data("notes.txt".utf8),
            kind: .file,
            size: size,
            modified: mtime,
            permissions: permissions,
            owner: "op",
            group: "op")
    }

    @Test("size change — reports changed")
    func sizeChange() {
        let baseline = entry(size: 100, mtime: .distantPast)
        let current = entry(size: 200, mtime: .distantPast)
        #expect(RoundTrip.changedSinceFetch(baseline: baseline, current: current))
    }

    @Test("mtime change — reports changed")
    func mtimeChange() {
        let baseline = entry(size: 100, mtime: Date(timeIntervalSince1970: 1_000_000))
        let current = entry(size: 100, mtime: Date(timeIntervalSince1970: 1_100_000))
        #expect(RoundTrip.changedSinceFetch(baseline: baseline, current: current))
    }

    @Test("size and mtime both change — reports changed")
    func sizAndMtimeBothChange() {
        let baseline = entry(size: 100, mtime: Date(timeIntervalSince1970: 1_000_000))
        let current = entry(size: 200, mtime: Date(timeIntervalSince1970: 1_100_000))
        #expect(RoundTrip.changedSinceFetch(baseline: baseline, current: current))
    }

    @Test("identical size and mtime — not changed")
    func identicalSizeAndMtime() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let baseline = entry(size: 100, mtime: mtime)
        let current = entry(size: 100, mtime: mtime)
        #expect(!RoundTrip.changedSinceFetch(baseline: baseline, current: current))
    }

    @Test("permissions-only difference — not changed")
    func permissionsOnlyDifference() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let baseline = entry(size: 100, mtime: mtime, permissions: "644")
        let current = entry(size: 100, mtime: mtime, permissions: "755")
        #expect(!RoundTrip.changedSinceFetch(baseline: baseline, current: current))
    }

    @Test("the changed-since-fetch note names size and date, locale aside")
    func changedNoteShape() {
        // Date and byte rendering are locale-dependent — pin the frame,
        // not the middle.
        let current = entry(size: 2048, mtime: Date(timeIntervalSince1970: 1_000_000))
        let note = RoundTrip.changedSinceFetchNote(current: current)
        #expect(note.hasPrefix("remote changed since fetch — "))
        #expect(note.hasSuffix(" now stands there"))
        #expect(note.contains(" · "))
    }
}

// MARK: - LockProtected

/// A value protected by an `NSLock`.
///
/// Used to share state between the test body and the watcher callback
/// across concurrency domains.
///
/// `@unchecked Sendable` is justified: all access to `value` goes through
/// `withLock`, which acquires and releases the lock on the way in and out.
/// The lock makes the mutable-state access thread-safe; the unchecked
/// annotation tells Swift Concurrency to trust that guarantee.
private final class LockProtected<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<Return>(_ body: (inout Value) -> Return) -> Return {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
