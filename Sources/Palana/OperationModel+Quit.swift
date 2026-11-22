// OperationModel+Quit — the quit path's stop, extracted to keep
// OperationModel.swift within its length budget (review 2026-11-18, F05).

import PalanaCore

extension OperationModel {
    /// The quit path's stop: every operation this model owns ends before
    /// the record is closed.
    ///
    /// A gather or snapshot read in flight is cancelled and awaited. A
    /// running enactment is stopped exactly as ⌃C stops it — its process
    /// group signalled, its exit awaited, its recovery notes received —
    /// and the record says the quit stopped it. A local command runs in
    /// its own process group with nothing tying it to this app, and
    /// closing the ssh masters cannot reach it: before this, quitting
    /// mid-copy left the copy running after the app was gone (review
    /// 2026-11-18, F05).
    ///
    /// The model is marked closing first and stays closing: a queued
    /// upload or a late callback that arrives while the current run is
    /// being stopped, or after, can no longer start another (pass 2).
    func stopOwnedWork() async {
        isClosing = true
        let gather = gatherTask
        gatherTask = nil
        gather?.cancel()
        let context = snapshotContextTask
        snapshotContextTask = nil
        context?.cancel()
        await gather?.value
        await context?.value
        guard phase == .enacting, let task = enactTask else { return }
        enactmentStopping = true
        task.cancel()
        await task.value
        guard phase == .enacting else { return }  // it finished or failed on its own first
        enactmentStopping = false
        echo.flushAll()
        echo.appendLine("quit — the running command was stopped before it finished", kind: .failure)
        log.appendLine(
            "! quit — the run was stopped before it finished; an interrupted transfer can leave partial entries")
        sealRecord()
        progress = nil
        phase = .cancelled
    }

    /// Cancels a pending quit the instant something fails or is stopped.
    ///
    /// Called from the phase observer, so no queued upload can start —
    /// and replace the failure — before the quit hears of it; the quit
    /// watch's periodic look could miss a failure that came and went
    /// between looks (review Q01).
    func interruptPendingQuit() {
        guard quitPending else { return }
        quitPending = false
        holdsUploadsForFailure = true
        let reason = phase == .failed ? "something failed" : "the run was stopped"
        echo.appendLine("quit cancelled — \(reason), so pālana stays open", kind: .note)
        panelShowing = true
    }

    /// The panel's work is being replaced by a new operation.
    ///
    /// The failure it showed is moved on from, and an upload that was
    /// waiting is no longer this panel's work (review Q03). Every real
    /// replacement passes through here: naming and gathering through the
    /// phase observer, Touch directly, because it composes straight to
    /// `.ready` (Q03, pass 4). An upload sets its own flag again right
    /// after entering `.gathering`. A command with nothing to act on
    /// returns before reaching this, so it leaves the panel's work, and
    /// its identity, as they were.
    func displacePanelWork() {
        holdsUploadsForFailure = false
        roundTripUploadActive = false
    }

    /// The phase observer's quit and upload bookkeeping.
    ///
    /// An upload's work ends with its operation — sent, failed, stopped or
    /// dismissed (review Q02). A failure or stop cancels a pending quit
    /// at once (Q01). Naming or gathering means a new plan is replacing
    /// whatever the panel held.
    func trackUploadAndQuit() {
        switch phase {
        case .idle, .finished, .failed, .cancelled:
            roundTripUploadActive = false
        case .naming, .gathering:
            displacePanelWork()
        case .ready, .enacting:
            break
        }
        if phase == .failed || phase == .cancelled { interruptPendingQuit() }
    }
}
