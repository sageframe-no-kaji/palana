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

    /// Whether any selected directory lands on a standing directory of
    /// the same name — a `.merge` collision.
    ///
    /// A rename cannot merge. `mv a/dir b/` with `b/dir` standing asks
    /// rename(2) to replace a directory, which succeeds only when the
    /// standing one is empty; otherwise the tool fails mid-batch or, in
    /// some userlands, nests the source as `b/dir/dir` — either way the
    /// plan's "will merge into dir" was false and no manifest ever
    /// checked the result (2026-09-07 hands session). Copy tools merge,
    /// so a merge takes the copy-then-gated-delete route even on a
    /// proven-shared filesystem. Replaces (file onto file) stay renames:
    /// `mv` overwrites a file exactly as the plan says.
    static func mergesAtDestination(_ facts: PlanFacts) -> Bool {
        facts.collisions?.contains { $0.nature == .merge } ?? false
    }
}
