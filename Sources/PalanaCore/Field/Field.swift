// The Field — the topology, as an actor over the Conduit. Hosts come from
// the operator's ssh config, facts come from on-demand discovery, and the
// cache remembers the last visit. No polling loop exists to enable:
// discovery runs when asked and only then.

import Foundation

/// The topology component.
///
/// `hosts()` never touches the wire. `discover(_:)` is the only method
/// that does, and only when called. `facts(for:)` and
/// `datasetContaining(path:on:)` answer from memory.
public actor Field {
    private let conduit: any Conduit
    private let knownHosts: [String]
    private let cache: FieldCache
    private let now: @Sendable () -> Date
    private var memory: [String: HostFacts]
    /// How many wire reads this process has made — the generation the
    /// next one is stamped with.
    private var readCount = 0

    /// A field over an explicit host list.
    ///
    /// The clock is injectable so tests can pin timestamps.
    public init(
        conduit: any Conduit,
        hosts: [String],
        cache: FieldCache,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.conduit = conduit
        self.knownHosts = hosts
        self.cache = cache
        self.now = now
        self.memory = cache.load()
    }

    /// A field over parsed ssh config text.
    public init(
        conduit: any Conduit,
        sshConfigText: String,
        including resolve: (String) -> [String] = { _ in [] },
        cache: FieldCache,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            conduit: conduit,
            hosts: SSHConfigParser.hosts(in: sshConfigText, including: resolve),
            cache: cache,
            now: now
        )
    }

    /// The named hosts.
    ///
    /// Parsed once, never discovered — the config is the trust boundary
    /// and the wire is not consulted.
    public func hosts() -> [String] {
        knownHosts
    }

    /// What memory holds for a host — cache only, possibly stale, honest
    /// about when it was gathered.
    ///
    /// For showing. A plan that routes on topology, mounts, capability,
    /// or sudo asks ``refresh(_:)`` instead — memory never authorizes.
    public func facts(for host: String) -> HostFacts? {
        memory[host]
    }

    /// Which read of this process a host's remembered facts came from —
    /// nil for facts loaded from the cache, or a host never read.
    public func generation(of host: String) -> Int? {
        memory[host]?.generation
    }

    /// A snapshot of all remembered facts — memory only, no wire contact.
    ///
    /// Returns the full in-memory dictionary as it stands at call time. A
    /// field that has never run discovery answers `[:]`.
    public func allFacts() -> [String: HostFacts] {
        memory
    }

    /// Discovers a host — the capability probe, then the topology read
    /// when zfs is present, then the mount table, memory and cache updated after.
    ///
    /// The only method that touches the wire, and only when called.
    ///
    /// A door-level failure is a fact, not an error — it records as
    /// unreachable and earlier facts stay remembered, for showing. What
    /// does throw: ``ProbeParseError``, a reached host answering garbage.
    ///
    /// On a reached host every plan-critical group is rewritten by this
    /// visit: a topology or mount read that fails clears the group and
    /// records why, so an older list can never survive a failed read
    /// into a plan. The facts carry this read's generation.
    @discardableResult
    public func discover(_ host: String) async throws -> HostFacts {
        var facts = memory[host] ?? HostFacts()
        do {
            let probe = try await conduit.run(on: host, CapabilityProbe.command).collect()
            let capability = try CapabilityProbe.parse(probe.stdoutText)
            readCount += 1
            facts.generation = readCount
            facts.reachability = Dated(value: .reachable, discoveredAt: now())
            facts.capability = Dated(value: capability, discoveredAt: now())
            try await readTopology(into: &facts, host: host, capability: capability)
            try await readMounts(into: &facts, host: host, capability: capability)
            facts.sudoNoPassword = Dated(
                value: await Self.probeSudoNoPassword(conduit: conduit, host: host),
                discoveredAt: now()
            )
        } catch let error as ConduitError {
            facts.reachability = Dated(
                value: .unreachable(detail: Self.describe(error)),
                discoveredAt: now()
            )
        }
        memory[host] = facts
        // Cache write failure downgrades to memory-only, deliberately —
        // the cache is a convenience over re-derivable truth, and a full
        // disk must not turn discovery itself into a failure.
        try? cache.save(memory)
        return facts
    }

    /// The topology read — absent zfs and a failed read both clear the
    /// group; only the failure leaves a reason behind.
    private func readTopology(
        into facts: inout HostFacts, host: String, capability: HostCapability
    ) async throws {
        guard capability.zfs != nil else {
            facts.zfsTopology = nil
            facts.zfsTopologyUnavailable = nil
            return
        }
        let list = try await conduit.run(on: host, ZFSTopology.listCommand).collect()
        guard list.exitStatus == 0 else {
            facts.zfsTopology = nil
            facts.zfsTopologyUnavailable = Dated(
                value: Self.readFailure(list), discoveredAt: now())
            return
        }
        facts.zfsTopology = Dated(value: ZFSTopology.parse(list.stdoutText), discoveredAt: now())
        facts.zfsTopologyUnavailable = nil
    }

    /// The mount table read — a failed read clears the group and says why.
    private func readMounts(
        into facts: inout HostFacts, host: String, capability: HostCapability
    ) async throws {
        let mountsCmd = MountTable.command(forKernel: capability.kernel)
        let result = try await conduit.run(on: host, mountsCmd).collect()
        guard result.exitStatus == 0 else {
            facts.mounts = nil
            facts.mountsUnavailable = Dated(value: Self.readFailure(result), discoveredAt: now())
            return
        }
        let parsed =
            capability.kernel == "Linux"
            ? MountTable.parseLinux(result.stdoutText)
            : MountTable.parseBSD(result.stdoutText)
        facts.mounts = Dated(value: parsed, discoveredAt: now())
        facts.mountsUnavailable = nil
    }

    private static func readFailure(_ result: CommandResult) -> FactReadFailure {
        FactReadFailure(
            exitStatus: result.exitStatus,
            detail: ConduitError.summaryLine(of: result.stderrText))
    }

    /// Discovers a host for a plan — the same read as ``discover(_:)``,
    /// answered only when the host was reached.
    ///
    /// The plan-authorizing door. What comes back was read on the wire
    /// by this call, generation stamped, every plan-critical group either
    /// fresh or explicitly absent. A door failure throws
    /// ``FieldError/unreachable(host:detail:)`` rather than handing back
    /// the memory of an earlier visit.
    public func refresh(_ host: String) async throws -> HostFacts {
        let facts = try await discover(host)
        if case .unreachable(let detail) = facts.reachability?.value {
            throw FieldError.unreachable(host: host, detail: detail)
        }
        return facts
    }

    /// The snapshot names of one dataset, oldest first, short form — the
    /// part after `@`.
    ///
    /// An on-demand read that remembers nothing: snapshots change under
    /// every rollback and destroy, and a gather wants the list as it
    /// stands now. A nonzero exit reads as no snapshots; a door failure
    /// throws.
    public func snapshotNames(of dataset: String, on host: String) async throws -> [String] {
        let command =
            "zfs list -H -t snapshot -o name -s creation -- \(ShellQuote.quote(dataset))"
        let result = try await conduit.run(on: host, command).collect()
        guard result.exitStatus == 0 else { return [] }
        return result.stdoutText
            .split(separator: "\n")
            .compactMap { line in
                guard let at = line.firstIndex(of: "@") else { return nil }
                return String(line[line.index(after: at)...])
            }
    }

    /// Which dataset contains this path on this host — the Plan Engine's
    /// boundary question, answered from cached topology.
    public func datasetContaining(path: String, on host: String) -> ZFSDataset? {
        guard let topology = memory[host]?.zfsTopology else { return nil }
        return ZFSTopology.datasetContaining(path, in: topology.value)
    }

    // MARK: - Forwarding

    /// The probe command: can this host reach the alias with the
    /// operator's forwarded agent, batch-mode, five-second door.
    ///
    /// It asks exactly what a composed transfer will ask — the alias
    /// resolves in the source host's own ssh config AND the auth rides.
    /// The verdict travels on stdout and the command exits 0 either
    /// way, so ssh's own 255 stays unambiguous: a 255 here is the door
    /// to the source failing, not the source failing to reach onward.
    static func forwardingProbeCommand(to destination: String) -> String {
        let hop = ShellQuote.quote(destination)
        return "ssh -o BatchMode=yes -o ConnectTimeout=5 \(hop) true 2>/dev/null"
            + " && echo forwarded || echo blocked"
    }

    /// Whether `source` can reach `destination` — memory first, one
    /// probe round trip when unprobed, remembered after.
    ///
    /// A door failure toward the source is not a forwarding fact: the
    /// answer is `.unprobed`, nothing is recorded, and the plan takes
    /// the proxy path, the conservative truth.
    public func forwardingFact(from source: String, to destination: String) async -> ForwardingFact {
        if let remembered = memory[source]?.forwarding?[destination] {
            return remembered.value
        }
        let fact: ForwardingFact
        do {
            let command = Self.forwardingProbeCommand(to: destination)
            let result = try await conduit.run(on: source, command).collect()
            let verdict = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.exitStatus == 0, verdict == "forwarded" || verdict == "blocked" else {
                return .unprobed
            }
            fact = verdict == "forwarded" ? .available : .unavailable
        } catch {
            return .unprobed
        }
        var facts = memory[source] ?? HostFacts()
        var forwarding = facts.forwarding ?? [:]
        forwarding[destination] = Dated(value: fact, discoveredAt: now())
        facts.forwarding = forwarding
        memory[source] = facts
        try? cache.save(memory)
        return fact
    }

    /// Probes passwordless sudo — blanket or scoped to the zfs verbs.
    ///
    /// One round trip, two questions chained: `sudo -n true` detects a
    /// blanket grant; when that fails, `sudo -n -l zfs mount` asks
    /// whether the SCOPED grant exists (a sudoers line naming only
    /// `zfs mount *`/`zfs unmount *` — the recommended posture — makes
    /// `true` refuse while the zfs verbs are allowed). `-l` only asks,
    /// runs nothing. Exit 0 from either grants. Never throws: any
    /// failure of this round trip reads as `false` rather than
    /// aborting the rest of discovery.
    private static func probeSudoNoPassword(conduit: any Conduit, host: String) async -> Bool {
        do {
            let probe = "sudo -n true 2>/dev/null || sudo -n -l zfs mount"
            let result = try await conduit.run(on: host, probe).collect()
            return result.exitStatus == 0
        } catch {
            return false
        }
    }

    /// A short human line for the unreachable fact's detail.
    static func describe(_ error: ConduitError) -> String {
        switch error {
        case .launchFailed(let detail):
            "ssh could not launch: \(detail)"
        case .hostUnreachable(let detail):
            "unreachable: \(detail)"
        case .authenticationDenied(let detail):
            "authentication denied: \(detail)"
        case .hostKeyVerificationFailed(let detail):
            "host key verification failed: \(detail)"
        case .connectionLost(let detail):
            "connection lost: \(detail)"
        case .sshFailure(let status, let stderr):
            "ssh failed (\(status)): \(ConduitError.summaryLine(of: stderr))"
        }
    }
}

/// Why a plan-authorizing read could not answer.
///
/// Distinct from the recorded ``Reachability`` fact: the fact is what
/// memory shows, the error is what a plan hears when it asked for fresh
/// truth and the door would not open.
public enum FieldError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The host could not be reached for the read; the detail names how.
    case unreachable(host: String, detail: String)

    /// One sentence, the panel's voice.
    public var description: String {
        switch self {
        case .unreachable(let host, let detail):
            "\(host) could not be read for this plan — \(detail)"
        }
    }
}
