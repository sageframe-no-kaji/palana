// zfs enactment against the throwaway pool — the only place mutating
// zfs operations run, ever. The pool plays both hosts through the
// zfs-self alias, and every composed command runs delegated: no sudo
// anywhere pālana composes. Fixture-side setup uses sudo only to put
// content behind an unmounted dataset — Linux mounting is root's.

import Foundation
import Testing

@testable import PalanaCore

// Serialized: one VM, one pool.
@Suite("zfs transports integration", .enabled(if: ZFSFixture.available), .serialized)
struct ZfsTransportsIntegrationTests {
    private static let token = "t62-\(ProcessInfo.processInfo.processIdentifier)"

    private struct World {
        var conduit: SSHConduit
        var configuration: SSHConfiguration
        var host: String
        var destinationHost: String
    }

    private static func makeWorld() throws -> World {
        let (configuration, host) = try ZFSFixture.configuration()
        return World(
            conduit: SSHConduit(configuration: configuration),
            configuration: configuration,
            host: host,
            destinationHost: try ZFSFixture.selfAlias())
    }

    /// Two unmounted datasets and deterministic content behind the source.
    ///
    /// Sweep and content-write run under sudo because they are fixture
    /// hygiene, exactly the mount reality ho-06.2 names. The commands
    /// pālana composes stay sudo-free.
    private static func setUp(
        _ world: World,
        case caseName: String
    ) async throws -> (source: String, destination: String) {
        let source = "palana/t62-\(caseName)-src"
        let destination = "palana/t62-\(caseName)-dst"
        let command = """
            sudo zfs destroy -r \(source) 2>/dev/null; \
            sudo zfs destroy -r \(destination) 2>/dev/null; \
            zfs create -o canmount=noauto \(source) && \
            zfs create -o canmount=noauto \(destination) && \
            sudo zfs mount \(source) && \
            sudo sh -c 'seq 1 100000 > /\(source)/data.txt' && \
            sudo zfs unmount \(source)
            """
        let result = try await world.conduit.run(on: world.host, command).collect()
        #expect(result.exitStatus == 0, "setup failed: \(result.stderrText)")
        return (source, destination)
    }

    private static func tearDown(
        _ world: World,
        _ datasets: (source: String, destination: String)
    ) async {
        let sweep =
            "sudo zfs destroy -r \(datasets.source) 2>/dev/null; "
            + "sudo zfs destroy -r \(datasets.destination) 2>/dev/null; true"
        _ = try? await world.conduit.run(on: world.host, sweep).collect()
    }

    private static func plan(
        _ operation: PlanOperation,
        world: World,
        datasets: (source: String, destination: String),
        forwarding: ForwardingFact
    ) throws -> Plan {
        let sourceName = String(datasets.source.split(separator: "/").last ?? "")
        let entry = FileEntry(
            nameData: Data(sourceName.utf8),
            kind: .directory,
            size: 0,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "755",
            owner: "op",
            group: "op")
        let capability = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: "zfs-2.4.1", rsync: nil)
        return try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: Locus(host: world.host, directory: "/palana"),
                entries: [entry],
                destination: Locus(
                    host: world.destinationHost, directory: "/\(datasets.destination)"),
                token: Self.token),
            facts: PlanFacts(
                sourceDataset: ZFSDataset(name: "palana", mountpoint: "/palana", mounted: true),
                destinationDataset: ZFSDataset(
                    name: datasets.destination,
                    mountpoint: "/\(datasets.destination)",
                    mounted: false),
                selectionWholeDataset: ZFSDataset(
                    name: datasets.source,
                    mountpoint: "/\(datasets.source)",
                    mounted: false),
                sourceCapability: capability,
                destinationCapability: capability,
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

    private static func datasetExists(_ world: World, _ name: String) async throws -> Bool {
        let command = "zfs list -H -o name \(name)"
        let result = try await world.conduit.run(on: world.host, command).collect()
        return result.exitStatus == 0
    }

    private static func tokenSnapshots(_ world: World) async throws -> String {
        let command = "zfs list -t snapshot -H -o name | grep \(Self.token) || true"
        return try await world.conduit.run(on: world.host, command).collect().stdoutText
    }

    @Test("a forwarded whole-dataset move: received, verified, source destroyed, snaps clean")
    func forwardedMove() async throws {
        let world = try Self.makeWorld()
        defer { Task { await world.conduit.closeAll() } }
        let datasets = try await Self.setUp(world, case: "fwd")
        defer { Task { await Self.tearDown(world, datasets) } }

        let plan = try Self.plan(.move, world: world, datasets: datasets, forwarding: .available)
        #expect(plan.transport == .zfsSendReceiveForwarded)
        let child = try #require(plan.receivedDataset)
        let events = try await Self.enactCollecting(plan, world: world)

        #expect(events.last == .finished)
        #expect(events.contains(.verified(.datasetReceived(name: child, exists: true))))
        #expect(try await Self.datasetExists(world, child), "the dataset landed")
        let sourceGone = try await Self.datasetExists(world, datasets.source)
        #expect(!sourceGone, "the gated destroy ran — this is a move")
        #expect(try await Self.tokenSnapshots(world).isEmpty, "cleanups swept the snapshots")

        // Content fidelity — mounted, checked, unmounted, all fixture-
        // side sudo, so the sweep can destroy it delegated.
        let check =
            "sudo zfs mount \(child) && cksum /\(child)/data.txt "
            + "| awk '{print $1, $2}' && sudo zfs unmount \(child)"
        let sum = try await world.conduit.run(on: world.host, check).collect()
        #expect(
            sum.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines) == "2052179976 588895",
            "seq 1 100000 has one checksum")
        _ = try? await world.conduit.run(on: world.host, "zfs destroy -r \(child)").collect()
    }

    @Test("a proxied whole-dataset copy: pumped through the operator's machine, source kept")
    func proxiedCopy() async throws {
        let world = try Self.makeWorld()
        defer { Task { await world.conduit.closeAll() } }
        let datasets = try await Self.setUp(world, case: "prx")
        defer { Task { await Self.tearDown(world, datasets) } }

        let plan = try Self.plan(.copy, world: world, datasets: datasets, forwarding: .unprobed)
        #expect(plan.transport == .zfsSendReceiveProxied)
        let child = try #require(plan.receivedDataset)
        let events = try await Self.enactCollecting(plan, world: world)

        #expect(events.last == .finished)
        let counted = events.compactMap { event -> Int64? in
            if case .progress(let report) = event { return report.bytesTransferred }
            return nil
        }
        #expect(counted.last ?? 0 > 10_000, "the pump counted the stream")
        #expect(try await Self.datasetExists(world, child))
        #expect(try await Self.datasetExists(world, datasets.source), "a copy keeps its source")
        #expect(try await Self.tokenSnapshots(world).isEmpty, "both cleanups ran")
        _ = try? await world.conduit.run(on: world.host, "zfs destroy -r \(child)").collect()
    }
}
