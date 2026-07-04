// The engine's inputs — a request and a facts bundle, both values. The
// engine holds no Field and no Conduit: the coupling lives at the call
// site, purity stays absolute, and the battery feeds facts by hand.

import Foundation

/// What the operator asked the engine to plan.
public struct PlanRequest: Sendable, Equatable {
    /// The operation.
    public var operation: PlanOperation
    /// Where the selection lives.
    public var source: Locus
    /// The selected entries in the source directory.
    public var entries: [FileEntry]
    /// Where the selection is going. nil for delete, rename, and create.
    public var destination: Locus?
    /// Uniquifies composed snapshot names — the caller supplies it
    /// because the engine is pure and mints nothing.
    public var token: String
    /// The bare new name for rename and create; nil for every other
    /// operation.
    public var targetName: String?

    /// Assembles a request.
    public init(
        operation: PlanOperation,
        source: Locus,
        entries: [FileEntry],
        destination: Locus? = nil,
        token: String = "palana-transfer",
        targetName: String? = nil
    ) {
        self.operation = operation
        self.source = source
        self.entries = entries
        self.destination = destination
        self.token = token
        self.targetName = targetName
    }
}

/// Whether the source host can authenticate to the destination with
/// the operator's forwarded agent.
///
/// Explicitly three-valued: unprobed is a real state and it selects
/// the proxy path, the conservative truth. ho-06 discovers this fact.
public enum ForwardingFact: String, Codable, Sendable {
    /// Probed and the source host reached the destination.
    case available
    /// Probed and it could not.
    case unavailable
    /// Never probed.
    case unprobed
}

/// The facts the engine composes over — gathered elsewhere, passed as a
/// value.
public struct PlanFacts: Sendable, Equatable {
    /// The dataset containing the source directory, where known.
    public var sourceDataset: ZFSDataset?
    /// The dataset containing the destination directory, where known.
    public var destinationDataset: ZFSDataset?
    /// Non-nil when the selection is a single directory entry whose
    /// path is exactly this dataset's mountpoint — the whole-dataset
    /// gate for zfs send/receive.
    public var selectionWholeDataset: ZFSDataset?
    /// The source host's probed capability, where known.
    public var sourceCapability: HostCapability?
    /// The destination host's probed capability, where known.
    public var destinationCapability: HostCapability?
    /// The forwarding fact — unprobed until ho-06 learns otherwise.
    public var agentForwarding: ForwardingFact
    /// Recursive size facts for directory entries, keyed by identity.
    ///
    /// Gathered per plan via `Listing.treeSizes` (ho-06.5). A directory
    /// with no fact here counts at inode size and marks the plan's
    /// total incomplete.
    public var recursiveSizes: [FileEntry.ID: RecursiveSize]

    /// Assembles a facts bundle — everything defaults to unknown.
    public init(
        sourceDataset: ZFSDataset? = nil,
        destinationDataset: ZFSDataset? = nil,
        selectionWholeDataset: ZFSDataset? = nil,
        sourceCapability: HostCapability? = nil,
        destinationCapability: HostCapability? = nil,
        agentForwarding: ForwardingFact = .unprobed,
        recursiveSizes: [FileEntry.ID: RecursiveSize] = [:]
    ) {
        self.sourceDataset = sourceDataset
        self.destinationDataset = destinationDataset
        self.selectionWholeDataset = selectionWholeDataset
        self.sourceCapability = sourceCapability
        self.destinationCapability = destinationCapability
        self.agentForwarding = agentForwarding
        self.recursiveSizes = recursiveSizes
    }
}

/// Why the engine refused to compose.
///
/// Refusal is the honest alternative to a plan that lies.
public enum PlanError: Error, Equatable, Sendable {
    /// Nothing selected — there is nothing to plan.
    case emptySelection
    /// Move and copy need somewhere to go.
    case missingDestination
    /// An entry's name bytes do not round-trip UTF-8; composing a
    /// command would name a different file than the one selected.
    case unrepresentableName(Data)
    /// rename and create must have no destination — the operation stays
    /// within the source directory.
    case destinationForbidden
    /// rename requires exactly one selected entry.
    case renameRequiresOneEntry
    /// rename refuses when the target name matches the current name.
    case targetNameUnchanged
    /// rename and create require a non-empty target name.
    case targetNameRequired
    /// create requires an empty selection — the new name is the selection.
    case entriesForbiddenForCreate
    /// The target name contains a path separator in a disallowed position.
    case targetNameContainsSeparator
}
