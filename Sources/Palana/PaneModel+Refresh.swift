// PaneModel+Refresh — the pane keeps itself current. A local pane watches
// its directory through the filesystem and re-reads, debounced, when
// anything in it changes; a remote pane re-lists on a poll while the app
// is frontmost, and once more the moment it comes back to the front. Both
// re-read quietly: no `reading…`, no cursor move, no lost selection, no
// persist — the pointing never changed (hands session, 2026-09-07: a file
// deleted from a terminal stayed listed until a manual re-read).
//
// Lifecycle follows RoundTripCenter's discipline: one watcher per pointed
// local directory, re-pointing closes the old one before opening the new,
// retirement drains everything, and a descriptor is closed by the cancel
// handler of the source that owns it — never by whatever the pane holds
// when the handler eventually runs.

import AppKit
import Foundation
import PalanaCore

/// A watch over one local directory — fires once per settled burst.
///
/// One `O_EVTONLY` descriptor, one dispatch source over it. Any write,
/// rename, delete, or attribute change on the directory schedules the
/// callback after a short debounce; a burst (an rsync landing fifty
/// files) collapses into one call. Delivered off the watcher's own
/// queue — callers that touch the pane hop to the main actor.
final class DirectoryWatcher: @unchecked Sendable {
    /// How long a burst settles before the callback fires.
    static let defaultDebounce: TimeInterval = 0.3

    private let path: String
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    /// Serialises every piece of mutable state below.
    private let queue = DispatchQueue(label: "net.sageframe.palana.pane-watcher", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var cancelled = false
    private var liveDescriptors = 0

    /// A watcher over `path`, not yet started.
    ///
    /// - Parameters:
    ///   - path: The local directory to watch.
    ///   - debounce: How long a burst settles before `onChange` fires.
    ///   - onChange: Called once per settled change, off the main actor.
    init(
        path: String,
        debounce: TimeInterval = DirectoryWatcher.defaultDebounce,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.path = path
        self.debounce = debounce
        self.onChange = onChange
    }

    /// Opens the descriptor and arms the source — once; later calls are no-ops.
    func start() {
        queue.async { [weak self] in
            guard let self, !self.cancelled, self.source == nil else { return }
            self.startLocked()
        }
    }

    /// Stops the watch — idempotent.
    ///
    /// The descriptor closes in the source's cancel handler; no callback
    /// fires after this.
    func cancel() {
        queue.async { [weak self] in
            guard let self, !self.cancelled else { return }
            self.cancelled = true
            self.pending?.cancel()
            self.pending = nil
            self.source?.cancel()
        }
    }

    /// The descriptors this watcher holds open — for tests.
    ///
    /// One while watching, zero once the cancel handler has run.
    func liveDescriptorCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.liveDescriptors ?? 0)
            }
        }
    }

    // MARK: - On the queue

    private func startLocked() {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        liveDescriptors += 1
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue)
        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        // Capture the descriptor — the handler closes the one THIS source
        // owns, whatever the watcher holds by the time it runs.
        source.setCancelHandler { [weak self] in
            close(descriptor)
            self?.liveDescriptors -= 1
        }
        self.source = source
        source.resume()
    }

    private func scheduleChange() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled else { return }
            self.pending = nil
            self.onChange()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}

/// The self-refresh a pane holds.
///
/// Drained from `deinit`, which cannot reach main-actor storage in Swift 6.
/// Mutated only on the main actor; read at retirement after all actor work
/// has finished.
final class PaneRefresher: @unchecked Sendable {
    /// The watcher over the pointed local directory, nil for a remote or
    /// unpointed pane.
    var watcher: DirectoryWatcher?
    /// The remote poll loop, nil for a local or unpointed pane.
    var pollTask: Task<Void, Never>?

    /// Closes the watcher and stops the poll — idempotent.
    func cancelAll() {
        watcher?.cancel()
        watcher = nil
        pollTask?.cancel()
        pollTask = nil
    }
}

/// The gates a self-refresh consults — every one injectable.
struct RefreshPolicy {
    /// How often a remote pane re-lists while the app is frontmost.
    var pollInterval: Duration = .seconds(10)
    /// Whether the app is frontmost — a poll never runs while it is not.
    var isAppActive: @MainActor () -> Bool = { NSApplication.shared.isActive }
    /// True after a quiet read failed.
    ///
    /// The poll stands down until the next activation or loud read. A
    /// local watcher is not affected.
    var suspended = false
    /// True when the directory changed while a read was in flight — the
    /// settled read runs one more quiet pass so the change is not lost.
    var changePending = false
}

extension PaneModel {
    // MARK: - Installing the watch or the poll

    /// Arms the right self-refresh for a landing.
    ///
    /// A directory watcher on this Mac, the poll loop for a remote host.
    /// Called from `commit`.
    ///
    /// A loud landing rebuilds the local watcher — the directory may have
    /// been replaced under the old descriptor — closing the old one first;
    /// a quiet one keeps what it has. Re-pointing from local to remote
    /// closes the watcher; from remote to local, stops the poll.
    ///
    /// - Parameters:
    ///   - host: The host that just committed.
    ///   - path: The directory that just committed.
    ///   - rebuild: True for a loud read — the watcher is opened afresh.
    func keepCurrent(host: String, path: String, rebuild: Bool) {
        if isLocalHost(host) {
            refresher.pollTask?.cancel()
            refresher.pollTask = nil
            guard rebuild || refresher.watcher == nil else { return }
            refresher.watcher?.cancel()
            let watcher = DirectoryWatcher(path: path) { [weak self] in
                Task { @MainActor [weak self] in self?.noteDirectoryChanged() }
            }
            refresher.watcher = watcher
            watcher.start()
        } else {
            refresher.watcher?.cancel()
            refresher.watcher = nil
            startPollingIfNeeded()
        }
    }

    /// The watcher fired: re-read now, or after the read already in
    /// flight settles — a change that lands mid-read is never dropped.
    func noteDirectoryChanged() {
        if isReadInFlight || isReading {
            refreshPolicy.changePending = true
        } else {
            refreshQuietly()
        }
    }

    /// A read settled: run the pass a mid-read change asked for.
    func readDidSettle() {
        guard refreshPolicy.changePending else { return }
        refreshPolicy.changePending = false
        refreshQuietly()
    }

    // MARK: - The remote poll

    /// Starts the poll loop once; each tick runs the gated re-list.
    ///
    /// The loop itself never stops while the pane is remote — the gates
    /// in ``pollTick()`` decide whether a tick does anything, so a pane
    /// that was inactive, busy, or suspended simply picks up at the next
    /// tick it is allowed.
    private func startPollingIfNeeded() {
        guard refresher.pollTask == nil else { return }
        let interval = refreshPolicy.pollInterval
        refresher.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.pollTick()
            }
        }
    }

    /// One poll: re-lists the remote directory when every gate is open.
    ///
    /// The gates: the app frontmost, the pane ready on a remote host and
    /// showing files, no read in flight, no failure standing. Exposed so
    /// tests pump it directly instead of waiting on the interval.
    func pollTick() {
        guard let host = state.host, !isLocalHost(host), !refreshPolicy.suspended, refreshPolicy.isAppActive()
        else { return }
        refreshQuietly()
    }

    /// The app came to the front: a standing failure is forgiven and a
    /// remote pane re-lists once, now, rather than at the next tick.
    func applicationDidBecomeActive() {
        refreshPolicy.suspended = false
        guard let host = state.host, !isLocalHost(host) else { return }
        refreshQuietly()
    }

    // MARK: - The quiet cursor

    /// Keeps the cursor where it stood across a re-read, or moves it to
    /// its nearest neighbor when its entry is gone.
    ///
    /// `PaneState.replaceEntries` keeps a surviving cursor by id and
    /// refoots a dead one on the first row; this puts it on the row that
    /// now sits where the vanished entry was — the one below it, or the
    /// last row when it was the last.
    ///
    /// - Parameters:
    ///   - previous: The cursor before the entries were replaced.
    ///   - index: Its row index before, nil when there was no cursor.
    func refootCursor(from previous: FileEntry.ID?, at index: Int?) {
        guard let previous, let index, state.cursor != previous, !rows.isEmpty else { return }
        state.cursor = rows[min(index, rows.count - 1)].id
    }
}
