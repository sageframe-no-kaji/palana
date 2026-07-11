// OperationModel+Gather — the fact-gathering helpers used by `gather()`:
// forwarding, this Mac's own capability, remembered-or-discovered facts,
// and the userland flavor. Moved out of OperationModel.swift for the
// type_body_length / file_length budget (ho-11 made room by relocating
// this self-contained extension, alongside the +Collisions, +RoundTrip,
// +ZFS, +Touch, and +DragDrop precedent).

import Foundation
import PalanaCore

extension OperationModel {
    /// The forwarding question exists only between two distinct
    /// remotes — this machine at either end authenticates itself.
    func needsForwardingFact(source: Locus, destination: Locus) -> Bool {
        destination.host != source.host
            && !engine.isLocal(source.host)
            && !engine.isLocal(destination.host)
    }

    /// This Mac's own capability — probed once per session, in memory.
    ///
    /// The engine flags rsync commands by the running side's rsync;
    /// this machine's answer decides whether progress2 rides.
    func localCapability() async -> HostCapability? {
        if let probedLocalCapability { return probedLocalCapability }
        guard
            let result = try? await engine.localConduit
                .run(on: PalanaCore.localHostName, CapabilityProbe.command).collect(),
            let capability = try? CapabilityProbe.parse(result.stdoutText)
        else { return nil }
        probedLocalCapability = capability
        return capability
    }

    /// Remembered facts, or one discovery when the host was never met.
    func ensureFacts(_ host: String) async throws -> HostFacts? {
        guard !engine.isLocal(host) else { return nil }
        if let facts = await engine.field.facts(for: host) { return facts }
        note("discovering \(host)…")
        return try await engine.field.discover(host)
    }

    /// The flavor fact — this Mac is BSD, remotes answer from memory or
    /// one discovery round trip.
    func resolveFlavor(_ host: String) async throws -> UserlandFlavor {
        if engine.isLocal(host) { return .bsd }
        if let flavor = await engine.field.facts(for: host)?.capability?.value.flavor {
            return flavor
        }
        let facts = try await engine.field.discover(host)
        guard let flavor = facts.capability?.value.flavor else {
            throw ListingError.listingFailed(exitStatus: -1, stderr: "no capability fact")
        }
        return flavor
    }
}
