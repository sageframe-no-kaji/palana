// OperationModel+RoundTrip — the upload entry point and gather for round-trip
// editing, extracted to keep OperationModel.swift within its length budget.
//
// beginRoundTripUpload: the entry point — sets up state and launches the
// gather task. gatherRoundTripUpload: reads the local per-open directory for
// a byte-honest FileEntry, gathers capability and destination facts, then
// rules on the destination (clean / conflict / unavailable) and either sends
// on its own, arms the plan for the operator, or blocks and stays local.

import Foundation
import PalanaCore

extension OperationModel {
    /// Opens the panel and composes an upload plan for the given round-trip record.
    ///
    /// The source is the per-open UUID directory on this Mac; the destination is
    /// the record's remote host and directory. Gather runs the same collision path
    /// as any other copy plan — the collision line names the replace — and adds the
    /// three-valued destination check that decides whether the send may run on its own.
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
        // The panel does NOT pop here — save is save (his ruling,
        // 2026-07-10). It shows only when the send needs him: the
        // ask setting is on, a conflict blocks the send, or a failure.
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

    /// Gathers the upload plan for a round-trip record and applies the
    /// destination ruling.
    func gatherRoundTripUpload(record: RoundTripRecord) async {
        do {
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
                panelShowing = true
                return
            }
            guard !Task.isCancelled else { return }

            var facts = PlanFacts()
            facts.sourceCapability = await localCapability()
            let destinationFacts = try await ensureFacts(record.host)
            facts.destinationCapability = destinationFacts?.capability?.value
            facts.rsyncOperatorFlags = effectiveRsyncFlags

            // The three-valued destination check — clean, conflict, or
            // unavailable. Sets facts.collisions as a side effect.
            let check = await checkRoundTripDestination(
                destination: destinationLocus,
                subjects: [localEntry],
                record: record,
                into: &facts)

            guard !Task.isCancelled else { return }
            let inputs = RoundTripPlanInputs(
                source: sourceLocus, destination: destinationLocus, entry: localEntry, facts: facts)
            applyRoundTripCheck(check, record: record, inputs: inputs)
        } catch {
            guard !Task.isCancelled else { return }
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
            panelShowing = true
        }
    }

    /// The composition inputs for a round-trip upload, bundled so the ruling
    /// step stays within the parameter-count budget.
    struct RoundTripPlanInputs {
        /// The per-open directory on this Mac.
        let source: Locus
        /// The remote host and directory the edit goes back to.
        let destination: Locus
        /// The byte-honest local entry being uploaded.
        let entry: FileEntry
        /// The facts gathered for the plan, collisions included.
        let facts: PlanFacts
    }

    /// Applies the destination ruling: block, arm, or send.
    ///
    /// Only a ``ConflictCheck/clean`` result with auto-send on runs on its
    /// own. A conflict names itself and arms the plan for the operator's
    /// Enter (naming, not resolving — ho-9.10 Decision 4). An unavailable
    /// check composes no plan: the edit stays local and a later save
    /// rechecks (review: fail-open collision check).
    private func applyRoundTripCheck(
        _ check: ConflictCheck,
        record: RoundTripRecord,
        inputs: RoundTripPlanInputs
    ) {
        if case .conflict(let reason) = check {
            note(RoundTrip.conflictNote(for: reason))
        }
        let disposition = RoundTrip.disposition(
            for: check, askBeforeSending: askBeforeSendingBack, record: record)
        if case .blocked(let reason) = disposition {
            echo.appendLine(reason, kind: .failure)
            phase = .failed
            panelShowing = true
            return
        }
        do {
            let request = PlanRequest(
                operation: .copy,
                source: inputs.source,
                entries: [inputs.entry],
                destination: inputs.destination,
                token: Self.mintToken())
            plan = try PlanEngine.plan(request, facts: inputs.facts)
        } catch {
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
            panelShowing = true
            return
        }
        switch disposition {
        case .sendNow:
            phase = .ready
            note("sending back — \(record.fetched.name) to \(record.host):\(record.remoteDirectory)")
            enact()
        case .askOperator(let callout):
            readyCallout = callout
            phase = .ready
            panelShowing = true
        case .blocked:
            break  // handled above
        }
    }

    /// Reads the destination and rules on it, three-valued.
    ///
    /// Any listing or read error is ``ConflictCheck/unavailable`` — a check
    /// that could not complete is never "clean." A missing remote entry is a
    /// conflict; changed size or mtime is a conflict; equal metadata with a
    /// different content digest is a conflict; equal metadata whose bytes
    /// could not be read is unavailable. Sets `facts.collisions` for the
    /// plan's collision line (nil on an unreadable destination).
    ///
    /// - Returns: The destination ruling.
    func checkRoundTripDestination(
        destination: Locus,
        subjects: [FileEntry],
        record: RoundTripRecord,
        into facts: inout PlanFacts
    ) async -> ConflictCheck {
        do {
            let flavor = try await resolveFlavor(destination.host)
            let listing = try await engine.listing(for: destination.host)
                .list(on: destination.host, path: destination.directory, flavor: flavor)
            facts.collisions = Collision.detect(sources: subjects, destinationListing: listing)
            if let collisions = facts.collisions, !collisions.isEmpty {
                let count = collisions.count
                note("\(count) \(count == 1 ? "file already exists" : "files already exist") at destination")
            }
            let remoteEntry = listing.first { $0.nameData == record.fetched.nameData }
            let currentDigest = await remoteDigestIfMetadataMatches(
                record: record, current: remoteEntry, on: destination)
            return RoundTrip.evaluate(record: record, current: remoteEntry, currentDigest: currentDigest)
        } catch {
            facts.collisions = nil
            note("couldn't check the destination — the edit stays local; save again to check again")
            return .unavailable(Self.describe(error))
        }
    }

    /// Reads the remote content digest, but only when it is needed.
    ///
    /// The read runs when the remote entry is present and its metadata still
    /// matches the fetch baseline. Returns `nil` when the read is unnecessary
    /// (metadata already differs, so `evaluate` rules on metadata alone) or
    /// when the read failed (so `evaluate` rules the destination unavailable).
    private func remoteDigestIfMetadataMatches(
        record: RoundTripRecord,
        current: FileEntry?,
        on destination: Locus
    ) async -> Data? {
        guard let current, !RoundTrip.changedSinceFetch(baseline: record.fetched, current: current)
        else { return nil }
        let path = PaneModel.childPath(of: destination.directory, name: current.name)
        guard
            let bytes = try? await engine.listing(for: destination.host)
                .readFile(on: destination.host, path: path)
        else { return nil }
        return RoundTrip.digest(of: bytes)
    }
}
