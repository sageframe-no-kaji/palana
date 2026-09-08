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
            let reading = await checkRoundTripDestination(
                destination: destinationLocus,
                subjects: [localEntry],
                record: record,
                into: &facts)

            guard !Task.isCancelled else { return }
            let inputs = RoundTripPlanInputs(
                source: sourceLocus, destination: destinationLocus, entry: localEntry, facts: facts)
            applyRoundTripCheck(reading, record: record, inputs: inputs)
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
    ///
    /// Whatever the ruling, the composed plan is bound to the exact
    /// version the reading saw. A send-back that cannot be bound is not
    /// composed at all — a check that could not name a version has no
    /// authority to replace one, and the operator's Enter authorises the
    /// conflict that was read, never whatever stands there later.
    private func applyRoundTripCheck(
        _ reading: RoundTripDestinationReading,
        record: RoundTripRecord,
        inputs: RoundTripPlanInputs
    ) {
        let check = reading.check
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
        guard
            let versionGuard = RoundTrip.versionGuard(
                for: check,
                record: record,
                currentDigest: reading.currentDigest,
                token: Self.mintToken())
        else {
            echo.appendLine(
                "couldn't pin what stands at \(record.host):\(record.remotePath) — the edit stays"
                    + " local rather than replace a version nobody checked; save again to check again",
                kind: .failure)
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
                token: versionGuard.token,
                versionGuard: versionGuard)
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

    /// What one destination check read — the ruling and the facts behind it.
    struct RoundTripDestinationReading {
        /// The three-valued ruling.
        var check: ConflictCheck
        /// SHA-256 of what stands at the destination now, where readable.
        ///
        /// The version a send-back would be bound to.
        var currentDigest: Data?
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
    /// - Returns: The destination ruling and the digest it read.
    func checkRoundTripDestination(
        destination: Locus,
        subjects: [FileEntry],
        record: RoundTripRecord,
        into facts: inout PlanFacts
    ) async -> RoundTripDestinationReading {
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
            let currentDigest = await remoteDigest(of: remoteEntry, on: destination)
            return RoundTripDestinationReading(
                check: RoundTrip.evaluate(
                    record: record, current: remoteEntry, currentDigest: currentDigest),
                currentDigest: currentDigest)
        } catch {
            facts.collisions = nil
            note("couldn't check the destination — the edit stays local; save again to check again")
            return RoundTripDestinationReading(
                check: .unavailable(Self.describe(error)), currentDigest: nil)
        }
    }

    /// Reads the remote content digest of whatever stands there now.
    ///
    /// Read for every present entry, not only one whose metadata still
    /// matches: the digest is what a send-back binds itself to, and a
    /// conflict the operator may confirm needs a version to name as much
    /// as a clean check does. `nil` when there is nothing there or the
    /// bytes could not be read — either way nothing can be bound.
    private func remoteDigest(of current: FileEntry?, on destination: Locus) async -> Data? {
        guard let current else { return nil }
        let path = PaneModel.childPath(of: destination.directory, name: current.name)
        guard
            let bytes = try? await engine.listing(for: destination.host)
                .readFile(on: destination.host, path: path)
        else { return nil }
        return RoundTrip.digest(of: bytes)
    }
}
