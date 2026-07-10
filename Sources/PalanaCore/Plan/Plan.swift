// The Plan — the value the panel renders and the Transports run. Plans
// are values: the post-release queue is a list of them, the battery
// compares them whole, and nothing in one can change between the
// operator reading it and Enter.

import Foundation

/// What the operator asked for.
public enum PlanOperation: String, Codable, Sendable {
    /// Transfer then delete source, delete gated on verification.
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
/// The committed vocabulary from the system design — a cross-dataset
/// move is a copy-plus-delete wearing a rename's clothes, and saying so
/// is the sentence this project exists to make true.
public enum Classification: String, Codable, Sendable {
    /// Same host, same dataset — a true rename.
    case withinDatasetRename = "within-dataset rename"
    /// Same host, different (or unproven-same) datasets.
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
        /// Source removal — the back half of a move, or a delete.
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
        collisions: CollisionReport? = nil
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
    }
}
