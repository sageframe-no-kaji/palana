// The Field's unit battery — discovery over RecordedConduit playback, the
// cache as memory across instances, and the no-wire guarantees. The
// transcript IS the network here; an UnrecordedCommand thrown is proof a
// method touched wire it promised not to.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Field")
struct FieldTests {
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

    private static func entry(
        _ host: String,
        _ command: String,
        stdout: String = "",
        stderr: String = "",
        exit: Int32 = 0
    ) -> ConduitTranscript.Entry {
        ConduitTranscript.Entry(
            host: host,
            command: command,
            stdout: stdout,
            stderr: stderr,
            exit: exit)
    }

    private static func transcript() -> ConduitTranscript {
        ConduitTranscript(entries: [
            entry("jodo", CapabilityProbe.command, stdout: gnuProbeStdout),
            entry("jodo", ZFSTopology.listCommand, stdout: zfsListStdout),
            entry("mac", CapabilityProbe.command, stdout: bsdProbeStdout),
            entry(
                "koan",
                CapabilityProbe.command,
                stderr: "ssh: connect to host koan port 22: Connection refused",
                exit: 255),
            entry("garbled", CapabilityProbe.command, stdout: "not a probe answer"),
        ])
    }

    private static func freshCache() -> FieldCache {
        FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-field-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
    }

    private static func makeField(cache: FieldCache = freshCache()) -> Field {
        Field(
            conduit: RecordedConduit(transcript: transcript()),
            hosts: ["jodo", "mac", "koan"],
            cache: cache,
            now: clock
        )
    }

    @Test("hosts() answers from the parse, never the wire")
    func hostsNeverTouchWire() async {
        // An empty transcript means ANY wire call throws UnrecordedCommand.
        let field = Field(
            conduit: RecordedConduit(transcript: ConduitTranscript()),
            sshConfigText: "Host jodo\nHost *\nHost koan",
            cache: Self.freshCache(),
            now: Self.clock
        )
        #expect(await field.hosts() == ["jodo", "koan"])
        #expect(await field.facts(for: "jodo") == nil)
        #expect(await field.datasetContaining(path: "/anything", on: "jodo") == nil)
    }

    @Test("discovery records reachability, capability, and topology, timestamped")
    func discoverFullHouse() async throws {
        let field = Self.makeField()
        let facts = try await field.discover("jodo")
        #expect(facts.reachability?.value == .reachable)
        #expect(facts.reachability?.discoveredAt == Self.clock())
        #expect(facts.capability?.value.flavor == .gnu)
        #expect(facts.capability?.value.zfsVersion == "2.2.2")
        #expect(facts.zfsTopology?.value.count == 3)
        #expect(await field.facts(for: "jodo") == facts)
    }

    @Test("a host without zfs gets no topology read — the transcript proves it")
    func noZfsNoTopologyRead() async throws {
        // The transcript carries no zfs list entry for "mac"; if discover
        // asked, UnrecordedCommand would surface here.
        let facts = try await Self.makeField().discover("mac")
        #expect(facts.capability?.value.zfs == nil)
        #expect(facts.zfsTopology == nil)
    }

    @Test("a door-level failure records as unreachable, earlier facts remembered")
    func unreachableIsAFact() async throws {
        let cache = Self.freshCache()
        // First visit: koan was reachable once, with facts worth keeping.
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: nil)
        let visited = HostFacts(
            capability: Dated(value: capability, discoveredAt: Date(timeIntervalSince1970: 1)))
        try cache.save(["koan": visited])
        let field = Self.makeField(cache: cache)
        let facts = try await field.discover("koan")
        guard case .unreachable(let detail) = facts.reachability?.value else {
            Issue.record("expected unreachable, got \(String(describing: facts.reachability))")
            return
        }
        #expect(detail.contains("unreachable"))
        #expect(facts.capability?.value == capability, "memory of the last visit survives")
    }

    @Test("a reached host answering garbage throws — not a fact, a surprise")
    func garbledProbeThrows() async {
        let field = Field(
            conduit: RecordedConduit(transcript: Self.transcript()),
            hosts: ["garbled"],
            cache: Self.freshCache(),
            now: Self.clock
        )
        await #expect(throws: ProbeParseError.self) {
            try await field.discover("garbled")
        }
    }

    @Test("dataset boundaries answer from cached topology")
    func boundaryFromCache() async throws {
        let field = Self.makeField()
        try await field.discover("jodo")
        let hit = await field.datasetContaining(path: "/palana/tank/media/x.raw", on: "jodo")
        #expect(hit?.name == "palana/tank")
        #expect(await field.datasetContaining(path: "/palana/tank", on: "mac") == nil)
    }

    @Test("memory persists across Field instances through the cache file")
    func memoryPersists() async throws {
        let cache = Self.freshCache()
        try await Self.makeField(cache: cache).discover("jodo")

        // A new Field over an empty transcript: facts answer, no wire.
        let revisit = Field(
            conduit: RecordedConduit(transcript: ConduitTranscript()),
            hosts: ["jodo"],
            cache: cache,
            now: Self.clock
        )
        #expect(await revisit.facts(for: "jodo")?.capability?.value.kernel == "Linux")
        let hit = await revisit.datasetContaining(path: "/palana/tank/x", on: "jodo")
        #expect(hit?.name == "palana/tank")
    }

    @Test("the cache survives deletion — the Field rebuilds by discovering")
    func cacheDeletionSurvivable() async throws {
        let cache = Self.freshCache()
        try await Self.makeField(cache: cache).discover("jodo")
        try FileManager.default.removeItem(at: cache.url)

        let rebuilt = Self.makeField(cache: cache)
        #expect(await rebuilt.facts(for: "jodo") == nil, "deleted memory is gone memory")
        let facts = try await rebuilt.discover("jodo")
        #expect(facts.capability?.value.kernel == "Linux")
        #expect(FileManager.default.fileExists(atPath: cache.url.path), "rediscovery rewrites")
    }

    @Test("every door failure describes as a short human line")
    func unreachableDetails() {
        #expect(Field.describe(.launchFailed("no binary")) == "ssh could not launch: no binary")
        #expect(Field.describe(.hostUnreachable("refused")) == "unreachable: refused")
        #expect(
            Field.describe(.authenticationDenied("bad key")) == "authentication denied: bad key")
        #expect(
            Field.describe(.hostKeyVerificationFailed("changed"))
                == "host key verification failed: changed")
        #expect(Field.describe(.connectionLost("reset")) == "connection lost: reset")
        #expect(
            Field.describe(.sshFailure(exitStatus: 255, stderr: "odd\nlast line"))
                == "ssh failed (255): last line")
    }

    @Test("a cache that cannot write downgrades to memory-only, discovery unharmed")
    func unwritableCacheTolerated() async throws {
        let cache = FieldCache(url: URL(fileURLWithPath: "/dev/null/impossible/cache.json"))
        let field = Self.makeField(cache: cache)
        let facts = try await field.discover("jodo")
        #expect(facts.reachability?.value == .reachable)
        #expect(await field.facts(for: "jodo") == facts)
    }
}
