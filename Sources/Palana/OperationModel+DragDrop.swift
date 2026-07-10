// The OperationModel entry point for Finder URL drops (ho-9.6). Kept in a
// separate file so OperationModel.swift stays within the line-length budget.
// The gather path is shared — phase law mirrors begin.

import Foundation
import PalanaCore

// MARK: - Finder drop entry point

extension OperationModel {
    /// Composes a plan from a Finder drop — entries already resolved from
    /// the local listing; no live source pane needed.
    ///
    /// Called by `routeFinderDrop` in `DragDrop.swift` after the local listing
    /// has been queried and the cohort has been filtered. Phase law is identical
    /// to `begin`: one enactment at a time; a gather in flight is cancelled and
    /// replaced; naming resets cleanly.
    func beginFromFinderDrop(
        _ planOperation: PlanOperation,
        source: Locus,
        destination: Locus,
        entries: [FileEntry]
    ) {
        if phase == .enacting {
            panelShowing = true
            return
        }
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        if phase == .naming { reset() }
        guard !entries.isEmpty else { return }
        requested = planOperation
        echo = EchoBuffer()
        progress = nil
        plan = nil
        resultName = nil
        phase = .gathering
        panelShowing = true
        gatherTask = Task { [weak self] in
            guard let self else { return }
            await self.gather(
                planOperation,
                source: source,
                destination: destination,
                subjects: entries
            )
        }
    }
}
