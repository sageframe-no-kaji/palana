// PreviewController — the app-scope loader behind the preview pane (ho-16,
// remote text added in review).
//
// The right pane in preview follows the left pane's cursor. This controller
// holds what that resolves to — text (local OR remote), a quick-look file, an
// info-only card, or the local-only line for a remote binary — and loads it
// with a debounce so arrow-spam never thrashes the UI. Routing decisions are
// PalanaCore's pure PreviewRouter; this class does the debounce, the bounded
// reads (local file handle, remote `head -c` via the injected reader), and the
// @Observable state the pane renders.

import Foundation
import Observation
import PalanaCore

/// The live preview state and its debounced loader.
@MainActor
@Observable
final class PreviewController {
    /// Reads at most `limit` bytes off the front of a remote file — injected by
    /// the session so this stays free of the engine. `nil` on failure.
    typealias RemoteReader = @MainActor (_ host: String, _ path: String, _ limit: Int) async -> Data?

    /// Reads a remote file whole — the size-gated binary fetch (ho-18).
    ///
    /// Only ever called for a file already known under the cap. `nil` on failure.
    typealias RemoteFileReader = @MainActor (_ host: String, _ path: String) async -> Data?

    /// What the preview pane should render right now.
    enum State: Equatable {
        /// The left pane has no cursor — nothing to preview.
        case empty
        /// A load is settling after the debounce.
        case loading(FileEntry)
        /// A text file (local or remote), read (capped) and ready to show mono.
        case text(FileEntry, PreviewText)
        /// A local quick-lookable file at this URL — image, PDF, media.
        case quickLook(FileEntry, URL)
        /// A file with no content preview (directory, symlink, device).
        case infoOnly(FileEntry)
        /// A remote file whose content is not shown — the info card plus the
        /// honest local-only line (a remote binary, or a failed read).
        case remote(FileEntry)
    }

    /// The current preview state — the pane observes this.
    private(set) var state: State = .empty

    /// The bounded-head reader for remote text, set by the session.
    var remoteReader: RemoteReader?

    /// The whole-file reader for remote binaries (ho-18), set by the session.
    var remoteFileReader: RemoteFileReader?

    /// The single ephemeral cache file for the current remote-binary preview —
    /// evicted on every load and on clear, so at most one exists.
    private var cacheURL: URL?

    /// The debounce window before a cursor move loads (design system §6 micro-
    /// interaction window) — arrow-spam within it never thrashes the preview.
    static let debounce: Duration = .milliseconds(110)

    private var loadTask: Task<Void, Never>?

    /// Follows the left pane's cursor.
    ///
    /// Cancels any pending load and schedules a fresh one after the debounce. A
    /// `nil` entry (no source cursor) clears immediately.
    ///
    /// - Parameters:
    ///   - entry: The ``FileEntry`` under the left cursor, if any.
    ///   - host: The left pane's host (ssh alias or the local sentinel).
    ///   - directory: The left pane's current directory.
    ///   - isLocal: Whether the host is this Mac.
    ///   - url: The local file URL for a local source; `nil` for a remote one.
    func follow(entry: FileEntry?, host: String?, directory: String, isLocal: Bool, url: URL?) {
        loadTask?.cancel()
        guard let entry else {
            state = .empty
            return
        }
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.load(
                entry: entry, host: host, directory: directory, isLocal: isLocal, url: url)
        }
    }

    /// Clears the preview and cancels any pending load — called on exit.
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        evictCache()
        state = .empty
    }

    /// Resolves and reads the file behind the cursor.
    private func load(
        entry: FileEntry, host: String?, directory: String, isLocal: Bool, url: URL?
    ) async {
        // One cache file at a time — the previous preview's fetch is stale now.
        evictCache()
        if isLocal {
            await loadLocal(entry: entry, url: url)
        } else {
            await loadRemote(entry: entry, host: host, directory: directory)
        }
    }

    /// The local branch — text (read via file handle), quick-look, or info-only.
    private func loadLocal(entry: FileEntry, url: URL?) async {
        guard entry.kind == .file, let url else {
            state = .infoOnly(entry)
            return
        }
        state = .loading(entry)
        let limit = PreviewRouter.textCap + 1
        let data = await Task.detached { Self.readHead(of: url, limit: limit) }.value
        guard !Task.isCancelled else { return }
        switch PreviewRouter.route(isLocal: true, entry: entry, contentHead: data) {
        case .text:
            state = .text(entry, PreviewRouter.decodeCapped(data ?? Data()))
        case .quickLook:
            state = .quickLook(entry, url)
        case .infoOnly, .remoteInfoOnly:
            state = .infoOnly(entry)
        }
    }

    /// The remote branch — ho-16 text plus ho-18 binary, size-gated on facts.
    ///
    /// Gated on facts we already hold, so no fetch is started that we'd abort
    /// for size. Text reads a bounded head; a small image/PDF is fetched whole
    /// to a cache and quick-looked; everything else stays info-only.
    private func loadRemote(entry: FileEntry, host: String?, directory: String) async {
        guard let host else {
            state = .infoOnly(entry)
            return
        }
        let path = PaneModel.childPath(of: directory, name: entry.name)
        switch PreviewRouter.remotePlan(entry: entry) {
        case .text:
            await loadRemoteText(entry: entry, host: host, path: path)
        case .fetchBinary:
            await loadRemoteBinary(entry: entry, host: host, path: path)
        case .infoOnly:
            state = .remote(entry)
        }
    }

    /// Remote text — a bounded `head -c` read, then extension-or-sniff routing.
    private func loadRemoteText(entry: FileEntry, host: String, path: String) async {
        guard let reader = remoteReader else {
            state = .remote(entry)
            return
        }
        state = .loading(entry)
        let data = await reader(host, path, PreviewRouter.textCap + 1)
        guard !Task.isCancelled else { return }
        guard let data else {
            state = .remote(entry)
            return
        }
        // A text extension is text; an extensionless file is sniffed.
        let hasExtension = PreviewRouter.fileExtension(of: entry.name) != nil
        if hasExtension || PreviewRouter.looksLikeText(head: data) {
            state = .text(entry, PreviewRouter.decodeCapped(data))
        } else {
            state = .remote(entry)
        }
    }

    /// Remote binary (ho-18) — fetch the whole file (already known under the
    /// cap), write it to the ephemeral cache, and quick-look the local copy.
    private func loadRemoteBinary(entry: FileEntry, host: String, path: String) async {
        guard let reader = remoteFileReader else {
            state = .remote(entry)
            return
        }
        state = .loading(entry)
        let data = await reader(host, path)
        guard !Task.isCancelled else { return }
        guard let data, let url = cacheRemote(data, name: entry.name) else {
            state = .remote(entry)
            return
        }
        state = .quickLook(entry, url)
    }

    /// Writes fetched remote bytes to a single temp cache file.
    ///
    /// The file carries the entry's extension so QuickLook infers the type; any
    /// prior cache file is evicted first.
    private func cacheRemote(_ data: Data, name: String) -> URL? {
        evictCache()
        let ext = (name as NSString).pathExtension
        var url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-remote-preview-\(UUID().uuidString)")
        if !ext.isEmpty { url.appendPathExtension(ext) }
        guard (try? data.write(to: url)) != nil else { return nil }
        cacheURL = url
        return url
    }

    /// Removes the cached remote-binary file, if any.
    private func evictCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
        cacheURL = nil
    }

    /// Reads up to `limit` bytes off the front of a local file, or `nil` on
    /// failure — pure I/O, run on a detached task off the main actor.
    nonisolated static func readHead(of url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }
}
