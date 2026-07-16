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

    /// The reader for remote files, set by the session after the engine exists.
    var remoteReader: RemoteReader?

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
        state = .empty
    }

    /// Resolves and reads the file behind the cursor.
    private func load(
        entry: FileEntry, host: String?, directory: String, isLocal: Bool, url: URL?
    ) async {
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

    /// The remote branch — human-readable text is fetched with a bounded
    /// `head -c` and shown; a remote binary (or a read we can't make) stays the
    /// info card plus the local-only line (ho-16 review: remote *text* is in,
    /// remote binary is still local-only).
    private func loadRemote(entry: FileEntry, host: String?, directory: String) async {
        guard entry.kind == .file else {
            state = .infoOnly(entry)
            return
        }
        // Only fetch what could be text: a text extension, or an extensionless
        // file we can sniff from the head. A known non-text extension (image,
        // PDF, archive) is not fetched — it stays local-only.
        let ext = PreviewRouter.fileExtension(of: entry.name)
        let couldBeText = ext.map { PreviewRouter.textExtensions.contains($0) } ?? true
        guard couldBeText, let host, let reader = remoteReader else {
            state = .remote(entry)
            return
        }
        state = .loading(entry)
        let path = PaneModel.childPath(of: directory, name: entry.name)
        let data = await reader(host, path, PreviewRouter.textCap + 1)
        guard !Task.isCancelled else { return }
        guard let data else {
            state = .remote(entry)
            return
        }
        // With an extension it is text (we only fetched text extensions);
        // extensionless we sniff the head we just read.
        if ext != nil || PreviewRouter.looksLikeText(head: data) {
            state = .text(entry, PreviewRouter.decodeCapped(data))
        } else {
            state = .remote(entry)
        }
    }

    /// Reads up to `limit` bytes off the front of a local file, or `nil` on
    /// failure — pure I/O, run on a detached task off the main actor.
    nonisolated static func readHead(of url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }
}
