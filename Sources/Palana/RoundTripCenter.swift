// RoundTripCenter — the app-side owner of live round-trip records and
// their watchers. One record per remote open, one watcher per record.
// Offers uploads to the operation model when the watcher fires; holds
// the offer when the panel is busy and re-offers when it frees.
//
// Decision 3 (ho-9.10): no plan is ever evicted by a save. The center
// polls the operation model's phase on a short timer when it has a
// pending offer, re-offering once the panel is free.

import Foundation
import PalanaCore

/// The app-side registry of live round-trip watches.
///
/// Every remote open registers a ``RoundTripRecord`` here; the center
/// starts a ``RoundTripWatcher`` for it and manages its lifetime. On a
/// debounced save the center offers the upload to the operation model —
/// waiting politely if the panel is busy, re-offering when it frees.
///
/// Records live for the app's run. Cancel-all fires on deinit via a
/// nonisolated watcher roster that is safe to drain outside the main actor.
@MainActor
@Observable
final class RoundTripCenter {
    /// A live record paired with its watcher.
    private struct Live {
        /// The record tracking this remote open.
        var record: RoundTripRecord
        /// The watcher that detects saves on the local copy.
        var watcher: RoundTripWatcher
    }

    /// All currently watched records, in registration order.
    private var lives: [Live] = []

    /// A `Sendable` holder for resources that must be cancelled at deinit.
    ///
    /// `deinit` cannot access `@MainActor`-isolated storage in Swift 6.
    /// Cancelable objects are stored here (written from the main actor,
    /// read only at deinit after all actor work has finished).
    ///
    /// `RoundTripWatcher.cancel()` is thread-safe (dispatches on its own
    /// internal queue). `Task.cancel()` is nonisolated.
    private final class DeinitCanceller: @unchecked Sendable {
        /// Watchers registered during the session.
        var watchers: [RoundTripWatcher] = []
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

    /// A pending offer waiting for the panel to free.
    ///
    /// At most one offer is queued at a time — a second save while an offer
    /// is pending replaces the queued record (the latest save is what matters).
    private var pendingOffer: RoundTripRecord?

    /// The operation model to offer uploads into.
    ///
    /// Weak reference — the center must not extend the model's lifetime.
    /// Set once by the session after construction.
    weak var operationModel: OperationModel?

    /// Creates an empty center.
    init() {}

    deinit {
        canceller.cancelAll()
    }

    // MARK: - Registration

    /// Registers a round-trip record and starts its watcher.
    ///
    /// The watcher fires on the center's behalf: a debounced save hops to
    /// the main actor and calls ``offerOrQueue(record:)``.
    ///
    /// - Parameter record: The record to watch.
    func register(record: RoundTripRecord) {
        let watcher = RoundTripWatcher(record: record) { [weak self] in
            // Delivered off the watcher's internal queue — hop to main actor.
            Task { @MainActor [weak self] in
                self?.offerOrQueue(record: record)
            }
        }
        lives.append(Live(record: record, watcher: watcher))
        canceller.watchers.append(watcher)
        watcher.start()
    }

    // MARK: - Offer machinery

    /// Offers the upload now when the panel is free; queues it otherwise.
    ///
    /// "Free" means the operation model's phase is idle, finished, failed,
    /// or cancelled — any phase where the panel is not mid-plan.
    /// Decision 3 (ho-9.10): a live plan is never evicted.
    ///
    /// - Parameter record: The record whose local file just changed.
    func offerOrQueue(record: RoundTripRecord) {
        guard let model = operationModel else { return }
        if isFree(model) {
            deliver(record: record, to: model)
        } else {
            pendingOffer = record
            startPollingIfNeeded()
        }
    }

    /// True when the operation model's phase allows a new offer.
    private func isFree(_ model: OperationModel) -> Bool {
        switch model.phase {
        case .idle, .finished, .failed, .cancelled:
            return true
        case .naming, .gathering, .ready, .enacting:
            return false
        }
    }

    /// Delivers the upload offer directly to the operation model.
    private func deliver(record: RoundTripRecord, to model: OperationModel) {
        pendingOffer = nil
        canceller.pollTask?.cancel()
        canceller.pollTask = nil
        model.beginRoundTripUpload(record: record)
    }

    /// Starts the poll task if it is not already running.
    ///
    /// The task checks the phase every 0.3 s and delivers the pending offer
    /// as soon as the panel frees. Cancels itself when the offer is delivered
    /// or cleared.
    private func startPollingIfNeeded() {
        guard canceller.pollTask == nil else { return }
        canceller.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                guard let model = self.operationModel else {
                    self.pendingOffer = nil
                    return
                }
                if let offer = self.pendingOffer, self.isFree(model) {
                    self.deliver(record: offer, to: model)
                    return
                }
                if self.pendingOffer == nil { return }
            }
        }
    }

    // MARK: - Baseline refresh

    /// Refreshes the watcher baseline for a record after a successful upload.
    ///
    /// Prevents the upload itself from triggering an immediate re-offer on
    /// the next watcher event — the stat baseline advances past the just-sent copy.
    ///
    /// - Parameter record: The record whose upload just finished.
    func refreshBaseline(for record: RoundTripRecord) {
        guard let live = lives.first(where: { $0.record == record }) else { return }
        live.watcher.refreshBaseline()
    }

    /// Refreshes the watcher baseline for any live record whose host and remote
    /// directory match the given pair.
    ///
    /// Called after a round-trip upload finishes — the plan's destination names
    /// the host and directory; this finds the matching record without requiring
    /// the caller to hold the exact ``RoundTripRecord`` value.
    ///
    /// - Parameters:
    ///   - host: The SSH alias of the remote host.
    ///   - remoteDirectory: The remote directory the upload targeted.
    func refreshBaselineIfMatches(host: String, remoteDirectory: String) {
        for live in lives
        where live.record.host == host && live.record.remoteDirectory == remoteDirectory {
            live.watcher.refreshBaseline()
        }
    }
}
