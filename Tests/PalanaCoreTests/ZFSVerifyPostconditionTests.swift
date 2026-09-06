// The zfs verify steps as commands, run for real against a stand-in zfs
// that answers whatever the test tells it and always exits 0 — the
// exact shape of the failure the review found: a query that ran is not
// a state that holds. Each composed verify must exit nonzero on the
// wrong answer and 0 on the right one.

import Foundation
import Testing

@testable import PalanaCore

@Suite("ZFS verify postconditions — against a stand-in zfs")
struct ZFSVerifyPostconditionTests {
    /// A `zfs` on PATH that prints the values from its environment and
    /// exits 0 regardless — the query always "runs".
    private static let shim = """
        #!/bin/sh
        case "$*" in
            *"-o value mountpoint"*) echo "$ZFS_FAKE_MOUNTPOINT" ;;
            *"-o source mountpoint"*) echo "$ZFS_FAKE_SOURCE" ;;
            *"-o mounted"*) echo "$ZFS_FAKE_MOUNTED" ;;
            *) echo "unexpected: $*" >&2; exit 2 ;;
        esac
        exit 0

        """

    private struct FakeState {
        var mountpoint = ""
        var source = ""
        var mounted = ""
    }

    /// Runs the plan's verify step in the local shell with the stand-in
    /// first on PATH and the fake state exported; answers its exit status.
    private static func runVerify(of plan: Plan, state: FakeState) async throws -> Int32 {
        let verify = try #require(plan.steps.last { $0.role == .verify })
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-zfs-shim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let zfs = directory.appendingPathComponent("zfs")
        try shim.write(to: zfs, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: zfs.path)
        let exports = [
            "export PATH=\(ShellQuote.quote(directory.path)):$PATH",
            "export ZFS_FAKE_MOUNTPOINT=\(ShellQuote.quote(state.mountpoint))",
            "export ZFS_FAKE_SOURCE=\(ShellQuote.quote(state.source))",
            "export ZFS_FAKE_MOUNTED=\(ShellQuote.quote(state.mounted))",
        ].joined(separator: "; ")
        let result = try await LocalConduit()
            .run(on: PalanaCore.localHostName, "\(exports); \(verify.command)")
            .collect()
        return result.exitStatus
    }

    private func plan(_ mutation: ZFSMutation, targetMounted: Bool = false) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .zfs,
                source: Locus(host: "jodo", directory: "/"),
                entries: [],
                zfs: mutation,
                targetMounted: targetMounted),
            facts: PlanFacts())
    }

    @Test("set-mountpoint: the old path answered with exit 0 fails the verify; the new path passes")
    func setMountpointAssertsValue() async throws {
        let plan = try plan(.setMountpoint(dataset: "tank/data", path: "/mnt/new"))
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/old")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/new")) == 0)
    }

    @Test("set-mountpoint on a mounted target also demands the remount landed")
    func setMountpointMountedAssertsRemount() async throws {
        let plan = try plan(.setMountpoint(dataset: "tank/data", path: "/mnt/new"), targetMounted: true)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/new", mounted: "no")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/old", mounted: "yes")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/new", mounted: "yes")) == 0)
    }

    @Test("set-mountpoint with a spaced path compares the whole path")
    func setMountpointSpacedPath() async throws {
        let plan = try plan(.setMountpoint(dataset: "tank/my data", path: "/mnt/my data"))
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/my")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mountpoint: "/mnt/my data")) == 0)
    }

    @Test("clear-mountpoint: a source still reading local fails; default or inherited passes")
    func clearMountpointAssertsSource() async throws {
        let plan = try plan(.clearMountpoint(dataset: "tank/data"))
        #expect(try await Self.runVerify(of: plan, state: FakeState(source: "local")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(source: "")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(source: "received")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(source: "default")) == 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(source: "inherited from tank")) == 0)
    }

    @Test("clear-mountpoint on a mounted target also demands the remount landed")
    func clearMountpointMountedAssertsRemount() async throws {
        let plan = try plan(.clearMountpoint(dataset: "tank/data"), targetMounted: true)
        #expect(
            try await Self.runVerify(of: plan, state: FakeState(source: "inherited from tank", mounted: "no")) != 0)
        #expect(
            try await Self.runVerify(of: plan, state: FakeState(source: "inherited from tank", mounted: "yes")) == 0)
    }

    @Test("mount: mounted=no answered with exit 0 fails the verify; mounted=yes passes")
    func mountAssertsYes() async throws {
        let plan = try plan(.mount(dataset: "tank/data"))
        #expect(try await Self.runVerify(of: plan, state: FakeState(mounted: "no")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mounted: "")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mounted: "yes")) == 0)
    }

    @Test("unmount: mounted=yes answered with exit 0 fails the verify; mounted=no passes")
    func unmountAssertsNo() async throws {
        let plan = try plan(.unmount(dataset: "tank/data"))
        #expect(try await Self.runVerify(of: plan, state: FakeState(mounted: "yes")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mounted: "")) != 0)
        #expect(try await Self.runVerify(of: plan, state: FakeState(mounted: "no")) == 0)
    }

    @Test("the stand-in itself exits 0 on a bare query — the old verify shape would have passed")
    func standInAlwaysRuns() async throws {
        // Documents what the assertion form protects against: the bare
        // query the previous verify steps ran is satisfied by any answer.
        let bare = Plan(
            operation: .zfs,
            classification: .zfsMutation,
            entries: [],
            totalSize: 0,
            source: Locus(host: "jodo", directory: "/"),
            destination: nil,
            transport: .local,
            steps: [
                PlanStep(runsOn: .host("jodo"), command: "zfs get -H -o value mountpoint -- tank/data", role: .verify)
            ])
        #expect(try await Self.runVerify(of: bare, state: FakeState(mountpoint: "/mnt/old")) == 0)
    }
}
