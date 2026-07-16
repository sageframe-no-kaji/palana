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

    /// Handles a ``DraggedSelection`` drop onto a **folder row** in `targetPane`
    /// (ho-14).
    ///
    /// Resolves the destination to the folder's full path — `targetPane`'s
    /// directory plus the folder's name — runs
    /// ``DropDecision/decideOntoFolder(payload:targetHost:folderPath:folderNameData:optionHeld:)``,
    /// and routes the outcome through the gather path with the folder as the
    /// destination directory. Self-drops (the folder is in the selection) and
    /// same-place drops refuse quietly.
    func handleSelectionDropOntoFolder(
        payload: DraggedSelection,
        targetPane: PaneModel,
        folder: FileEntry,
        optionHeld: Bool
    ) {
        guard let host = targetPane.state.host, targetPane.status == .ready else { return }
        let folderPath = PaneModel.childPath(of: targetPane.state.path, name: folder.name)
        let decision = DropDecision.decideOntoFolder(
            payload: payload,
            targetHost: host,
            folderPath: folderPath,
            folderNameData: folder.nameData,
            optionHeld: optionHeld
        )
        routeFolderDrop(
            decision,
            payload: payload,
            destination: Locus(host: host, directory: folderPath),
            sourcePanes: [left, right],
            operation: operation
        )
    }

    /// Handles a Finder URL drop onto a **folder row** in `targetPane` (ho-14
    /// review) — the files land inside the folder, not in the pane's cwd.
    func handleFinderDropOntoFolder(
        urls: [URL],
        targetPane: PaneModel,
        folder: FileEntry,
        optionHeld: Bool
    ) {
        let folderPath = PaneModel.childPath(of: targetPane.state.path, name: folder.name)
        routeFinderDrop(
            urls: urls,
            targetPane: targetPane,
            engine: sessionEngine,
            operation: operation,
            optionHeld: optionHeld,
            destinationDirectory: folderPath
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
