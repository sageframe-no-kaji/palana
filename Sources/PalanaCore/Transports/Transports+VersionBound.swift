// What a version-bound send-back leaves when its transfer fails.

extension Transports {
    /// Names the staging directory a version-bound send-back leaves
    /// when a step between its stage and its commit fails or is
    /// cancelled (review 2026-11-15, finding 13).
    ///
    /// The commit is the only step that clears staging, so a transfer
    /// that stops first leaves `palana-send-<token>/`, perhaps with a
    /// partial file, in the operator's directory. Nothing runs to
    /// remove it — a removal would be a command the plan never showed —
    /// so the run says where it is. A failed stage step made nothing,
    /// and a failed commit names its own leftovers.
    static func reportStagingLeft(
        _ plan: Plan, failedIndex: Int, emit: @Sendable (EnactmentEvent) -> Void
    ) {
        guard let versionGuard = plan.versionGuard,
            let destination = plan.destination,
            let stage = plan.steps.firstIndex(where: { $0.role == .stage }),
            let promote = plan.steps.firstIndex(where: { $0.role == .promote }),
            stage < failedIndex, failedIndex < promote
        else { return }
        let staging = RemoteVersionGuard.stagingDirectory(
            in: destination.directory, token: versionGuard.token)
        emit(
            .recovery(
                RecoveryNote(
                    kind: .retained,
                    host: destination.host,
                    detail: "\(destination.host):\(staging) — the send did not finish"
                        + ", so its staging directory and any partial copy in it are kept here")))
    }
}
