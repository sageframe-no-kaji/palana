// The same-filesystem proof — extracted from PlanEngine.swift to keep
// that file within the length budget. Pure functions over PlanFacts.

import Foundation

extension PlanEngine {
    /// Whether both ends provably share one filesystem — a rename is
    /// then honest and instant.
    ///
    /// Proof, in order: same dataset (ZFS facts), or same mount target
    /// (the any-filesystem mounts fact, ho-9.3). Nothing else counts.
    /// The local Mac used to be assumed same-filesystem without facts —
    /// but `mv` across volumes is a copy-then-delete in a rename's
    /// clothes, and the plan said "instant" over a copy that could be
    /// interrupted half-way (2026-09-06 review). The app now reads this
    /// Mac's mount table for the proof; ends without facts, local or
    /// remote, take the verified copy-then-gated-delete.
    static func provenSameFilesystem(_ facts: PlanFacts) -> Bool {
        if let source = facts.sourceDataset, let destination = facts.destinationDataset {
            if source.name == destination.name { return true }
        }
        if let source = facts.sourceMountTarget, let destination = facts.destinationMountTarget {
            return source == destination
        }
        return false
    }
}
