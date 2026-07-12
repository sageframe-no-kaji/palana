// The same-filesystem proof — extracted from PlanEngine.swift to keep
// that file within the length budget. Pure functions over PlanFacts.

import Foundation

extension PlanEngine {
    /// Whether both ends provably share one filesystem — a rename is
    /// then honest and instant.
    ///
    /// Proof, in order: same dataset (ZFS facts), same mount target (the
    /// any-filesystem mounts fact, ho-9.3), or the local Mac with no
    /// facts saying otherwise — `mv` is POSIX-correct even across
    /// devices, and a local move that rsyncs reads as weird (the hands
    /// round said so). Remote ends with no facts stay conservative:
    /// the verified copy-then-gated-delete.
    static func provenSameFilesystem(_ facts: PlanFacts, request: PlanRequest) -> Bool {
        if let source = facts.sourceDataset, let destination = facts.destinationDataset {
            if source.name == destination.name { return true }
        }
        if let source = facts.sourceMountTarget, let destination = facts.destinationMountTarget {
            return source == destination
        }
        return request.source.host == PalanaCore.localHostName
    }
}
