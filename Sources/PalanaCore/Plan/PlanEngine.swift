// The Plan Engine — a pure function from gathered facts to a Plan. It
// performs no I/O, holds no Field, touches no wire. That purity makes
// it the most testable object in the system, and it had better be,
// because it is the part that must never lie.

import Foundation

/// Classification, transport selection, and command composition.
///
/// Facts in, Plan out. Refusal (``PlanError``) is the honest
/// alternative to a plan that lies.
public enum PlanEngine {
    /// Composes a Plan, or refuses with a typed reason.
    public static func plan(_ request: PlanRequest, facts: PlanFacts) throws -> Plan {
        try validate(request)
        let classification = classify(request, facts: facts)
        let transport = transport(for: classification, request: request, facts: facts)
        let steps = compose(
            request, facts: facts, classification: classification, transport: transport)
        let sizeFacts = totalSize(request.entries, facts: facts)
        return Plan(
            operation: request.operation,
            classification: classification,
            entries: request.entries,
            totalSize: sizeFacts.bytes,
            totalSizeComplete: sizeFacts.complete,
            source: request.source,
            destination: request.destination,
            transport: transport,
            steps: steps,
            receivedDataset: zfsChild(request: request, facts: facts, transport: transport)
        )
    }

    /// The selection's byte truth (ho-06.5): recursive facts for
    /// directories where gathered, reported sizes for files, inode
    /// size as the honest floor — and the floor is never silent.
    private static func totalSize(
        _ entries: [FileEntry], facts: PlanFacts
    ) -> RecursiveSize {
        var bytes: Int64 = 0
        var complete = true
        for entry in entries {
            if entry.kind == .directory {
                if let fact = facts.recursiveSizes[entry.id] {
                    bytes += fact.bytes
                    complete = complete && fact.complete
                } else {
                    bytes += entry.size
                    complete = false
                }
            } else {
                bytes += entry.size
            }
        }
        return RecursiveSize(bytes: bytes, complete: complete)
    }

    /// The dataset a zfs transport will create at the destination.
    private static func zfsChild(
        request: PlanRequest,
        facts: PlanFacts,
        transport: Transport
    ) -> String? {
        guard
            transport == .zfsSendReceiveForwarded || transport == .zfsSendReceiveProxied,
            let source = facts.selectionWholeDataset,
            let destination = facts.destinationDataset
        else { return nil }
        return "\(destination.name)/\(lastComponent(of: source.name))"
    }

    // MARK: - Validation

    private static func validate(_ request: PlanRequest) throws {
        switch request.operation {
        case .move, .copy:
            guard !request.entries.isEmpty else { throw PlanError.emptySelection }
            guard request.destination != nil else { throw PlanError.missingDestination }
        case .delete:
            guard !request.entries.isEmpty else { throw PlanError.emptySelection }
        case .rename:
            try validateRename(request)
        case .create:
            try validateCreate(request)
        }
        for entry in request.entries {
            guard String(data: entry.nameData, encoding: .utf8) != nil else {
                throw PlanError.unrepresentableName(entry.nameData)
            }
        }
    }

    private static func validateRename(_ request: PlanRequest) throws {
        guard request.destination == nil else { throw PlanError.destinationForbidden }
        guard request.entries.count == 1 else { throw PlanError.renameRequiresOneEntry }
        let name = request.targetName ?? ""
        guard !name.isEmpty else { throw PlanError.targetNameRequired }
        guard !name.contains("/") else { throw PlanError.targetNameContainsSeparator }
        guard name != request.entries[0].name else { throw PlanError.targetNameUnchanged }
    }

    private static func validateCreate(_ request: PlanRequest) throws {
        guard request.destination == nil else { throw PlanError.destinationForbidden }
        guard request.entries.isEmpty else { throw PlanError.entriesForbiddenForCreate }
        let name = request.targetName ?? ""
        guard !name.isEmpty else { throw PlanError.targetNameRequired }
        let stripped = name.hasSuffix("/") ? String(name.dropLast()) : name
        guard !stripped.isEmpty else { throw PlanError.targetNameRequired }
        guard !stripped.contains("/") else { throw PlanError.targetNameContainsSeparator }
    }

    // MARK: - Classification

    /// The total fact table.
    ///
    /// Unknown datasets classify conservatively: a rename is claimed
    /// only when both datasets are known and equal.
    static func classify(_ request: PlanRequest, facts: PlanFacts) -> Classification {
        switch request.operation {
        case .rename:
            return .withinDatasetRename
        case .create:
            return .creation
        case .delete:
            return .deletion
        case .move:
            let sameHost = request.source.host == request.destination?.host
            guard sameHost else { return .crossHostTransfer }
            return provenSameDataset(facts) ? .withinDatasetRename : .crossDatasetCopyPlusDelete
        case .copy:
            let sameHost = request.source.host == request.destination?.host
            return sameHost ? .withinHostCopy : .crossHostCopy
        }
    }

    private static func provenSameDataset(_ facts: PlanFacts) -> Bool {
        guard let source = facts.sourceDataset, let destination = facts.destinationDataset else {
            return false
        }
        return source.name == destination.name
    }

    // MARK: - Transport selection

    /// Selects how the bytes move.
    ///
    /// zfs when both ends are whole datasets, forwarded rsync when the
    /// fact says available, tar stream through the operator's machine
    /// otherwise — unprobed selects the proxy path, the conservative
    /// truth. This machine at either end runs rsync here directly: the
    /// operator's own agent authenticates, no forwarding exists to
    /// probe, and proxying through yourself to yourself is absurd.
    static func transport(
        for classification: Classification,
        request: PlanRequest,
        facts: PlanFacts
    ) -> Transport {
        switch classification {
        case .withinDatasetRename, .crossDatasetCopyPlusDelete, .withinHostCopy, .deletion,
            .creation:
            return .local
        case .crossHostTransfer, .crossHostCopy:
            let touchesThisMachine =
                request.source.host == PalanaCore.localHostName
                || request.destination?.host == PalanaCore.localHostName
            if touchesThisMachine {
                let pushing = request.source.host == PalanaCore.localHostName
                let remote = pushing ? facts.destinationCapability : facts.sourceCapability
                let local = pushing ? facts.sourceCapability : facts.destinationCapability
                // rsync from this machine asks for both binaries known.
                // An unknown local rsync could be modern (protects args
                // itself) or openrsync (refuses -s) — the composes are
                // incompatible, so unknown falls to tar, which always
                // speaks. The app probes this machine once per session.
                return remote?.rsync != nil && local?.rsync != nil
                    ? .rsyncDirect : .tarStreamDirect
            }
            let forwarded = facts.agentForwarding == .available
            if wholeDatasetGate(request: request, facts: facts) {
                return forwarded ? .zfsSendReceiveForwarded : .zfsSendReceiveProxied
            }
            // rsync asks for rsync on both ends and a sender modern
            // enough for progress2 — anything less falls to tar, which
            // every userland speaks.
            let rsyncViable =
                modernRsync(facts.sourceCapability) && facts.destinationCapability?.rsync != nil
            return forwarded && rsyncViable ? .rsyncAgentForwarded : .tarStreamProxied
        }
    }

    /// Real rsync, 3.1 or newer — the dotted version is the tell;
    /// openrsync's "protocol version 29" never parses one.
    static func modernRsync(_ capability: HostCapability?) -> Bool {
        guard let version = capability?.rsyncVersion else { return false }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 1)
    }

    /// Both ends whole datasets: the selection is exactly a dataset
    /// root, the destination directory is exactly a dataset mountpoint,
    /// and both hosts carry zfs.
    private static func wholeDatasetGate(request: PlanRequest, facts: PlanFacts) -> Bool {
        guard
            facts.selectionWholeDataset != nil,
            let destinationDataset = facts.destinationDataset,
            let destination = request.destination,
            facts.sourceCapability?.zfs != nil,
            facts.destinationCapability?.zfs != nil
        else { return false }
        return normalize(destination.directory) == normalize(destinationDataset.mountpoint)
    }
}

// MARK: - Composition

extension PlanEngine {
    private static func compose(
        _ request: PlanRequest,
        facts: PlanFacts,
        classification: Classification,
        transport: Transport
    ) -> [PlanStep] {
        switch transport {
        case .local:
            return composeLocal(request, facts: facts, classification: classification)
        case .rsyncAgentForwarded:
            return composeRsync(request, facts: facts)
        case .rsyncDirect:
            return composeRsyncDirect(request, facts: facts)
        case .tarStreamProxied:
            return composeTarStream(request)
        case .tarStreamDirect:
            return composeTarDirect(request)
        case .zfsSendReceiveForwarded:
            return composeZfs(request, facts: facts, forwarded: true)
        case .zfsSendReceiveProxied:
            return composeZfs(request, facts: facts, forwarded: false)
        }
    }

    /// The rsync flag set: archive, keep partials so an interrupted
    /// transfer resumes — `-s` and progress2 only when the running
    /// side's rsync is modern enough to speak them. openrsync refuses
    /// `-s` outright (CI found it live), so the floor protects remote
    /// paths by inner-quoting instead — see `composeRsyncDirect`.
    private static func rsyncFlags(runningOn capability: HostCapability?) -> String {
        Self.modernRsync(capability)
            ? "-a -s --partial --info=progress2"
            : "-a --partial"
    }

    private static func composeLocal(
        _ request: PlanRequest,
        facts: PlanFacts,
        classification: Classification
    ) -> [PlanStep] {
        let host = Runner.host(request.source.host)
        let sources = sourcePaths(request).map(ShellQuote.quote).joined(separator: " ")
        // A same-host copy rides rsync when the host carries it —
        // progress and resume where cp -a is opaque and starts over
        // (second hands session: "on a local machine you might want
        // that for a big copy"). cp -a stays the floor.
        let copyCommand: (String) -> String = { dest in
            facts.sourceCapability?.rsync != nil
                ? "rsync \(rsyncFlags(runningOn: facts.sourceCapability)) \(sources) \(dest)"
                : "cp -a \(sources) \(dest)"
        }
        switch classification {
        case .deletion:
            return [PlanStep(runsOn: host, command: "rm -rf \(sources)", role: .delete)]
        case .withinDatasetRename:
            if request.operation == .rename {
                return composeInPlaceRename(request)
            }
            let dest = quotedDestinationDirectory(request)
            return [PlanStep(runsOn: host, command: "mv \(sources) \(dest)", role: .rename)]
        case .crossDatasetCopyPlusDelete:
            let dest = quotedDestinationDirectory(request)
            return [
                PlanStep(runsOn: host, command: copyCommand(dest), role: .copy),
                PlanStep(
                    runsOn: host,
                    command: "rm -rf \(sources)",
                    role: .delete,
                    gatedOnVerification: true),
            ]
        case .withinHostCopy:
            let dest = quotedDestinationDirectory(request)
            return [PlanStep(runsOn: host, command: copyCommand(dest), role: .copy)]
        case .creation:
            return composeCreate(request)
        case .crossHostTransfer, .crossHostCopy:
            return []  // never local — the transport switch routes these away
        }
    }

    private static func composeRsync(_ request: PlanRequest, facts: PlanFacts) -> [PlanStep] {
        let sourceHost = Runner.host(request.source.host)
        let sources = sourcePaths(request).map(ShellQuote.quote).joined(separator: " ")
        let remote = ShellQuote.quote(
            "\(request.destination?.host ?? ""):\(destinationDirectorySlash(request))")
        var steps = [
            PlanStep(
                runsOn: sourceHost,
                command: "rsync \(rsyncFlags(runningOn: facts.sourceCapability)) \(sources) \(remote)",
                role: .transfer)
        ]
        if request.operation == .move {
            steps.append(
                PlanStep(
                    runsOn: sourceHost,
                    command: "rm -rf \(sources)",
                    role: .delete,
                    gatedOnVerification: true))
        }
        return steps
    }

    /// Composes the rsync-from-this-machine steps.
    ///
    /// Pushing when the selection lives here, pulling when it lives on
    /// the remote. The gated delete runs wherever the source is, routed
    /// like any other host step. The flags follow this machine's own
    /// rsync — an openrsync Mac still transfers, without progress2.
    private static func composeRsyncDirect(_ request: PlanRequest, facts: PlanFacts) -> [PlanStep] {
        let here = Runner.host(PalanaCore.localHostName)
        let pushing = request.source.host == PalanaCore.localHostName
        let localCapability = pushing ? facts.sourceCapability : facts.destinationCapability
        // A modern rsync carries -s and remote paths ride the protocol
        // literally. The floor has no -s, so the remote shell sees the
        // path — an inner quote keeps its spaces whole.
        let modernHere = Self.modernRsync(localCapability)
        let remotePath: (String) -> String = { modernHere ? $0 : ShellQuote.quote($0) }
        let sources: String
        let target: String
        if pushing {
            sources = sourcePaths(request).map(ShellQuote.quote).joined(separator: " ")
            target = ShellQuote.quote(
                "\(request.destination?.host ?? ""):\(remotePath(destinationDirectorySlash(request)))")
        } else {
            sources = sourcePaths(request)
                .map { ShellQuote.quote("\(request.source.host):\(remotePath($0))") }
                .joined(separator: " ")
            target = quotedDestinationDirectory(request)
        }
        var steps = [
            PlanStep(
                runsOn: here,
                command: "rsync \(rsyncFlags(runningOn: localCapability)) \(sources) \(target)",
                role: .transfer)
        ]
        if request.operation == .move {
            let removed = sourcePaths(request).map(ShellQuote.quote).joined(separator: " ")
            steps.append(
                PlanStep(
                    runsOn: .host(request.source.host),
                    command: "rm -rf \(removed)",
                    role: .delete,
                    gatedOnVerification: true))
        }
        return steps
    }

    /// Composes the tar-from-this-machine steps — the remote end has no
    /// rsync, so one pipe runs here and ssh carries the other half.
    ///
    /// No proxy in the name because there is none: with this machine at
    /// one end, the bytes were coming through here anyway.
    private static func composeTarDirect(_ request: PlanRequest) -> [PlanStep] {
        let pushing = request.source.host == PalanaCore.localHostName
        let names = request.entries.map { ShellQuote.quote($0.name) }.joined(separator: " ")
        let pack = "tar -cf - -C \(ShellQuote.quote(request.source.directory)) -- \(names)"
        let unpack = "tar -xpf - -C \(ShellQuote.quote(request.destination?.directory ?? ""))"
        let command =
            pushing
            ? "\(pack) | ssh \(request.destination?.host ?? "") \(ShellQuote.quote(unpack))"
            : "ssh \(request.source.host) \(ShellQuote.quote(pack)) | \(unpack)"
        var steps = [
            PlanStep(
                runsOn: .host(PalanaCore.localHostName),
                command: command,
                role: .transfer)
        ]
        if request.operation == .move {
            let removed = sourcePaths(request).map(ShellQuote.quote).joined(separator: " ")
            steps.append(
                PlanStep(
                    runsOn: .host(request.source.host),
                    command: "rm -rf \(removed)",
                    role: .delete,
                    gatedOnVerification: true))
        }
        return steps
    }

    private static func composeTarStream(_ request: PlanRequest) -> [PlanStep] {
        let names = request.entries.map { ShellQuote.quote($0.name) }.joined(separator: " ")
        let pack = "tar -cf - -C \(ShellQuote.quote(request.source.directory)) -- \(names)"
        let unpack = "tar -xpf - -C \(ShellQuote.quote(request.destination?.directory ?? ""))"
        let destinationHost = request.destination?.host ?? ""
        var steps = [
            PlanStep(
                runsOn: .operatorMachine,
                command: "ssh \(request.source.host) \(ShellQuote.quote(pack)) | "
                    + "ssh \(destinationHost) \(ShellQuote.quote(unpack))",
                role: .transfer,
                pipeline: Pipeline(
                    fromHost: request.source.host,
                    fromCommand: pack,
                    toHost: destinationHost,
                    toCommand: unpack))
        ]
        if request.operation == .move {
            let sources = sourcePaths(request).map(ShellQuote.quote).joined(separator: " ")
            steps.append(
                PlanStep(
                    runsOn: .host(request.source.host),
                    command: "rm -rf \(sources)",
                    role: .delete,
                    gatedOnVerification: true))
        }
        return steps
    }

    private static func composeZfs(
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
                    command: "\(send) | ssh \(destinationHost) \(ShellQuote.quote(receive))",
                    role: .transfer))
        } else {
            steps.append(
                PlanStep(
                    runsOn: .operatorMachine,
                    command: "ssh \(request.source.host) \(ShellQuote.quote(send)) | "
                        + "ssh \(destinationHost) \(ShellQuote.quote(receive))",
                    role: .transfer,
                    pipeline: Pipeline(
                        fromHost: request.source.host,
                        fromCommand: send,
                        toHost: destinationHost,
                        toCommand: receive)))
        }
        steps.append(
            PlanStep(
                runsOn: .host(destinationHost),
                command: "zfs destroy -r \(ShellQuote.quote("\(child)@\(request.token)"))",
                role: .cleanup,
                gatedOnVerification: true))
        if request.operation == .move {
            steps.append(
                PlanStep(
                    runsOn: sourceHost,
                    command: "zfs destroy -r \(ShellQuote.quote(sourceDataset.name))",
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

    private static func composeInPlaceRename(_ request: PlanRequest) -> [PlanStep] {
        let host = Runner.host(request.source.host)
        let entry = request.entries[0]
        let newName = request.targetName ?? ""
        let oldPath = ShellQuote.quote(join(request.source.directory, entry.name))
        let newPath = ShellQuote.quote(join(request.source.directory, newName))
        return [
            PlanStep(
                runsOn: host,
                command: "\(refusalGuard(newPath)) mv -- \(oldPath) \(newPath)",
                role: .rename),
            PlanStep(
                runsOn: host,
                command: "test -e \(newPath) && test ! -e \(oldPath)",
                role: .verify),
        ]
    }

    /// The guard that refuses an existing destination, legibly — the
    /// panel shows a sentence, not a bare exit 1 (third hands session).
    private static func refusalGuard(_ quotedPath: String) -> String {
        "test -e \(quotedPath) && { echo refused: \(quotedPath) exists >&2; exit 1; };"
    }

    private static func composeCreate(_ request: PlanRequest) -> [PlanStep] {
        let host = Runner.host(request.source.host)
        let nameRaw = request.targetName ?? ""
        let isDirectory = nameRaw.hasSuffix("/")
        let name = isDirectory ? String(nameRaw.dropLast()) : nameRaw
        let path = ShellQuote.quote(join(request.source.directory, name))
        guard isDirectory else {
            return [
                PlanStep(
                    runsOn: host,
                    command: "\(refusalGuard(path)) touch -- \(path)",
                    role: .create),
                PlanStep(runsOn: host, command: "test -f \(path)", role: .verify),
            ]
        }
        return [
            PlanStep(runsOn: host, command: "mkdir -- \(path)", role: .create),
            PlanStep(runsOn: host, command: "test -d \(path)", role: .verify),
        ]
    }

    // MARK: - Path helpers

    private static func sourcePaths(_ request: PlanRequest) -> [String] {
        request.entries.map { join(request.source.directory, $0.name) }
    }

    private static func quotedDestinationDirectory(_ request: PlanRequest) -> String {
        ShellQuote.quote(destinationDirectorySlash(request))
    }

    private static func destinationDirectorySlash(_ request: PlanRequest) -> String {
        let directory = normalize(request.destination?.directory ?? "")
        return directory == "/" ? "/" : directory + "/"
    }

    private static func join(_ directory: String, _ name: String) -> String {
        normalize(directory) == "/" ? "/\(name)" : "\(normalize(directory))/\(name)"
    }

    private static func normalize(_ path: String) -> String {
        guard path != "/" else { return "/" }
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func lastComponent(of datasetName: String) -> String {
        datasetName.split(separator: "/").last.map(String.init) ?? datasetName
    }
}
