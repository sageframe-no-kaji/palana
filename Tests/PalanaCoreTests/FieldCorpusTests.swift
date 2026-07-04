// The recorded corpus replayed — real fixture truth, committed, running
// in every environment whether or not a fixture stands. If a parser
// change breaks against these transcripts, it broke against reality.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Field corpus replay")
struct FieldCorpusTests {
    private static func corpus(_ name: String) throws -> ConduitTranscript {
        try ConduitTranscript(
            contentsOf: SSHFixture.repoRoot.appendingPathComponent(
                "Tests/PalanaCoreTests/Fixtures/\(name)"))
    }

    @Test("the container's recorded probe parses: Linux, no zfs, rsync since ho-06.1")
    func containerProbe() throws {
        let transcript = try Self.corpus("probe-container.json")
        let entry = try #require(
            transcript.entries.first { $0.command == CapabilityProbe.command })
        let capability = try CapabilityProbe.parse(entry.stdout)
        #expect(capability.kernel == "Linux")
        #expect(capability.zfs == nil)
        // ho-06.1 gave the fixture rsync; the ho-07.5 recapture recorded
        // that truth. Version drifts with the container — presence is
        // the fact.
        #expect(capability.rsyncVersion != nil)
    }

    @Test("the pool VM's recorded probe parses: GNU, zfs and rsync versioned")
    func poolProbe() throws {
        let transcript = try Self.corpus("zfs-pool.json")
        let entry = try #require(
            transcript.entries.first { $0.command == CapabilityProbe.command })
        let capability = try CapabilityProbe.parse(entry.stdout)
        #expect(capability.kernel == "Linux")
        #expect(capability.flavor == .gnu)
        #expect(capability.zfsVersion?.hasPrefix("2.") == true)
        #expect(capability.rsyncVersion?.hasPrefix("3.") == true)
    }

    @Test("the recorded pool topology parses and resolves boundaries")
    func poolTopology() throws {
        let transcript = try Self.corpus("zfs-pool.json")
        let entry = try #require(
            transcript.entries.first { $0.command == ZFSTopology.listCommand })
        let datasets = ZFSTopology.parse(entry.stdout)

        let names = Set(datasets.map(\.name))
        #expect(
            names.isSuperset(of: [
                "palana", "palana/tank/media/photos", "palana/svc/baserow",
                "palana/legacy", "palana/detached",
            ]))

        // The recorded truth carries every shape the resolver cares about.
        let legacy = try #require(datasets.first { $0.name == "palana/legacy" })
        #expect(legacy.mountpoint == "legacy")
        #expect(!legacy.mounted)
        let detached = try #require(datasets.first { $0.name == "palana/detached" })
        #expect(!detached.mounted)

        let nested = ZFSTopology.datasetContaining("/palana/tank/media/photos/x", in: datasets)
        #expect(nested?.name == "palana/tank/media/photos")
        let outOfTree = ZFSTopology.datasetContaining("/opt/services/baserow/db", in: datasets)
        #expect(outOfTree?.name == "palana/svc/baserow")
        #expect(ZFSTopology.datasetContaining("/palana/detached/x", in: datasets)?.name == "palana")
    }

    private static let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_751_500_800) }

    @Test("the whole Field runs over the recorded pool — discovery with no wire at all")
    func fieldOverRecordedPool() async throws {
        let transcript = try Self.corpus("zfs-pool.json")
        let host = try #require(transcript.entries.first?.host)
        let field = Field(
            conduit: RecordedConduit(transcript: transcript),
            hosts: [host],
            cache: FieldCache(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("palana-corpus-\(UUID().uuidString)")
                    .appendingPathComponent("field-cache.json")),
            now: Self.clock
        )
        let facts = try await field.discover(host)
        #expect(facts.reachability?.value == .reachable)
        #expect(facts.zfsTopology?.value.isEmpty == false)
        let hit = await field.datasetContaining(path: "/palana/tank/media/img.raw", on: host)
        #expect(hit?.name == "palana/tank/media")
    }
}
