// Drag-and-drop wiring for the Surface: NSItemProvider drag helpers,
// unified onDrop handler, Finder-URL-drop resolution helpers, and the
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

/// Builds an ``NSItemProvider`` carrying a ``DraggedSelection`` encoded as JSON.
///
/// Registered under `UTType.json.identifier` ("public.json") — a system-declared
/// type that requires no app-bundle registration and conforms to public.data and
/// public.text. The drop side identifies our payload by successful JSON decode
/// into ``DraggedSelection`` rather than by a custom type identifier.
///
/// When `localFileURL` is non-nil the provider ALSO registers the real
/// file URL, so the drag lands anywhere a file lands — Finder, a browser
/// upload, Mail. Local panes only: a remote entry has no URL this Mac can
/// honor (the file-promise download drag is banked as its own item).
/// pālana's own drop side prefers the json payload, so pane-to-pane drags
/// are untouched by the extra representation.
///
/// Returns `nil` when encoding fails (a programming error).
@MainActor
func itemProvider(for selection: DraggedSelection, localFileURL: URL? = nil) -> NSItemProvider? {
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
    if let url = localFileURL {
        provider.suggestedName = url.lastPathComponent
        provider.registerObject(url as NSURL, visibility: .all)
    }
    return provider
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

// MARK: - Unified drop handler support

/// The resolved outcome of a unified drop, delivered asynchronously to the pane's `.onDrop` handler.
///
/// Value-typed and `Sendable`; safe to hop across actor boundaries.
enum DropResult: Sendable {
    /// A ``DraggedSelection`` was decoded from the JSON pasteboard type.
    case selection(DraggedSelection, moveHeld: Bool)
    /// File URLs were collected from a Finder drop.
    case urls([URL], moveHeld: Bool)
}

/// Resolves providers from `.onDrop` to a ``DropResult`` asynchronously.
///
/// Tries `public.json` first and decodes as ``DraggedSelection`` (pane-to-pane
/// drag); a decode failure means it is unrelated JSON — falls through to URL
/// collection. Falls back to collecting file URLs (Finder drop). Returns `nil`
/// when no recognisable content is found.
///
/// The result is `Sendable` so the caller can freely dispatch it on `MainActor`.
///
/// - Parameters:
///   - providers: The `NSItemProvider` array from the `.onDrop` closure.
///   - moveHeld: Whether Option was held at drop time (captured before the
///     async hops to avoid checking modifier state off-thread).
/// - Returns: A ``DropResult`` or `nil` when the providers carry nothing usable.
func resolveDropProviders(
    providers: [NSItemProvider],
    moveHeld: Bool
) async -> DropResult? {
    // Try public.json first — pane-to-pane drag.
    if let provider = providers.first(where: {
        $0.hasItemConformingToTypeIdentifier(UTType.json.identifier)
    }) {
        let result = await withCheckedContinuation { (cont: CheckedContinuation<DraggedSelection?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, error in
                guard let data, error == nil,
                    let payload = try? JSONDecoder().decode(DraggedSelection.self, from: data)
                else {
                    // Decode failure means unrelated JSON (e.g. Finder copy) — not ours.
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: payload)
            }
        }
        if let payload = result {
            return .selection(payload, moveHeld: moveHeld)
        }
        // Decoded nothing — fall through to URL resolution below.
    }

    // Fall back to file URLs — Finder drop.
    let fileURLProviders = providers.filter {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }
    guard !fileURLProviders.isEmpty else { return nil }

    var urls: [URL] = []
    for provider in fileURLProviders {
        let url = await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
        if let url { urls.append(url) }
    }
    return urls.isEmpty ? nil : .urls(urls, moveHeld: moveHeld)
}

// MARK: - Unified drop handler

/// Unified `.onDrop` handler — dispatches provider resolution and routes the
/// result to the appropriate callback on `MainActor`.
///
/// Returns `true` immediately when the pane is ready and providers look
/// promising — the actual dispatch happens asynchronously. Returns `false`
/// when the pane is not ready or no usable content is found.
///
/// Callbacks are dispatched via `DispatchQueue.main.async` after provider
/// resolution so they require no `@Sendable` annotation — the callers are
/// always `@MainActor`-isolated SwiftUI closure literals.
///
/// Instrumentation:
/// - (c) logged at entry — proves the drop closure fires, lists all type identifiers.
/// - (d) logged at resolve outcome — selection / urls / nothing.
///
/// - Parameters:
///   - providers: The `NSItemProvider` array from the `.onDrop` closure.
///   - model: The pane that is the drop target.
///   - onDropSelection: Called on the main queue with the decoded payload +
///     move-held flag (⌘).
///   - onFinderDrop: Called on the main queue with the resolved URLs +
///     move-held flag (⌘).
/// - Returns: `true` when a drop is attempted; `false` on refusal or empty providers.
@MainActor
func handleUnifiedDrop(
    providers: [NSItemProvider],
    model: PaneModel,
    onDropSelection: @escaping (DraggedSelection, Bool) -> Void,
    onFinderDrop: @escaping ([URL], Bool) -> Void
) -> Bool {
    guard model.status == .ready, model.state.host != nil else {
        return false
    }
    // Copy is the default; ⌘ escalates to a move — the one universal modifier,
    // read the same for pane-to-pane and Finder drags (a ⌘-drag from Finder
    // sets the drag's operation mask to .move). The plan is still the gate.
    let moveHeld = NSEvent.modifierFlags.contains(.command)

    // Quick check — bail before async work when nothing looks right.
    let hasJSON = providers.contains {
        $0.hasItemConformingToTypeIdentifier(UTType.json.identifier)
    }
    let hasURLs = providers.contains {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }
    guard hasJSON || hasURLs else {
        return false
    }

    // Provider loads are async. resolveDropProviders returns a Sendable
    // DropResult; once we have it we hop to the main queue via DispatchQueue
    // (no @Sendable requirement on the dispatch block) to call the callbacks.
    Task {
        let result = await resolveDropProviders(
            providers: providers,
            moveHeld: moveHeld
        )
        guard let result else { return }
        DispatchQueue.main.async {
            switch result {
            case .selection(let payload, let held):
                onDropSelection(payload, held)
            case .urls(let urls, let held):
                onFinderDrop(urls, held)
            }
        }
    }
    return true
}

// MARK: - Folder-row drop handler

/// Row-level `.onDrop` handler for a folder row (ho-14, extended in review).
///
/// Consumes both drag currencies onto the folder: the pane-to-pane
/// `public.json` selection AND Finder file URLs — a file dragged in from Finder
/// onto a folder row lands *inside* that folder, not in the pane's cwd. The
/// pane-level drop is left for drops off any folder row.
///
/// Returns `true` when a promising drag is present so the row consumes the drop
/// and the pane-level handler does not also fire (no double-plan). The resolved
/// payload or URLs are delivered on the main queue with the folder entry and
/// the move-held flag (⌘).
///
/// - Parameters:
///   - providers: The `NSItemProvider` array from the row's `.onDrop` closure.
///   - model: The pane hosting the folder row.
///   - folder: The directory entry the drop landed on.
///   - onSelectionOntoFolder: Called for a pane-to-pane drop onto the folder.
///   - onFinderOntoFolder: Called for a Finder URL drop onto the folder.
/// - Returns: `true` when the row consumes the drag; `false` otherwise.
@MainActor
func handleFolderDrop(
    providers: [NSItemProvider],
    model: PaneModel,
    folder: FileEntry,
    onSelectionOntoFolder: @escaping (DraggedSelection, FileEntry, Bool) -> Void,
    onFinderOntoFolder: @escaping ([URL], FileEntry, Bool) -> Void
) -> Bool {
    guard model.status == .ready, model.state.host != nil else { return false }
    let hasJSON = providers.contains {
        $0.hasItemConformingToTypeIdentifier(UTType.json.identifier)
    }
    let hasURLs = providers.contains {
        $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }
    guard hasJSON || hasURLs else { return false }
    // Same rule as the pane-level drop: copy by default, ⌘ moves.
    let moveHeld = NSEvent.modifierFlags.contains(.command)
    Task {
        let result = await resolveDropProviders(providers: providers, moveHeld: moveHeld)
        guard let result else { return }
        DispatchQueue.main.async {
            switch result {
            case .selection(let payload, let held):
                onSelectionOntoFolder(payload, folder, held)
            case .urls(let urls, let held):
                onFinderOntoFolder(urls, folder, held)
            }
        }
    }
    return true
}

// MARK: - Finder URL resolution

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
@MainActor
func routeFinderDrop(
    urls: [URL],
    targetPane: PaneModel,
    engine: Engine,
    operation: OperationModel,
    moveHeld: Bool,
    destinationDirectory: String? = nil
) {
    guard !urls.isEmpty else { return }
    // Group by parent path — keep the first parent's cohort.
    let grouped = Dictionary(grouping: urls) { url in
        url.deletingLastPathComponent().path
    }
    let sortedParents = grouped.keys.sorted()
    guard let firstParent = sortedParents.first else { return }
    let firstCohortURLs = grouped[firstParent] ?? []
    let droppedNames = Set(firstCohortURLs.map { $0.lastPathComponent })
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
            let cohort = entries.filter { droppedNames.contains($0.name) }
            guard !cohort.isEmpty else {
                operation.note("finder drop: no matching entries found in \(firstParent)")
                return
            }
            let sourceLocus = Locus(host: PalanaCore.localHostName, directory: firstParent)
            guard let destHost = targetPane.state.host, targetPane.status == .ready else {
                operation.note("finder drop: destination pane is not ready")
                return
            }
            let destinationLocus = Locus(
                host: destHost, directory: destinationDirectory ?? targetPane.state.path)
            operation.beginFromFinderDrop(
                planOperation,
                source: sourceLocus,
                destination: destinationLocus,
                entries: cohort
            )
        } catch {
            operation.note("finder drop: could not read \(firstParent) — \(error)")
        }
    }
}
