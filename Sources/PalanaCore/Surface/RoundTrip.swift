// Round-trip editing machinery — the record of what was fetched (its
// immutable remote identity and content digest), the directory + file
// watcher that detects saves (including atomic-replace saves), and the
// pure decisions that name a remote that moved underneath the edit and
// rule whether a save may go back on its own. No persistence: records
// live for the app's run. No FSEvents: DispatchSource on the directory
// fd survives atomic replace.

import CryptoKit
import Foundation

// MARK: - RemoteIdentity

/// The immutable identity of one remote file — host and full path bytes.
///
/// Two opens of the same remote file share an identity; the registry
/// deduplicates on it. Host and directory alone are not an identity —
/// sibling files in one directory are distinct records.
public struct RemoteIdentity: Hashable, Sendable {
    /// The SSH alias of the remote host.
    public var host: String
    /// The full remote path, byte-exact — never passed through `String`.
    public var pathData: Data

    /// Assembles an identity.
    public init(host: String, pathData: Data) {
        self.host = host
        self.pathData = pathData
    }

    /// Joins a directory and a raw name into an absolute path, byte-accurate.
    public static func pathData(directory: String, name: Data) -> Data {
        var joined = Data(directory == "/" ? "/".utf8 : "\(directory)/".utf8)
        joined.append(name)
        return joined
    }
}

// MARK: - RoundTripRecord

/// The memory of one remote file open — what was fetched, from where,
/// exactly, and where the local copy lives.
///
/// Every remote-side field is captured before the fetch begins and never
/// read from live pane state afterwards: a navigation during the download
/// cannot change where a save goes back to. The fetch-time ``FileEntry``
/// plus the content ``digest`` form the conflict baseline; the
/// ``localURL`` points into the per-open UUID directory under
/// ``openRoot``. Records live for the app's run; there is no persistence
/// across launches.
public struct RoundTripRecord: Sendable, Equatable, Identifiable {
    /// The per-open identity — distinct for every fetch, even of one file.
    public let id: UUID

    /// The SSH alias of the remote host the file came from.
    public var host: String

    /// The remote directory that contained the file when it was opened.
    public var remoteDirectory: String

    /// The full remote path, byte-exact, joined from the directory and the
    /// fetched entry's name bytes at open time.
    public var remotePathData: Data

    /// The pane's open generation at fetch time — a later open on the
    /// same pane carries a higher number.
    public var generation: Int

    /// The ``FileEntry`` as it was at fetch time — the metadata baseline.
    public var fetched: FileEntry

    /// SHA-256 of the bytes that were fetched — the content baseline.
    public var digest: Data

    /// The local URL where the fetched copy lives.
    public var localURL: URL

    /// The per-open directory that holds the local copy.
    public var localDirectory: URL { localURL.deletingLastPathComponent() }

    /// The remote identity — host plus full path bytes.
    public var identity: RemoteIdentity {
        RemoteIdentity(host: host, pathData: remotePathData)
    }

    /// The full remote path for display — lossy when the name is not UTF-8.
    public var remotePath: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: remotePathData, as: UTF8.self)  // display only — a lossy path is fine here
    }

    /// A human-readable label: `host remote/dir/filename`.
    public var displayName: String {
        "\(host) \(remoteDirectory)/\(fetched.name)"
    }

    /// Where every per-open directory lives: `<tmp>/palana-open/`.
    public static var openRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-open", isDirectory: true)
    }

    /// Creates a fresh per-open directory under ``openRoot`` and returns it.
    ///
    /// A fresh directory per open — a re-open must never overwrite a copy
    /// the operator may have edited.
    public static func makeOpenDirectory() throws -> URL {
        let directory = openRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// True when `directory` is a direct child of ``openRoot`` — the only
    /// directories retirement is allowed to delete.
    public static func isOpenDirectory(_ directory: URL) -> Bool {
        let parent = directory.deletingLastPathComponent().resolvingSymlinksInPath().path
        return parent == openRoot.resolvingSymlinksInPath().path
    }

    /// Assembles a round-trip record from values captured before the fetch.
    ///
    /// - Parameters:
    ///   - id: The per-open identity; fresh by default.
    ///   - host: The SSH alias of the remote host.
    ///   - remoteDirectory: The directory on the remote that contained the file at open time.
    ///   - fetched: The entry as reported by the remote listing at fetch time.
    ///   - digest: SHA-256 of the fetched bytes (``RoundTrip/digest(of:)``).
    ///   - localURL: The URL of the local copy in the per-open UUID directory.
    ///   - generation: The pane's open generation at fetch time.
    public init(
        id: UUID = UUID(),
        host: String,
        remoteDirectory: String,
        fetched: FileEntry,
        digest: Data,
        localURL: URL,
        generation: Int = 0
    ) {
        self.id = id
        self.host = host
        self.remoteDirectory = remoteDirectory
        self.remotePathData = RemoteIdentity.pathData(directory: remoteDirectory, name: fetched.nameData)
        self.generation = generation
        self.fetched = fetched
        self.digest = digest
        self.localURL = localURL
    }
}

// MARK: - RoundTripWatching

/// What the registry needs from a watcher — start, stop, and a guarded
/// baseline advance. ``RoundTripWatcher`` is the real one; tests inject spies.
public protocol RoundTripWatching: AnyObject, Sendable {
    /// Begins watching.
    func start()
    /// Stops watching and releases every descriptor; idempotent.
    func cancel()
    /// Advances the baseline to the snapshot that was sent, and no further.
    func refreshBaseline(to sent: RoundTripWatcher.Snapshot)
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
/// closed in their respective cancel handlers — ``liveDescriptorCount()``
/// reads zero once they have run.
///
/// ## Sendable / concurrency
///
/// `RoundTripWatcher` is `@unchecked Sendable`. All mutable state
/// (`lastSeen`, `debounceWorkItem`, `cancelled`, `dirSource`,
/// `fileSource`, `liveDescriptors`) is protected by a single serial
/// `DispatchQueue` created at init. No state is ever accessed off that
/// queue. Each dispatch source's cancel handler closes the fd it captured
/// at arm time. The callback is `@Sendable` and is delivered on the
/// watcher's internal queue; callers that update UI must dispatch to
/// `@MainActor`.
public final class RoundTripWatcher: RoundTripWatching, @unchecked Sendable {
    // MARK: - Snapshot

    /// The size-and-mtime pair the stat-compare gate works on.
    public struct Snapshot: Equatable, Sendable {
        /// The file's size in bytes.
        public var size: Int64
        /// The file's modification time, sub-second where the filesystem keeps it.
        public var mtime: Date

        /// Assembles a snapshot.
        public init(size: Int64, mtime: Date) {
            self.size = size
            self.mtime = mtime
        }
    }

    /// Stats a local file the way the watcher does.
    ///
    /// Returns `nil` when the file is absent or unreadable (e.g., during
    /// an atomic replace's transient window). The upload gather captures
    /// this before composing so completion can advance the baseline to
    /// exactly what was sent.
    public static func snapshot(of url: URL) -> Snapshot? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard
            let attrs,
            let size = attrs[.size] as? Int64,
            let mtime = attrs[.modificationDate] as? Date
        else { return nil }
        return Snapshot(size: size, mtime: mtime)
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
    /// Advanced by every observed event, and by ``refreshBaseline(to:)``
    /// only when the file still matches what was sent.
    private var lastSeen: Snapshot?

    /// The pending debounce work item.
    private var debounceWorkItem: DispatchWorkItem?

    /// True once ``cancel()`` has been called.
    private var cancelled: Bool = false

    /// The dispatch source on the directory fd.
    private var dirSource: DispatchSourceFileSystemObject?

    /// The dispatch source on the file fd.
    private var fileSource: DispatchSourceFileSystemObject?

    /// How many descriptors this watcher currently holds open.
    private var liveDescriptors: Int = 0

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

    /// Advances the stat baseline to what was just sent — and no further.
    ///
    /// Called after a successful upload. The baseline moves only when the
    /// file on disk still matches `sent`; a save that landed after the
    /// upload's gather differs from `sent`, so its event still passes the
    /// stat-compare gate whether it is processed before or after this call.
    /// A refresh that read the current stat instead would swallow that save.
    public func refreshBaseline(to sent: Snapshot) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.statFile() == sent else { return }
            self.lastSeen = sent
        }
    }

    /// The number of descriptors this watcher holds open — two while
    /// watching, zero once both cancel handlers have run.
    public func liveDescriptorCount() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                continuation.resume(returning: self?.liveDescriptors ?? 0)
            }
        }
    }

    // MARK: - Private: start (runs on queue)

    private func startLocked() {
        // Open the directory source first — it never goes stale.
        let dirURL = record.localURL.deletingLastPathComponent()
        let dfd = open(dirURL.path, O_EVTONLY)
        guard dfd >= 0 else { return }
        liveDescriptors += 1

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
        dir.setCancelHandler { [weak self] in
            close(dfd)
            self?.liveDescriptors -= 1
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
        liveDescriptors += 1

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
        src.setCancelHandler { [weak self] in
            close(ffd)
            self?.liveDescriptors -= 1
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
    private func statFile() -> Snapshot? {
        Self.snapshot(of: record.localURL)
    }
}

// MARK: - Conflict decisions

/// What the destination check found.
///
/// Three-valued on purpose: an unreadable destination is not a clean one.
/// Only ``clean`` may send on its own.
public enum ConflictCheck: Sendable, Equatable {
    /// The remote file is exactly what was fetched — metadata and bytes.
    case clean
    /// The remote moved underneath the edit.
    case conflict(ConflictReason)
    /// The check itself could not be completed — the reason, in a sentence.
    case unavailable(String)
}

/// Why a destination is a conflict.
public enum ConflictReason: Sendable, Equatable {
    /// The remote file no longer exists.
    case missing
    /// Size or mtime differ from the fetch-time entry.
    case metadataChanged(current: FileEntry)
    /// Same size and mtime, different bytes.
    case contentChanged
}

/// What the gather does once the destination check is in.
public enum SendDisposition: Sendable, Equatable {
    /// Clean and the operator asked not to be asked — send now.
    case sendNow
    /// Arm the plan and show the callout; Enter sends, Esc keeps the edit local.
    case askOperator(callout: String)
    /// No plan — the panel names why, and the edit stays local until a
    /// later save checks again.
    case blocked(reason: String)
}

// MARK: - RoundTrip namespace

/// Pure helpers for round-trip editing decisions.
///
/// These are stateless functions; they carry no I/O and have no side
/// effects. They live in `PalanaCore` so they sit under the coverage floor
/// where the unit battery can beat on them directly.
public enum RoundTrip {
    /// SHA-256 of the bytes — the content baseline a fetch records and a
    /// send-back check re-reads.
    public static func digest(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

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

    /// Rules on the destination from what the check could read.
    ///
    /// Absence is a conflict; changed size or mtime is a conflict; equal
    /// metadata with a different digest is a conflict; equal metadata whose
    /// bytes could not be read is unavailable. Size and mtime are never
    /// content identity on their own.
    ///
    /// - Parameters:
    ///   - record: The record carrying the fetch-time baseline.
    ///   - current: The entry from the current remote listing; `nil` when absent.
    ///   - currentDigest: SHA-256 of the current remote bytes; `nil` when unread.
    /// - Returns: The three-valued ruling — clean, conflict, or unavailable.
    public static func evaluate(record: RoundTripRecord, current: FileEntry?, currentDigest: Data?) -> ConflictCheck {
        guard let current else { return .conflict(.missing) }
        if changedSinceFetch(baseline: record.fetched, current: current) {
            return .conflict(.metadataChanged(current: current))
        }
        guard let currentDigest else {
            return .unavailable("the remote content could not be read")
        }
        return currentDigest == record.digest ? .clean : .conflict(.contentChanged)
    }

    /// Turns the check into what the gather does.
    ///
    /// The one place the auto-send rule lives: only ``ConflictCheck/clean``
    /// may send unasked.
    public static func disposition(
        for check: ConflictCheck,
        askBeforeSending: Bool,
        record: RoundTripRecord
    ) -> SendDisposition {
        let target = "\(record.host):\(record.remoteDirectory)"
        switch check {
        case .clean:
            return askBeforeSending
                ? .askOperator(callout: "⏎ press enter to send it back to \(target) · esc keeps the edit local")
                : .sendNow
        case .conflict(.missing):
            return .askOperator(
                callout:
                    "the remote copy is gone — ⏎ press enter to put it back at \(target) · esc keeps the edit local")
        case .conflict:
            return .askOperator(
                callout: "the remote copy changed since you opened it — ⏎ press enter to overwrite it anyway"
                    + " · esc keeps the edit local")
        case .unavailable(let reason):
            return .blocked(
                reason: "couldn't check \(record.host):\(record.remotePath) — \(reason)"
                    + " · the edit stays local; save again to check again")
        }
    }

    /// The transcript line for a conflict — read before the callout.
    public static func conflictNote(for reason: ConflictReason) -> String {
        switch reason {
        case .missing:
            return "the remote copy is gone since you opened it"
        case .metadataChanged(let current):
            return changedSinceFetchNote(current: current)
        case .contentChanged:
            return "the remote copy changed since you opened it — same size and date, different bytes"
        }
    }

    /// Composes the one-line note for a remote that moved since the fetch.
    ///
    /// Returns a sentence of the form
    /// `"the remote copy changed since you opened it — <size> · <date> now stands there"`.
    /// Pure — no I/O, no side effects. Lives in core so the unit battery
    /// can pin the sentence format directly.
    ///
    /// - Parameter current: The ``FileEntry`` from the current remote listing.
    /// - Returns: A human-readable note naming what now stands at the destination.
    public static func changedSinceFetchNote(current: FileEntry) -> String {
        let size = current.size.formatted(.byteCount(style: .file))
        let date = current.modified.formatted(date: .abbreviated, time: .shortened)
        return "the remote copy changed since you opened it — \(size) · \(date) now stands there"
    }
}
