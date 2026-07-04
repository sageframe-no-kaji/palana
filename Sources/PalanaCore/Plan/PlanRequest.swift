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
    /// Where the selection is going. nil for delete.
    public var destination: Locus?
    /// Uniquifies composed snapshot names — the caller supplies it
    /// because the engine is pure and mints nothing.
    public var token: String

    /// Assembles a request.
    public init(
        operation: PlanOperation,
        source: Locus,
        entries: [FileEntry],
        destination: Locus? = nil,
        token: String = "palana-transfer"
    ) {
        self.operation = operation
        self.source = source
        self.entries = entries
        self.destination = destination
        self.token = token
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

    /// Assembles a facts bundle — everything defaults to unknown.
    public init(
        sourceDataset: ZFSDataset? = nil,
        destinationDataset: ZFSDataset? = nil,
        selectionWholeDataset: ZFSDataset? = nil,
        sourceCapability: HostCapability? = nil,
        destinationCapability: HostCapability? = nil,
        agentForwarding: ForwardingFact = .unprobed
    ) {
        self.sourceDataset = sourceDataset
        self.destinationDataset = destinationDataset
        self.selectionWholeDataset = selectionWholeDataset
        self.sourceCapability = sourceCapability
        self.destinationCapability = destinationCapability
        self.agentForwarding = agentForwarding
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
}
