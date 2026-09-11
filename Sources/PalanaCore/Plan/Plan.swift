// The Plan — the value the panel renders and the Transports run. Plans
// are values: the post-release queue is a list of them, the battery
// compares them whole, and nothing in one can change between the
// operator reading it and Enter.

import Foundation

/// What the operator asked for.
public enum PlanOperation: String, Codable, Sendable {
    /// Move the source by rename, ZFS release, or progressive rsync.
    case move
    /// Transfer, source untouched.
    case copy
    /// Remove the selected entries.
    case delete
    /// Rename an entry in the source directory in place.
    case rename
    /// Create a new entry in the source directory.
    case create
    /// Update modification times on the selected entries in place.
    case touch
    /// A ZFS in-place mutation — create, destroy, rename, snapshot,
    /// rollback, or property change.
    case zfs
}

/// What the operation actually is, named before it runs.
///
/// The committed vocabulary from the system design. A cross-dataset
/// move is classified honestly whether its release is a rename, ZFS,
/// or rsync removing each source file after transfer.
public enum Classification: String, Codable, Sendable {
    /// Same host, same dataset — a true rename.
    case withinDatasetRename = "within-dataset rename"
    /// Same host, different (or unproven-same) datasets — or a merge
    /// into a standing directory, which a rename cannot do.
    case crossDatasetCopyPlusDelete = "cross-dataset copy-plus-delete"
    /// Different hosts — bytes travel host to host.
    case crossHostTransfer = "cross-host transfer"
    /// A copy that never leaves the host.
    case withinHostCopy = "within-host copy"
    /// A copy whose bytes travel host to host.
    case crossHostCopy = "cross-host copy"
    /// Entries removed where they stand.
    case deletion
    /// An entry created where it stands.
    case creation
    /// Modification times updated where the entries stand.
    case modificationTimeUpdate = "modification-time update"
    /// A ZFS in-place mutation on a single host.
    case zfsMutation = "zfs mutation"
}

extension Classification {
    /// Display name in plain English — what the operator sees in the plan header.
    ///
    /// Raw values are the on-disk vocabulary and are frozen. This var provides
    /// plain-language equivalents for every case without touching rawValues.
    public var plainName: String {
        switch self {
        case .withinDatasetRename:
            return "move on the same disk (instant)"
        case .crossDatasetCopyPlusDelete:
            return "move across storage boundaries"
        case .crossHostTransfer:
            return "move to another machine"
        case .withinHostCopy:
            return "copy"
        case .crossHostCopy:
            return "copy to another machine"
        case .deletion:
            return "delete"
        case .creation:
            return "create"
        case .modificationTimeUpdate:
            return "update timestamps"
        case .zfsMutation:
            return "zfs change"
        }
    }
}

extension Transport {
    /// Display string in plain English — what the operator sees in the plan body.
    ///
    /// Raw values are the on-disk vocabulary and are frozen. This var provides
    /// plain-language equivalents for every case without touching rawValues.
    public var plainDescription: String {
        switch self {
        case .local:
            return "how: runs locally on the one host involved"
        case .rsyncAgentForwarded:
            return "how: rsync, run host-to-host · using the forwarded ssh key"
        case .rsyncDirect:
            return "how: rsync, run from this Mac · using this Mac's ssh keys"
        case .tarStreamProxied:
            return "how: tar stream, proxied through this Mac · no rsync at one end"
        case .tarStreamDirect:
            return "how: tar stream, run from this Mac · using this Mac's ssh keys"
        case .zfsSendReceiveForwarded:
            return "how: zfs send/receive, run host-to-host · using the forwarded ssh key"
        case .zfsSendReceiveProxied:
            return "how: zfs send/receive, proxied through this Mac"
        }
    }
}

/// How the bytes move, auth path included — the plan names it, the
/// operator never chooses.
public enum Transport: String, Codable, Sendable {
    /// No wire — the command runs on the one host involved.
    case local
    /// rsync host-to-host, the operator's agent forwarded to the source
    /// host. The fast path.
    case rsyncAgentForwarded = "rsync host-to-host · auth: agent-forwarded direct"
    /// rsync with this machine at one end — the operator's own agent
    /// authenticates and nothing is forwarded, so the plan never claims
    /// a forwarding that isn't happening.
    case rsyncDirect = "rsync from this machine · auth: this machine's agent"
    /// A tar stream piped through the operator's machine — the fallback
    /// when forwarding is unavailable or unprobed. rsync cannot proxy:
    /// it refuses two remote endpoints.
    case tarStreamProxied = "tar stream · proxied through this machine"
    /// A tar stream with this machine at one end — the fallback when
    /// the remote end has no rsync. One pipe, no proxy: the bytes were
    /// coming through here anyway.
    case tarStreamDirect = "tar stream · from this machine"
    /// zfs send piped to zfs receive over the forwarded path.
    case zfsSendReceiveForwarded = "zfs send/receive · auth: agent-forwarded direct"
    /// zfs send piped to zfs receive through the operator's machine.
    case zfsSendReceiveProxied = "zfs send/receive · proxied through this machine"
}

/// Where a step's command runs.
public enum Runner: Codable, Sendable, Equatable, Hashable {
    /// The operator's machine — proxied pipelines run here.
    case operatorMachine
    /// A named host, reached through the Conduit.
    case host(String)
}

/// The two halves of a proxied pipeline, structured.
///
/// The step's command string is the paste-able truth; this is the same
/// truth in parts, so enactment can spawn the halves in-process and
/// count the bytes between them without re-parsing shell. Both are
/// composed together by the engine — they cannot drift.
public struct Pipeline: Codable, Sendable, Equatable {
    /// The host the producing half runs against.
    public var fromHost: String
    /// The producing command — tar -cf, zfs send.
    public var fromCommand: String
    /// The host the consuming half runs against.
    public var toHost: String
    /// The consuming command — tar -xpf, zfs receive.
    public var toCommand: String

    /// Assembles a pipeline spec.
    public init(fromHost: String, fromCommand: String, toHost: String, toCommand: String) {
        self.fromHost = fromHost
        self.fromCommand = fromCommand
        self.toHost = toHost
        self.toCommand = toCommand
    }
}

/// One command in an approved sequence.
public struct PlanStep: Codable, Sendable, Equatable {
    /// What the step is for — the panel labels it, the Transports gate
    /// on it.
    public enum Role: String, Codable, Sendable {
        /// Bytes moving toward the destination.
        case transfer
        /// A same-host copy.
        case copy
        /// A true rename.
        case rename
        /// Source removal — an explicit delete or a bound ZFS release.
        case delete
        /// A zfs snapshot taken so send has a stable point.
        case snapshot
        /// Snapshot removal after a completed transfer.
        case cleanup
        /// An entry created in the source directory.
        case create
        /// Modification times updated in place.
        case touch
        /// The result confirmed after a mutation.
        case verify
        /// A dataset or snapshot rolled back to a prior state.
        case rollback
        /// A ZFS property set or cleared on a dataset.
        case property
        /// An operation-owned staging entry created at the destination.
        case stage
        /// A legacy quarantine step, retained only for decoding and refusing old plans.
        case quarantine
        /// A staged upload committed against the version it is bound to.
        case promote
    }

    /// Where the command runs.
    public var runsOn: Runner
    /// The exact command — something the operator could paste and get
    /// the same result.
    public var command: String
    /// What the step is for.
    public var role: Role
    /// True when the step must not run until the transfer verified.
    ///
    /// The Plan declares the gate; enforcing it is enactment's job.
    public var gatedOnVerification: Bool
    /// The structured halves, present only on proxied pipeline steps.
    public var pipeline: Pipeline?

    /// Assembles a step.
    public init(
        runsOn: Runner,
        command: String,
        role: Role,
        gatedOnVerification: Bool = false,
        pipeline: Pipeline? = nil
    ) {
        self.runsOn = runsOn
        self.command = command
        self.role = role
        self.gatedOnVerification = gatedOnVerification
        self.pipeline = pipeline
    }
}

/// An endpoint: a directory on a host.
public struct Locus: Codable, Sendable, Equatable {
    /// The host alias, as the ssh config names it.
    public var host: String
    /// The directory path on that host.
    public var directory: String

    /// An endpoint.
    public init(host: String, directory: String) {
        self.host = host
        self.directory = directory
    }
}

/// The composed plan — everything the operator reads before Enter.
public struct Plan: Codable, Sendable, Equatable {
    /// What was asked.
    public var operation: PlanOperation
    /// What it actually is.
    public var classification: Classification
    /// The selected entries.
    public var entries: [FileEntry]
    /// The selection's byte total — recursive truth for directory
    /// entries when the facts carry it (ho-06.5), reported size for
    /// files, inode size as the honest floor when a fact is missing.
    public var totalSize: Int64
    /// False when any directory's walk was refused or ungathered —
    /// the total is a floor, and the panel must say so.
    public var totalSizeComplete: Bool
    /// Where the entries are.
    public var source: Locus
    /// Where they are going. nil for deletion.
    public var destination: Locus?
    /// How the bytes move.
    public var transport: Transport
    /// The commands, in order, gates declared.
    public var steps: [PlanStep]
    /// The dataset a zfs transport will create at the destination —
    /// what verification asks for by name. nil on file transports.
    public var receivedDataset: String?
    /// The collision report for this plan.
    ///
    /// Nil on plans with no destination directory (rename, create, touch,
    /// delete, zfs mutations). Present on every destination-ful
    /// classification; `gathered` reflects whether the destination
    /// listing was read.
    public var collisions: CollisionReport?
    /// The topology truth this plan was composed over — present when a
    /// zfs transport or a zfs mutation routes on it or destroys by it.
    ///
    /// Enactment re-reads and confirms it before the first step runs.
    /// Nil on plans that owe nothing to topology, and on plans written
    /// before the binding existed — an absent key decodes as nil.
    public var topologyBinding: TopologyBinding?
    /// The exact remote version a send-back may replace.
    ///
    /// Present only on version-bound copies. Absent on every other
    /// plan, and on plans written before the guard existed — an absent
    /// key decodes as nil, and enactment refuses a commit step that
    /// has no version behind it.
    public var versionGuard: RemoteVersionGuard?
    /// The exact ZFS cleanup steps authorized by a successful receive.
    ///
    /// Present on ZFS send/receive plans. An absent value keeps gated
    /// destroys in older decoded plans closed.
    public var zfsReleaseGuard: ZFSReleaseGuard?
    /// Assembles a plan.
    public init(
        operation: PlanOperation,
        classification: Classification,
        entries: [FileEntry],
        totalSize: Int64,
        totalSizeComplete: Bool = true,
        source: Locus,
        destination: Locus?,
        transport: Transport,
        steps: [PlanStep],
        receivedDataset: String? = nil,
        collisions: CollisionReport? = nil,
        topologyBinding: TopologyBinding? = nil,
        versionGuard: RemoteVersionGuard? = nil,
        zfsReleaseGuard: ZFSReleaseGuard? = nil
    ) {
        self.operation = operation
        self.classification = classification
        self.entries = entries
        self.totalSize = totalSize
        self.totalSizeComplete = totalSizeComplete
        self.source = source
        self.destination = destination
        self.transport = transport
        self.steps = steps
        self.receivedDataset = receivedDataset
        self.collisions = collisions
        self.topologyBinding = topologyBinding
        self.versionGuard = versionGuard
        self.zfsReleaseGuard = zfsReleaseGuard
    }

    /// Whether the plan performs a progressive rsync move whose files
    /// may be split between source and destination if interrupted.
    public var usesProgressiveRsyncMove: Bool {
        guard operation == .move else { return false }
        switch transport {
        case .rsyncAgentForwarded, .rsyncDirect:
            return true
        case .local:
            return classification == .crossDatasetCopyPlusDelete
        case .tarStreamProxied, .tarStreamDirect, .zfsSendReceiveForwarded,
            .zfsSendReceiveProxied:
            return false
        }
    }
}

// MARK: - Topology binding

/// The datasets a plan stands on, exactly as they were read when it
/// composed — each with the read that produced it.
///
/// A plan whose routing or destructive target comes from topology is
/// only as true as that topology. The binding records what was true,
/// and ``Plan/confirmTopology(fresh:)`` checks a later read against it
/// dataset by dataset: name, mountpoint, mounted state, and the
/// relationship the selection rests on.
public struct TopologyBinding: Codable, Sendable, Equatable {
    /// What a bound dataset is to the plan — how a fresh read is asked for it.
    public enum Role: String, Codable, Sendable {
        /// The whole dataset the selection is — the source of a zfs send.
        case selection
        /// The dataset whose mountpoint is the destination directory — a
        /// zfs receive's parent.
        case destination
        /// The dataset a zfs mutation names directly.
        case target
    }

    /// One dataset the plan depends on.
    public struct Bound: Codable, Sendable, Equatable {
        /// The host the dataset lives on.
        public var host: String
        /// How the plan came to depend on it.
        public var role: Role
        /// The dataset as read — name, mountpoint, mounted.
        public var dataset: ZFSDataset
        /// The Field read that produced it.
        public var generation: Int

        /// Records one dependency.
        public init(host: String, role: Role, dataset: ZFSDataset, generation: Int) {
            self.host = host
            self.role = role
            self.dataset = dataset
            self.generation = generation
        }
    }

    /// Every dataset the plan depends on.
    public var bound: [Bound]

    /// Binds a plan to its datasets.
    public init(bound: [Bound]) {
        self.bound = bound
    }

    /// The hosts to re-read before enactment, first appearance order.
    public var hosts: [String] {
        var seen: Set<String> = []
        return bound.compactMap { seen.insert($0.host).inserted ? $0.host : nil }
    }
}

/// Why a fresh read did not confirm a plan's topology binding.
///
/// Every case refuses the enactment — a plan composed over one topology
/// never runs over another.
public enum TopologyBindingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The host's topology could not be re-read.
    case unavailable(host: String, detail: String)
    /// The re-read was not newer than the read the plan was bound to.
    case notFresh(host: String, generation: Int)
    /// The bound dataset no longer answers the plan's question.
    case gone(host: String, dataset: String, role: TopologyBinding.Role)
    /// The dataset is there, but its mountpoint or mounted state moved.
    case changed(host: String, was: ZFSDataset, now: ZFSDataset)

    /// One sentence, the panel's voice — what changed, and that nothing ran.
    public var description: String {
        switch self {
        case .unavailable(let host, let detail):
            "the zfs topology on \(host) could not be re-read — nothing ran: \(detail)"
        case .notFresh(let host, let generation):
            "the re-read of \(host) was not newer than read \(generation) — nothing ran"
        case .gone(let host, let dataset, let role):
            "\(dataset) on \(host) no longer \(role.gonePhrase) — the topology changed since "
                + "the plan was read; nothing ran, compose it again"
        case .changed(let host, let was, let now):
            "\(was.name) on \(host) changed since the plan was read — "
                + "\(was.changes(to: now)); nothing ran, compose it again"
        }
    }
}

extension TopologyBinding.Role {
    /// The predicate a gone dataset failed — completes "no longer …".
    var gonePhrase: String {
        switch self {
        case .selection: "is the whole dataset the selection stands on"
        case .destination: "holds the destination directory"
        case .target: "exists"
        }
    }
}

extension Plan {
    /// Confirms a fresh read still says what the plan was composed over.
    ///
    /// `fresh` holds the facts ``Field/refresh(_:)`` just returned, keyed
    /// by host. Each bound dataset is asked for the way the plan found
    /// it — the selection's whole dataset, the destination's containing
    /// dataset, the named target — and must come back identical. A plan
    /// without a binding confirms trivially.
    public func confirmTopology(fresh: [String: HostFacts]) throws {
        guard let binding = topologyBinding else { return }
        for bound in binding.bound {
            guard let facts = fresh[bound.host] else {
                throw TopologyBindingError.unavailable(host: bound.host, detail: "no read")
            }
            guard let datasets = facts.zfsTopology?.value else {
                let detail = facts.zfsTopologyUnavailable?.value.detail ?? "no zfs topology"
                throw TopologyBindingError.unavailable(host: bound.host, detail: detail)
            }
            guard let generation = facts.generation, generation > bound.generation else {
                throw TopologyBindingError.notFresh(host: bound.host, generation: bound.generation)
            }
            guard let now = answer(for: bound, in: datasets) else {
                throw TopologyBindingError.gone(
                    host: bound.host, dataset: bound.dataset.name, role: bound.role)
            }
            guard now == bound.dataset else {
                throw TopologyBindingError.changed(host: bound.host, was: bound.dataset, now: now)
            }
        }
    }

    /// The fresh dataset that answers a bound role's question, if any.
    private func answer(for bound: TopologyBinding.Bound, in datasets: [ZFSDataset]) -> ZFSDataset? {
        switch bound.role {
        case .selection:
            return ZFSTopology.wholeDatasetSelection(
                entries: entries, sourceDirectory: source.directory, datasets: datasets)
        case .destination:
            guard let destination else { return nil }
            return ZFSTopology.datasetContaining(destination.directory, in: datasets)
        case .target:
            return datasets.first { $0.name == bound.dataset.name }
        }
    }
}
