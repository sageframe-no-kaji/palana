// Enactment against the real fixture — the whole stack in one trace:
// probe the flavor, list the entries, compose the Plan, enact it,
// watch the events, verify the counts released the gate. The rsync
// path needs real rsync on the source (the probe fact decides — the
// runner's openrsync skips itself); the tar proxy runs everywhere.
// Never a live homelab host.

import Foundation
import Testing

@testable import PalanaCore

// Serialized: one sshd fixture, ho-02's observed throttling.
@Suite(
    "Transports integration: sshd fixture",
    .enabled(if: SSHFixture.aliasesAvailable),
    .serialized)
struct TransportsIntegrationTests {
    private static let root = "/tmp/palana-t61-\(ProcessInfo.processInfo.processIdentifier)"

    private struct World {
        var conduit: SSHConduit
        var configuration: SSHConfiguration
        var source: String
        var destination: String
        var capability: HostCapability
    }

    private static func makeWorld() async throws -> World {
        let aliases = try SSHFixture.aliasConfiguration()
        let conduit = SSHConduit(configuration: aliases.configuration)
        let probe = try await conduit.run(on: aliases.source, CapabilityProbe.command).collect()
        return World(
            conduit: conduit,
            configuration: aliases.configuration,
            source: aliases.source,
            destination: aliases.destination,
            capability: try CapabilityProbe.parse(probe.stdoutText))
    }

    /// Deterministic content, a hostile name, and a fresh pair of
    /// directories under a per-case root.
    private static func setUp(_ world: World, case caseName: String) async throws -> String {
        let base = "\(root)-\(caseName)"
        let command = """
            rm -rf \(base) && mkdir -p \(base)/src \(base)/dst && \
            seq 1 20000 > \(base)/src/payload.txt && \
            printf 'small' > '\(base)/src/with space'
            """
        let result = try await world.conduit.run(on: world.source, command).collect()
        #expect(result.exitStatus == 0, "setup failed: \(result.stderrText)")
        return base
    }

    private static func tearDown(_ world: World, base: String) async {
        _ = try? await world.conduit.run(on: world.source, "rm -rf \(base)").collect()
    }

    private static func movePlan(
        _ world: World, base: String, forwarding: ForwardingFact
    ) async throws -> Plan {
        let entries = try await Listing(conduit: world.conduit)
            .list(on: world.source, path: "\(base)/src", flavor: world.capability.flavor)
        #expect(entries.count == 2)
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: world.source, directory: "\(base)/src"),
                entries: entries,
                destination: Locus(host: world.destination, directory: "\(base)/dst"),
                token: "t61"),
            facts: PlanFacts(
                sourceCapability: world.capability,
                // One container plays both hosts — the destination's
                // userland is the source's.
                destinationCapability: world.capability,
                agentForwarding: forwarding))
    }

    private static func enactCollecting(
        _ plan: Plan, world: World
    ) async throws -> [EnactmentEvent] {
        let transports = Transports(
            conduit: world.conduit, configuration: world.configuration)
        var events: [EnactmentEvent] = []
        for try await event in transports.enact(plan) {
            events.append(event)
        }
        return events
    }

    private static func assertMoved(_ world: World, base: String) async throws {
        let listing = Listing(conduit: world.conduit)
        let after = try await listing.list(
            on: world.source, path: "\(base)/dst", flavor: world.capability.flavor)
        #expect(Set(after.map(\.name)) == ["payload.txt", "with space"])
        let payload = try #require(after.first { $0.name == "payload.txt" })
        #expect(payload.size > 100_000, "seq 1 20000 is six figures of bytes")
        let sourceLeft = try await listing.list(
            on: world.source, path: "\(base)/src", flavor: world.capability.flavor)
        #expect(sourceLeft.isEmpty, "the gated delete ran and the source is empty")
    }

    @Test("an rsync-direct move enacts end to end: events, progress, verify, gated delete")
    func rsyncDirectMove() async throws {
        let world = try await Self.makeWorld()
        defer { Task { await world.conduit.closeAll() } }
        guard world.capability.rsyncVersion != nil else {
            // openrsync on the CI runner — ho-06's ≥3.1 fact, applied.
            return
        }
        let base = try await Self.setUp(world, case: "rsync")
        defer { Task { await Self.tearDown(world, base: base) } }

        let plan = try await Self.movePlan(world, base: base, forwarding: .available)
        #expect(plan.transport == .rsyncAgentForwarded)
        let events = try await Self.enactCollecting(plan, world: world)

        #expect(events.last == .finished)
        let progressReports = events.compactMap { event -> ProgressReport? in
            if case .progress(let report) = event { return report }
            return nil
        }
        #expect(!progressReports.isEmpty, "progress2 produced observations")
        #expect(progressReports.last?.fraction == 1.0, "the bar finishes at 100 exactly")
        #expect(
            events.contains(.verified(VerificationReport.counts(source: 2, destination: 2))))
        try await Self.assertMoved(world, base: base)
    }

    @Test("a tar-proxy move enacts through the operator's machine, bytes counted")
    func tarProxyMove() async throws {
        let world = try await Self.makeWorld()
        defer { Task { await world.conduit.closeAll() } }
        let base = try await Self.setUp(world, case: "tar")
        defer { Task { await Self.tearDown(world, base: base) } }

        let sourceSum = "cksum \(base)/src/payload.txt | awk '{print $1, $2}'"
        let before = try await world.conduit.run(on: world.source, sourceSum).collect()

        let plan = try await Self.movePlan(world, base: base, forwarding: .unprobed)
        #expect(plan.transport == .tarStreamProxied)
        let events = try await Self.enactCollecting(plan, world: world)

        #expect(events.last == .finished)
        let counted = events.compactMap { event -> Int64? in
            if case .progress(let report) = event { return report.bytesTransferred }
            return nil
        }
        #expect(counted.last ?? 0 > 100_000, "the byte counter saw the payload go through")
        try await Self.assertMoved(world, base: base)

        // Byte fidelity: the transplanted payload checksums identically.
        let destinationSum = "cksum \(base)/dst/payload.txt | awk '{print $1, $2}'"
        let after = try await world.conduit.run(on: world.source, destinationSum).collect()
        #expect(before.stdoutText == after.stdoutText)
        #expect(!before.stdoutText.isEmpty)
    }

    @Test(
        "capture a real progress2 stream for the parser corpus",
        .enabled(if: ProcessInfo.processInfo.environment["PALANA_RECORD_FIXTURES"] == "1"))
    func captureProgressSample() async throws {
        let world = try await Self.makeWorld()
        defer { Task { await world.conduit.closeAll() } }
        guard world.capability.rsyncVersion != nil else { return }
        let base = try await Self.setUp(world, case: "capture")
        defer { Task { await Self.tearDown(world, base: base) } }

        let plan = try await Self.movePlan(world, base: base, forwarding: .available)
        let events = try await Self.enactCollecting(plan, world: world)
        var stdout = Data()
        for case .outputChunk(0, .stdout, let data) in events {
            stdout.append(data)
        }
        try stdout.write(
            to: SSHFixture.repoRoot.appendingPathComponent(
                "Tests/PalanaCoreTests/Fixtures/rsync-progress2-sample.bin"))
        #expect(!stdout.isEmpty)
    }
}
