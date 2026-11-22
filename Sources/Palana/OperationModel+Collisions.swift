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
        // pālana's own folder for interrupted copies is not copied by
        // rsync — say so when one is selected (owner ruling 2026-11-19, Q05).
        if subjects.contains(where: { $0.name == PlanEngine.partialDirName }) {
            note("\(PlanEngine.partialDirName) is pālana's folder for interrupted copies — rsync skips it")
        }
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
            var collisions = Collision.detect(sources: subjects, destinationListing: listing)
            // Names the byte compare missed may still resolve to an entry
            // the destination filesystem treats as the same (owner ruling
            // 2026-11-18, final review F02) — ask it.
            guard
                let resolved = try await resolvedCollisions(
                    destination: destination, subjects: subjects, listing: listing)
            else {
                facts.collisions = nil
                note("couldn't check the destination — this may overwrite files there")
                return
            }
            collisions += resolved
            facts.collisions = collisions
            if !collisions.isEmpty {
                let count = collisions.count
                note(
                    "\(count) \(count == 1 ? "file already exists" : "files already exist") at destination")
            }
        } catch {
            facts.collisions = nil
            note("couldn't check the destination — this may overwrite files there")
        }
    }

    /// Collisions the destination filesystem resolves for arriving names
    /// with no byte-exact listing match — case-insensitive storage.
    ///
    /// Nil when they cannot be established: a name with no exact text to
    /// ask about, or a hit that names no single listed entry. A failed
    /// probe throws, and the caller treats both as unknown.
    private func resolvedCollisions(
        destination: Locus,
        subjects: [FileEntry],
        listing: [FileEntry]
    ) async throws -> [Collision]? {
        let arrivals = Collision.unmatched(sources: subjects, destinationListing: listing)
        guard !arrivals.isEmpty else { return [] }
        let names = arrivals.compactMap(\.exactName)
        guard names.count == arrivals.count else { return nil }
        let hits = try await engine.listing(for: destination.host)
            .resolving(names: names, in: destination.directory, on: destination.host)
        return Collision.resolved(arrivals: arrivals, hits: hits, destinationListing: listing)
    }
}
