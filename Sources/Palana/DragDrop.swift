// Drag-and-drop wiring for the Surface: Transferable conformance for
// DraggedSelection, Finder-URL-drop resolution helpers, and the glue
// that routes a DropDecision through the standing begin/gather path.
// PaneView's diff stays thin — all non-trivial logic lives here.

import AppKit
import PalanaCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom content type

extension UTType {
    /// The custom pasteboard type for a ``DraggedSelection`` payload.
    ///
    /// Exported by the app and used to distinguish pālana-internal drags
    /// from Finder URL drops. Declared plain here — no bundle identifier
    /// needed; the string is the type identity.
    static let draggedSelection = UTType(exportedAs: "com.sageframe.palana.selection")
}

// MARK: - Transferable conformance

/// Retroactive conformance to `Transferable` — declared in the app target,
/// not in PalanaCore, per Decision 1 and ho-07's same-package finding.
extension DraggedSelection: Transferable {
    /// The representation uses the custom UTType and Codable serialisation.
    ///
    /// JSON is the wire format: ``DraggedSelection`` is `Codable`, and
    /// `JSONEncoder` base64-encodes the `names` byte arrays losslessly.
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .draggedSelection)
    }
}

// MARK: - Drop routing

/// Routes a resolved ``DropDecision`` through the standing `begin`/gather
/// path, exactly as `y`/`m` do via the keyboard.
///
/// Refusal notes are emitted through `operation.note` — one transcript line
/// per refuse, none for empty.
///
/// - Parameters:
///   - decision: The outcome of ``DropDecision/decide(payload:targetHost:targetDirectory:optionHeld:)``.
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
///   - optionHeld: Whether Option was held at drop time.
@MainActor
func routeFinderDrop(
    urls: [URL],
    targetPane: PaneModel,
    engine: Engine,
    operation: OperationModel,
    optionHeld: Bool
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
    let planOperation: PlanOperation = optionHeld ? .move : .copy
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
            let destinationLocus = Locus(host: destHost, directory: targetPane.state.path)
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
