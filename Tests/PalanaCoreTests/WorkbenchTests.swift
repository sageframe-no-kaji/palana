// WorkbenchTests — the Workbench boundary and its first read-only tool.
// Inline transcripts, no wire contact. CapabilityRequirement.evaluate is a
// pure function tested directly; the integration suite seeds a Field via
// a recorded discovery run and drives the full Workbench.availability path.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Shared test plumbing

private enum WorkbenchFixtures {
    static let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_752_000_000) }
    static func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-workbench-\(UUID().uuidString)")
            .appendingPathComponent("field-cache.json")
    }
    static func entry(
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
            exit: exit
        )
    }
    static func emptyField(hosts: [String]) -> Field {
        Field(
            conduit: RecordedConduit(transcript: ConduitTranscript()),
            hosts: hosts,
            cache: FieldCache(url: tempCacheURL()),
            now: clock
        )
    }
}

// MARK: - CapabilityRequirement.evaluate (pure)

@Suite("CapabilityRequirement.evaluate")
struct CapabilityRequirementEvaluateTests {
    @Test("reachable: available when facts are nil — unprobed host, including local")
    func reachableUnprobed() {
        #expect(CapabilityRequirement.reachable.evaluate(host: "host", facts: nil) == .available)
        #expect(
            CapabilityRequirement.reachable.evaluate(host: "localhost", facts: nil) == .available
        )
    }
    @Test("reachable: available when host is known reachable")
    func reachableKnownReachable() {
        var facts = HostFacts()
        facts.reachability = Dated(value: .reachable, discoveredAt: Date())
        #expect(
            CapabilityRequirement.reachable.evaluate(host: "host", facts: facts) == .available
        )
    }
    @Test("reachable: unmet when host is known unreachable")
    func reachableKnownUnreachable() {
        var facts = HostFacts()
        facts.reachability = Dated(
            value: .unreachable(detail: "connection refused"),
            discoveredAt: Date()
        )
        #expect(
            CapabilityRequirement.reachable.evaluate(host: "jodo", facts: facts)
                == .unmet("jodo is unreachable")
        )
    }
    @Test("reachable: available when facts exist but reachability is nil")
    func reachableFactsNoReachabilityEntry() {
        let facts = HostFacts()
        #expect(
            CapabilityRequirement.reachable.evaluate(host: "host", facts: facts) == .available
        )
    }
    @Test("zfs: unmet with not-yet-probed message when facts are nil")
    func zfsUnprobed() {
        #expect(
            CapabilityRequirement.zfs.evaluate(host: "jodo", facts: nil)
                == .unmet("jodo not yet probed—probe from the field or map")
        )
    }
    @Test("zfs: unmet with no-zfs message when facts exist but have no topology")
    func zfsFactsNoTopology() {
        var facts = HostFacts()
        facts.reachability = Dated(value: .reachable, discoveredAt: Date())
        #expect(
            CapabilityRequirement.zfs.evaluate(host: "jodo", facts: facts)
                == .unmet("jodo has no zfs")
        )
    }
    @Test("zfs: available when facts carry a zfsTopology (zfs-bearing host)")
    func zfsAvailable() {
        var facts = HostFacts()
        facts.zfsTopology = Dated(value: [], discoveredAt: Date())
        #expect(CapabilityRequirement.zfs.evaluate(host: "jodo", facts: facts) == .available)
    }
}

// MARK: - SystemReadsTool

@Suite("SystemReadsTool")
struct SystemReadsToolTests {
    @Test("tool id, label, and verb count")
    func identity() {
        let tool = SystemReadsTool()
        #expect(tool.id == "reads")
        #expect(tool.label == "system reads")
        #expect(tool.verbs.count == 4)
    }
    @Test("all four verbs are read-kind")
    func allVerbsAreRead() {
        let tool = SystemReadsTool()
        for verb in tool.verbs {
            #expect(verb.kind == .read)
        }
    }
    @Test("df requires reachable; zfs verbs require zfs")
    func requirements() throws {
        let tool = SystemReadsTool()
        let dfVerb = try #require(tool.verbs.first { $0.id == "df" })
        #expect(dfVerb.requirement == .reachable)
        for verbID in ["zfs-list", "zpool-status", "zpool-list"] {
            let verb = try #require(tool.verbs.first { $0.id == verbID })
            #expect(verb.requirement == .zfs)
        }
    }
    @Test("command strings: df -h, zfs list, zpool status, zpool list")
    func commandStrings() throws {
        let tool = SystemReadsTool()
        let host = "jodo"
        let dfVerb = try #require(tool.verbs.first { $0.id == "df" })
        let zfsListVerb = try #require(tool.verbs.first { $0.id == "zfs-list" })
        let zpoolStatusVerb = try #require(tool.verbs.first { $0.id == "zpool-status" })
        let zpoolListVerb = try #require(tool.verbs.first { $0.id == "zpool-list" })
        #expect(tool.command(for: dfVerb, on: host) == "df -h")
        #expect(tool.command(for: zfsListVerb, on: host) == "zfs list")
        #expect(tool.command(for: zpoolStatusVerb, on: host) == "zpool status")
        #expect(tool.command(for: zpoolListVerb, on: host) == "zpool list")
    }
    @Test("planRequest default returns nil for all verbs")
    func planRequestDefaultNil() {
        let tool = SystemReadsTool()
        for verb in tool.verbs {
            #expect(tool.planRequest(for: verb, on: "jodo") == nil)
        }
    }
}

// MARK: - Workbench.run (recorded corpus)

@Suite("Workbench.run")
struct WorkbenchRunTests {
    @Test("df -h: raw stdout passes through collect unchanged")
    func runDfH() async throws {
        let host = "jodo"
        let expected =
            "Filesystem      Size  Used Avail Use% Mounted on\n"
            + "/dev/sda1        20G  5.0G   14G  27% /\n"
        let transcript = ConduitTranscript(entries: [
            WorkbenchFixtures.entry(host, "df -h", stdout: expected)
        ])
        let conduit = RecordedConduit(transcript: transcript)
        let workbench = Workbench(
            conduit: conduit,
            field: WorkbenchFixtures.emptyField(hosts: [host])
        )
        let tool = SystemReadsTool()
        let verb = try #require(tool.verbs.first { $0.id == "df" })
        let running = try await workbench.run(verb, of: tool, on: host)
        let result = try await running.collect()
        #expect(result.stdoutText == expected)
        #expect(result.exitStatus == 0)
    }
    @Test("zpool status: raw stdout passes through collect unchanged")
    func runZpoolStatus() async throws {
        let host = "jodo"
        let expected = "  pool: tank\n state: ONLINE\n"
        let transcript = ConduitTranscript(entries: [
            WorkbenchFixtures.entry(host, "zpool status", stdout: expected)
        ])
        let conduit = RecordedConduit(transcript: transcript)
        let workbench = Workbench(
            conduit: conduit,
            field: WorkbenchFixtures.emptyField(hosts: [host])
        )
        let tool = SystemReadsTool()
        let verb = try #require(tool.verbs.first { $0.id == "zpool-status" })
        let running = try await workbench.run(verb, of: tool, on: host)
        let result = try await running.collect()
        #expect(result.stdoutText == expected)
    }
    @Test("run refuses a mutation verb — throws notARead")
    func runRefusesMutation() async throws {
        let host = "jodo"
        let mutationVerb = WorkbenchVerb(
            id: "delete",
            label: "delete",
            keyHint: "x",
            requirement: .reachable,
            kind: .mutation
        )
        let workbench = Workbench(
            conduit: RecordedConduit(transcript: ConduitTranscript()),
            field: WorkbenchFixtures.emptyField(hosts: [host])
        )
        let tool = SystemReadsTool()
        await #expect(throws: WorkbenchError.notARead) {
            _ = try await workbench.run(mutationVerb, of: tool, on: host)
        }
    }
}

// MARK: - Workbench.availability integration (seeded Field via discovery)

@Suite("Workbench.availability integration")
struct WorkbenchAvailabilityTests {
    private static let gnuNoZfsProbe = """
        palana:kernel:Linux
        palana:flavor:GNU
        palana:zfs:
        palana:rsync:
        """
    private static let gnuZfsProbe = """
        palana:kernel:Linux
        palana:flavor:GNU
        palana:zfs:zfs-2.2.2-0ubuntu9.1
        palana:rsync:rsync  version 3.2.7  protocol version 31
        """
    private static let linuxMounts = "/dev/sda1 / ext4 rw,relatime 0 0\n"
    private static let zfsList = "palana\t/palana\tyes\n"
    private static func fieldAfterDiscover(
        transcript: ConduitTranscript,
        host: String
    ) async throws -> (Workbench, SystemReadsTool) {
        let conduit = RecordedConduit(transcript: transcript)
        let field = Field(
            conduit: conduit,
            hosts: [host],
            cache: FieldCache(url: WorkbenchFixtures.tempCacheURL()),
            now: WorkbenchFixtures.clock
        )
        _ = try await field.discover(host)
        return (Workbench(conduit: conduit, field: field), SystemReadsTool())
    }
    @Test("zfs host: all four verbs available")
    func zfsHostAllAvailable() async throws {
        let host = "jodo"
        let transcript = ConduitTranscript(entries: [
            WorkbenchFixtures.entry(host, CapabilityProbe.command, stdout: Self.gnuZfsProbe),
            WorkbenchFixtures.entry(host, ZFSTopology.listCommand, stdout: Self.zfsList),
            WorkbenchFixtures.entry(
                host, MountTable.command(forKernel: "Linux"), stdout: Self.linuxMounts),
        ])
        let (workbench, tool) = try await Self.fieldAfterDiscover(
            transcript: transcript, host: host)
        for verb in tool.verbs {
            #expect(await workbench.availability(of: verb, on: host) == .available)
        }
    }
    @Test("reachable host with no zfs: df available, zfs verbs unmet")
    func reachableNoZfsHost() async throws {
        let host = "jodo"
        let transcript = ConduitTranscript(entries: [
            WorkbenchFixtures.entry(host, CapabilityProbe.command, stdout: Self.gnuNoZfsProbe),
            WorkbenchFixtures.entry(
                host, MountTable.command(forKernel: "Linux"), stdout: Self.linuxMounts),
        ])
        let (workbench, tool) = try await Self.fieldAfterDiscover(
            transcript: transcript, host: host)
        let dfVerb = try #require(tool.verbs.first { $0.id == "df" })
        #expect(await workbench.availability(of: dfVerb, on: host) == .available)
        for verbID in ["zfs-list", "zpool-status", "zpool-list"] {
            let verb = try #require(tool.verbs.first { $0.id == verbID })
            #expect(
                await workbench.availability(of: verb, on: host)
                    == .unmet("\(host) has no zfs")
            )
        }
    }
    @Test("unprobed host: df available, zfs verbs unmet with not-yet-probed message")
    func unprobedHost() async throws {
        let host = "phantom"
        let workbench = Workbench(
            conduit: RecordedConduit(transcript: ConduitTranscript()),
            field: WorkbenchFixtures.emptyField(hosts: [host])
        )
        let tool = SystemReadsTool()
        let dfVerb = try #require(tool.verbs.first { $0.id == "df" })
        #expect(await workbench.availability(of: dfVerb, on: host) == .available)
        for verbID in ["zfs-list", "zpool-status", "zpool-list"] {
            let verb = try #require(tool.verbs.first { $0.id == verbID })
            #expect(
                await workbench.availability(of: verb, on: host)
                    == .unmet("\(host) not yet probed—probe from the field or map")
            )
        }
    }
    @Test("unreachable host: df verb is unmet")
    func unreachableHost() async throws {
        let host = "koan"
        let transcript = ConduitTranscript(entries: [
            WorkbenchFixtures.entry(
                host,
                CapabilityProbe.command,
                stderr: "ssh: connect to host koan port 22: Connection refused",
                exit: 255
            )
        ])
        let conduit = RecordedConduit(transcript: transcript)
        let field = Field(
            conduit: conduit,
            hosts: [host],
            cache: FieldCache(url: WorkbenchFixtures.tempCacheURL()),
            now: WorkbenchFixtures.clock
        )
        _ = try await field.discover(host)
        let workbench = Workbench(conduit: conduit, field: field)
        let tool = SystemReadsTool()
        let dfVerb = try #require(tool.verbs.first { $0.id == "df" })
        #expect(
            await workbench.availability(of: dfVerb, on: host) == .unmet("\(host) is unreachable")
        )
    }
}
