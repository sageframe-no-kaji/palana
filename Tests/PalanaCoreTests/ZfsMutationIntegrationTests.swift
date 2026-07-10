// ZFS mutation integration — enact real ZFS mutations against the Lima
// throwaway pool. Gated on ZFSFixture.available; self-skips if the
// fixture is down. Serialized: one VM, one pool.
//
// The round trip: create a dataset, snapshot it, roll it back, set then
// clear its mountpoint, destroy the snapshot, destroy the dataset.
// Each step planned via PlanEngine.plan() and enacted via Transports.
// No sudo in any composed command (Decision 3). Fixture teardown may
// use sudo for Linux-root mount hygiene only.

import Foundation
import Testing

@testable import PalanaCore

@Suite("zfs mutation integration", .enabled(if: ZFSFixture.available), .serialized)
struct ZfsMutationIntegrationTests {
    // Unique token per process so parallel test runs don't collide.
    private static let token = "m10-\(ProcessInfo.processInfo.processIdentifier)"

    private struct World {
        var conduit: SSHConduit
        var configuration: SSHConfiguration
        var host: String
    }

    private static func makeWorld() throws -> World {
        let (configuration, host) = try ZFSFixture.configuration()
        return World(
            conduit: SSHConduit(configuration: configuration),
            configuration: configuration,
            host: host)
    }

    /// Destroy the test dataset unconditionally — fixture teardown only.
    private static func sweepDataset(_ world: World, _ name: String) async {
        let sweep = "sudo zfs destroy -r \(name) 2>/dev/null; true"
        _ = try? await world.conduit.run(on: world.host, sweep).collect()
    }

    // MARK: - Helpers

    private static func datasetExists(_ world: World, _ name: String) async throws -> Bool {
        let cmd = "zfs list -H -o name -- \(ShellQuote.quote(name))"
        let running = try await world.conduit.run(on: world.host, cmd)
        let result = try await running.collect()
        return result.exitStatus == 0
    }

    private static func snapshotExists(_ world: World, _ full: String) async throws -> Bool {
        let cmd = "zfs list -H -o name -t snapshot -- \(ShellQuote.quote(full))"
        let running = try await world.conduit.run(on: world.host, cmd)
        let result = try await running.collect()
        return result.exitStatus == 0
    }

    private static func mountpointValue(_ world: World, _ dataset: String) async throws -> String {
        let cmd = "zfs get -H -o value mountpoint -- \(ShellQuote.quote(dataset))"
        let running = try await world.conduit.run(on: world.host, cmd)
        let result = try await running.collect()
        return result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func enact(_ plan: Plan, world: World) async throws {
        let transports = Transports(
            conduit: world.conduit, configuration: world.configuration)
        var events: [EnactmentEvent] = []
        for try await event in transports.enact(plan) {
            events.append(event)
        }
        #expect(events.last == .finished, "enactment must finish cleanly")
    }

    private static func planMutation(_ mutation: ZFSMutation, on host: String) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .zfs,
                source: Locus(host: host, directory: "/"),
                entries: [],
                destination: nil,
                token: Self.token,
                zfs: mutation),
            facts: PlanFacts())
    }

    // MARK: - Round-trip test

    @Test("zfs mutation round trip: create → snapshot → rollback → mountpoint → destroy")
    func mutationRoundTrip() async throws {
        let world = try Self.makeWorld()
        defer { Task { await world.conduit.closeAll() } }

        let dsName = "palana/\(Self.token)-ds"
        let snapName = "\(Self.token)-snap"
        let snapFull = "\(dsName)@\(snapName)"
        defer { Task { await Self.sweepDataset(world, dsName) } }

        // 1. Create dataset (no mountpoint)
        let createPlan = try Self.planMutation(
            .createDataset(name: dsName, mountpoint: nil), on: world.host)
        try await Self.enact(createPlan, world: world)
        #expect(try await Self.datasetExists(world, dsName), "dataset created")

        // 2. Snapshot it
        let snapPlan = try Self.planMutation(
            .snapshot(dataset: dsName, name: snapName, recursive: false), on: world.host)
        try await Self.enact(snapPlan, world: world)
        #expect(try await Self.snapshotExists(world, snapFull), "snapshot created")

        // 3. Rollback to snapshot
        let rollbackPlan = try Self.planMutation(
            .rollback(dataset: dsName, name: snapName), on: world.host)
        try await Self.enact(rollbackPlan, world: world)
        #expect(
            try await Self.snapshotExists(world, snapFull),
            "snapshot still present after rollback")

        // 4. Set mountpoint
        let mountPath = "/tmp/palana-mt-\(Self.token)"
        let setMpPlan = try Self.planMutation(
            .setMountpoint(dataset: dsName, path: mountPath), on: world.host)
        try await Self.enact(setMpPlan, world: world)
        let gotMp = try await Self.mountpointValue(world, dsName)
        #expect(gotMp == mountPath, "mountpoint set to \(mountPath)")

        // 5. Clear mountpoint (inherit)
        let clearMpPlan = try Self.planMutation(
            .clearMountpoint(dataset: dsName), on: world.host)
        try await Self.enact(clearMpPlan, world: world)
        let clearedMp = try await Self.mountpointValue(world, dsName)
        #expect(clearedMp != mountPath, "mountpoint no longer \(mountPath) after inherit")

        // 6. Destroy snapshot
        let destroySnapPlan = try Self.planMutation(
            .destroySnapshot(dataset: dsName, name: snapName), on: world.host)
        try await Self.enact(destroySnapPlan, world: world)
        #expect(try await !Self.snapshotExists(world, snapFull), "snapshot destroyed")

        // 7. Destroy dataset
        let destroyDsPlan = try Self.planMutation(
            .destroyDataset(name: dsName, recursive: false), on: world.host)
        try await Self.enact(destroyDsPlan, world: world)
        #expect(try await !Self.datasetExists(world, dsName), "dataset destroyed")
    }
}
