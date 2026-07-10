// OperationModel+Collisions — destination listing and collision detection
// extracted from gather to keep that function within SwiftLint's body and
// complexity limits.

import PalanaCore

extension OperationModel {
    /// Gathers collision facts when a destination exists; no-ops when nil.
    ///
    /// Exists as a wrapper so `gather` stays within SwiftLint's body-length
    /// limit — the nil guard lives here, not in the already-dense caller.
    func gatherCollisionsIfNeeded(
        destination: Locus?,
        subjects: [FileEntry],
        into facts: inout PlanFacts
    ) async {
        guard let destination else { return }
        await gatherCollisions(destination: destination, subjects: subjects, into: &facts)
    }

    /// Reads the destination directory and sets `facts.collisions`.
    ///
    /// On success, `facts.collisions` is set to the detected collisions
    /// (an empty array when the destination is clean). On any thrown
    /// read, `facts.collisions` stays nil and a note names the unknown.
    /// The gather must not fail the plan for an unreadable destination —
    /// the collision line carries the truth (Decision 3).
    func gatherCollisions(
        destination: Locus,
        subjects: [FileEntry],
        into facts: inout PlanFacts
    ) async {
        do {
            let flavor = try await resolveFlavor(destination.host)
            let listing = try await engine.listing(for: destination.host)
                .list(on: destination.host, path: destination.directory, flavor: flavor)
            let collisions = Collision.detect(sources: subjects, destinationListing: listing)
            facts.collisions = collisions
            if !collisions.isEmpty {
                let count = collisions.count
                note(
                    "\(count) \(count == 1 ? "collision" : "collisions") at destination")
            }
        } catch {
            facts.collisions = nil
            note("destination unread — collisions unknown")
        }
    }
}
