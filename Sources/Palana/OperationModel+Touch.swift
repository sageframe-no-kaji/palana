// OperationModel+Touch — extracted from OperationModel.swift to keep
// that file within the 500-line budget.

import PalanaCore

extension OperationModel {
    /// t: opens the panel and composes a touch plan immediately — no
    /// gathering, no naming. touch needs no facts: it stays in place
    /// and the exit status is its verification.
    ///
    /// Subjects follow the same law as the other verbs — the selection
    /// when non-empty, else the cursor entry. Phase law mirrors `begin`.
    func beginTouch(source: PaneModel) {
        if phase == .enacting {
            panelShowing = true
            return
        }
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        if phase == .naming { reset() }
        guard let sourceHost = source.state.host, source.status == .ready else { return }
        let subjects = source.operationSubjects
        guard !subjects.isEmpty else { return }
        panelShowing = true
        requested = .touch
        echo = EchoBuffer()
        progress = nil
        plan = nil
        resultName = nil
        let request = PlanRequest(
            operation: .touch,
            source: Locus(host: sourceHost, directory: source.state.path),
            entries: subjects,
            token: Self.mintToken())
        do {
            plan = try PlanEngine.plan(request, facts: PlanFacts())
            phase = .ready
        } catch {
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
        }
    }
}
