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
    public func facts(for host: String) -> HostFacts? {
        memory[host]
    }

    /// Discovers a host — the capability probe, then the topology read
    /// when zfs is present, memory and cache updated after.
    ///
    /// The only method that touches the wire, and only when called.
    ///
    /// A door-level failure is a fact, not an error — it records as
    /// unreachable and earlier facts stay remembered. What does throw:
    /// ``ProbeParseError``, a reached host answering garbage.
    @discardableResult
    public func discover(_ host: String) async throws -> HostFacts {
        var facts = memory[host] ?? HostFacts()
        do {
            let probe = try await conduit.run(on: host, CapabilityProbe.command).collect()
            let capability = try CapabilityProbe.parse(probe.stdoutText)
            facts.reachability = Dated(value: .reachable, discoveredAt: now())
            facts.capability = Dated(value: capability, discoveredAt: now())
            if capability.zfs != nil {
                let list = try await conduit.run(on: host, ZFSTopology.listCommand).collect()
                if list.exitStatus == 0 {
                    facts.zfsTopology = Dated(
                        value: ZFSTopology.parse(list.stdoutText),
                        discoveredAt: now()
                    )
                }
            }
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
