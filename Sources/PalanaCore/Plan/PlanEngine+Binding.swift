// Binding — the two places a composed plan is wrapped so that what it
// destroys is exactly what it proved.
//
// A send-back stages its bytes beside the destination and commits
// against the version it was bound to. A ZFS transfer binds cleanup to
// the dataset created by its receive. Generic POSIX copy-then-delete
// moves are refused because they cannot establish an equivalent atomic
// release boundary.

import Foundation

extension PlanEngine {
    /// The composed steps, wrapped by whichever binding the request carries.
    static func composeBound(
        _ request: PlanRequest,
        facts: PlanFacts,
        classification: Classification,
        transport: Transport
    ) throws -> [PlanStep] {
        if let versionGuard = request.versionGuard {
            guard let destination = request.destination, let entry = request.entries.first else {
                return try composeTransport(
                    request,
                    facts: facts,
                    classification: classification,
                    transport: transport)
            }
            return try composeVersionBound(
                request,
                route: Route(facts: facts, classification: classification, transport: transport),
                versionGuard: versionGuard,
                destination: destination,
                name: entry.name)
        }
        return try composeTransport(
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
    ) throws -> [PlanStep] {
        let staging = RemoteVersionGuard.stagingDirectory(
            in: destination.directory, token: request.token)
        var staged = request
        staged.destination = Locus(host: destination.host, directory: staging)
        staged.versionGuard = nil
        let transfer = try composeTransport(
            staged,
            facts: route.facts,
            classification: route.classification,
            transport: route.transport)
        let host = Runner.host(destination.host)
        return [PlanStep(runsOn: host, command: "mkdir -- \(ShellQuote.quote(staging))", role: .stage)]
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
        guard versionGuard.token == request.token else {
            throw PlanError.versionGuardUnbindable(
                "the guard and upload name different operation identities")
        }
        guard Self.validOperationToken(versionGuard.token) else {
            throw PlanError.versionGuardUnbindable("the operation identity is not a safe bare name")
        }
        let digestMalformed =
            versionGuard.expectedDigest.map { digest in
                digest.count != 64
                    || !digest.allSatisfy { character in
                        character.isHexDigit && !character.isUppercase
                    }
            } ?? false
        if digestMalformed {
            throw PlanError.versionGuardUnbindable("the expected SHA-256 digest is malformed")
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

    /// Operation identities become bare filesystem names and must never
    /// carry separators, shell whitespace, or relative-path components.
    static func validOperationToken(_ token: String) -> Bool {
        !token.isEmpty
            && token.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
    }

    /// Binds a successful receive to the only cleanup commands it may release.
    static func zfsReleaseGuard(
        request: PlanRequest,
        facts: PlanFacts,
        transport: Transport
    ) -> ZFSReleaseGuard? {
        guard
            transport == .zfsSendReceiveForwarded || transport == .zfsSendReceiveProxied,
            let source = facts.selectionWholeDataset,
            let destination = request.destination,
            let received = zfsChild(request: request, facts: facts, transport: transport)
        else { return nil }
        return ZFSReleaseGuard(
            sourceHost: request.source.host,
            destinationHost: destination.host,
            sourceDataset: source.name,
            receivedDataset: received,
            token: request.token,
            deletesSource: request.operation == .move)
    }
}
