// The final review's F03 against the real throwaway pool (owner ruling:
// fence and prove; pass 2 found the proof read its own snapshot). These
// cases run only with the Lima ZFS fixture (.fixtures/zfs.env) and touch
// only datasets named palana/t63-*. Composed commands run as pālana would
// run them; fixture-side setup and sweeps use sudo, as the other zfs
// integration suite does.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Final review F03 — fence and proof on a real pool", .enabled(if: ZFSFixture.available), .serialized)
struct FinalReviewZFSLiveTests {
    private static let token = "t63-\(ProcessInfo.processInfo.processIdentifier)"

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

    @discardableResult
    private static func run(_ world: World, _ command: String) async throws -> CommandResult {
        try await world.conduit.run(on: world.host, command).collect()
    }

    /// A source tree with content and a destination parent.
    ///
    /// `mounted`: the source and its child stay mounted, so the fence has
    /// real work. Otherwise both are left unmounted (`canmount=noauto`).
    private static func setUp(
        _ world: World, case name: String, mounted: Bool
    ) async throws -> (source: String, destination: String) {
        let source = "palana/t63-\(name)-src"
        let destination = "palana/t63-\(name)-dst"
        let canmount = mounted ? "" : "-o canmount=noauto "
        let command = [
            "sudo zfs destroy -r \(source) 2>/dev/null; sudo zfs destroy -r \(destination) 2>/dev/null; true",
            "sudo zfs create \(canmount)\(source)",
            "sudo zfs create \(canmount)\(source)/child",
            "sudo zfs create -o canmount=noauto \(destination)",
            mounted ? "true" : "sudo zfs mount \(source) && sudo zfs mount \(source)/child",
            "sudo sh -c 'seq 1 100000 > /\(source)/data.txt; seq 1 50 > /\(source)/child/small.txt'",
            mounted ? "true" : "sudo zfs unmount \(source)/child && sudo zfs unmount \(source)",
        ].joined(separator: " && ")
        let result = try await run(world, command)
        #expect(result.exitStatus == 0, "setup failed: \(result.stderrText)")
        return (source, destination)
    }

    private static func tearDown(_ world: World, _ datasets: (source: String, destination: String)) async {
        _ = try? await run(
            world,
            "pkill -f 'palana-busy-holde[r]' 2>/dev/null; sleep 0.2; "
                + "sudo zfs destroy -r \(datasets.source) 2>/dev/null; "
                + "sudo zfs destroy -r \(datasets.destination) 2>/dev/null; true")
    }

    /// Sets up a case, runs it, and always awaits its sweep before the
    /// test returns — a deferred task would die with the test process and
    /// leave its datasets in the pool.
    private static func scenario(
        case name: String,
        mounted: Bool,
        _ body: (World, (source: String, destination: String)) async throws -> Void
    ) async throws {
        let world = try makeWorld()
        let datasets = try await setUp(world, case: name, mounted: mounted)
        var failure: (any Error)?
        do {
            try await body(world, datasets)
        } catch {
            failure = error
        }
        await tearDown(world, datasets)
        await world.conduit.closeAll()
        if let failure { throw failure }
    }

    private static func plan(
        _ world: World, _ datasets: (source: String, destination: String), mounted: Bool
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
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.4.1", rsync: nil)
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: world.host, directory: "/palana"),
                entries: [entry],
                destination: Locus(host: world.destinationHost, directory: "/\(datasets.destination)"),
                token: token),
            facts: PlanFacts(
                sourceDataset: ZFSDataset(name: "palana", mountpoint: "/palana", mounted: true),
                destinationDataset: ZFSDataset(
                    name: datasets.destination, mountpoint: "/\(datasets.destination)", mounted: false),
                selectionWholeDataset: ZFSDataset(
                    name: datasets.source, mountpoint: "/\(datasets.source)", mounted: mounted),
                sourceCapability: capability,
                destinationCapability: capability,
                agentForwarding: .available))
    }

    /// Enacts; returns the events and the error, if any.
    private static func enact(_ plan: Plan, _ world: World) async -> (events: [EnactmentEvent], error: (any Error)?) {
        var events: [EnactmentEvent] = []
        let transports = Transports(conduit: world.conduit, configuration: world.configuration)
        do {
            for try await event in transports.enact(plan) {
                events.append(event)
            }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }

    private static func exists(_ world: World, _ name: String) async throws -> Bool {
        try await run(world, "zfs list -H -o name \(name)").exitStatus == 0
    }

    private static func mounted(_ world: World, _ name: String) async throws -> String {
        try await run(world, "zfs get -H -o value mounted \(name)").stdoutText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func retainedNotes(_ events: [EnactmentEvent]) -> [RecoveryNote] {
        events.compactMap { event in
            if case .recovery(let note) = event, note.kind == .retained { return note }
            return nil
        }
    }

    /// A non-gated fixture step between the transfer and the gated release
    /// — the other writer, arriving between the snapshot and the destroy.
    private static func meanwhile(_ plan: Plan, _ world: World, _ command: String) -> Plan {
        var plan = plan
        let firstGate = plan.steps.firstIndex(where: \.gatedOnVerification) ?? plan.steps.count
        plan.steps.insert(PlanStep(runsOn: .host(world.host), command: command, role: .verify), at: firstGate)
        return plan
    }

    @Test("real zfs get: the recursive query lists the operation's snapshot as '-'; -t filesystem,volume does not")
    func queryDomainOnRealZFS() async throws {
        try await Self.scenario(case: "query", mounted: false) { world, datasets in
            try await Self.run(world, "sudo zfs snapshot -r \(datasets.source)@\(Self.token)")
            let unrestricted = try await Self.run(
                world, "zfs get -H -p -r -o name,value written@\(Self.token) \(datasets.source)")
            let restricted = try await Self.run(
                world, "zfs get -t filesystem,volume -H -p -r -o name,value written@\(Self.token) \(datasets.source)")
            print("unrestricted:\n\(unrestricted.stdoutText)restricted:\n\(restricted.stdoutText)")
            #expect(unrestricted.stdoutText.contains("@\(Self.token)\t-"), "the snapshot row reads '-' against itself")
            let values = restricted.stdoutText.split(separator: "\n").map { $0.split(separator: "\t").last ?? "" }
            #expect(values == ["0", "0"], "parent and child, live state only")
        }
    }

    @Test("a clean move of a mounted tree: fenced, sent, proved, released; content intact")
    func cleanMountedMove() async throws {
        try await Self.scenario(case: "clean", mounted: true) { world, datasets in
            #expect(try await Self.mounted(world, datasets.source) == "yes")

            let plan = try Self.plan(world, datasets, mounted: true)
            let child = try #require(plan.receivedDataset)
            let outcome = await Self.enact(plan, world)
            #expect(outcome.error == nil, "\(String(describing: outcome.error))")
            #expect(outcome.events.last == .finished)
            #expect(!(try await Self.exists(world, datasets.source)), "the proved source was released")
            #expect(try await Self.exists(world, "\(child)/child"), "the tree arrived whole")
            let check =
                "sudo zfs mount \(child) && cksum /\(child)/data.txt | awk '{print $1, $2}'; sudo zfs unmount \(child)"
            let sum = try await Self.run(world, check).stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(sum == "2052179976 588895", "seq 1 100000 has one checksum")
        }
    }

    @Test("a write after the snapshot keeps the source, names it, and leaves it and its snapshot in place")
    func writeAfterSnapshotKeepsSource() async throws {
        try await Self.scenario(case: "late", mounted: false) { world, datasets in
            let late =
                "sudo zfs mount \(datasets.source) && sudo sh -c 'echo late >> /\(datasets.source)/late.txt'"
                + " && sudo zfs unmount \(datasets.source)"
            let plan = Self.meanwhile(try Self.plan(world, datasets, mounted: false), world, late)

            let outcome = await Self.enact(plan, world)
            guard case EnactmentError.stepFailed(_, let status, _)? = outcome.error else {
                Issue.record("the release must refuse, got \(String(describing: outcome.error))")
                return
            }
            #expect(status == ZFSReleaseGuard.sourceKeptExitStatus)
            #expect(try await Self.exists(world, datasets.source), "the written source is kept")
            #expect(try await Self.exists(world, "\(datasets.source)@\(Self.token)"))
            #expect(
                Self.retainedNotes(outcome.events).contains {
                    $0.detail.hasPrefix("\(world.host):\(datasets.source) — it was written to after the snapshot")
                })
        }
    }

    @Test("a child created after the snapshot keeps the source")
    func newChildKeepsSource() async throws {
        try await Self.scenario(case: "newchild", mounted: false) { world, datasets in
            let plan = Self.meanwhile(
                try Self.plan(world, datasets, mounted: false),
                world,
                "sudo zfs create -o canmount=noauto \(datasets.source)/arrived")

            let outcome = await Self.enact(plan, world)
            guard case EnactmentError.stepFailed(_, let status, _)? = outcome.error else {
                Issue.record("the release must refuse, got \(String(describing: outcome.error))")
                return
            }
            #expect(status == ZFSReleaseGuard.sourceKeptExitStatus)
            #expect(try await Self.exists(world, "\(datasets.source)/arrived"))
        }
    }

    @Test("a busy dataset refuses the move before the snapshot, and the child the fence unmounted is mounted again")
    func busyFenceRefuses() async throws {
        try await Self.scenario(case: "busy", mounted: true) { world, datasets in
            try await Self.run(
                world,
                "nohup bash -c 'cd /\(datasets.source) && exec -a palana-busy-holder sleep 60' >/dev/null 2>&1 &"
                    + " sleep 0.3")

            let plan = try Self.plan(world, datasets, mounted: true)
            let outcome = await Self.enact(plan, world)
            guard case EnactmentError.stepFailed(let index, _, let tail)? = outcome.error else {
                Issue.record("the fence must refuse, got \(String(describing: outcome.error))")
                return
            }
            #expect(index == 0, "refused at the fence")
            #expect(tail.contains("could not be unmounted, so nothing was sent"))
            #expect(try await Self.mounted(world, datasets.source) == "yes")
            #expect(try await Self.mounted(world, "\(datasets.source)/child") == "yes", "remounted after the refusal")
            #expect(!(try await Self.exists(world, "\(datasets.source)@\(Self.token)")), "no snapshot was taken")
            #expect(!(try await Self.exists(world, try #require(plan.receivedDataset))), "nothing was sent")
        }
    }
}
