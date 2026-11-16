// DragOut — the remote half of a drag out of a pane.
//
// A row dragged out of a remote pane carries a file representation on its
// own item provider (DragDrop.swift): when the receiver — Finder, a browser,
// Mail — asks for the file, RemoteDragFetch streams it through the conduit
// into its own temp directory and hands the URL over once every byte has
// landed. The receiver copies it before the completion returns; the temp
// directory goes then, or at the next launch.

import Foundation
import PalanaCore

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
