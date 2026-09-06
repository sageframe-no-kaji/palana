// The Field's plan-authorizing half — a read that answers only what it
// read, generation-stamped, with every failed group cleared and named.
// Memory of another launch is for showing; refresh() is what a plan
// hears. Same playback idiom as FieldTests: the transcript is the wire.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Field — fresh reads")
struct FieldFreshReadTests {
    private static let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_751_500_800) }

    private static let gnuProbeStdout = """
        palana:kernel:Linux
        palana:flavor:GNU
        palana:zfs:zfs-2.2.2-0ubuntu9.1
        palana:rsync:rsync  version 3.2.7  protocol version 31
        """

    private static let bsdProbeStdout = """
        palana:kernel:Darwin
        palana:flavor:BSD
        palana:zfs:
        palana:rsync:openrsync: protocol version 29
        """

    private static let zfsListStdout =
        "palana\t/palana\tyes\npalana/tank\t/palana/tank\tyes\npalana/legacy\tlegacy\tno\n"

    private static let sudoProbe = "sudo -n true 2>/dev/null || sudo -n -l zfs mount"

    private static func entry(
        _ host: String,
        _ command: String,
        stdout: String = "",
        stderr: String = "",
        exit: Int32 = 0
    ) -> ConduitTranscript.Entry {
        ConduitTranscript.Entry(host: host, command: command, stdout: stdout, stderr: stderr, exit: exit)
    }

    private static func transcript() -> ConduitTranscript {
        ConduitTranscript(entries: [
            entry("jodo", CapabilityProbe.command, stdout: gnuProbeStdout),
            entry("jodo", ZFSTopology.listCommand, stdout: zfsListStdout),
            entry("jodo", MountTable.command(forKernel: "Linux"), stdout: "/dev/sda1 / ext4 rw,relatime 0 0"),
            entry("jodo", sudoProbe, exit: 0),
            entry("mac", CapabilityProbe.command, stdout: bsdProbeStdout),
            entry("mac", MountTable.command(forKernel: "Darwin"), stdout: "/dev/disk1s1 on / (apfs, local)"),
            entry("mac", sudoProbe, exit: 1),
            entry(
                "koan",
                CapabilityProbe.command,
                stderr: "ssh: connect to host koan port 22: Connection refused",
                exit: 255),
            // notopo: zfs present, but the topology read exits nonzero
            entry("notopo", CapabilityProbe.command, stdout: gnuProbeStdout),
            entry(
                "notopo",
                ZFSTopology.listCommand,
                stderr: "cannot open 'palana': permission denied",
                exit: 1),
            entry("notopo", MountTable.command(forKernel: "Linux"), stdout: "/dev/sda1 / ext4 rw 0 0"),
            entry("notopo", sudoProbe, exit: 0),
        ])
    }

    private static func freshCache() -> FieldCache {
        FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-field-fresh-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
    }

    private static func makeField(cache: FieldCache = freshCache()) -> Field {
        Field(
            conduit: RecordedConduit(transcript: transcript()),
            hosts: ["jodo", "mac", "koan", "notopo"],
            cache: cache,
            now: clock
        )
    }

    @Test("a nonzero topology exit clears the prior topology fact and records why")
    func failedTopologyReadClearsMemory() async throws {
        let cache = Self.freshCache()
        let priorTopology = [ZFSDataset(name: "palana/old", mountpoint: "/old", mounted: true)]
        let prior = HostFacts(
            zfsTopology: Dated(value: priorTopology, discoveredAt: Date(timeIntervalSince1970: 1)))
        try cache.save(["notopo": prior])
        let field = Self.makeField(cache: cache)
        #expect(
            await field.datasetContaining(path: "/old/x", on: "notopo")?.name == "palana/old",
            "before the read, memory still maps the path")
        let facts = try await field.discover("notopo")
        #expect(facts.zfsTopology == nil, "the older dataset list is gone, not retained")
        #expect(facts.zfsTopologyUnavailable?.value.exitStatus == 1)
        #expect(facts.zfsTopologyUnavailable?.value.detail == "cannot open 'palana': permission denied")
        #expect(facts.capability?.value.zfs != nil, "the capability fact itself is fresh")
        #expect(await field.datasetContaining(path: "/old/x", on: "notopo") == nil)
        #expect(
            CapabilityRequirement.zfs.evaluate(host: "notopo", facts: facts) == .unmet("notopo has no zfs"),
            "no topology means no zfs verb — never a verb over the old list")
    }

    @Test("a successful read after a failed one clears the recorded failure")
    func successfulReadClearsFailure() async throws {
        let cache = Self.freshCache()
        let failure = FactReadFailure(exitStatus: 1, detail: "earlier")
        let prior = HostFacts(
            zfsTopologyUnavailable: Dated(value: failure, discoveredAt: Date(timeIntervalSince1970: 1)),
            mountsUnavailable: Dated(value: failure, discoveredAt: Date(timeIntervalSince1970: 1)))
        try cache.save(["jodo": prior])
        let facts = try await Self.makeField(cache: cache).discover("jodo")
        #expect(facts.zfsTopology?.value.count == 3)
        #expect(facts.zfsTopologyUnavailable == nil)
        #expect(facts.mounts != nil)
        #expect(facts.mountsUnavailable == nil)
    }

    @Test("a host that lost zfs loses its remembered topology")
    func zfsGoneClearsTopology() async throws {
        let cache = Self.freshCache()
        let prior = HostFacts(
            zfsTopology: Dated(
                value: [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)],
                discoveredAt: Date(timeIntervalSince1970: 1)))
        try cache.save(["mac": prior])
        let facts = try await Self.makeField(cache: cache).discover("mac")
        #expect(facts.zfsTopology == nil)
        #expect(facts.zfsTopologyUnavailable == nil, "no zfs is an absence, not a failure")
    }

    @Test("every read stamps a rising generation; cache-loaded facts carry none")
    func generationsRise() async throws {
        let cache = Self.freshCache()
        let field = Self.makeField(cache: cache)
        #expect(await field.generation(of: "jodo") == nil)
        let first = try await field.discover("jodo")
        #expect(first.generation == 1)
        let second = try await field.discover("mac")
        #expect(second.generation == 2)
        let third = try await field.discover("jodo")
        #expect(third.generation == 3)
        #expect(await field.generation(of: "jodo") == 3)
        #expect(await field.generation(of: "mac") == 2)

        let revisit = Field(
            conduit: RecordedConduit(transcript: ConduitTranscript()),
            hosts: ["jodo"],
            cache: cache,
            now: Self.clock
        )
        #expect(await revisit.facts(for: "jodo")?.capability != nil, "the facts came back")
        #expect(await revisit.generation(of: "jodo") == nil, "but not as anything this process read")
    }

    @Test("a door failure leaves the remembered generation alone — unreachable stamps no read")
    func unreachableStampsNoGeneration() async throws {
        let field = Self.makeField()
        let facts = try await field.discover("koan")
        #expect(facts.generation == nil)
        #expect(await field.generation(of: "koan") == nil)
    }

    @Test("refresh answers a reached host with generation-stamped facts")
    func refreshAnswersFresh() async throws {
        let field = Self.makeField()
        let facts = try await field.refresh("jodo")
        #expect(facts.generation == 1)
        #expect(facts.reachability?.value == .reachable)
        #expect(facts.zfsTopology?.value.count == 3)
        #expect(await field.facts(for: "jodo") == facts, "memory carries the same read")
    }

    @Test("refresh throws for an unreachable host instead of handing back remembered facts")
    func refreshRefusesUnreachable() async throws {
        let cache = Self.freshCache()
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil)
        let visited = HostFacts(
            capability: Dated(value: capability, discoveredAt: Date(timeIntervalSince1970: 1)),
            zfsTopology: Dated(
                value: [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)],
                discoveredAt: Date(timeIntervalSince1970: 1)))
        try cache.save(["koan": visited])
        let field = Self.makeField(cache: cache)
        await #expect(throws: FieldError.self) {
            try await field.refresh("koan")
        }
        do {
            _ = try await field.refresh("koan")
            Issue.record("refresh answered an unreachable host")
        } catch let error as FieldError {
            guard case .unreachable(let host, let detail) = error else {
                Issue.record("unexpected \(error)")
                return
            }
            #expect(host == "koan")
            #expect(detail.contains("unreachable"))
            #expect("\(error)".hasPrefix("koan could not be read for this plan — unreachable"))
        }
        #expect(
            await field.facts(for: "koan")?.zfsTopology?.value.first?.name == "tank",
            "memory still shows the last visit — for showing, never for a plan")
    }

    @Test("snapshotNames reads short names oldest first and remembers nothing")
    func snapshotNamesRead() async throws {
        let command = "zfs list -H -t snapshot -o name -s creation -- palana/tank"
        let entries = [
            Self.entry("jodo", command, stdout: "palana/tank@first\npalana/tank@second\nnoise\n"),
            Self.entry(
                "jodo",
                "zfs list -H -t snapshot -o name -s creation -- 'palana/no such'",
                stderr: "cannot open",
                exit: 1),
            Self.entry(
                "koan",
                command,
                stderr: "ssh: connect to host koan port 22: Connection refused",
                exit: 255),
        ]
        let field = Field(
            conduit: RecordedConduit(transcript: ConduitTranscript(entries: entries)),
            hosts: ["jodo", "koan"],
            cache: Self.freshCache(),
            now: Self.clock
        )
        #expect(try await field.snapshotNames(of: "palana/tank", on: "jodo") == ["first", "second"])
        #expect(try await field.snapshotNames(of: "palana/no such", on: "jodo").isEmpty)
        await #expect(throws: ConduitError.self) {
            try await field.snapshotNames(of: "palana/tank", on: "koan")
        }
        #expect(await field.allFacts().isEmpty, "a snapshot read is not a fact")
    }
}
