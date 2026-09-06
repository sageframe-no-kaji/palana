// RoundTripCenter — the app-side owner of live round-trip records and
// their watchers. One record per remote open, one watcher per record.
// Offers uploads to the operation model when the watcher fires; holds
// the offer when the panel is busy and re-offers when it frees.
//
// Decision 3 (ho-9.10): no plan is ever evicted by a save. The center
// polls the operation model's phase on a short timer while it has queued
// offers, delivering each as soon as the panel frees.
//
// Lifecycle (review repair, Task 4): records retire explicitly — a
// re-open of the same remote file supersedes the earlier record, and a
// bounded per-session cap evicts the oldest when it is exceeded. Retiring
// a record cancels its watcher, drops its registry state, removes its
// queued offers, and deletes its per-open temporary directory. Cleanup
// does not wait for app termination.

import Foundation
import PalanaCore

/// The app-side registry of live round-trip watches.
///
/// Every remote open registers a ``RoundTripRecord`` here; the center
/// starts a watcher for it and manages its lifetime. On a debounced save
/// the center offers the upload to the operation model — waiting politely
/// if the panel is busy, re-offering when it frees. Distinct files each
/// hold their place in a FIFO queue; repeated saves of one file coalesce.
///
/// Cancel-all fires on deinit via a nonisolated watcher roster that is
/// safe to drain outside the main actor.
@MainActor
@Observable
final class RoundTripCenter {
    /// The bounded per-session cap on concurrent round-trip records.
    ///
    /// When registering would exceed it, the oldest record is retired
    /// first (its watcher cancelled, its temp directory deleted). This is
    /// the documented eviction policy: cleanup never depends solely on app
    /// termination, and there is no editor-close signal to key on.
    static let maxRecords = 32

    /// A live record paired with its watcher.
    private struct Live {
        /// The record tracking this remote open.
        var record: RoundTripRecord
        /// The watcher that detects saves on the local copy.
        var watcher: RoundTripWatching
    }

    /// A queued offer: the record and a snapshot of the file at delivery
    /// time, so completion can advance the baseline to exactly what was sent.
    private struct Offer {
        var record: RoundTripRecord
        var snapshot: RoundTripWatcher.Snapshot?
    }

    /// All currently watched records, in registration order (oldest first).
    private var lives: [Live] = []

    /// A factory for the watcher of a record.
    ///
    /// The real ``RoundTripWatcher`` in production, a spy in tests. Takes the
    /// record and the change callback (already hopped nowhere — the center wraps it).
    private let makeWatcher: (RoundTripRecord, @escaping @Sendable () -> Void) -> RoundTripWatching

    /// A `Sendable` holder for resources that must be cancelled at deinit.
    ///
    /// `deinit` cannot access `@MainActor`-isolated storage in Swift 6.
    /// Cancelable objects are stored here (written from the main actor,
    /// read only at deinit after all actor work has finished).
    private final class DeinitCanceller: @unchecked Sendable {
        /// Watchers registered during the session.
        var watchers: [RoundTripWatching] = []
        /// The current poll task, if any.
        var pollTask: Task<Void, Never>?

        /// Cancels everything held by this canceller.
        func cancelAll() {
            for watcher in watchers { watcher.cancel() }
            pollTask?.cancel()
        }
    }

    /// The nonisolated cancellable holder — safe because `DeinitCanceller`
    /// is `@unchecked Sendable` and its mutation is gated to the main actor.
    private let canceller = DeinitCanceller()

    /// Offers waiting for the panel to free, in FIFO order.
    ///
    /// Distinct records keep their order; a repeated save of a record
    /// already queued coalesces in place (the latest snapshot wins, the
    /// position is kept) so no distinct file's save can displace another's.
    private var pendingQueue: [Offer] = []

    /// The record currently being uploaded, with the snapshot delivered.
    ///
    /// Set when an offer is delivered; consulted on the next finish to
    /// advance exactly that record's baseline. An ordinary copy finishing
    /// while this is nil refreshes nothing.
    private var inFlightUpload: Offer?

    /// Whether the panel is free to receive a new offer.
    ///
    /// The session wires this to the operation model's phase. A closure
    /// rather than a model reference so the center depends on the one fact
    /// it needs and stays testable with a plain toggle.
    var isPanelFree: @MainActor () -> Bool = { true }

    /// Delivers one upload offer.
    ///
    /// The session wires this to `OperationModel.beginRoundTripUpload`. A
    /// closure so the center never reaches into the model and tests can
    /// observe deliveries directly.
    var deliverUpload: @MainActor (RoundTripRecord) -> Void = { _ in }

    /// The production watcher factory — a real ``RoundTripWatcher``.
    nonisolated private static func defaultWatcher(
        _ record: RoundTripRecord,
        _ onChange: @escaping @Sendable () -> Void
    ) -> RoundTripWatching {
        RoundTripWatcher(record: record, onChange: onChange)
    }

    /// Creates a center over a watcher factory.
    ///
    /// - Parameter makeWatcher: Builds a watcher for a record. Defaults to
    ///   the production ``RoundTripWatcher``; tests inject a spy.
    init(
        makeWatcher: @escaping (RoundTripRecord, @escaping @Sendable () -> Void) -> RoundTripWatching =
            RoundTripCenter.defaultWatcher
    ) {
        self.makeWatcher = makeWatcher
    }

    deinit {
        canceller.cancelAll()
    }

    // MARK: - Registration

    /// Registers a round-trip record and starts its watcher.
    ///
    /// A re-open of the same remote file (same host and full path) retires
    /// the earlier record first — one live watcher per remote file. When
    /// the registry is at ``maxRecords``, the oldest record is retired to
    /// make room. The watcher fires on the center's behalf: a debounced
    /// save hops to the main actor and enqueues an offer.
    ///
    /// - Parameter record: The record to watch.
    func register(record: RoundTripRecord) {
        // Deduplicate: a fresh open of the same remote file supersedes the old.
        if let existing = lives.first(where: { $0.record.identity == record.identity }) {
            retire(id: existing.record.id)
        }
        // Bounded eviction: retire the oldest until there is room.
        while lives.count >= Self.maxRecords, let oldest = lives.first {
            retire(id: oldest.record.id)
        }
        let watcher = makeWatcher(record) { [weak self] in
            // Delivered off the watcher's internal queue — hop to main actor.
            Task { @MainActor [weak self] in
                self?.offerOrQueue(record: record)
            }
        }
        lives.append(Live(record: record, watcher: watcher))
        canceller.watchers.append(watcher)
        watcher.start()
    }

    /// Retires a record: cancels its watcher, drops its registry and queue
    /// state, clears it from the in-flight slot, and deletes its per-open
    /// temporary directory.
    ///
    /// Idempotent — a record already gone is a no-op. Safe to call from
    /// dedup, eviction, or an explicit close.
    ///
    /// - Parameter id: The record's per-open id.
    func retire(id: RoundTripRecord.ID) {
        guard let index = lives.firstIndex(where: { $0.record.id == id }) else { return }
        let live = lives.remove(at: index)
        live.watcher.cancel()
        canceller.watchers.removeAll { $0 === live.watcher }
        pendingQueue.removeAll { $0.record.id == id }
        if inFlightUpload?.record.id == id { inFlightUpload = nil }
        deleteOpenDirectory(live.record.localDirectory)
    }

    /// Deletes a per-open temporary directory, guarded so only directories
    /// under `palana-open/` are ever removed.
    private func deleteOpenDirectory(_ directory: URL) {
        guard RoundTripRecord.isOpenDirectory(directory) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// The number of live records — the count of watchers and per-open
    /// directories currently held.
    var liveRecordCount: Int { lives.count }

    /// The ids of the live records, oldest first — for tests and diagnostics.
    var liveRecordIDs: [RoundTripRecord.ID] { lives.map(\.record.id) }

    /// The ids of the queued offers, in delivery order — for tests and diagnostics.
    var pendingRecordIDs: [RoundTripRecord.ID] { pendingQueue.map(\.record.id) }

    // MARK: - Offer machinery

    /// Offers the upload now when the panel is free; queues it otherwise.
    ///
    /// "Free" means the operation model's phase is idle, finished, failed,
    /// or cancelled — any phase where the panel is not mid-plan.
    /// Decision 3 (ho-9.10): a live plan is never evicted.
    ///
    /// - Parameter record: The record whose local file just changed.
    func offerOrQueue(record: RoundTripRecord) {
        // A retired record's watcher may have a callback already in flight;
        // ignore it.
        guard let live = lives.first(where: { $0.record.id == record.id }) else { return }
        let snapshot = RoundTripWatcher.snapshot(of: live.record.localURL)
        let offer = Offer(record: live.record, snapshot: snapshot)
        if isPanelFree(), pendingQueue.isEmpty {
            deliver(offer)
        } else {
            enqueue(offer)
            startPollingIfNeeded()
        }
    }

    /// Enqueues an offer, coalescing a repeated save of a record already
    /// queued (latest snapshot wins, position kept).
    private func enqueue(_ offer: Offer) {
        if let index = pendingQueue.firstIndex(where: { $0.record.id == offer.record.id }) {
            pendingQueue[index] = offer
        } else {
            pendingQueue.append(offer)
        }
    }

    /// Delivers the upload offer.
    private func deliver(_ offer: Offer) {
        inFlightUpload = offer
        deliverUpload(offer.record)
    }

    /// Starts the poll task if it is not already running.
    ///
    /// The task checks the panel every 0.3 s and delivers the head of the
    /// queue as soon as it frees, in order. Cancels itself when the queue
    /// drains.
    private func startPollingIfNeeded() {
        guard canceller.pollTask == nil else { return }
        canceller.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                if self.drainOneIfFree() { return }
            }
        }
    }

    /// Delivers the head of the queue if the panel is free.
    ///
    /// Returns true when polling should stop (queue drained). Exposed for
    /// tests: they pump this directly rather than waiting on the 0.3 s poll timer.
    @discardableResult
    func drainOneIfFree() -> Bool {
        if isPanelFree(), !pendingQueue.isEmpty {
            let offer = pendingQueue.removeFirst()
            deliver(offer)
        }
        if pendingQueue.isEmpty {
            canceller.pollTask?.cancel()
            canceller.pollTask = nil
            return true
        }
        return false
    }

    // MARK: - Baseline refresh

    /// Refreshes the baseline of the record whose upload just finished.
    ///
    /// Called from the session's finish hook. Advances only the exact
    /// in-flight record's watcher, and only to the snapshot that was
    /// delivered — a save that landed after delivery differs from that
    /// snapshot, so the watcher leaves the baseline alone and the unsent
    /// edit survives (review: broad-baseline-refresh, lost-queued-saves).
    /// An ordinary copy (no in-flight upload) refreshes nothing.
    func uploadDidFinish() {
        guard let offer = inFlightUpload else { return }
        inFlightUpload = nil
        guard let snapshot = offer.snapshot else { return }
        guard let live = lives.first(where: { $0.record.id == offer.record.id }) else { return }
        live.watcher.refreshBaseline(to: snapshot)
    }
}
