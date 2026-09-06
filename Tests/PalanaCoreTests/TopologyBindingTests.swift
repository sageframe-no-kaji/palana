// The topology binding's battery — a plan records the datasets it stood
// on, and a fresh read either confirms every one of them exactly or
// refuses. The Field half reproduces the moved mountpoint: the same
// path answered by a different dataset one read later.

import Foundation
import Testing

@testable import PalanaCore

private let dataAtData = ZFSDataset(name: "tank/data", mountpoint: "/data", mounted: true)
private let mediaAtMedia = ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true)
private let backupAtBackup = ZFSDataset(name: "tank/backup", mountpoint: "/backup", mounted: true)

private func facts(_ datasets: [ZFSDataset]?, generation: Int? = 2, failure: String? = nil) -> HostFacts {
    let stamp = Date(timeIntervalSince1970: 1)
    return HostFacts(
        zfsTopology: datasets.map { Dated(value: $0, discoveredAt: stamp) },
        zfsTopologyUnavailable: failure.map {
            Dated(value: FactReadFailure(exitStatus: 1, detail: $0), discoveredAt: stamp)
        },
        generation: generation)
}

private func mutationPlan(bound: [TopologyBinding.Bound]) -> Plan {
    Plan(
        operation: .zfs,
        classification: .zfsMutation,
        entries: [],
        totalSize: 0,
        source: Locus(host: "jodo", directory: "tank/data"),
        destination: nil,
        transport: .local,
        steps: [PlanStep(runsOn: .host("jodo"), command: "zfs destroy tank/data", role: .delete)],
        topologyBinding: TopologyBinding(bound: bound))
}

private func sendPlan() -> Plan {
    let media = FileEntry(
        nameData: Data("media".utf8),
        kind: .directory,
        size: 0,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "755",
        owner: "op",
        group: "op")
    return Plan(
        operation: .move,
        classification: .crossHostTransfer,
        entries: [media],
        totalSize: 0,
        source: Locus(host: "jodo", directory: "/tank"),
        destination: Locus(host: "koan", directory: "/backup"),
        transport: .zfsSendReceiveProxied,
        steps: [],
        receivedDataset: "tank/backup/media",
        topologyBinding: TopologyBinding(bound: [
            TopologyBinding.Bound(host: "jodo", role: .selection, dataset: mediaAtMedia, generation: 1),
            TopologyBinding.Bound(host: "koan", role: .destination, dataset: backupAtBackup, generation: 1),
        ]))
}

@Suite("TopologyBinding — confirmation against a fresh read")
struct TopologyBindingConfirmTests {
    private let target = TopologyBinding.Bound(host: "jodo", role: .target, dataset: dataAtData, generation: 1)

    @Test("a plan without a binding confirms trivially — nothing to compare")
    func unboundConfirms() throws {
        var plan = mutationPlan(bound: [])
        plan.topologyBinding = nil
        try plan.confirmTopology(fresh: [:])
    }

    @Test("the same dataset, name mountpoint and mounted alike, confirms")
    func identicalConfirms() throws {
        try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": facts([dataAtData])])
    }

    @Test("a host with no fresh read refuses as unavailable")
    func missingHostRefuses() {
        #expect(throws: TopologyBindingError.unavailable(host: "jodo", detail: "no read")) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: [:])
        }
    }

    @Test("a fresh read whose topology failed refuses with the read's own reason")
    func failedTopologyRefuses() {
        let fresh = facts(nil, failure: "cannot open 'tank': permission denied")
        #expect(
            throws: TopologyBindingError.unavailable(host: "jodo", detail: "cannot open 'tank': permission denied")
        ) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": fresh])
        }
    }

    @Test("a fresh read with no topology and no reason still refuses")
    func absentTopologyRefuses() {
        #expect(throws: TopologyBindingError.unavailable(host: "jodo", detail: "no zfs topology")) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": facts(nil)])
        }
    }

    @Test("a read no newer than the bound one refuses — cached facts are not a re-read")
    func staleGenerationRefuses() {
        #expect(throws: TopologyBindingError.notFresh(host: "jodo", generation: 1)) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": facts([dataAtData], generation: 1)])
        }
        #expect(throws: TopologyBindingError.notFresh(host: "jodo", generation: 1)) {
            try mutationPlan(bound: [target]).confirmTopology(
                fresh: ["jodo": facts([dataAtData], generation: nil)])
        }
    }

    @Test("a target dataset that vanished refuses as gone")
    func targetGoneRefuses() {
        #expect(throws: TopologyBindingError.gone(host: "jodo", dataset: "tank/data", role: .target)) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": facts([mediaAtMedia])])
        }
    }

    @Test("a target whose mountpoint moved refuses as changed, naming both paths")
    func targetMovedRefuses() {
        let moved = ZFSDataset(name: "tank/data", mountpoint: "/elsewhere", mounted: true)
        #expect(throws: TopologyBindingError.changed(host: "jodo", was: dataAtData, now: moved)) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": facts([moved])])
        }
    }

    @Test("a target that was unmounted since the plan refuses as changed")
    func targetUnmountedRefuses() {
        let unmounted = ZFSDataset(name: "tank/data", mountpoint: "/data", mounted: false)
        #expect(throws: TopologyBindingError.changed(host: "jodo", was: dataAtData, now: unmounted)) {
            try mutationPlan(bound: [target]).confirmTopology(fresh: ["jodo": facts([unmounted])])
        }
    }

    @Test("a send plan confirms when both ends still answer the selection and destination")
    func sendPlanConfirms() throws {
        try sendPlan().confirmTopology(
            fresh: ["jodo": facts([mediaAtMedia]), "koan": facts([backupAtBackup])])
    }

    @Test("the selection is re-derived from the path — a dataset moved off it is gone")
    func selectionMovedRefuses() {
        let moved = ZFSDataset(name: "tank/media", mountpoint: "/tank/archive", mounted: true)
        #expect(throws: TopologyBindingError.gone(host: "jodo", dataset: "tank/media", role: .selection)) {
            try sendPlan().confirmTopology(
                fresh: ["jodo": facts([moved]), "koan": facts([backupAtBackup])])
        }
    }

    @Test("another dataset now standing at the selection's path refuses as changed")
    func selectionReplacedRefuses() {
        let impostor = ZFSDataset(name: "tank/other", mountpoint: "/tank/media", mounted: true)
        #expect(throws: TopologyBindingError.changed(host: "jodo", was: mediaAtMedia, now: impostor)) {
            try sendPlan().confirmTopology(
                fresh: ["jodo": facts([impostor]), "koan": facts([backupAtBackup])])
        }
    }

    @Test("the destination is re-derived from its directory — a different holder refuses")
    func destinationReplacedRefuses() {
        let other = ZFSDataset(name: "tank/backup2", mountpoint: "/backup", mounted: true)
        #expect(throws: TopologyBindingError.changed(host: "koan", was: backupAtBackup, now: other)) {
            try sendPlan().confirmTopology(
                fresh: ["jodo": facts([mediaAtMedia]), "koan": facts([other])])
        }
        #expect(throws: TopologyBindingError.gone(host: "koan", dataset: "tank/backup", role: .destination)) {
            try sendPlan().confirmTopology(
                fresh: ["jodo": facts([mediaAtMedia]), "koan": facts([])])
        }
    }

    @Test("a destination role on a plan with no destination is gone, never a crash")
    func destinationRoleWithoutDestination() {
        let bound = TopologyBinding.Bound(host: "jodo", role: .destination, dataset: dataAtData, generation: 1)
        #expect(throws: TopologyBindingError.gone(host: "jodo", dataset: "tank/data", role: .destination)) {
            try mutationPlan(bound: [bound]).confirmTopology(fresh: ["jodo": facts([dataAtData])])
        }
    }

    @Test("hosts lists each bound host once, in first-appearance order")
    func hostsDeduplicate() throws {
        let binding = try #require(sendPlan().topologyBinding)
        #expect(binding.hosts == ["jodo", "koan"])
        let doubled = TopologyBinding(bound: binding.bound + binding.bound)
        #expect(doubled.hosts == ["jodo", "koan"])
    }
}

@Suite("TopologyBinding — words and wire shape")
struct TopologyBindingShapeTests {
    @Test("every refusal is one plain sentence that says nothing ran")
    func descriptions() {
        let moved = ZFSDataset(name: "tank/data", mountpoint: "/elsewhere", mounted: false)
        #expect(
            "\(TopologyBindingError.unavailable(host: "jodo", detail: "refused"))"
                == "the zfs topology on jodo could not be re-read — nothing ran: refused")
        #expect(
            "\(TopologyBindingError.notFresh(host: "jodo", generation: 4))"
                == "the re-read of jodo was not newer than read 4 — nothing ran")
        #expect(
            "\(TopologyBindingError.gone(host: "jodo", dataset: "tank/data", role: .target))"
                == "tank/data on jodo no longer exists — the topology changed since the plan was read; "
                + "nothing ran, compose it again")
        #expect(
            "\(TopologyBindingError.gone(host: "jodo", dataset: "tank/media", role: .selection))"
                .contains("no longer is the whole dataset the selection stands on"))
        #expect(
            "\(TopologyBindingError.gone(host: "koan", dataset: "tank/backup", role: .destination))"
                .contains("no longer holds the destination directory"))
        #expect(
            "\(TopologyBindingError.changed(host: "jodo", was: dataAtData, now: moved))"
                == "tank/data on jodo changed since the plan was read — mountpoint /data → /elsewhere, "
                + "now unmounted; nothing ran, compose it again")
        let remounted = ZFSDataset(name: "tank/data", mountpoint: "/data", mounted: false)
        #expect(
            "\(TopologyBindingError.changed(host: "jodo", was: remounted, now: dataAtData))"
                .contains("— now mounted;"))
    }

    @Test("a bound plan round-trips JSON whole")
    func codableRoundTrip() throws {
        let plan = sendPlan()
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded == plan)
        #expect(decoded.topologyBinding?.bound.count == 2)
    }

    @Test("a plan written before the binding existed decodes with none — the key is optional")
    func legacyPlanDecodes() throws {
        var plan = mutationPlan(bound: [])
        plan.topologyBinding = nil
        let data = try JSONEncoder().encode(plan)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("topologyBinding"), "nil never writes the key")
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded.topologyBinding == nil)
        #expect(decoded == plan)
    }
}

@Suite("TopologyBinding — the moved mountpoint, through the Field")
struct TopologyBindingFieldTests {
    private static let probe = """
        palana:kernel:Linux
        palana:flavor:GNU
        palana:zfs:zfs-2.2.2
        palana:rsync:
        """

    /// One read maps /data to tank/data; the next maps it to tank/new
    /// with tank/data moved aside — the review's scenario.
    private static func field() -> Field {
        let conduit = SequencedConduit()
        conduit.enqueue("jodo", CapabilityProbe.command, [.init(stdout: probe), .init(stdout: probe)])
        conduit.enqueue(
            "jodo",
            ZFSTopology.listCommand,
            [
                .init(stdout: "tank\t/tank\tyes\ntank/data\t/data\tyes\n"),
                .init(stdout: "tank\t/tank\tyes\ntank/data\t/aside\tyes\ntank/new\t/data\tyes\n"),
            ])
        conduit.enqueue("jodo", MountTable.command(forKernel: "Linux"), [.init(stdout: "/dev/sda1 / ext4 rw 0 0")])
        conduit.enqueue("jodo", "sudo -n true 2>/dev/null || sudo -n -l zfs mount", [.init(stdout: "")])
        let cache = FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-binding-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
        return Field(conduit: conduit, hosts: ["jodo"], cache: cache)
    }

    @Test("a plan bound to the first read refuses after the path changed hands")
    func movedMountpointRefuses() async throws {
        let field = Self.field()
        let first = try await field.refresh("jodo")
        let chosen = try #require(ZFSTopology.datasetContaining("/data/photos", in: first.zfsTopology?.value ?? []))
        #expect(chosen == dataAtData)
        let plan = mutationPlan(bound: [
            TopologyBinding.Bound(
                host: "jodo", role: .target, dataset: chosen, generation: try #require(first.generation))
        ])
        // Memory alone would still confirm — it is the read the plan was bound to.
        #expect(throws: TopologyBindingError.notFresh(host: "jodo", generation: 1)) {
            try plan.confirmTopology(fresh: ["jodo": first])
        }
        let second = try await field.refresh("jodo")
        let moved = ZFSDataset(name: "tank/data", mountpoint: "/aside", mounted: true)
        #expect(throws: TopologyBindingError.changed(host: "jodo", was: dataAtData, now: moved)) {
            try plan.confirmTopology(fresh: ["jodo": second])
        }
        #expect(
            ZFSTopology.datasetContaining("/data/photos", in: second.zfsTopology?.value ?? [])?.name
                == "tank/new",
            "the path the operator stood on now belongs to another dataset")
    }
}

/// A conduit that answers each `(host, command)` from a queue, in order.
///
/// The last answer repeats; a command with no queue throws
/// ``UnrecordedCommand`` like playback does.
final class SequencedConduit: Conduit, @unchecked Sendable {
    struct Answer {
        var stdout = ""
        var stderr = ""
        var exit: Int32 = 0
    }

    private let lock = NSLock()
    private var queues: [String: [Answer]] = [:]

    func enqueue(_ host: String, _ command: String, _ answers: [Answer]) {
        lock.withLock { queues["\(host)\n\(command)"] = answers }
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        let answer: Answer? = lock.withLock {
            let key = "\(host)\n\(command)"
            guard var queue = queues[key], !queue.isEmpty else { return nil }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            queues[key] = queue
            return next
        }
        guard let answer else { throw UnrecordedCommand(host: host, command: command) }
        return RunningCommand(
            replayingStdout: Data(answer.stdout.utf8),
            stderr: Data(answer.stderr.utf8),
            exitStatus: answer.exit)
    }

    func close(host: String) async {}

    func closeAll() async {}
}
