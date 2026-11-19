// PlanEngine+ZFSTransport — whole-dataset send/receive composition,
// extracted from PlanEngine.swift to keep it within its length budget when
// the move gained its fence and proof (owner ruling 2026-11-18, final
// review F03).

extension PlanEngine {
    static func composeZfs(
        _ request: PlanRequest,
        facts: PlanFacts,
        forwarded: Bool
    ) -> [PlanStep] {
        guard
            let sourceDataset = facts.selectionWholeDataset,
            let destinationDataset = facts.destinationDataset,
            let destinationHost = request.destination?.host
        else { return [] }
        let child = "\(destinationDataset.name)/\(lastComponent(of: sourceDataset.name))"
        let snapshot = "\(sourceDataset.name)@\(request.token)"
        // -v: send's stderr cadence is the forwarded path's progress.
        // -u: Linux mounting is root's alone regardless of delegation —
        // a bare receive lands the dataset and then fails the mount,
        // an exit code that lies about the transfer (ho-06.2).
        let send = "zfs send -R -v \(ShellQuote.quote(snapshot))"
        let receive = "zfs receive -u \(ShellQuote.quote(child))"
        let sourceHost = Runner.host(request.source.host)

        var steps = [
            PlanStep(
                runsOn: sourceHost,
                command: "zfs snapshot -r \(ShellQuote.quote(snapshot))",
                role: .snapshot)
        ]
        if forwarded {
            steps.append(
                PlanStep(
                    runsOn: sourceHost,
                    command:
                        "\(send) | ssh \(sshDestination(destinationHost)) \(ShellQuote.quote(receive))",
                    role: .transfer))
        } else {
            let pipeline = Pipeline(
                fromHost: request.source.host,
                fromCommand: send,
                toHost: destinationHost,
                toCommand: receive)
            steps.append(
                PlanStep(
                    runsOn: .operatorMachine,
                    command: pipelineCommand(pipeline),
                    role: .transfer,
                    pipeline: pipeline))
        }
        steps.append(
            PlanStep(
                runsOn: .host(destinationHost),
                command: "zfs destroy -r \(ShellQuote.quote("\(child)@\(request.token)"))",
                role: .cleanup,
                gatedOnVerification: true))
        return zfsSourceEnds(steps, request: request, sourceDataset: sourceDataset, snapshot: snapshot)
    }

    /// The source end of a whole-dataset transfer: a move fences before its
    /// snapshot and releases through the written proof; a copy only cleans
    /// up its snapshot.
    private static func zfsSourceEnds(
        _ composed: [PlanStep],
        request: PlanRequest,
        sourceDataset: ZFSDataset,
        snapshot: String
    ) -> [PlanStep] {
        var steps = composed
        let sourceHost = Runner.host(request.source.host)
        if request.operation == .move {
            // Fence and prove (owner ruling 2026-11-18, final review F03):
            // the tree is unmounted before its snapshot, and the source is
            // destroyed only if nothing was written to it since.
            steps.insert(
                PlanStep(
                    runsOn: sourceHost,
                    command: ZFSReleaseGuard.fenceCommand(host: request.source.host, dataset: sourceDataset.name),
                    role: .snapshot),
                at: 0)
            steps.append(
                PlanStep(
                    runsOn: sourceHost,
                    command: ZFSReleaseGuard.guardedSourceRelease(
                        host: request.source.host, dataset: sourceDataset.name, token: request.token),
                    role: .delete,
                    gatedOnVerification: true))
        } else {
            steps.append(
                PlanStep(
                    runsOn: sourceHost,
                    command: "zfs destroy -r \(ShellQuote.quote(snapshot))",
                    role: .cleanup,
                    gatedOnVerification: true))
        }
        return steps
    }
}
