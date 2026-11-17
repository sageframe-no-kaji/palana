// Drag-and-drop wiring for the Surface: NSItemProvider drag helpers,
// Finder-URL-drop resolution helpers, and the
// glue that routes a DropDecision through the standing begin/gather path.
//
// ho-9.6 rework — root-cause fixes:
//   RC1: UTType(exportedAs:) requires an app-bundle Info.plist
//        registration; a bare SwiftPM binary has none, so the Transferable
//        CodableRepresentation write silently fails.
//   RC2: Two stacked .dropDestination modifiers — SwiftUI honours only one
//        per view; the second replaced the first, so DraggedSelection drops
//        were never caught. We now use a single .onDrop that handles both.
//
// Third attempt — root-cause fix (RC3):
//   UTType("com.sageframe.palana.selection") returns nil for undeclared
//   identifiers, so onDrop's type list silently degraded to [.data, .fileURL].
//   Our NSItemProvider only carried the raw undeclared string, which does NOT
//   conform to public.data — so the drop view never accepted our drags.
//
//   Fix: encode the DraggedSelection JSON under "public.json" (UTType.json),
//   a system-declared type that conforms to public.data and public.text.
//   Both the drag side and the drop side use .json; unrelated JSON that
//   happens to land on the pane is caught by a decode failure and refused
//   quietly (fall through to URL resolution).
//
// Diagnostics from the proving rounds were removed once the practitioner
// confirmed drag working live (2026-07-10, "its working").

import AppKit
import PalanaCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag payload builder

/// What a remote row needs to deliver its file at the drop.
struct RemoteDragSupport: Sendable {
    /// The reader that reaches the row's host.
    let listing: Listing
    /// Writes one transcript line — downloads and refusals report here.
    let report: @Sendable (String) -> Void
}

/// Builds an ``NSItemProvider`` carrying a ``DraggedSelection`` encoded as JSON,
/// plus what the row delivers to the rest of the Mac.
///
/// The payload is registered under `UTType.json.identifier` ("public.json") —
/// a system-declared type that requires no app-bundle registration and
/// conforms to public.data and public.text — with process-only visibility.
/// The drop side identifies it by a successful decode into
/// ``DraggedSelection``; pālana's drop never asks for the other
/// representations, so pane-to-pane drags are untouched by them.
///
/// What leaves the app follows `outbound` (from ``DragOutPlan``):
/// - a local entry registers its file URL, and a file representation opened
///   in place, so a sandboxed receiver (a browser, a chat app) gets a file it
///   may read;
/// - a remote file registers a file representation that downloads it when
///   the receiver asks (``RemoteDragFetch``), with a transcript line;
/// - a refused remote entry registers a representation that refuses with
///   the reason, written to the transcript — only an outside receiver asks.
///
/// Returns `nil` when encoding fails (a programming error).
@MainActor
func itemProvider(
    for selection: DraggedSelection,
    outbound: DragOutItem? = nil,
    remote: RemoteDragSupport? = nil
) -> NSItemProvider? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(selection) else {
        return nil
    }
    let provider = NSItemProvider()
    provider.suggestedName = "selection"
    provider.registerDataRepresentation(
        forTypeIdentifier: UTType.json.identifier,
        // Same-process only: the payload is pane-to-pane vocabulary, not
        // an export. Visibility .all let a remote drag materialize a
        // 'selection.json' on outside targets (his round-9 finding).
        visibility: .ownProcess
    ) { completion in
        completion(data, nil)
        return nil
    }
    switch outbound {
    case .localFile(let path):
        registerLocalFile(on: provider, url: URL(fileURLWithPath: path))
    case .remoteFile(let host, let path, let size):
        if let remote { registerRemoteFile(on: provider, host: host, path: path, size: size, remote: remote) }
    case .refused(let name, let reason):
        if let remote { registerRefusal(on: provider, name: name, reason: reason, report: remote.report) }
    case nil:
        break
    }
    return provider
}

/// A local entry: its URL for Finder and pālana, and the file itself,
/// opened in place, for receivers that cannot open a bare URL.
@MainActor
private func registerLocalFile(on provider: NSItemProvider, url: URL) {
    provider.suggestedName = url.lastPathComponent
    provider.registerObject(url as NSURL, visibility: .all)
    let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    let type = isFolder ? UTType.folder.identifier : dragOutFileType(for: url.path)
    let deliver: @Sendable (@escaping (URL?, Bool, (any Error)?) -> Void) -> Progress? = { completion in
        completion(url, true, nil)
        return nil
    }
    provider.registerFileRepresentation(
        forTypeIdentifier: type, fileOptions: [.openInPlace], visibility: .all, loadHandler: deliver)
}

/// A remote file: downloaded when the receiver asks, never a partial file.
@MainActor
private func registerRemoteFile(
    on provider: NSItemProvider, host: String, path: String, size: Int64, remote: RemoteDragSupport
) {
    provider.suggestedName = (path as NSString).lastPathComponent
    provider.registerFileRepresentation(
        forTypeIdentifier: dragOutFileType(for: path), fileOptions: [], visibility: .all
    ) { completion in
        let done = DragOutCompletion(completion)
        let fetch = RemoteDragFetch(listing: remote.listing, host: host, path: path, size: size)
        remote.report("downloading \(fetch.location) for a drop…")
        return fetch.start { result in
            switch result {
            case .success(let url):
                // The receiver copies the file before this returns.
                done.call(url, nil)
                fetch.cleanUp()
                remote.report("\(fetch.location) delivered to the drop")
            case .failure(let error):
                done.call(nil, error)
                remote.report("\(fetch.location) — download failed: \(error)")
            }
        }
    }
}

/// A remote entry drag-out refuses: an outside receiver hears why.
@MainActor
private func registerRefusal(
    on provider: NSItemProvider, name: String, reason: DragOutRefusal, report: @escaping @Sendable (String) -> Void
) {
    let line = reason.line(name: name)
    provider.suggestedName = name
    let refuse: @Sendable (@escaping (URL?, Bool, (any Error)?) -> Void) -> Progress? = { completion in
        report(line)
        completion(nil, false, DragOutRefused(message: line))
        return nil
    }
    provider.registerFileRepresentation(
        forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all, loadHandler: refuse)
}

/// The error an outside receiver gets for a refused entry.
struct DragOutRefused: LocalizedError, Equatable {
    /// The transcript line, word for word.
    let message: String
    var errorDescription: String? { message }
}

/// Carries a file-representation completion to the download's thread.
private final class DragOutCompletion: @unchecked Sendable {
    // @unchecked: NSItemProvider documents the load-handler completion as
    // callable from any thread; it is called exactly once.
    private let handler: (URL?, Bool, (any Error)?) -> Void

    init(_ handler: @escaping (URL?, Bool, (any Error)?) -> Void) {
        self.handler = handler
    }

    func call(_ url: URL?, _ error: (any Error)?) {
        handler(url, false, error)
    }
}

/// A file's type from its extension; `public.data` when unknown (an unknown
/// extension yields a dynamic "dyn.…" type no receiver knows).
func dragOutFileType(for path: String) -> String {
    guard let type = UTType(filenameExtension: (path as NSString).pathExtension), !type.isDynamic else {
        return UTType.data.identifier
    }
    return type.identifier
}

// MARK: - Drop routing

/// Routes a resolved ``DropDecision`` through the standing `begin`/gather
/// path, exactly as `y`/`m` do via the keyboard.
///
/// Refusal notes are emitted through `operation.note` — one transcript line
/// per refuse, none for empty.
///
/// - Parameters:
///   - decision: The outcome of ``DropDecision/decide(payload:targetHost:targetDirectory:moveHeld:)``.
///   - payload: The drag payload from the source pane.
///   - targetPane: The destination pane model.
///   - sourcePanes: Both pane models — used to locate the source pane for
///     pane-to-pane drags (resolves entries from live rows).
///   - operation: The ``OperationModel`` that owns the panel.
@MainActor
func routeDropDecision(
    _ decision: DropDecision,
    payload: DraggedSelection,
    targetPane: PaneModel,
    sourcePanes: [PaneModel],
    operation: OperationModel
) {
    switch decision {
    case .refuseSamePlace:
        operation.note("drop refused — same location")
    case .refuseEmpty:
        break  // nothing to say
    case .compose(let planOperation):
        // Locate the source pane by host + directory — a pane-to-pane drag
        // always has a live source pane in the session.
        let sourcePane = sourcePanes.first {
            $0.state.host == payload.host && $0.state.path == payload.directory
        }
        if let sourcePane {
            // Pane-to-pane: aim the subjects at the dragged names and call
            // begin, exactly as the context menu's operate(_:ids:) does.
            let draggedNames = Set(payload.names)
            let matchingIDs = sourcePane.rows
                .filter { draggedNames.contains($0.nameData) }
                .map(\.id)
            // If the dragged names no longer resolve (the source changed
            // between drag and drop), composing from the pane's stale
            // cursor/selection would plan entries the operator never
            // dragged — refuse instead.
            guard !matchingIDs.isEmpty else {
                operation.note("drop refused — dragged entries no longer present at the source")
                return
            }
            let ids = Set(matchingIDs)
            if !ids.isSubset(of: sourcePane.state.selection) {
                sourcePane.state.selection = ids.count > 1 ? ids : []
                sourcePane.state.cursor = ids.first
            }
            operation.begin(planOperation, source: sourcePane, destination: targetPane)
        } else {
            // Finder drop: source pane is unavailable — guard; Finder drops
            // use routeFinderDrop instead and never reach this branch.
            operation.note("drop refused — source pane not found")
        }
    }
}

/// Routes a folder-row ``DropDecision`` (ho-14) — like ``routeDropDecision``,
/// but `destination` is the folder's full path, not the pane's cwd.
///
/// Resolves the source pane and the dragged cohort from live rows, then hands
/// them to ``OperationModel/beginFromFinderDrop(_:source:destination:entries:)``
/// — the generic "already-resolved entries + explicit destination Locus" begin
/// (its name is historical; a pane-to-pane folder drop resolves its cohort the
/// same way a Finder drop does). Nothing enacts; the panel is the gate.
///
/// - Parameters:
///   - decision: The outcome of ``DropDecision/decideOntoFolder(payload:targetHost:folderPath:folderNameData:moveHeld:)``.
///   - payload: The drag payload from the source pane.
///   - destination: The folder as a ``Locus`` — the destination host and the
///     folder's full path, resolved by the caller.
///   - sourcePanes: Both pane models, to locate the source pane.
///   - operation: The ``OperationModel`` that owns the panel.
@MainActor
func routeFolderDrop(
    _ decision: DropDecision,
    payload: DraggedSelection,
    destination: Locus,
    sourcePanes: [PaneModel],
    operation: OperationModel
) {
    switch decision {
    case .refuseSamePlace:
        operation.note("drop refused — same location")
    case .refuseEmpty:
        break
    case .compose(let planOperation):
        guard
            let sourcePane = sourcePanes.first(where: {
                $0.state.host == payload.host && $0.state.path == payload.directory
            })
        else {
            operation.note("drop refused — source pane not found")
            return
        }
        let draggedNames = Set(payload.names)
        let cohort = sourcePane.rows.filter { draggedNames.contains($0.nameData) }
        guard !cohort.isEmpty else {
            operation.note("drop refused — dragged entries no longer present at the source")
            return
        }
        operation.beginFromFinderDrop(
            planOperation,
            source: Locus(host: payload.host, directory: payload.directory),
            destination: destination,
            entries: cohort
        )
    }
}

// MARK: - Finder URL resolution

/// Where a resolved Finder-drop cohort is handed — the begin seam.
typealias FinderDropBegin = @MainActor (PlanOperation, Locus, Locus, [FileEntry]) -> Void

/// The destination a Finder drop binds to, read at the moment of the drop.
///
/// The pane's host and directory (or the folder row's full path) as they
/// stand right now — nil when the pane is not ready to receive. Pure and
/// synchronous by design: the caller captures the result before any await,
/// and the plan uses it unchanged however the pane moves afterwards.
@MainActor
func finderDropDestination(targetPane: PaneModel, destinationDirectory: String?) -> Locus? {
    guard let host = targetPane.state.host, targetPane.status == .ready else { return nil }
    return Locus(host: host, directory: destinationDirectory ?? targetPane.state.path)
}

/// Resolves a Finder URL drop onto a pane into a copy plan composed
/// through the standing gather path.
///
/// Decision 4: entries come from the local listing of the dropped
/// URLs' parent directory — never hand-built from FileManager attributes.
/// When URLs span more than one parent directory, only the first parent's
/// cohort is composed; the remainder are named in the transcript via
/// `operation.note`.
///
/// - Parameters:
///   - urls: The file URLs dropped from Finder.
///   - targetPane: The destination pane.
///   - engine: The session's engine (for the local listing).
///   - operation: The ``OperationModel`` that owns the panel and the transcript.
///   - moveHeld: Whether Option was held at drop time.
///   - destinationDirectory: When non-nil, the plan targets this directory on
///     the destination host instead of the pane's cwd — a Finder drop onto a
///     folder row (ho-14 review) passes the folder's full path.
///   - begin: Where the resolved cohort goes; defaults to
///     ``OperationModel/beginFromFinderDrop(_:source:destination:entries:)``.
///     A test seam — the routing is observed without a gather.
@MainActor
func routeFinderDrop(
    urls: [URL],
    targetPane: PaneModel,
    engine: Engine,
    operation: OperationModel,
    moveHeld: Bool,
    destinationDirectory: String? = nil,
    begin: FinderDropBegin? = nil
) {
    guard !urls.isEmpty else { return }
    // The destination is where the drop landed — read now, synchronously,
    // before any await. A pane that navigates while the source listing is
    // in flight must not move the plan with it (review).
    guard
        let destinationLocus = finderDropDestination(
            targetPane: targetPane, destinationDirectory: destinationDirectory)
    else {
        operation.note("finder drop: destination pane is not ready")
        return
    }
    let begin =
        begin ?? { planOperation, source, destination, entries in
            operation.beginFromFinderDrop(planOperation, source: source, destination: destination, entries: entries)
        }
    // Group by parent path — keep the first parent's cohort.
    let grouped = Dictionary(grouping: urls) { url in
        url.deletingLastPathComponent().path
    }
    let sortedParents = grouped.keys.sorted()
    guard let firstParent = sortedParents.first else { return }
    let firstCohortURLs = grouped[firstParent] ?? []
    // Matched on bytes: the listing's identity is the name bytes, and a
    // display-string match could pair a dropped name with a sibling whose
    // bytes merely display the same.
    let droppedNames = Set(firstCohortURLs.map { Data($0.lastPathComponent.utf8) })
    // Names left behind — all URLs not in the first parent's cohort.
    if sortedParents.count > 1 {
        let leftBehind = sortedParents.dropFirst()
            .flatMap { grouped[$0] ?? [] }
            .map(\.lastPathComponent)
        if !leftBehind.isEmpty {
            operation.note(
                "finder drop: using files from \(firstParent); "
                    + "left behind from other directories: \(leftBehind.joined(separator: ", "))"
            )
        }
    }
    // Resolve entries from the local listing — byte-honest, never hand-built.
    let planOperation: PlanOperation = moveHeld ? .move : .copy
    Task { @MainActor in
        do {
            let entries = try await engine.localListing
                .list(on: PalanaCore.localHostName, path: firstParent, flavor: .bsd)
            let cohort = entries.filter { droppedNames.contains($0.nameData) }
            guard !cohort.isEmpty else {
                operation.note("finder drop: no matching entries found in \(firstParent)")
                return
            }
            let sourceLocus = Locus(host: PalanaCore.localHostName, directory: firstParent)
            begin(planOperation, sourceLocus, destinationLocus, cohort)
        } catch {
            operation.note("finder drop: could not read \(firstParent) — \(error)")
        }
    }
}
