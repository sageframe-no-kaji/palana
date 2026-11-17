// DragOut — the remote half of a drag out of a pane.
//
// A row dragged out of a remote pane carries a file representation on its
// own item provider (DragDrop.swift): when the receiver — Finder, a browser,
// Mail — asks for the file, RemoteDragFetch streams it through the conduit
// into its own temp directory and hands the URL over once every byte has
// landed. The receiver copies it before the completion returns; the temp
// directory goes then, or at the next launch.

import AppKit
import PalanaCore
import UniformTypeIdentifiers

// MARK: - One remote file, fetched for a drop

/// One remote file fetched for a drop, into its own temp directory.
///
/// The bytes land under `<tmp>/palana-dragout-<uuid>/<name>` through
/// ``PalanaCore/Listing/fetchFile(on:path:to:limit:timeout:)``, which
/// removes the file on any failure. The completion runs once: the file's
/// URL when every byte has landed, or the error with the directory gone —
/// never a partial file.
final class RemoteDragFetch: Sendable {
    /// The most a drag downloads — the plan's ceiling.
    static let ceiling = Int(DragOutPlan.remoteCeiling)
    /// Wall time for a drag download: the ceiling at 1 MiB/s (1024 s).
    static let timeout = Duration.seconds(DragOutPlan.remoteCeiling / (1 << 20))
    /// The temp directory prefix, swept at launch.
    static let directoryPrefix = "palana-dragout-"

    /// The reader that reaches `host`.
    let listing: Listing
    /// The remote host.
    let host: String
    /// The file's path on `host`.
    let path: String
    /// The listed size — the progress total.
    let size: Int64
    /// This fetch's own temp directory.
    let directory: URL

    /// A fetch of `host:path`, staged under `root`.
    init(
        listing: Listing,
        host: String,
        path: String,
        size: Int64,
        root: URL = FileManager.default.temporaryDirectory
    ) {
        self.listing = listing
        self.host = host
        self.path = path
        self.size = size
        self.directory = root.appendingPathComponent(Self.directoryPrefix + UUID().uuidString, isDirectory: true)
    }

    /// The file's name — the last path component.
    var fileName: String { (path as NSString).lastPathComponent }

    /// Where the transcript names it.
    var location: String { "\(host):\(path)" }

    /// Starts the download.
    ///
    /// - Parameter completion: Called once, off the main thread, with the
    ///   downloaded file's URL or the error.
    /// - Returns: A progress whose completed count follows the bytes on disk
    ///   and whose cancellation stops the download.
    func start(completion: @escaping @Sendable (Result<URL, any Error>) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: size)
        let counter = ProgressCounter(progress)
        let destination = directory.appendingPathComponent(fileName)
        let task = Task { [self] in
            let watcher = Task {
                while !Task.isCancelled {
                    counter.set(Self.bytesOnDisk(at: destination))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { watcher.cancel() }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fetched = try await listing.fetchFile(
                    on: host, path: path, to: destination, limit: Self.ceiling, timeout: Self.timeout)
                try Task.checkCancellation()
                counter.set(Int64(fetched.byteCount))
                completion(.success(destination))
            } catch {
                cleanUp()
                completion(.failure(error))
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    /// Removes this fetch's temp directory.
    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Removes temp directories an earlier run left behind.
    ///
    /// - Parameter root: Where fetches stage — the temp directory by default.
    static func sweep(root: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix(directoryPrefix) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }

    private static func bytesOnDisk(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// Moves a progress's count from a task without sending the progress.
private final class ProgressCounter: @unchecked Sendable {
    // @unchecked: Progress is thread-safe by contract (NSProgress's counts
    // may be set from any thread); the box only carries it across.
    private let progress: Progress

    init(_ progress: Progress) {
        self.progress = progress
    }

    func set(_ count: Int64) {
        progress.completedUnitCount = count
    }
}

// MARK: - The file promise

/// A remote file promised to a drop.
///
/// The receiver names a place; ``RemoteDropDelegate`` fetches the bytes and
/// moves them there. It also carries the pane-to-pane payload, so a drop on
/// the other pane still plans the whole selection.
final class RemoteFilePromise: NSFilePromiseProvider {
    /// The pane-to-pane payload, on the drag's first writer only.
    var selectionPayload: Data?
    /// Held strongly: the provider's own `delegate` reference is weak.
    var keeper: RemoteDropDelegate?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let types = super.writableTypes(for: pasteboard)
        return selectionPayload == nil ? types : types + [.palanaPayload]
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .palanaPayload ? selectionPayload : super.pasteboardPropertyList(forType: type)
    }
}

/// Answers a remote file promise: download, move into place, report.
final class RemoteDropDelegate: NSObject, NSFilePromiseProviderDelegate, Sendable {
    /// The download behind the promise.
    let fetch: RemoteDragFetch
    /// Writes one transcript line — the operator's sign bytes are moving.
    let report: @Sendable (String) -> Void
    private let queue: OperationQueue

    /// A delegate for one remote file.
    init(fetch: RemoteDragFetch, report: @escaping @Sendable (String) -> Void) {
        self.fetch = fetch
        self.report = report
        let queue = OperationQueue()
        queue.name = "palana.dragout"
        self.queue = queue
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fetch.fileName
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let done = Completion(completionHandler)
        _ = deliver(to: url) { done.call($0) }
    }

    /// Downloads the file and moves it to `url`.
    ///
    /// - Parameters:
    ///   - url: Where the receiver wants the file.
    ///   - completion: nil when the file is in place, else the error.
    /// - Returns: The download's progress, also published for `url`.
    func deliver(to url: URL, completion: @escaping @Sendable ((any Error)?) -> Void) -> Progress {
        let fetch = fetch
        let report = report
        report("downloading \(fetch.location) for a drop…")
        let progress = fetch.start { result in
            switch result {
            case .success(let file):
                do {
                    try FileManager.default.moveItem(at: file, to: url)
                    fetch.cleanUp()
                    report("\(fetch.location) delivered to the drop")
                    completion(nil)
                } catch {
                    fetch.cleanUp()
                    report("\(fetch.location) — could not place the download: \(error.localizedDescription)")
                    completion(error)
                }
            case .failure(let error):
                report("\(fetch.location) — download failed: \(error)")
                completion(error)
            }
        }
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = url
        progress.publish()
        let published = PublishedProgress(progress)
        progress.cancellationHandler = { [cancel = progress.cancellationHandler] in
            cancel?()
            published.unpublish()
        }
        return progress
    }
}

/// Carries AppKit's non-Sendable completion handler to the download's thread.
private final class Completion: @unchecked Sendable {
    // @unchecked: AppKit documents the promise completion handler as
    // callable from any thread; it is called exactly once.
    private let handler: (Error?) -> Void

    init(_ handler: @escaping (Error?) -> Void) {
        self.handler = handler
    }

    func call(_ error: (any Error)?) {
        handler(error)
    }
}

/// Unpublishes a progress from a cancellation handler.
private final class PublishedProgress: @unchecked Sendable {
    // @unchecked: Progress is thread-safe by contract; unpublish is
    // documented as callable from any thread.
    private let progress: Progress

    init(_ progress: Progress) {
        self.progress = progress
    }

    func unpublish() {
        progress.unpublish()
    }
}

// MARK: - The row writer

extension NSPasteboard.PasteboardType {
    /// The pane-to-pane payload's type: public.json, as the drop side reads it.
    static let palanaPayload = NSPasteboard.PasteboardType(UTType.json.identifier)
    /// Native remote rows expose no public JSON, file URL, or file promise.
    static let palanaInternalSelection = NSPasteboard.PasteboardType("net.sageframe.palana.internal-selection")
}

/// An internal transfer descriptor, with no representation an uploader can use
/// as a file.
///
/// Both panes read this exact native pasteboard type; it does not
/// depend on Uniform Type Identifier registration or SwiftUI conversion.
func internalRowPasteboardWriter(payload: Data) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setData(payload, forType: .palanaInternalSelection)
    return item
}

/// The pasteboard writer a dragged row hands the table, when pālana has one.
///
/// SwiftUI writes a row's file URL lazily, and macOS then cannot make the
/// sandbox extension a receiver needs ("Sandbox extension data required
/// immediately for flavor public.file-url"): Finder and browsers get an
/// empty URL. This writes it up front. A local entry is a pasteboard item
/// with its file URL; a remote file is a file promise downloaded at the
/// drop. Both carry the pane-to-pane payload. Anything else (a refused
/// remote entry) returns nil and keeps SwiftUI's own writer, whose payload
/// stays process-only.
///
/// - Parameters:
///   - outbound: The row's drag-out item (``DragOutPlan``).
///   - payload: The encoded ``DraggedSelection``.
///   - remote: The reader and transcript for a remote row.
/// - Returns: The writer, or nil to keep SwiftUI's.
func rowPasteboardWriter(
    for outbound: DragOutItem, payload: Data, remote: RemoteDragSupport?
) -> (any NSPasteboardWriting)? {
    switch outbound {
    case .localFile(let path):
        let item = NSPasteboardItem()
        let url = URL(fileURLWithPath: path).absoluteString
        item.setString(url, forType: .fileURL)
        item.setString(url, forType: .URL)
        item.setData(payload, forType: .palanaPayload)
        return item
    case .remoteFile(let host, let path, let size):
        guard let remote else { return nil }
        let fetch = RemoteDragFetch(listing: remote.listing, host: host, path: path, size: size)
        let delegate = RemoteDropDelegate(fetch: fetch, report: remote.report)
        let promise = RemoteFilePromise(fileType: dragOutFileType(for: path), delegate: delegate)
        promise.keeper = delegate
        promise.selectionPayload = payload
        return promise
    case .refused:
        return nil
    }
}
