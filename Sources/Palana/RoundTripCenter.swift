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
//
// Owner ruling, 2026-11-18 (final review F01): retirement never deletes
// an edit the remote has not confirmed. A copy whose bytes differ from
// the record's confirmed remote version keeps its directory, and the
// transcript names where it is; only a copy that matches is deleted.

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
        /// SHA-256 of the local bytes when the offer was delivered.
        ///
        /// The version this upload is expected to land; nil until delivery.
        var deliveredDigest: Data?
    }

    /// What a read of the remote file found after an upload finished.
    struct RemoteReading: Sendable {
        /// The remote listing's entry for the file; nil when absent.
        var entry: FileEntry?
        /// SHA-256 of the remote bytes; nil when absent or unreadable.
        var digest: Data?
    }

    /// True once ``shutDown()`` has run; never cleared.
    private(set) var isShutDown = false

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

    /// Told when retirement keeps a per-open directory because its copy
    /// holds an edit the remote never confirmed — the session names it in
    /// the transcript and the run record.
    var onRetainedCopy: @MainActor (RoundTripRecord) -> Void = { _ in }

    /// Reads what stands at a record's remote path now.
    ///
    /// Its listing entry and content digest; nil when the read itself failed.
    ///
    /// The session wires this to the operation model's listing. After an
    /// upload finishes the center reads the remote once, and advances the
    /// record's conflict baseline only when the remote holds exactly the
    /// bytes that were delivered (review 2026-11-18, F09).
    var readRemoteVersion: @MainActor (RoundTripRecord) async -> RemoteReading? = { _ in nil }

    /// The post-upload remote read, while it runs.
    ///
    /// New offers wait for it: a save delivered before the baseline
    /// settles would be checked against the version before the upload,
    /// and conflict with the operator's own send.
    private var settlingTask: Task<Void, Never>?

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
        guard !isShutDown else { return }
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
    /// temporary directory — unless the copy holds an unconfirmed edit.
    ///
    /// A copy whose bytes are not the record's confirmed remote version
    /// (the fetched one, or the last a send-back was confirmed to land)
    /// is an edit the remote may never have received: queued, declined,
    /// failed, or still in flight. Its directory is kept and named; the
    /// queued send is dropped with the record, so a superseded copy never
    /// sends on its own (owner ruling 2026-11-18, final review F01).
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
        if Self.holdsUnconfirmedEdit(live.record) {
            onRetainedCopy(live.record)
        } else {
            deleteOpenDirectory(live.record.localDirectory)
        }
    }

    /// True when the local copy's bytes are not the record's confirmed remote version.
    ///
    /// An absent copy holds nothing; an unreadable one is kept, because
    /// what it holds cannot be shown to be sent.
    static func holdsUnconfirmedEdit(_ record: RoundTripRecord) -> Bool {
        guard FileManager.default.fileExists(atPath: record.localURL.path) else { return false }
        guard let bytes = try? Data(contentsOf: record.localURL) else { return true }
        return RoundTrip.digest(of: bytes) != record.digest
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
        guard !isShutDown else { return }
        // A retired record's watcher may have a callback already in flight;
        // ignore it.
        guard let live = lives.first(where: { $0.record.id == record.id }) else { return }
        let snapshot = RoundTripWatcher.snapshot(of: live.record.localURL)
        let offer = Offer(record: live.record, snapshot: snapshot)
        if isPanelFree(), pendingQueue.isEmpty, settlingTask == nil {
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
    ///
    /// The record is re-read from the registry, so an offer that waited in
    /// the queue carries the baseline as it stands now — including one a
    /// finished upload advanced while it waited. The local bytes are hashed
    /// here: the version this upload is expected to land.
    private func deliver(_ offer: Offer) {
        var offer = offer
        if let live = lives.first(where: { $0.record.id == offer.record.id }) {
            offer.record = live.record
        }
        offer.deliveredDigest = (try? Data(contentsOf: offer.record.localURL)).map(RoundTrip.digest(of:))
        inFlightUpload = offer
        deliverUpload(offer.record)
    }

    /// Starts the poll task if it is not already running.
    ///
    /// The task checks the panel every 0.3 s and delivers the head of the
    /// queue as soon as it frees, in order. Cancels itself when the queue
    /// drains.
    private func startPollingIfNeeded() {
        guard !isShutDown, canceller.pollTask == nil else { return }
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
        guard !isShutDown else { return true }
        if isPanelFree(), settlingTask == nil, !pendingQueue.isEmpty {
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
    ///
    /// Then the remote baseline: the record's fetched entry and digest
    /// still name the version before the upload, so the next save would
    /// conflict with the operator's own send (review 2026-11-18, F09). The
    /// center reads the remote once and advances the record to that entry
    /// and digest only when the remote bytes are exactly the bytes hashed
    /// at delivery. A local edit made during the transfer, or a remote
    /// writer after the landing, leaves the baseline where it was, so the
    /// next save is checked against it and asks rather than sends.
    func uploadDidFinish() {
        guard let offer = inFlightUpload else { return }
        inFlightUpload = nil
        guard let live = lives.first(where: { $0.record.id == offer.record.id }) else { return }
        if let snapshot = offer.snapshot {
            live.watcher.refreshBaseline(to: snapshot)
        }
        guard let delivered = offer.deliveredDigest else { return }
        let record = live.record
        settlingTask = Task { [weak self] in
            guard let self else { return }
            let reading = await self.readRemoteVersion(record)
            self.settleBaseline(of: record.id, delivered: delivered, reading: reading)
            self.settlingTask = nil
            if !self.pendingQueue.isEmpty { self.startPollingIfNeeded() }
        }
    }

    /// Advances a record's remote baseline to the version a finished
    /// upload landed — only when the remote now holds exactly those bytes.
    private func settleBaseline(of id: RoundTripRecord.ID, delivered: Data, reading: RemoteReading?) {
        guard let reading, let entry = reading.entry, reading.digest == delivered,
            entry.nameData == lives.first(where: { $0.record.id == id })?.record.fetched.nameData,
            let index = lives.firstIndex(where: { $0.record.id == id })
        else { return }
        lives[index].record.fetched = entry
        lives[index].record.digest = delivered
    }

    /// The quit path's stop for the upload producers.
    ///
    /// Cancels every watcher, the poll, and a baseline read in flight, and
    /// drops queued offers, so no save can be delivered once shutdown has
    /// begun (review 2026-11-18, F05, pass 2). Local copies are not touched:
    /// an unsent edit stays on disk where its watch left it.
    func shutDown() {
        isShutDown = true
        for live in lives { live.watcher.cancel() }
        canceller.pollTask?.cancel()
        canceller.pollTask = nil
        settlingTask?.cancel()
        pendingQueue.removeAll()
        inFlightUpload = nil
    }

    /// Waits for a post-upload baseline read to finish — for tests.
    func awaitBaselineSettled() async {
        await settlingTask?.value
    }

    /// The live record for an id, with its current baseline — for tests and diagnostics.
    func liveRecord(id: RoundTripRecord.ID) -> RoundTripRecord? {
        lives.first { $0.record.id == id }?.record
    }
}
