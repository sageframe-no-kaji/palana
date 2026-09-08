// Binding — where a composed plan is wrapped so that what it destroys is
// exactly what it proved.
//
// A send-back stages its bytes beside the destination and commits
// against the version it was bound to. The wrap goes around the
// transport's own steps rather than replacing them: the bytes still
// travel the way the transport says they do.

import Foundation

extension PlanEngine {
    /// The composed steps, wrapped by whichever binding the request carries.
    static func composeBound(
        _ request: PlanRequest,
        facts: PlanFacts,
        classification: Classification,
        transport: Transport
    ) -> [PlanStep] {
        let guarded = request.versionGuard.flatMap { versionGuard in
            request.destination.flatMap { destination in
                request.entries.first.map { entry in
                    composeVersionBound(
                        request,
                        route: Route(
                            facts: facts, classification: classification, transport: transport),
                        versionGuard: versionGuard,
                        destination: destination,
                        name: entry.name)
                }
            }
        }
        if let guarded { return guarded }
        return composeTransport(
            request,
            facts: facts,
            classification: classification,
            transport: transport)
    }

    /// How the bytes were routed — the three values every compose needs,
    /// bundled so the bound composes stay inside the parameter budget.
    struct Route {
        /// The facts the plan composed over.
        var facts: PlanFacts
        /// What the operation actually is.
        var classification: Classification
        /// How the bytes move.
        var transport: Transport
    }

    /// Stage, transfer, commit — the send-back that never writes the
    /// destination path until it has proved what stands there.
    ///
    /// The transfer is the transport's own compose, aimed at a staging
    /// directory of this operation's own on the destination filesystem.
    /// Nothing touches the requested pathname until the commit step,
    /// which re-reads the destination and refuses unless it is still
    /// the exact version the guard names.
    private static func composeVersionBound(
        _ request: PlanRequest,
        route: Route,
        versionGuard: RemoteVersionGuard,
        destination: Locus,
        name: String
    ) -> [PlanStep] {
        let staging = RemoteVersionGuard.stagingDirectory(
            in: destination.directory, token: request.token)
        var staged = request
        staged.destination = Locus(host: destination.host, directory: staging)
        staged.versionGuard = nil
        let transfer = composeTransport(
            staged,
            facts: route.facts,
            classification: route.classification,
            transport: route.transport)
        let host = Runner.host(destination.host)
        return [
            PlanStep(runsOn: host, command: "mkdir -- \(ShellQuote.quote(staging))", role: .stage)
        ]
            + transfer
            + [
                PlanStep(
                    runsOn: host,
                    command: versionGuard.commitProgram(
                        directory: destination.directory, name: name),
                    role: .promote)
            ]
    }

    /// Refuses a version guard that does not name what the plan does.
    ///
    /// A guard is only a guard while it names the same host and the
    /// same byte-exact path the composed commit will touch. Anything
    /// looser would let the commit prove one file and replace another.
    static func validateVersionGuard(_ request: PlanRequest) throws {
        guard let versionGuard = request.versionGuard else { return }
        guard request.operation == .copy else {
            throw PlanError.versionGuardUnbindable("only a copy can be bound to a remote version")
        }
        guard request.entries.count == 1 else {
            throw PlanError.versionGuardUnbindable("a bound send-back carries exactly one entry")
        }
        guard let destination = request.destination, destination.host == versionGuard.host else {
            throw PlanError.versionGuardUnbindable(
                "the guard names \(versionGuard.host), the plan sends to "
                    + (request.destination?.host ?? "nowhere"))
        }
        let expected = RemoteIdentity.pathData(
            directory: destination.directory, name: request.entries[0].nameData)
        guard expected == versionGuard.pathData else {
            throw PlanError.versionGuardUnbindable(
                "the guard names a different path than the plan's destination")
        }
    }
}
