// Enactment validation for progressive rsync moves.

extension Transports {
    /// Refuses decoded or mutated plans whose source-removal command does
    /// not match the operation and accounting steps shown to the operator.
    static func validateProgressiveMovePlan(_ plan: Plan) throws {
        // Option tokens only: a path (always quoted) that merely contains
        // "remove-sent" is not an option (review 2026-11-15, finding 6).
        let removesSourceFiles = plan.steps.contains(where: Self.removesSourceFiles)
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

    /// Runs a progressive move's leftover-source report after its
    /// transfer failed or was cancelled, so the operator learns which
    /// sources remain (review 2026-11-15, finding 7).
    ///
    /// The transfer may have removed some sources and not others; the
    /// report is the plan's own last step, shown to the operator, and it
    /// only reads. The empty-directory sweep never runs here: it could
    /// remove directories whose files never landed. The report runs in
    /// a task of its own because a cancelled run stays cancelled, and
    /// its events are emitted once it ends. Its own failure is the
    /// expected outcome — sources remain — and never replaces the
    /// transfer's error, which the caller raises next.
    static func reportRetainedSources(
        _ plan: Plan,
        failedStep: PlanStep,
        conduit: any Conduit,
        emit: @Sendable (EnactmentEvent) -> Void
    ) async {
        guard plan.usesProgressiveRsyncMove,
            Self.removesSourceFiles(failedStep),
            let index = plan.steps.indices.last,
            plan.steps[index].role == .verify,
            case .host(let host) = plan.steps[index].runsOn
        else { return }
        let report = plan.steps[index]
        let reading = Task { try await conduit.run(on: host, report.command).collect() }
        guard let result = try? await reading.value else { return }
        emit(.stepBegan(index: index, step: report))
        if !result.stderr.isEmpty {
            emit(.outputChunk(stepIndex: index, channel: .stderr, data: result.stderr))
        }
        emit(.stepEnded(index: index, exitStatus: result.exitStatus))
        var scanner = RecoveryNoteScanner(host: host)
        scanner.consume(result.stderr)
        scanner.finish()
        for note in scanner.notes {
            emit(.recovery(note))
        }
    }

    /// Whether a step carries an rsync source-removal option token.
    static func removesSourceFiles(_ step: PlanStep) -> Bool {
        step.command.split(whereSeparator: \.isWhitespace)
            .contains { PlanEngine.namesSourceRemoval(String($0)) }
    }
}
