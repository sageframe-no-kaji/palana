// OperationModel+Descriptions — the sentences the panel shows for a
// verification report and for a refused plan. Moved out of
// OperationModel.swift for the file-length budget, alongside the
// +Gather, +Collisions, and +LocalPlacement precedent.

import PalanaCore

extension OperationModel {
    static func describe(_ report: VerificationReport) -> String {
        switch report {
        case .manifests(let source, let destination):
            let checked =
                "checked \(source.entries.count) at source, \(destination.entries.count) at destination"
            if let name = source.firstUnmatched(in: destination) {
                return "\(checked) — DIFFERENT at \(name)"
            }
            guard !source.entries.isEmpty else { return "\(checked) — nothing to compare" }
            // The subset rule: a merge keeps what already stood at the
            // destination, and every source entry is proven beside it.
            let kept = destination.entries.count - source.entries.count
            return kept > 0
                ? "\(checked) — every source entry landed · \(kept) already there, kept"
                : "\(checked) — identical"
        case .datasetReceived(let name, let exists):
            return exists
                ? "dataset \(name) exists at the destination"
                : "dataset \(name) is MISSING at the destination"
        }
    }

    /// Translates PlanError cases to one-sentence descriptions, nil for non-PlanErrors.
    ///
    /// Split in two for the complexity budget: selection and destination
    /// refusals here, naming refusals in ``describeNamingPlanError(_:)``.
    static func describePlanError(_ error: any Error) -> String? {
        switch error {
        case PlanError.emptySelection:
            return "nothing selected — there is nothing to plan"
        case PlanError.missingDestination:
            return "the other pane is the destination — point it somewhere first"
        case PlanError.unrepresentableName:
            return "an entry's name does not survive composition — refusing rather than guessing"
        case PlanError.kindClash(let report):
            return report.clashSentence() ?? "won't work — kind mismatch at the destination"
        case PlanError.zfsPoolRootRefused:
            return "that is the pool root — pālana manages datasets, never the pool itself"
        case PlanError.zfsMountpointNotAbsolute:
            return "a mountpoint must be an absolute path — /like/this, not ~ or relative"
        default:
            return describeNamingPlanError(error)
        }
    }

    /// The rename and create refusals, nil for anything else.
    private static func describeNamingPlanError(_ error: any Error) -> String? {
        switch error {
        case PlanError.renameRequiresOneEntry:
            return "rename operates on one entry — cursor on exactly one"
        case PlanError.targetNameRequired:
            return "a name is required"
        case PlanError.targetNameUnchanged:
            return "the name did not change"
        case PlanError.targetNameContainsSeparator:
            return "a name cannot contain path separators"
        case PlanError.entriesForbiddenForCreate:
            return "create needs an empty selection — deselect first"
        case PlanError.destinationForbidden:
            return "rename and create stay in the source directory — no destination"
        default:
            return nil
        }
    }
}
