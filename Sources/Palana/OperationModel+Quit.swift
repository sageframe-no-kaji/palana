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
}
