// PreviewController — the app-scope loader behind the preview pane (ho-16).
//
// A pane in preview mode follows the *other* pane's cursor. This controller
// holds what that resolves to — text, a quick-look file, an info-only card, or
// the local-only line for a remote source — and loads it with a debounce so
// arrow-spam never thrashes the UI. The routing decisions are PalanaCore's pure
// PreviewRouter; this class does only the debounce, the bounded local read, and
// the @Observable state the pane renders.

import Foundation
import Observation
import PalanaCore

/// The live preview state and its debounced loader.
@MainActor
@Observable
final class PreviewController {
    /// What the preview pane should render right now.
    enum State: Equatable {
        /// The opposite pane has no cursor — nothing to preview.
        case empty
        /// A load is settling after the debounce.
        case loading(FileEntry)
        /// A local text file, read (capped) and ready to show monospace.
        case text(FileEntry, PreviewText)
        /// A local quick-lookable file at this URL — image, PDF, media.
        case quickLook(FileEntry, URL)
        /// A local file with no content preview (directory, symlink, device).
        case infoOnly(FileEntry)
        /// A remote file — the info card plus the honest local-only line.
        case remote(FileEntry)
    }

    /// The current preview state — the pane observes this.
    private(set) var state: State = .empty

    /// The debounce window before a cursor move loads (design system §6 micro-
    /// interaction window) — arrow-spam within it never thrashes the preview.
    static let debounce: Duration = .milliseconds(110)

    private var loadTask: Task<Void, Never>?

    /// Follows the opposite pane's cursor.
    ///
    /// Cancels any pending load and schedules a fresh one after the debounce.
    /// A `nil` entry (no source cursor) clears immediately.
    ///
    /// - Parameters:
    ///   - entry: The ``FileEntry`` under the source cursor, if any.
    ///   - isLocal: Whether the source pane's host is this Mac.
    ///   - url: The local file URL for a local source; `nil` for a remote one.
    func follow(entry: FileEntry?, isLocal: Bool, url: URL?) {
        loadTask?.cancel()
        guard let entry else {
            state = .empty
            return
        }
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.load(entry: entry, isLocal: isLocal, url: url)
        }
    }

    /// Clears the preview and cancels any pending load — called on exit.
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        state = .empty
    }

    /// Resolves and, for local text, reads the file behind the cursor.
    private func load(entry: FileEntry, isLocal: Bool, url: URL?) async {
        guard isLocal else {
            state = .remote(entry)
            return
        }
        guard entry.kind == .file, let url else {
            state = .infoOnly(entry)
            return
        }
        state = .loading(entry)
        // Bounded read off the main actor — never more than the cap plus one
        // byte, so a multi-GB log is a 256 KB read, not a hang.
        let limit = PreviewRouter.textCap + 1
        let data = await Task.detached { Self.readHead(of: url, limit: limit) }.value
        guard !Task.isCancelled else { return }
        switch PreviewRouter.route(isLocal: true, entry: entry, contentHead: data) {
        case .text:
            state = .text(entry, PreviewRouter.decodeCapped(data ?? Data()))
        case .quickLook:
            state = .quickLook(entry, url)
        case .infoOnly:
            state = .infoOnly(entry)
        case .remoteInfoOnly:
            state = .remote(entry)
        }
    }

    /// Reads up to `limit` bytes off the front of a file, or `nil` on failure.
    ///
    /// `nonisolated` and pure I/O so it runs on a detached task, off the main
    /// actor. Uses a file handle so a huge file is never fully read.
    nonisolated static func readHead(of url: URL, limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit)
    }
}
