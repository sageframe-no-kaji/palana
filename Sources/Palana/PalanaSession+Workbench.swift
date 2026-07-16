// PalanaSession+Workbench — running a Workbench verb against the
// focused host. Moved out of PalanaSession.swift for the file_length
// budget (ho-11 made room by relocating this self-contained extension,
// alongside the +ZFS, +RoundTrip, +DragDrop, +VerbKeys, and +Onboarding
// precedent).

import PalanaCore

extension PalanaSession {
    /// Runs a Workbench verb against the focused host.
    ///
    /// Read verbs: checks availability, starts the read, drains raw output into
    /// the transcript. Phase is never touched — a read is not an operation.
    ///
    /// Mutation verbs: resolves the target dataset from the focused pane's path,
    /// checks availability, then hands off to the operation gather.
    ///
    /// The read and mutation helpers live in `PalanaSession+ZFS.swift`.
    func runWorkbenchVerb(_ verb: WorkbenchVerb) {
        guard !operation.terminalBusy else { return }
        guard let host = focusedPane.state.host else {
            operation.appendToolError("point a pane at a host first")
            return
        }
        // Local honesty: zfs verbs are not applicable on this Mac.
        guard !(verb.requirement == .zfs && host == PalanaCore.localHostName) else { return }
        switch verb.kind {
        case .read:
            runWorkbenchRead(verb, on: host)
        case .mutation:
            runWorkbenchMutation(verb, on: host)
        }
    }
}
