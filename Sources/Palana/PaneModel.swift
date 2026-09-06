// The pane model — one pane's live state and its engine wiring. Holds
// the PaneState value, computes the displayed rows once per display
// change, and runs the ho-04 read path: facts, discover if the
// capability is missing, list with the flavor.
//
// Reads commit only on success. A pane never navigates to a failure:
// pointing somewhere unreadable leaves the pane where it was and says
// why in a quiet line — second hands session's finding. Every failure
// renders in place, never as an alert.

import AppKit
import PalanaCore
import SwiftUI
import os

/// The engine handles a pane borrows — built once by the session.
struct Engine: Sendable {
    /// The reserved host name for the operator's own machine.
    static let localHost = PalanaCore.localHostName

    /// The single door to the wire.
    let conduit: SSHConduit
    /// The topology and its facts.
    let field: Field
    /// The directory reader over the wire.
    let listing: Listing
    /// The door into this Mac — no wire, no sessions.
    let localConduit = LocalConduit()
    /// The directory reader over the local shell.
    let localListing: Listing

    /// Wires both doors.
    init(conduit: SSHConduit, field: Field, listing: Listing) {
        self.conduit = conduit
        self.field = field
        self.listing = listing
        self.localListing = Listing(conduit: localConduit)
    }

    /// True for the operator's own machine.
    func isLocal(_ host: String) -> Bool {
        host == Self.localHost
    }

    /// The reader that speaks to this host.
    func listing(for host: String) -> Listing {
        isLocal(host) ? localListing : listing
    }

    /// The door that reaches this host.
    func conduit(for host: String) -> any Conduit {
        isLocal(host) ? localConduit : conduit
    }
}

/// One pane: state, rows, status, and the wiring behind them.
@MainActor
@Observable
final class PaneModel {
    /// Where the pane stands with its host.
    enum Status: Equatable {
        /// Never pointed anywhere — the go-to hint renders.
        case unpointed
        /// First read in flight — nothing older to show.
        case loading
        /// Entries are showing.
        case ready
    }

    /// The pane's value — the core's contract.
    var state = PaneState()
    /// The displayed rows, recomputed only when the display changes.
    private(set) var rows: [FileEntry] = []
    /// Where the pane stands.
    private(set) var status = Status.unpointed
    /// The last read's failure, cleared by the next success — a banner
    /// over a ready pane, the whole line otherwise.
    private(set) var lastError: String?
    /// How the last typed address was corrected before it landed.
    ///
    /// A notice over the pane until the next pointing; nil after an exact
    /// landing or any navigation that was not a typed address.
    private(set) var addressNotice: String?

    /// The notice bar leaves on a click or after its five seconds.
    func dismissAddressNotice() {
        addressNotice = nil
    }
    /// The notice a recovery in flight will post when its read commits —
    /// set by `PaneModel+Address.swift`, consumed here.
    var pendingAddressNotice: String?
    /// True while a read is in flight over a ready pane.
    private(set) var isReading = false
    /// Dataset mountpoints gathered from cached ZFS facts at the last
    /// successful commit — empty when the host is local, facts are absent,
    /// or ZFS is not in the facts.
    private(set) var datasetMountpoints: Set<String> = []
    /// Mount targets gathered from cached mount facts at the last successful
    /// commit — the plain-mount boundary set, empty when the host is local,
    /// facts are absent, or mounts were never gathered.
    private(set) var mountTargets: Set<String> = []
    /// Rows a page move jumps — the view updates it from geometry.
    var pageSize = 25
    /// The most bytes a remote open streams to its temp copy.
    ///
    /// Enforced on the bytes as they arrive, not on the listing's size —
    /// the size is a courtesy refusal, stale by definition. A test lowers
    /// it to prove the stream, not the listing, is the ceiling.
    var openByteCeiling = Listing.defaultReadCeiling
    /// Whether this pane renders files or a host's dataset tree (ho-10.3).
    ///
    /// App-level only — `PaneState`/`PaneIntent` never learn about this.
    /// Mutated only from `PaneModel+ZFSMode.swift`'s entry/exit/walk API —
    /// `internal(set)` (the default) rather than `private(set)` because
    /// Swift's `private` is file-scoped and that machinery lives in its
    /// own extension file.
    var paneMode = Mode.files
    /// The dataset tree, populated while `paneMode == .zfs` — empty otherwise.
    var zfsDatasets: [ZFSDataset] = []
    /// The selected dataset's name while `paneMode == .zfs` — nil otherwise
    /// or before the tree has read anything.
    var zfsSelectedDataset: String?
    /// True while the header's path field is being typed in — the key
    /// monitor stands down so the letters reach the field.
    var pathEditing = false
    /// The pane's navigation history — back and forward stacks.
    var history = PaneHistory()
    /// True while a back/forward navigation is in flight — suppresses history push.
    var isHistoryNavigation = false

    /// Fires on pointing, sort, and hidden changes — the session persists there.
    ///
    /// Set once, right after construction.
    var onDisplayChange: @MainActor () -> Void = {}

    /// Fires after a remote file is fetched and the round-trip record is ready.
    ///
    /// The session wires this to `RoundTripCenter.register(record:)`. Keeping
    /// the pane free of any direct reach into the center lets the pane remain
    /// ignorant of the operation model — the same pattern `onDisplayChange` uses.
    ///
    /// Set once, right after construction.
    var onRoundTripRegistered: @MainActor (RoundTripRecord) -> Void = { _ in }

    /// Hands a fetched or local file to the system editor, activated.
    ///
    /// Defaults to `NSWorkspace.shared.open`; a test overrides it so an
    /// open can be observed without launching a real editor.
    var openHandler: @MainActor (URL) -> Void = { url in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    private static let logger = Logger(subsystem: "net.sageframe.palana", category: "pane")

    private let engine: Engine
    private var loadTask: Task<Void, Never>?
    /// The typed-address recovery in flight, cancelled by any pointing.
    var recoveryTask: Task<Void, Never>?
    /// A monotonic counter stamped onto each remote open's round-trip record.
    ///
    /// A later open on this pane carries a higher number, so a record can
    /// prove it predates the pane's current location.
    private var openGeneration = 0
    private var landOn: Data?
    /// A file name to cursor AND select once its parent folder has loaded —
    /// set when a pointed path turns out to be a file (⌘⇧G / address bar with a
    /// file path), so the pane lands in the folder with the file revealed.
    private var revealOnLand: Data?

    /// A pane over the session's engine.
    init(engine: Engine) {
        self.engine = engine
    }

    /// True when this pane points at the operator's own machine.
    ///
    /// The one locality test the pane has — ``Engine/isLocal(_:)``, the same
    /// judgement the local-in-place file open makes — reached from the menu
    /// layer, which cannot see the private engine. A pane pointing nowhere
    /// yet is not local.
    var isLocalPane: Bool {
        guard let host = state.host else { return false }
        return engine.isLocal(host)
    }

    /// True for the operator's own machine — the engine's judgement, for
    /// the address extension's probe, which cannot see the engine.
    func isLocalHost(_ host: String) -> Bool {
        engine.isLocal(host)
    }

    /// The reader that speaks to a host — for the same probe, which asks
    /// through the listing so a fixture stands in for the wire.
    func listing(for host: String) -> Listing {
        engine.listing(for: host)
    }

    /// Re-points the pane from a remembered session.
    func restore(_ remembered: SessionSnapshot.Pane) {
        state.sort = remembered.sort
        state.showHidden = remembered.showHidden
        if let host = remembered.host {
            point(host: host, path: remembered.path)
        }
    }

    /// Points the pane at a host and path.
    ///
    /// The pointing commits only if the read succeeds — a bad path
    /// leaves the pane exactly where it was.
    func point(host: String, path: String) {
        recoveryTask?.cancel()
        read(host: host, path: path.isEmpty ? "/" : path)
    }

    /// Applies one intent.
    ///
    /// Cursor and selection moves mutate synchronously; reads spawn. In
    /// zfs mode the file-cursor intents redirect to the tree walk instead
    /// (`PaneModel+ZFSMode.swift`) — everything else that has no meaning
    /// on a dataset row (sort, selection, ascend/descend, clipboard) is a
    /// quiet no-op rather than reaching the file state underneath.
    func apply(_ intent: PaneIntent) {
        if paneMode == .zfs {
            applyZFSModeIntent(intent)
            return
        }
        if applyCursorOrSelection(intent) { return }
        switch intent {
        case .toggleHidden: applyDisplayChange { $0.toggleHidden() }
        case .sortByName: applyDisplayChange { $0.setSort(key: .name) }
        case .sortBySize: applyDisplayChange { $0.setSort(key: .size) }
        case .sortByModified: applyDisplayChange { $0.setSort(key: .modified) }
        case .ascend: ascend()
        case .descend: descend(openingFiles: false)
        case .descendOrOpen: descend(openingFiles: true)
        case .refresh: refresh()
        case .copyPath, .copyDirectory, .copyFilename, .copyNameSansExtension:
            copyToClipboard(intent, ids: nil)
        default:
            break  // the session's verbs — dispatched before reaching a pane
        }
    }

    /// The hot half of the grammar — true when the intent was one of them.
    private func applyCursorOrSelection(_ intent: PaneIntent) -> Bool {
        switch intent {
        case .cursorDown: state.moveCursor(by: 1, in: rows)
        case .cursorUp: state.moveCursor(by: -1, in: rows)
        case .cursorHalfPageDown: state.moveCursor(by: max(pageSize / 2, 1), in: rows)
        case .cursorHalfPageUp: state.moveCursor(by: -max(pageSize / 2, 1), in: rows)
        case .cursorPageDown: state.moveCursor(by: max(pageSize, 1), in: rows)
        case .cursorPageUp: state.moveCursor(by: -max(pageSize, 1), in: rows)
        case .cursorToTop: state.moveCursorToTop(in: rows)
        case .cursorToBottom: state.moveCursorToBottom(in: rows)
        case .toggleSelectionAndAdvance: state.toggleSelectionAtCursorAndAdvance(in: rows)
        case .selectAll: state.selectAll(in: rows)
        case .clearSelection: state.clearSelection()
        default: return false
        }
        return true
    }

    // MARK: - Navigation

    /// Schedules a cursor landing on the named entry after the next read.
    ///
    /// Rename and create operations call this before refreshing so the
    /// cursor follows the result to its new or freshly created position.
    func setLandOn(_ name: String) {
        landOn = Data(name.utf8)
    }

    private func ascend() {
        guard let host = state.host, state.path != "/" else { return }
        let leaving = Self.lastComponent(of: state.path)
        landOn = Data(leaving.utf8)
        point(host: host, path: Self.parentPath(of: state.path))
    }

    /// Arrows navigate, Enter opens — a file under an arrow key stays
    /// shut (second hands session: "what about enter alone?").
    private func descend(openingFiles: Bool) {
        guard let host = state.host, let entry = cursorEntry else { return }
        switch entry.kind {
        case .directory, .symlink:
            // A symlink descends as a directory attempt — read-then-
            // commit means a link to a file just says so and stays put
            // (second hands session: "why can't I navigate it?").
            guard let path = exactPath(for: entry) else { return }
            point(host: host, path: path)
        case .file:
            if openingFiles {
                openFile(entry, on: host)
            }
        case .other:
            break
        }
    }

    /// A double-click: aim the cursor at the row, then enter or open.
    func activate(_ id: FileEntry.ID) {
        state.cursor = id
        descend(openingFiles: true)
    }

    /// Enter on a file: fetch a temp copy, hand it to the system.
    ///
    /// Guarded by size — a pane is not a transfer tool, and the real
    /// moves belong to the plan panel.
    private func refresh() {
        guard let host = state.host else { return }
        read(host: host, path: state.path)
    }

    /// One directory read through the engine — ho-04's wiring exactly,
    /// with one Surface courtesy first: a leading `~` resolves to the
    /// remote home, because the listing quotes its path and the remote
    /// shell never sees a tilde to expand.
    private func read(host: String, path targetPath: String) {
        loadTask?.cancel()
        if status != .ready { status = .loading }
        isReading = true
        loadTask = Task {
            do {
                let started = ContinuousClock.now
                var path = targetPath
                if path == "~" || path.hasPrefix("~/") {
                    path = try await self.resolveTilde(path, host: host)
                }
                let flavor = try await self.resolveFlavor(host: host)
                let entries = try await self.engine.listing(for: host)
                    .list(on: host, path: path, flavor: flavor)
                guard !Task.isCancelled else { return }
                // Read timing in the unified log — notice level because
                // info is memory-only and `log show` would miss it.
                let elapsed = "\(ContinuousClock.now - started)"
                let line = "read \(host):\(path) — \(entries.count) entries in \(elapsed)"
                Self.logger.notice("\(line, privacy: .public)")
                await self.commit(host: host, path: path, entries: entries)
            } catch {
                guard !Task.isCancelled else { return }
                // A pointed path that is a file, not a directory (⌘⇧G or the
                // address bar with a file path): land in its parent folder and
                // reveal the file instead of erroring. `notADirectory` means the
                // path exists but is a file — a clean signal, distinct from a
                // bad path. The parent strictly shortens the path, so no loop.
                if case ListingError.notADirectory = error {
                    let parent = Self.parentPath(of: targetPath)
                    if parent != targetPath {
                        self.revealOnLand = Data(Self.lastComponent(of: targetPath).utf8)
                        self.read(host: host, path: parent)
                        return
                    }
                }
                self.isReading = false
                if self.status == .loading { self.status = self.rows.isEmpty ? .unpointed : .ready }
                self.lastError = Self.describe(error)
                self.pendingAddressNotice = nil
                // A failed history traversal must not leave the suppress
                // flag standing — the next real navigation still pushes.
                self.isHistoryNavigation = false
            }
        }
    }

    /// A successful read lands: the pointing, the entries, the cursor.
    private func commit(host: String, path: String, entries: [FileEntry]) async {
        // Gather ZFS mountpoints and mount targets from memory — no wire, Decisions 5–6.
        let hostFacts = await engine.field.facts(for: host)
        let datasets = hostFacts?.zfsTopology?.value ?? []
        let allMounts = hostFacts?.mounts?.value ?? []
        // The facts hop is an await — a superseding read may have
        // cancelled this one mid-hop, and a stale commit never lands.
        guard !Task.isCancelled else { return }
        datasetMountpoints = engine.isLocal(host) ? [] : ZFSTopology.mountpointSet(in: datasets)
        mountTargets = engine.isLocal(host) ? [] : MountTable.targetSet(in: allMounts)
        let moved = host != state.host || path != state.path
        // Push the current location before the move commits — only for
        // real navigations, not history traversals, and only when the
        // pane already points somewhere (no push from the initial unpointed state).
        if moved, !isHistoryNavigation, let currentHost = state.host {
            history.push(PaneLocation(host: currentHost, path: state.path))
        }
        isHistoryNavigation = false
        state.host = host
        state.path = path
        if moved {
            state.selection = []
            state.cursor = nil
        }
        state.replaceEntries(entries)
        refreshRows()
        if let landOn {
            self.landOn = nil
            if rows.contains(where: { $0.id == landOn }) { state.cursor = landOn }
        }
        if let revealOnLand {
            self.revealOnLand = nil
            if rows.contains(where: { $0.id == revealOnLand }) {
                state.cursor = revealOnLand
                state.selection = [revealOnLand]
            }
        }
        status = .ready
        isReading = false
        lastError = nil
        addressNotice = pendingAddressNotice
        pendingAddressNotice = nil
        // A zfs-mode pane whose HOST just landed somewhere new shows that
        // host's tree. This lives here, not in point(): reads are async,
        // and refreshing before the host commits refreshed the OLD host
        // (the hands round's stale-tree screenshots, twice).
        if paneMode == .zfs, moved {
            Task { await refreshZFSTree(engine: engine) }
        }
        onDisplayChange()
    }

    /// Asks the host where home is — one round trip, POSIX-plain.
    ///
    /// Internal rather than private because the typed-address recovery in
    /// `PaneModel+Address.swift` expands `~` before it probes.
    func resolveTilde(_ path: String, host: String) async throws -> String {
        let door = engine.conduit(for: host)
        let result = try await door.run(on: host, "printf %s \"$HOME\"").collect()
        let home = result.stdoutText
        guard result.exitStatus == 0, home.hasPrefix("/") else { return path }
        return path == "~" ? home : home + path.dropFirst(1)
    }

    /// The flavor fact, from memory or one discovery round trip.
    ///
    /// The local machine is this Mac — Darwin, BSD, no discovery.
    private func resolveFlavor(host: String) async throws -> UserlandFlavor {
        if engine.isLocal(host) { return .bsd }
        if let flavor = await engine.field.facts(for: host)?.capability?.value.flavor {
            return flavor
        }
        let facts = try await engine.field.discover(host)
        if let flavor = facts.capability?.value.flavor {
            return flavor
        }
        if case .unreachable(let detail) = facts.reachability?.value {
            throw PointingError.unreachable(detail)
        }
        throw PointingError.unreachable("no capability fact")
    }

    /// A display-changing move: mutate, recompute rows, persist.
    private func applyDisplayChange(_ change: (inout PaneState) -> Void) {
        change(&state)
        refreshRows()
        onDisplayChange()
    }

    private func refreshRows() {
        rows = state.sortedEntries()
    }

    // MARK: - Clipboard

    /// The clipboard verbs — explicit rows when the context menu names
    /// them, the selection when it exists, the cursor otherwise.
    func copyToClipboard(_ intent: PaneIntent, ids: Set<FileEntry.ID>?) {
        let subjects: [FileEntry]
        if let ids, !ids.isEmpty {
            subjects = rows.filter { ids.contains($0.id) }
        } else if state.selection.isEmpty {
            subjects = [cursorEntry].compactMap { $0 }
        } else {
            subjects = rows.filter { state.selection.contains($0.id) }
        }
        guard !subjects.isEmpty || intent == .copyDirectory else { return }
        let lines: [String]
        switch intent {
        case .copyPath:
            guard let paths = exactPaths(for: subjects) else { return }
            lines = paths
        case .copyDirectory: lines = [state.path]
        case .copyFilename: lines = subjects.map(\.name)
        case .copyNameSansExtension: lines = subjects.map { Self.nameSansExtension($0.name) }
        default: return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: - Errors

    /// One quiet line for the pane — typed errors say what they are.
    ///
    /// Internal rather than private so the typed-address probe in
    /// `PaneModel+Address.swift` reports a failed lookup in the same words.
    nonisolated static func describe(_ error: any Error) -> String {
        switch error {
        case ListingError.directoryNotFound(let path): "no such directory: \(path)"
        case ListingError.permissionDenied(let path): "permission denied: \(path)"
        case ListingError.notADirectory(let path): "not a directory: \(path)"
        case ListingError.listingFailed(_, let stderr): "read failed: \(stderr)"
        case ListingError.malformedListing: "the listing did not parse — worth reporting"
        case ListingError.exceedsLimit(_, let limit):
            "too large to open here: past \(Int64(limit).formatted(.byteCount(style: .file))) while reading"
        case ListingError.timedOut(let path): "the read timed out: \(path)"
        case PointingError.unreachable(let detail): detail
        case is ProbeParseError:
            "the host answered, but its capability probe came back unreadable — worth reporting"
        case let conduitError as ConduitError: "\(conduitError)"
        default: "\(error)"
        }
    }

    /// Why a pane could not point.
    private enum PointingError: Error {
        case unreachable(String)
    }
}

// MARK: - Sort (ho-9.8 — extended for all nine columns)

extension PaneModel {
    /// Sets the sort from a Table header click.
    ///
    /// True when the entry is a directory the operator has starred.
    ///
    /// A name no path can carry was never starred — starring itself
    /// refuses such a name — so it partitions as plain.
    private func isStarredDirectory(_ entry: FileEntry, host: String, favorites: FavoritesModel) -> Bool {
        guard entry.kind == .directory, let childPath = Self.exactChildPath(of: state.path, entry: entry)
        else { return false }
        return favorites.isFavorited(host: host, path: childPath)
    }

    /// The Table reports the tapped column and its direction through its
    /// `sortOrder` binding; this maps that to the pane's own `Sort` and
    /// re-sorts through the listing's natural comparators — the same path
    /// the sort-key grammar (`,n` / `,s` / `,m`) takes.
    ///
    /// `★` uses `\.kind` as a routing token (see `StarMarkerComparator` in
    /// `PaneView+Columns.swift`). When `\.kind` arrives here, `favorites`
    /// drives a starred-first partition rather than a normal sort — starred
    /// directories gather at top/bottom without mutating `state.sort`, so the
    /// rest of the sort order is preserved when the ★ column is toggled off.
    ///
    /// - Parameters:
    ///   - comparator: The `KeyPathComparator<FileEntry>` the Table emitted.
    ///   - favorites: The favorites registry — required for the ★ routing branch.
    ///                Callers that cannot reach `FavoritesModel` may pass `nil`;
    ///                the ★ branch then silently no-ops.
    func applySort(
        from comparator: KeyPathComparator<FileEntry>,
        favorites: FavoritesModel? = nil
    ) {
        // ★ routing token: \.kind is the sentinel keypath emitted by the ★ column
        // (see StarMarkerComparator in PaneView+Columns.swift). Perform a
        // starred-first partition rather than touching state.sort — ★ order is
        // transient/app-side, not a PaneState fact. Starred directories gather at
        // the top (ascending) or bottom (descending); non-directory entries are
        // never starred and always go to the plain bucket.
        if comparator.keyPath == \FileEntry.kind {
            guard let host = state.host, let favorites else { return }
            // Determine star status via isFavorited — the single truth about what
            // the operator has bookmarked. Never derive from FileEntry itself.
            let isStarred: (FileEntry) -> Bool = { entry in
                self.isStarredDirectory(entry, host: host, favorites: favorites)
            }
            // Explicit filter-and-concatenate — never rely on sort stability.
            let starredRows = rows.filter { isStarred($0) }
            let plainRows = rows.filter { !isStarred($0) }
            rows =
                comparator.order == .forward
                ? starredRows + plainRows  // ascending: starred first
                : plainRows + starredRows  // descending: starred last
            onDisplayChange()
            return
        }

        let key: PaneState.SortKey
        switch comparator.keyPath {
        case \FileEntry.size: key = .size
        case \FileEntry.modified: key = .modified
        case \FileEntry.name: key = .name
        case \FileEntry.created: key = .created
        case \FileEntry.changed: key = .changed
        case \FileEntry.permissions: key = .permissions
        case \FileEntry.owner: key = .owner
        case \FileEntry.group: key = .group
        default:
            return  // a column with no core sort key — nothing to apply
        }
        state.sort = PaneState.Sort(key: key, ascending: comparator.order == .forward)
        refreshRows()
        onDisplayChange()
    }
}

// MARK: - Dataset boundary mark (ho-09 Decisions 5–6)

extension PaneModel {
    /// The boundary mark for a directory entry — dataset, plain mount, or absent.
    enum BoundaryMark {
        /// A ZFS dataset mountpoint — the filled drive glyph.
        case dataset
        /// A plain mount target — the outlined drive glyph.
        case mount
    }

    /// Resolves the boundary mark for a directory entry.
    ///
    /// Dataset mountpoint → `.dataset`, plain mount target → `.mount`,
    /// nil otherwise. Non-directory entries always return nil.
    func boundaryMark(for entry: FileEntry) -> BoundaryMark? {
        // Mountpoints are strings the host reported; an entry no string
        // carries exactly cannot be one of them.
        guard entry.kind == .directory, let fullPath = Self.exactChildPath(of: state.path, entry: entry)
        else { return nil }
        if datasetMountpoints.contains(fullPath) { return .dataset }
        if mountTargets.contains(fullPath) { return .mount }
        return nil
    }
}

// MARK: - The exact-path boundary

extension PaneModel {
    /// The refusal a pane shows for a name no path can carry exactly.
    static let unrepresentableNameRefusal =
        "this name is not valid UTF-8 — no path can address it exactly, so pālana refuses rather than guess"

    /// Joins the pane's directory and an entry's exact name, or nil.
    ///
    /// The one way an action turns a ``FileEntry`` into a path. It goes
    /// through ``FileEntry/exactName`` — the bytes round-trip UTF-8 or
    /// there is no path — never through the display `name`, whose
    /// replacement characters would address a different entry.
    nonisolated static func exactChildPath(of path: String, entry: FileEntry) -> String? {
        entry.exactName.map { childPath(of: path, name: $0) }
    }

    /// The entry's exact path in this pane, or nil with the refusal posted.
    func exactPath(for entry: FileEntry) -> String? {
        guard let path = Self.exactChildPath(of: state.path, entry: entry) else {
            lastError = Self.unrepresentableNameRefusal
            return nil
        }
        return path
    }

    /// Every entry's exact path, or nil with the refusal posted — all or
    /// nothing, so a pasted list never silently drops a name.
    func exactPaths(for entries: [FileEntry]) -> [String]? {
        let paths = entries.map { Self.exactChildPath(of: state.path, entry: $0) }
        guard !paths.contains(nil) else {
            lastError = Self.unrepresentableNameRefusal
            return nil
        }
        return paths.compactMap { $0 }
    }
}

// MARK: - Opening files (ho-07 addendum; local-in-place per the third session)

extension PaneModel {
    private func openFile(_ entry: FileEntry, on host: String) {
        // The byte boundary, before any path exists: the fetch command,
        // the temp copy's name, and the round-trip record all carry this
        // one exact name, or the open refuses (review: a lossy name
        // uploaded an edited copy under the wrong filename).
        guard let path = exactPath(for: entry), let exactName = entry.exactName else { return }
        // A local file opens in place — the operator's edits land in
        // the file itself, never in a copy (third session: edits saved
        // to the fetched copy read as vanished).
        if engine.isLocal(host) {
            openInForeground(URL(fileURLWithPath: path))
            return
        }
        // The listing's size is a courtesy refusal — stale by definition.
        // The ceiling that holds is the streaming one in the fetch below.
        let ceiling = openByteCeiling
        guard entry.size <= Int64(ceiling) else {
            lastError = "too large to open here: \(entry.size.formatted(.byteCount(style: .file)))"
            return
        }
        // Capture the remote identity BEFORE the download — host, the
        // directory the file was opened from, the entry as listed, and this
        // open's generation. A navigation during the fetch must not change
        // where a later save goes back to (review: wrong-upload-directory).
        let capturedHost = host
        let capturedDirectory = state.path
        let capturedEntry = entry
        openGeneration += 1
        let capturedGeneration = openGeneration
        isReading = true
        Task {
            do {
                // A fresh directory per open — a re-open must never
                // overwrite a copy the operator may have edited.
                let directory = try RoundTripRecord.makeOpenDirectory()
                let local = directory.appendingPathComponent(exactName)
                // The bytes stream straight to the copy under the ceiling;
                // a file that outgrew its listing is refused mid-stream,
                // its command terminated, and the directory taken back.
                let fetched: FetchedFile
                do {
                    fetched = try await self.engine.listing(for: capturedHost)
                        .fetchFile(on: capturedHost, path: path, to: local, limit: ceiling)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    throw error
                }
                self.isReading = false
                self.openInForeground(local)
                // Register a round-trip watch for this remote open. The
                // record is built only from the values captured before the
                // download, plus the content digest of what was fetched —
                // the send-back conflict baseline. The session wires
                // onRoundTripRegistered to RoundTripCenter.
                let record = RoundTripRecord(
                    host: capturedHost,
                    remoteDirectory: capturedDirectory,
                    fetched: capturedEntry,
                    digest: fetched.digest,
                    localURL: local,
                    generation: capturedGeneration)
                self.onRoundTripRegistered(record)
            } catch {
                self.isReading = false
                self.lastError = Self.describe(error)
            }
        }
    }

    /// Hands a URL to the system, activated — an open that lands
    /// behind the window is an open that looks like it didn't happen.
    ///
    /// Routed through ``openHandler`` so a test can observe the open without
    /// launching a real editor.
    private func openInForeground(_ url: URL) {
        openHandler(url)
    }
}

// MARK: - Address refusal — the half that needs the pane's own state

extension PaneModel {
    /// Refuses a typed address in place: the pane stays where it was and
    /// says why in its quiet line.
    ///
    /// Internal rather than private because ``pointAddress(_:)`` lives in
    /// `PaneModel+Address.swift` and Swift's `private` is file-scoped; the
    /// error line it writes is what keeps this half here.
    func refuseAddress(_ reason: String) {
        isReading = false
        lastError = reason
    }

    /// Marks a typed-address recovery in flight — the header reads
    /// `reading…` while the host is asked, before any listing starts.
    func beginAddressRecovery() {
        isReading = true
    }
}
