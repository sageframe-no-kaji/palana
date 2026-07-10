// The session's drag-and-drop entry points (ho-9.6) — extracted from
// PalanaSession.swift to keep it within the line-length budget.
// Nothing enacts on a drop; the panel is the gate.

import Foundation
import PalanaCore

// MARK: - Drag and drop

extension PalanaSession {
    /// Handles a ``DraggedSelection`` drop onto `targetPane`.
    ///
    /// Resolves the source pane by host and directory from the live session
    /// panes, runs ``DropDecision/decide(payload:targetHost:targetDirectory:optionHeld:)``,
    /// and routes the outcome through the standing `begin`/gather path — the
    /// same path `y`/`m` follow from the keyboard. Nothing enacts on the drop;
    /// the panel arrives gathering→ready, and Enter is the gate.
    func handleSelectionDrop(
        payload: DraggedSelection,
        targetPane: PaneModel,
        optionHeld: Bool
    ) {
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: targetPane.state.host ?? "",
            targetDirectory: targetPane.state.path,
            optionHeld: optionHeld
        )
        routeDropDecision(
            decision,
            payload: payload,
            targetPane: targetPane,
            sourcePanes: [left, right],
            operation: operation
        )
    }

    /// Handles a Finder URL drop onto `targetPane`.
    ///
    /// Queries the local listing for the dropped URLs' parent directory,
    /// filters to the dropped names, and routes through the gather path
    /// exactly as a ``DraggedSelection`` drop does. Nothing enacts; the
    /// panel is the gate.
    func handleFinderDrop(urls: [URL], targetPane: PaneModel, optionHeld: Bool) {
        routeFinderDrop(
            urls: urls,
            targetPane: targetPane,
            engine: sessionEngine,
            operation: operation,
            optionHeld: optionHeld
        )
    }
}
