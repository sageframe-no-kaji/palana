// OperationModel+RenameCommit — the operator's way past a destination
// with no hard links. The link commit refuses there with nothing
// replaced; the panel then offers the same send-back committed by
// rename, which the operator must choose, because a rename cannot
// refuse atomically the way `ln` does.

import Foundation
import PalanaCore

extension OperationModel {
    /// The rename version of a send-back whose link commit refused for
    /// want of hard links, or nil for any other failure.
    static func renameCommitOffer(for plan: Plan?, after error: any Error) -> Plan? {
        guard let plan,
            case EnactmentError.stepFailed(let index, let status, _) = error,
            status == RemoteVersionGuard.noHardLinkExitStatus,
            plan.steps.indices.contains(index),
            plan.steps[index].role == .promote
        else { return nil }
        return plan.renameCommitted()
    }

    /// What the panel says beside the offer.
    static let renameCommitExplanation =
        "this destination cannot make hard links, so the safe replace refused and nothing changed"
        + " · replacing by rename works here, but if another program writes this same file"
        + " in that instant, its write can be lost"

    /// The operator chose the rename commit: the same send-back runs again with it.
    ///
    /// Only a round-trip upload carries the commit step an offer is made
    /// from, so the retry is that upload — a save going back — and a
    /// pending quit lets it run and waits for it. Whether it may run is
    /// settled before the panel changes: during shutdown nothing starts,
    /// and nothing is left at `.ready` that no one may enact (review Q03,
    /// pass 5).
    func acceptRenameCommit() {
        guard !isClosing, phase == .failed, let offer = renameCommitOffer else { return }
        plan = offer
        readyCallout = nil
        echo.appendLine("replacing without the safe check — the commit renames", kind: .note)
        phase = .ready
        roundTripUploadActive = true
        enact()
    }
}
