// OperationModel+RoundTrip — the upload entry point and gather for round-trip
// editing, extracted to keep OperationModel.swift within its length budget.
//
// beginRoundTripUpload: the entry point — sets up state and launches the
// gather task. gatherRoundTripUpload: reads the local per-open directory for
// a byte-honest FileEntry, gathers capability and collision facts (including
// the changed-since-fetch note), then commits the composed plan.

import Foundation
import PalanaCore

extension OperationModel {
    /// Opens the panel and composes an upload plan for the given round-trip record.
    ///
    /// The source is the per-open UUID directory on this Mac; the destination is
    /// the record's remote host and directory. Gather runs the same collision path
    /// as any other copy plan — the collision line names the replace, and when the
    /// remote entry changed since the fetch, a note names that too.
    ///
    /// Phase law mirrors `begin`: an in-flight enactment re-shows the panel and
    /// stops; a gathering is cancelled and replaced; resting phases clear for a
    /// fresh compose.
    ///
    /// - Parameter record: The round-trip record whose local copy was just saved.
    func beginRoundTripUpload(record: RoundTripRecord) {
        if phase == .enacting {
            panelShowing = true
            return
        }
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        if phase == .naming { reset() }
        panelShowing = true
        requested = .copy
        echo = EchoBuffer()
        progress = nil
        plan = nil
        resultName = nil
        phase = .gathering
        gatherTask = Task {
            await gatherRoundTripUpload(record: record)
        }
    }

    // MARK: - Gather

    /// Gathers the upload plan for a round-trip record.
    ///
    /// Reads the local listing over the per-open directory to get a
    /// byte-honest ``FileEntry`` for the temp file, then composes the
    /// ``PlanRequest`` and runs collision gathering so the panel arrives
    /// in `.ready` with the collision line and any changed-since-fetch note.
    func gatherRoundTripUpload(record: RoundTripRecord) async {
        do {
            // The per-open directory — source locus for the upload.
            let localDir = record.localURL.deletingLastPathComponent().path
            let sourceLocus = Locus(host: PalanaCore.localHostName, directory: localDir)
            let destinationLocus = Locus(host: record.host, directory: record.remoteDirectory)

            // Byte-honest FileEntry from the local listing — no hand-built attributes.
            let localEntries = try await engine.listing(for: PalanaCore.localHostName)
                .list(on: PalanaCore.localHostName, path: localDir, flavor: .bsd)
            guard
                let localEntry = localEntries.first(where: {
                    $0.nameData == record.fetched.nameData
                })
            else {
                guard !Task.isCancelled else { return }
                echo.appendLine("local copy not found — was it moved or deleted?", kind: .failure)
                phase = .failed
                return
            }
            guard !Task.isCancelled else { return }

            var facts = PlanFacts()

            // Source capability — this Mac.
            facts.sourceCapability = await localCapability()

            // Destination host facts.
            let destinationFacts = try await ensureFacts(record.host)
            facts.destinationCapability = destinationFacts?.capability?.value

            facts.rsyncOperatorFlags = effectiveRsyncFlags

            // Collision gather — delivers the changed-since-fetch note inline.
            let conflicted = await gatherRoundTripCollisions(
                destination: destinationLocus,
                subjects: [localEntry],
                record: record,
                into: &facts)

            guard !Task.isCancelled else { return }

            let request = PlanRequest(
                operation: .copy,
                source: sourceLocus,
                entries: [localEntry],
                destination: destinationLocus,
                token: Self.mintToken())
            plan = try PlanEngine.plan(request, facts: facts)

            // Auto-send: skip the confirmation gate when the toggle is on and
            // there is no conflict. A conflict (the remote changed since the
            // fetch) always blocks auto-send — an automatic overwrite of a file
            // someone else changed is the one case the gate exists for.
            if autoSendRoundTrips, !conflicted {
                phase = .ready
                note("sending back automatically — auto-send is on in settings")
                enact()
            } else {
                readyCallout =
                    "⏎ press enter to send it back to \(record.host):\(record.remoteDirectory) · esc keeps the edit local"
                phase = .ready
            }
        } catch {
            guard !Task.isCancelled else { return }
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
        }
    }

    /// Gathers collision facts for the round-trip upload and emits the
    /// changed-since-fetch note when applicable.
    ///
    /// Mirrors ``gatherCollisions(destination:subjects:into:)`` from
    /// `OperationModel+Collisions.swift` but adds the baseline comparison
    /// that names a remote that moved underneath the edit (Decision 4).
    ///
    /// The record's ``RoundTripRecord/fetched`` entry is the baseline;
    /// ``RoundTrip/changedSinceFetch(baseline:current:)`` is the pure
    /// comparison; ``RoundTrip/changedSinceFetchNote(current:)`` is the
    /// sentence (both live in core under the coverage floor).
    ///
    /// - Parameters:
    ///   - destination: The remote locus to read.
    ///   - subjects: The local entries being uploaded (single file for a round-trip).
    ///   - record: The round-trip record carrying the fetch-time baseline.
    ///   - facts: The facts bundle to write collision results into.
    /// - Returns: `true` when a changed-since-fetch conflict was detected — the
    ///   caller uses this to block auto-send regardless of the toggle.
    func gatherRoundTripCollisions(
        destination: Locus,
        subjects: [FileEntry],
        record: RoundTripRecord,
        into facts: inout PlanFacts
    ) async -> Bool {
        do {
            let flavor = try await resolveFlavor(destination.host)
            let listing = try await engine.listing(for: destination.host)
                .list(on: destination.host, path: destination.directory, flavor: flavor)

            // Changed-since-fetch note — emitted before the collision summary
            // so the operator reads the conflict context first.
            let remoteEntry = listing.first { $0.nameData == record.fetched.nameData }
            var conflicted = false
            if let remoteEntry, RoundTrip.changedSinceFetch(baseline: record.fetched, current: remoteEntry) {
                note(RoundTrip.changedSinceFetchNote(current: remoteEntry))
                conflicted = true
            }

            let collisions = Collision.detect(sources: subjects, destinationListing: listing)
            facts.collisions = collisions
            if !collisions.isEmpty {
                let count = collisions.count
                note("\(count) \(count == 1 ? "file already exists" : "files already exist") at destination")
            }
            return conflicted
        } catch {
            facts.collisions = nil
            note("couldn't check the destination — this may overwrite files there")
            return false
        }
    }
}
