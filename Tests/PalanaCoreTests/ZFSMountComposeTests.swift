// ZFS mount and unmount compose tests — split from ZFSMutationPlanTests
// for that file's length budget. Same contract: the exact command strings
// are what the panel shows, and the verify asserts the mounted state
// asked for rather than that a list ran.

import Foundation
import Testing

@testable import PalanaCore

private let jodo = Locus(host: "jodo", directory: "/")

private func planZfs(_ mutation: ZFSMutation) throws -> Plan {
    try PlanEngine.plan(
        PlanRequest(operation: .zfs, source: jodo, entries: [], destination: nil, token: "t-unit", zfs: mutation),
        facts: PlanFacts())
}

@Suite("ZFSMutation compose — mount")
struct ZFSMountComposeTests {
    @Test("mount composes sudo -n zfs mount and an unprivileged verify that asserts mounted=yes")
    func mount() throws {
        let plan = try planZfs(.mount(dataset: "tank/data"))
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs mount tank/data",
                "test \"$(zfs list -H -o mounted -- tank/data)\" = yes",
            ])
        #expect(plan.steps.map(\.role) == [.property, .verify])
    }

    @Test("mount quotes spaced dataset in both the mutating and verify commands")
    func mountSpacedName() throws {
        let plan = try planZfs(.mount(dataset: "tank/my data"))
        #expect(plan.steps[0].command == "sudo -n zfs mount 'tank/my data'")
        #expect(plan.steps[1].command == "test \"$(zfs list -H -o mounted -- 'tank/my data')\" = yes")
    }

    @Test("mount composes on the pool root — mounting is never destructive")
    func mountPoolRootAllowed() throws {
        let plan = try planZfs(.mount(dataset: "tank"))
        #expect(plan.steps[0].command == "sudo -n zfs mount tank")
        #expect(plan.steps[1].command == "test \"$(zfs list -H -o mounted -- tank)\" = yes")
    }
}

@Suite("ZFSMutation compose — unmount")
struct ZFSUnmountComposeTests {
    @Test("unmount composes sudo -n zfs unmount and an unprivileged verify that asserts mounted=no")
    func unmount() throws {
        let plan = try planZfs(.unmount(dataset: "tank/data"))
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs unmount tank/data",
                "test \"$(zfs list -H -o mounted -- tank/data)\" = no",
            ])
        #expect(plan.steps.map(\.role) == [.property, .verify])
    }

    @Test("unmount quotes spaced dataset in both the mutating and verify commands")
    func unmountSpacedName() throws {
        let plan = try planZfs(.unmount(dataset: "tank/my data"))
        #expect(plan.steps[0].command == "sudo -n zfs unmount 'tank/my data'")
        #expect(plan.steps[1].command == "test \"$(zfs list -H -o mounted -- 'tank/my data')\" = no")
    }

    @Test("unmount composes on the pool root — unmounting is never destructive")
    func unmountPoolRootAllowed() throws {
        let plan = try planZfs(.unmount(dataset: "tank"))
        #expect(plan.steps[0].command == "sudo -n zfs unmount tank")
        #expect(plan.steps[1].command == "test \"$(zfs list -H -o mounted -- tank)\" = no")
    }
}
