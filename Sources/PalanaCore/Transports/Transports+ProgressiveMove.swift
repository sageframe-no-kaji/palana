// Enactment validation for progressive rsync moves.

extension Transports {
    /// Refuses decoded or mutated plans whose source-removal command does
    /// not match the operation and accounting steps shown to the operator.
    static func validateProgressiveMovePlan(_ plan: Plan) throws {
        let removesSourceFiles = plan.steps.contains {
            let command = $0.command.lowercased()
            return command.contains("remove-source") || command.contains("remove-sent")
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
        let transferRole: PlanStep.Role = plan.transport == .local ? .copy : .transfer
        guard removesSourceFiles,
            plan.steps.count == release.count + 1,
            plan.steps.first?.role == transferRole,
            Array(plan.steps.dropFirst()) == release
        else {
            throw EnactmentError.malformedPlan(
                "the progressive move does not match its source-removal contract")
        }
    }
}
