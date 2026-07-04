// The local branch, live — "local" is a host and the fixture is the
// other one. A push move and a pull copy run rsyncDirect end to end
// through the router: real rsync on this Mac, real sshd in the
// container, counts releasing the gate. The forwarding probe answers
// from the container's own view of the world. Never a live homelab
// host — this Mac's temp directory and the container only.

import Foundation
import Testing

@testable import PalanaCore

// Serialized: one sshd fixture, ho-02's observed throttling — and the
// suite sets RSYNC_RSH process-wide so the composed rsync resolves the
// fixture alias, an operator-config concern the fixture fakes with -F.
@Suite(
    "Routing integration: local ↔ fixture",
    .enabled(if: SSHFixture.aliasesAvailable),
    .serialized)
struct RoutingIntegrationTests {
    private struct World {
        var router: RoutingConduit
        var remote: SSHConduit
        var configuration: SSHConfiguration
        var container: String
        var capability: HostCapability
        var flavor: UserlandFlavor
        var localBase: URL
        var remoteBase: String
    }

    private static func makeWorld(case caseName: String) async throws -> World {
        let aliases = try SSHFixture.aliasConfiguration()
        let remote = SSHConduit(configuration: aliases.configuration)
        let probe = try await remote.run(on: aliases.source, CapabilityProbe.command).collect()
        let capability = try CapabilityProbe.parse(probe.stdoutText)
        let configPath = try SSHFixture.facts()["PALANA_FIXTURE_SSH_CONFIG"] ?? ""
        // The composed rsync spawns plain `ssh`; the fixture alias lives
        // in a -F config the operator's real ~/.ssh/config would carry.
        setenv("RSYNC_RSH", "ssh -F \(configPath)", 1)
        let localBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-routing-\(caseName)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(
            at: localBase.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: localBase.appendingPathComponent("dst"), withIntermediateDirectories: true)
        let remoteBase = "/tmp/palana-routing-\(caseName)-\(ProcessInfo.processInfo.processIdentifier)"
        let setup = "rm -rf \(remoteBase) && mkdir -p \(remoteBase)/src \(remoteBase)/dst"
        let made = try await remote.run(on: aliases.source, setup).collect()
        #expect(made.exitStatus == 0, "remote setup failed: \(made.stderrText)")
        return World(
            router: RoutingConduit(remote: remote),
            remote: remote,
            configuration: aliases.configuration,
            container: aliases.source,
            capability: capability,
            flavor: capability.flavor,
            localBase: localBase,
            remoteBase: remoteBase)
    }

    private static func tearDown(_ world: World) async {
        try? FileManager.default.removeItem(at: world.localBase)
        _ = try? await world.remote.run(on: world.container, "rm -rf \(world.remoteBase)").collect()
        await world.remote.closeAll()
    }

    private static func enactCollecting(_ plan: Plan, world: World) async throws -> [EnactmentEvent] {
        let transports = Transports(conduit: world.router, configuration: world.configuration)
        var events: [EnactmentEvent] = []
        for try await event in transports.enact(plan) {
            events.append(event)
        }
        return events
    }

    @Test("a push move runs rsyncDirect here, gates on counts, deletes the source")
    func pushMove() async throws {
        let world = try await Self.makeWorld(case: "push")
        defer { Task { await Self.tearDown(world) } }
        let src = world.localBase.appendingPathComponent("src")
        try String(repeating: "line\n", count: 20000)
            .write(to: src.appendingPathComponent("payload.txt"), atomically: true, encoding: .utf8)
        try "small".write(
            to: src.appendingPathComponent("with space"), atomically: true, encoding: .utf8)

        let entries = try await Listing(conduit: LocalConduit())
            .list(on: "local", path: src.path, flavor: .bsd)
        #expect(entries.count == 2)
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "local", directory: src.path),
                entries: entries,
                destination: Locus(host: world.container, directory: "\(world.remoteBase)/dst")),
            facts: PlanFacts(destinationCapability: world.capability))
        #expect(plan.transport == .rsyncDirect)
        #expect(plan.steps.first?.runsOn == .host("local"))

        let events = try await Self.enactCollecting(plan, world: world)
        #expect(events.contains(.finished))
        let verified = events.contains {
            if case .verified(let report) = $0 { return report.matched }
            return false
        }
        #expect(verified, "the count gate must have released the delete")
        // The move's back half ran: the local source entries are gone.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: src.path)
        #expect(remaining.isEmpty)
        // The bytes landed: the container counts both names.
        let countLanded = "find \(world.remoteBase)/dst -mindepth 1 | wc -l"
        let landed = try await world.remote.run(on: world.container, countLanded).collect()
        #expect(landed.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
    }

    @Test("a pull copy runs rsyncDirect here and leaves the source standing")
    func pullCopy() async throws {
        let world = try await Self.makeWorld(case: "pull")
        defer { Task { await Self.tearDown(world) } }
        let fill = """
            seq 1 5000 > \(world.remoteBase)/src/numbers.txt && \
            printf 'hostile' > '\(world.remoteBase)/src/pull me.txt'
            """
        let filled = try await world.remote.run(on: world.container, fill).collect()
        #expect(filled.exitStatus == 0)

        let entries = try await Listing(conduit: world.remote)
            .list(on: world.container, path: "\(world.remoteBase)/src", flavor: world.flavor)
        #expect(entries.count == 2)
        let dst = world.localBase.appendingPathComponent("dst")
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: world.container, directory: "\(world.remoteBase)/src"),
                entries: entries,
                destination: Locus(host: "local", directory: dst.path)),
            facts: PlanFacts(sourceCapability: world.capability))
        #expect(plan.transport == .rsyncDirect)

        let events = try await Self.enactCollecting(plan, world: world)
        #expect(events.contains(.finished))
        let landedNames = try FileManager.default.contentsOfDirectory(atPath: dst.path).sorted()
        #expect(landedNames == ["numbers.txt", "pull me.txt"])
        let pulled = try String(
            contentsOf: dst.appendingPathComponent("pull me.txt"), encoding: .utf8)
        #expect(pulled == "hostile")
        // A copy leaves the source standing.
        let countStill = "find \(world.remoteBase)/src -mindepth 1 | wc -l"
        let still = try await world.remote.run(on: world.container, countStill).collect()
        #expect(still.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
    }

    @Test("the forwarding probe answers live from the container's view")
    func forwardingProbeLive() async throws {
        let aliases = try SSHFixture.aliasConfiguration()
        let remote = SSHConduit(configuration: aliases.configuration)
        defer { Task { await remote.closeAll() } }
        let cache = FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-fwd-live-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
        let field = Field(
            conduit: remote, hosts: [aliases.source, aliases.destination], cache: cache)
        // The container reaches its second name — ho-06.1's self-alias.
        let toSelf = await field.forwardingFact(from: aliases.source, to: aliases.destination)
        #expect(toSelf == .available)
        // A name its config has never heard of is a blocked hop, not a
        // door failure.
        let toNowhere = await field.forwardingFact(from: aliases.source, to: "palana-no-such-host")
        #expect(toNowhere == .unavailable)
    }
}
