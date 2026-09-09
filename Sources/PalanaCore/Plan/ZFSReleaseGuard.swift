import Foundation

/// The exact ZFS cleanup commands a received dataset authorizes.
///
/// Dataset existence proves only that one receive landed. This value binds
/// that proof to the snapshot cleanup and, for a move, the source dataset
/// destroy composed for the same operation identity.
public struct ZFSReleaseGuard: Codable, Sendable, Equatable {
    /// The source host that owns the sent dataset and snapshot.
    public var sourceHost: String
    /// The destination host that owns the received dataset.
    public var destinationHost: String
    /// The dataset sent from the source host.
    public var sourceDataset: String
    /// The dataset whose existence opens the gate.
    public var receivedDataset: String
    /// The snapshot and cleanup identity.
    public var token: String
    /// Whether the source dataset itself may be destroyed.
    public var deletesSource: Bool

    /// Assembles a release binding from the facts used to compose the plan.
    public init(
        sourceHost: String,
        destinationHost: String,
        sourceDataset: String,
        receivedDataset: String,
        token: String,
        deletesSource: Bool
    ) {
        self.sourceHost = sourceHost
        self.destinationHost = destinationHost
        self.sourceDataset = sourceDataset
        self.receivedDataset = receivedDataset
        self.token = token
        self.deletesSource = deletesSource
    }

    /// The only gated steps this binding authorizes, in execution order.
    public var releaseSteps: [PlanStep] {
        let receivedSnapshot = "\(receivedDataset)@\(token)"
        let sourceTarget = deletesSource ? sourceDataset : "\(sourceDataset)@\(token)"
        return [
            PlanStep(
                runsOn: .host(destinationHost),
                command: "zfs destroy -r \(ShellQuote.quote(receivedSnapshot))",
                role: .cleanup,
                gatedOnVerification: true),
            PlanStep(
                runsOn: .host(sourceHost),
                command: "zfs destroy -r \(ShellQuote.quote(sourceTarget))",
                role: deletesSource ? .delete : .cleanup,
                gatedOnVerification: true),
        ]
    }
}
