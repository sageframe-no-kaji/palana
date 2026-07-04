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
    /// True while a read is in flight over a ready pane.
    private(set) var isReading = false
    /// Dataset mountpoints gathered from cached ZFS facts at the last
    /// successful commit — empty when the host is local, facts are absent,
    /// or ZFS is not in the facts.
    private(set) var datasetMountpoints: Set<String> = []
    /// Rows a page move jumps — the view updates it from geometry.
    var pageSize = 25
    /// True while the header's path field is being typed in — the key
    /// monitor stands down so the letters reach the field.
    var pathEditing = false

    /// Fires on pointing, sort, and hidden changes — the session persists there.
    ///
    /// Set once, right after construction.
    var onDisplayChange: @MainActor () -> Void = {}

    private static let logger = Logger(subsystem: "net.sageframe.palana", category: "pane")

    private let engine: Engine
    private var loadTask: Task<Void, Never>?
    private var landOn: Data?

    /// A pane over the session's engine.
    init(engine: Engine) {
        self.engine = engine
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
        read(host: host, path: path.isEmpty ? "/" : path)
    }

    /// Applies one intent.
    ///
    /// Cursor and selection moves mutate synchronously; reads spawn.
    func apply(_ intent: PaneIntent) {
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

    /// The entry under the cursor, if any.
    var cursorEntry: FileEntry? {
        guard let cursor = state.cursor else { return nil }
        return rows.first { $0.id == cursor }
    }

    /// What an operation verb acts on.
    ///
    /// The selection when it exists, the cursor entry otherwise — the
    /// clipboard-verb precedent.
    var operationSubjects: [FileEntry] {
        if state.selection.isEmpty {
            return [cursorEntry].compactMap { $0 }
        }
        return rows.filter { state.selection.contains($0.id) }
    }

    // MARK: - Navigation

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
            point(host: host, path: Self.childPath(of: state.path, name: entry.name))
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

    /// Shift-click: select the run from the cursor to the clicked row,
    /// inclusive — Finder's manners over yazi's marks.
    func extendSelection(to id: FileEntry.ID) {
        guard
            let anchor = state.cursor,
            let from = rows.firstIndex(where: { $0.id == anchor }),
            let to = rows.firstIndex(where: { $0.id == id })
        else {
            state.selection.insert(id)
            return
        }
        for row in rows[min(from, to)...max(from, to)] {
            state.selection.insert(row.id)
        }
    }

    /// ⌘- or ⌥-click: toggle one row in or out of the selection.
    func toggleSelection(_ id: FileEntry.ID) {
        if state.selection.contains(id) {
            state.selection.remove(id)
        } else {
            state.selection.insert(id)
        }
    }

    /// Enter on a file: fetch a temp copy, hand it to the system.
    ///
    /// Guarded by size — a pane is not a transfer tool, and the real
    /// moves belong to the plan panel.
    private func openFile(_ entry: FileEntry, on host: String) {
        let ceiling: Int64 = 50_000_000
        guard entry.size <= ceiling else {
            lastError = "too large to open here: \(entry.size.formatted(.byteCount(style: .file)))"
            return
        }
        let remotePath = Self.childPath(of: state.path, name: entry.name)
        isReading = true
        Task {
            do {
                let data = try await self.engine.listing(for: host)
                    .readFile(on: host, path: remotePath)
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("palana-open", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                let local = directory.appendingPathComponent(entry.name)
                try data.write(to: local, options: .atomic)
                self.isReading = false
                // In the foreground — an open that lands behind the
                // window is an open that looks like it didn't happen.
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.open(local, configuration: configuration)
            } catch {
                self.isReading = false
                self.lastError = Self.describe(error)
            }
        }
    }

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
                self.isReading = false
                if self.status == .loading { self.status = self.rows.isEmpty ? .unpointed : .ready }
                self.lastError = Self.describe(error)
            }
        }
    }

    /// A successful read lands: the pointing, the entries, the cursor.
    private func commit(host: String, path: String, entries: [FileEntry]) async {
        // Gather ZFS mountpoints from memory — no wire, Decision 6.
        let datasets = await engine.field.facts(for: host)?.zfsTopology?.value ?? []
        // The facts hop is an await — a superseding read may have
        // cancelled this one mid-hop, and a stale commit never lands.
        guard !Task.isCancelled else { return }
        datasetMountpoints = engine.isLocal(host) ? [] : ZFSTopology.mountpointSet(in: datasets)
        let moved = host != state.host || path != state.path
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
        status = .ready
        isReading = false
        lastError = nil
        onDisplayChange()
    }

    /// Asks the host where home is — one round trip, POSIX-plain.
    private func resolveTilde(_ path: String, host: String) async throws -> String {
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
        case .copyPath: lines = subjects.map { Self.childPath(of: state.path, name: $0.name) }
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
    private static func describe(_ error: any Error) -> String {
        switch error {
        case ListingError.directoryNotFound(let path): "no such directory: \(path)"
        case ListingError.permissionDenied(let path): "permission denied: \(path)"
        case ListingError.notADirectory(let path): "not a directory: \(path)"
        case ListingError.listingFailed(_, let stderr): "read failed: \(stderr)"
        case ListingError.malformedListing: "the listing did not parse — worth reporting"
        case PointingError.unreachable(let detail): detail
        case is ProbeParseError:
            "the host answered, but its capability probe came back unreadable — worth reporting"
        case let conduitError as ConduitError: "\(conduitError)"
        default: "\(error)"
        }
    }

    /// Points from a typed `host:path` address — bare host means home.
    func pointAddress(_ address: String) {
        let typed = address.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        if let colon = typed.firstIndex(of: ":") {
            let host = String(typed[..<colon])
            let path = String(typed[typed.index(after: colon)...])
            guard !host.isEmpty else { return }
            point(host: host, path: path.isEmpty ? "~" : path)
        } else {
            point(host: typed, path: "~")
        }
    }

    /// Why a pane could not point.
    private enum PointingError: Error {
        case unreachable(String)
    }
    // MARK: - Path arithmetic (UTF-8 v1, per ho-04's named limitation)

    static func childPath(of path: String, name: String) -> String {
        path == "/" ? "/\(name)" : "\(path)/\(name)"
    }

    static func parentPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let cut = trimmed.lastIndex(of: "/"), cut != trimmed.startIndex else { return "/" }
        return String(trimmed[..<cut])
    }

    static func lastComponent(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let cut = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: cut)...])
    }

    static func nameSansExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}

// MARK: - Dataset boundary mark (ho-09 Decision 6)

extension PaneModel {
    /// True when the entry is a directory whose full path is an exact
    /// dataset mountpoint in the cached ZFS facts — the boundary mark.
    func isDatasetMountpoint(_ entry: FileEntry) -> Bool {
        guard entry.kind == .directory else { return false }
        let fullPath = Self.childPath(of: state.path, name: entry.name)
        return datasetMountpoints.contains(fullPath)
    }
}
