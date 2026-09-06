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
    /// this machine's answer decides whether progress2 rides. The local
    /// probe searches the prefixes a Finder-launched app cannot see and
    /// names the rsync it found, so the plan names what will run.
    func localCapability() async -> HostCapability? {
        if let probedLocalCapability { return probedLocalCapability }
        guard
            let result = try? await engine.localConduit
                .run(on: PalanaCore.localHostName, CapabilityProbe.localCommand).collect(),
            let capability = try? CapabilityProbe.parse(result.stdoutText)
        else { return nil }
        probedLocalCapability = capability
        return capability
    }

    /// The host's facts, read on the wire for this plan.
    ///
    /// Memory is for showing; a plan that routes on capability,
    /// topology, mounts, or sudo reads them now. An unreachable host
    /// refuses the plan here rather than composing over a remembered
    /// map. nil for this Mac, which is never discovered.
    func ensureFacts(_ host: String) async throws -> HostFacts? {
        guard !engine.isLocal(host) else { return nil }
        note("reading \(host)…")
        return try await engine.field.refresh(host)
    }

    /// Binds a zfs-transport plan to the datasets it routes on — the
    /// selection's whole dataset at the source, the containing dataset
    /// at the destination — each with the read that produced it.
    ///
    /// Plans on any other transport come back untouched: nothing in
    /// them is decided by topology. A zfs transport whose facts cannot
    /// be bound — a topology with no read behind it — refuses, since an
    /// unbound zfs plan would run unconfirmed.
    func bindTopology(
        of plan: Plan, sourceFacts: HostFacts?, destinationFacts: HostFacts?
    ) throws -> Plan {
        guard plan.transport == .zfsSendReceiveForwarded || plan.transport == .zfsSendReceiveProxied
        else { return plan }
        guard let destination = plan.destination,
            let sourceTopology = sourceFacts?.zfsTopology?.value,
            let sourceGeneration = sourceFacts?.generation,
            let destinationTopology = destinationFacts?.zfsTopology?.value,
            let destinationGeneration = destinationFacts?.generation,
            let selected = ZFSTopology.wholeDatasetSelection(
                entries: plan.entries, sourceDirectory: plan.source.directory, datasets: sourceTopology),
            let receiving = ZFSTopology.datasetContaining(destination.directory, in: destinationTopology)
        else {
            throw TopologyBindingError.unavailable(
                host: plan.source.host, detail: "the zfs plan's topology carries no read to bind to")
        }
        var bound = plan
        bound.topologyBinding = TopologyBinding(bound: [
            TopologyBinding.Bound(
                host: plan.source.host,
                role: .selection,
                dataset: selected,
                generation: sourceGeneration),
            TopologyBinding.Bound(
                host: destination.host,
                role: .destination,
                dataset: receiving,
                generation: destinationGeneration),
        ])
        return bound
    }

    /// Where each end LIVES: containing dataset, whole-dataset selection,
    /// and the any-filesystem mount target (ho-9.3's fact).
    ///
    /// The mount proof lets a same-host move be a rename even off ZFS —
    /// on this Mac too, whose table is read now rather than remembered
    /// (``placementMounts(for:remembered:)``). Extracted from `gather`
    /// for the body-length budget; moved here from OperationModel.swift
    /// for the file-length budget.
    func addPlacementFacts(
        _ facts: inout PlanFacts,
        source: (locus: Locus, facts: HostFacts?),
        destination: (locus: Locus?, facts: HostFacts?),
        subjects: [FileEntry]
    ) async {
        if let topology = source.facts?.zfsTopology?.value {
            facts.sourceDataset = ZFSTopology.datasetContaining(
                source.locus.directory, in: topology)
            facts.selectionWholeDataset = ZFSTopology.wholeDatasetSelection(
                entries: subjects, sourceDirectory: source.locus.directory, datasets: topology)
        }
        if let dest = destination.locus, let topology = destination.facts?.zfsTopology?.value {
            facts.destinationDataset = ZFSTopology.datasetContaining(
                dest.directory, in: topology)
        }
        if let mounts = await placementMounts(for: source.locus, remembered: source.facts) {
            facts.sourceMountTarget = MountTable.mountContaining(
                source.locus.directory, in: mounts)
        }
        if let dest = destination.locus {
            let mounts = await placementMounts(for: dest, remembered: destination.facts)
            facts.destinationMountTarget = mounts.flatMap {
                MountTable.mountContaining(dest.directory, in: $0)
            }
        }
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
