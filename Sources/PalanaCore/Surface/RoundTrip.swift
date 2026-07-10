// Round-trip editing machinery — the record of what was fetched, the
// directory + file watcher that detects saves (including atomic-replace
// saves), and the pure comparison that names a remote that moved
// underneath the edit. No persistence: records live for the app's run.
// No FSEvents: DispatchSource on the directory fd survives atomic replace.

import Foundation

// MARK: - RoundTripRecord

/// The memory of one remote file open — what was fetched and where the
/// local copy lives.
///
/// The fetch-time ``FileEntry`` is the baseline for the changed-since-fetch
/// question; the ``localURL`` points into the per-open UUID directory the
/// pane owns. Records live for the app's run; there is no persistence
/// across launches.
public struct RoundTripRecord: Sendable, Equatable {
    /// The SSH alias of the remote host the file came from.
    public var host: String

    /// The remote directory that contains the file.
    public var remoteDirectory: String

    /// The ``FileEntry`` as it was at fetch time — the conflict-detection baseline.
    public var fetched: FileEntry

    /// The local URL where the fetched copy lives.
    public var localURL: URL

    /// A human-readable label: `host remote/dir/filename`.
    public var displayName: String {
        "\(host) \(remoteDirectory)/\(fetched.name)"
    }

    /// Assembles a round-trip record.
    ///
    /// - Parameters:
    ///   - host: The SSH alias of the remote host.
    ///   - remoteDirectory: The directory on the remote that contains the file.
    ///   - fetched: The entry as reported by the remote listing at fetch time.
    ///   - localURL: The URL of the local copy in the per-open UUID directory.
    public init(host: String, remoteDirectory: String, fetched: FileEntry, localURL: URL) {
        self.host = host
        self.remoteDirectory = remoteDirectory
        self.fetched = fetched
        self.localURL = localURL
    }
}

// MARK: - RoundTripWatcher

/// A change detector for one round-trip record.
///
/// Uses a dual `DispatchSource` strategy to detect both kinds of save:
///
/// - **In-place writes** (overwrite in situ): watched via a `.write` source
///   on the file's own fd. This is the simple case — the file fd stays
///   alive and its write event fires.
///
/// - **Atomic-replace saves** (write-temp-then-rename): editors that save
///   this way silently destroy the original file, killing any fd-based watch
///   on it. The directory's `O_EVTONLY` fd survives the rename because the
///   *directory* changed (a name was swapped out). The directory watch fires,
///   the stat compare confirms the file's size or mtime changed, and the
///   callback is delivered. After the atomic replace, `rebindFileFD()` opens
///   a fresh fd on the new inode so in-place watches resume.
///
/// Both sources share the same debounce queue and stat-compare gate, so a
/// burst of events (however they arrive) coalesces to one callback.
///
/// ## Lifecycle
///
/// Call ``start()`` to begin watching. Call ``cancel()`` to stop; cancel is
/// idempotent and safe to call multiple times. Both file descriptors are
/// closed in their respective cancel handlers — no leaks.
///
/// ## Sendable / concurrency
///
/// `RoundTripWatcher` is `@unchecked Sendable`. All mutable state
/// (`lastSeen`, `debounceWorkItem`, `cancelled`, `dirSource`,
/// `fileSource`) is protected by a single serial `DispatchQueue` created
/// at init. No state is ever accessed off that queue. Each dispatch
/// source's cancel handler closes the fd it captured at arm time. The
/// callback is `@Sendable` and is delivered on the watcher's internal
/// queue; callers that update UI must dispatch to `@MainActor`.
public final class RoundTripWatcher: @unchecked Sendable {
    // MARK: - Stat snapshot

    /// The size-and-mtime pair used for stat-compare.
    private struct StatSnapshot: Equatable {
        var size: Int64
        var mtime: Date
    }

    // MARK: - Internal state (all access serialised on `queue`)

    /// The record this watcher tracks.
    public let record: RoundTripRecord

    /// The debounce interval in seconds.
    ///
    /// Injected at init for testability; defaults to 500 ms in production.
    private let debounceInterval: TimeInterval

    /// The callback to fire when a real change is detected (after debounce).
    private let onChange: @Sendable () -> Void

    /// The serial queue that serialises all mutable state.
    private let queue: DispatchQueue

    /// The last-known stat of the watched file.
    ///
    /// Updated by ``refreshBaseline()`` after a successful upload.
    private var lastSeen: StatSnapshot?

    /// The pending debounce work item.
    private var debounceWorkItem: DispatchWorkItem?

    /// True once ``cancel()`` has been called.
    private var cancelled: Bool = false

    /// The dispatch source on the directory fd.
    private var dirSource: DispatchSourceFileSystemObject?

    /// The dispatch source on the file fd.
    private var fileSource: DispatchSourceFileSystemObject?

    // MARK: - Init

    /// Creates a watcher for a round-trip record.
    ///
    /// - Parameters:
    ///   - record: The record whose local file should be watched.
    ///   - debounceInterval: How long to wait for the burst to settle before
    ///     firing `onChange`. Defaults to 500 ms; inject a shorter value in tests.
    ///   - onChange: Called once per settled change. Delivered off the watcher's
    ///     internal queue — callers that update UI must dispatch to `@MainActor`.
    public init(
        record: RoundTripRecord,
        debounceInterval: TimeInterval = 0.5,
        onChange: @Sendable @escaping () -> Void
    ) {
        self.record = record
        self.debounceInterval = debounceInterval
        self.onChange = onChange
        self.queue = DispatchQueue(label: "net.sageframe.palana.roundtrip-watcher", qos: .utility)
    }

    // MARK: - Lifecycle

    /// Starts watching the record's local file and directory for changes.
    ///
    /// Calling `start()` more than once is a no-op after the first call.
    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.cancelled, self.dirSource == nil else { return }
            self.startLocked()
        }
    }

    /// Stops the watcher.
    ///
    /// Safe to call multiple times (idempotent). After cancellation no
    /// further callbacks will be delivered. Both file descriptors are
    /// closed in their respective cancel handlers.
    public func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.cancelled else { return }
            self.cancelled = true
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.fileSource?.cancel()
            self.dirSource?.cancel()
            // FDs are closed in the cancel handlers (see startLocked).
        }
    }

    /// Refreshes the stat baseline to the file's current size and mtime.
    ///
    /// Call this after a successful upload so the next save starts from the
    /// new baseline rather than triggering an immediate spurious callback.
    public func refreshBaseline() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastSeen = self.statFile()
        }
    }

    // MARK: - Private: start (runs on queue)

    private func startLocked() {
        // Open the directory source first — it never goes stale.
        let dirURL = record.localURL.deletingLastPathComponent()
        let dfd = open(dirURL.path, O_EVTONLY)
        guard dfd >= 0 else { return }

        // Snapshot the baseline before arming any source.
        lastSeen = statFile()

        let dir = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dfd,
            eventMask: .write,
            queue: queue)

        dir.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }

        // Capture the fd — the handler must close the fd THIS source owns,
        // never whatever self.dirFD holds when the handler eventually runs.
        dir.setCancelHandler {
            close(dfd)
        }

        dirSource = dir
        dir.resume()

        // Also open a file source for in-place writes.
        armFileFD()
    }

    // MARK: - Private: file-fd arm/rebind (runs on queue)

    /// Opens a fresh `O_EVTONLY` fd on the file and arms a write source.
    ///
    /// Safe to call when `fileFD` is already -1 (initial arm) or after
    /// the old fd was invalidated by an atomic replace.
    private func armFileFD() {
        let ffd = open(record.localURL.path, O_EVTONLY)
        guard ffd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: ffd,
            eventMask: .write,
            queue: queue)

        src.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }

        // Capture the fd — after an atomic-replace rebind the old source's
        // cancel handler runs while self.fileFD may already name the NEW
        // fd; closing by capture removes the race class entirely.
        src.setCancelHandler {
            close(ffd)
        }

        fileSource = src
        src.resume()
    }

    // MARK: - Private: event handling (runs on queue)

    /// Handles a `.write` event on the directory fd.
    ///
    /// Directory events fire on atomic-replace saves (and on any other
    /// directory-content change). Stat-compare gates the real change test;
    /// after a genuine change the file fd is rebound to the new inode.
    private func handleDirectoryEvent() {
        let current = statFile()
        guard current != lastSeen else { return }
        lastSeen = current

        // The file may have been replaced — rebind the file fd to the
        // new inode so in-place watch stays live.
        fileSource?.cancel()
        fileSource = nil
        // fileFD closed by the cancel handler above (async but on same queue).
        queue.async { [weak self] in
            guard let self, !self.cancelled else { return }
            self.armFileFD()
        }

        scheduleCallback()
    }

    /// Handles a `.write` event on the file fd.
    ///
    /// File events fire on in-place writes. Stat-compare gates the real
    /// change test — permission writes alone do not differ.
    private func handleFileEvent() {
        let current = statFile()
        guard current != lastSeen else { return }
        lastSeen = current
        scheduleCallback()
    }

    /// Debounces and schedules the `onChange` callback.
    private func scheduleCallback() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    // MARK: - Private: stat (runs on queue)

    /// Stats the watched file.
    ///
    /// Returns `nil` when the file is absent or unreadable (e.g., during
    /// an atomic replace's transient window).
    private func statFile() -> StatSnapshot? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: record.localURL.path)
        guard
            let attrs,
            let size = attrs[.size] as? Int64,
            let mtime = attrs[.modificationDate] as? Date
        else { return nil }
        return StatSnapshot(size: size, mtime: mtime)
    }
}

// MARK: - RoundTrip namespace

/// Pure helpers for round-trip editing decisions.
///
/// These are stateless functions; they carry no I/O and have no side
/// effects. They live in `PalanaCore` so they sit under the coverage floor
/// where the unit battery can beat on them directly.
public enum RoundTrip {
    /// Returns `true` when the file has changed since it was fetched.
    ///
    /// Compares `size` and `modified` only. Permissions drift is not an
    /// edit — a `chmod` on the remote is not a reason to offer an upload.
    ///
    /// - Parameters:
    ///   - baseline: The ``FileEntry`` recorded at fetch time.
    ///   - current: The ``FileEntry`` from the current remote listing.
    /// - Returns: `true` when size or mtime differ; `false` otherwise.
    public static func changedSinceFetch(baseline: FileEntry, current: FileEntry) -> Bool {
        baseline.size != current.size || baseline.modified != current.modified
    }

    /// Composes the one-line note for a remote that moved since the fetch.
    ///
    /// Returns a sentence of the form
    /// `"remote changed since fetch — <size> · <date> now stands there"`.
    /// Pure — no I/O, no side effects. Lives in core so the unit battery
    /// can pin the sentence format directly.
    ///
    /// - Parameter current: The ``FileEntry`` from the current remote listing.
    /// - Returns: A human-readable note naming what now stands at the destination.
    public static func changedSinceFetchNote(current: FileEntry) -> String {
        let size = current.size.formatted(.byteCount(style: .file))
        let date = current.modified.formatted(date: .abbreviated, time: .shortened)
        return "remote changed since fetch — \(size) · \(date) now stands there"
    }
}
