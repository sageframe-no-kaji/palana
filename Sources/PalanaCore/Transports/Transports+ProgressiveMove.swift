// Enactment validation for progressive rsync moves.

extension Transports {
    /// Refuses decoded or mutated plans whose source-removal command does
    /// not match the operation and accounting steps shown to the operator.
    static func validateProgressiveMovePlan(_ plan: Plan) throws {
        // Option tokens only: a path (always quoted) that merely contains
        // "remove-sent" is not an option (review 2026-11-15, finding 6).
        let removesSourceFiles = plan.steps.contains { step in
            step.command.split(whereSeparator: \.isWhitespace)
                .contains { PlanEngine.namesSourceRemoval(String($0)) }
        }
        if removesSourceFiles, !plan.usesProgressiveRsyncMove {
            throw EnactmentError.malformedPlan(
                "source-removing rsync options belong only to a progressive move")
        }
        guard plan.usesProgressiveRsyncMove else { return }

        let request = PlanRequest(
            operation: .move,
            source: plan.source,
            entries: plan.entries,
            destination: plan.destination)
        let release = PlanEngine.sourceReleaseSteps(request, on: plan.source.host)
        let placeGuard = plan.transport == .local ? PlanEngine.progressivePlaceGuard(request) : []
        let transferRole: PlanStep.Role = plan.transport == .local ? .copy : .transfer
        let body = Array(plan.steps.dropFirst(placeGuard.count))
        guard removesSourceFiles,
            Array(plan.steps.prefix(placeGuard.count)) == placeGuard,
            body.count == release.count + 1,
            body.first?.role == transferRole,
            Array(body.dropFirst()) == release
        else {
            throw EnactmentError.malformedPlan(
                "the progressive move does not match its source-removal contract")
        }
    }
}
