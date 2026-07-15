// ZFS mutation plan compose tests — exact command strings are the
// contract: the panel shows exactly these. Refusal tests lock the typed
// PlanError values. The Codable round-trip confirms PlanOperation and
// ZFSMutation raw values belong to the on-disk vocabulary.

import Foundation
import Testing

@testable import PalanaCore

private let jodo = Locus(host: "jodo", directory: "/")

private func planZfs(
    _ mutation: ZFSMutation, token: String = "t-unit", targetMounted: Bool = false
) throws -> Plan {
    try PlanEngine.plan(
        PlanRequest(
            operation: .zfs,
            source: jodo,
            entries: [],
            destination: nil,
            token: token,
            zfs: mutation,
            targetMounted: targetMounted),
        facts: PlanFacts())
}

@Suite("ZFSMutation compose — createDataset")
struct ZFSCreateDatasetComposeTests {
    @Test("createDataset without mountpoint composes bare zfs create")
    func createNoMountpoint() throws {
        let plan = try planZfs(.createDataset(name: "tank/data", mountpoint: nil))
        #expect(
            plan.steps.map(\.command) == [
                "zfs create tank/data",
                "zfs list -H -o name,mounted -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.create, .verify])
        #expect(plan.steps.map(\.runsOn) == [.host("jodo"), .host("jodo")])
        #expect(plan.steps.map(\.gatedOnVerification) == [false, false])
    }

    @Test("createDataset with mountpoint appends -o mountpoint")
    func createWithMountpoint() throws {
        let plan = try planZfs(.createDataset(name: "tank/data", mountpoint: "/mnt/data"))
        #expect(plan.steps[0].command == "zfs create -o mountpoint=/mnt/data tank/data")
        #expect(plan.steps[1].command == "zfs list -H -o name,mounted -- tank/data")
    }

    @Test("createDataset quotes names with spaces")
    func createSpacedName() throws {
        let plan = try planZfs(.createDataset(name: "tank/my data", mountpoint: "/mnt/my data"))
        #expect(plan.steps[0].command == "zfs create -o mountpoint='/mnt/my data' 'tank/my data'")
        #expect(plan.steps[1].command == "zfs list -H -o name,mounted -- 'tank/my data'")
    }

    @Test("createDataset classifies as zfsMutation, transports local")
    func createClassification() throws {
        let plan = try planZfs(.createDataset(name: "tank/x", mountpoint: nil))
        #expect(plan.classification == .zfsMutation)
        #expect(plan.transport == .local)
        #expect(plan.operation == .zfs)
        #expect(plan.destination == nil)
        #expect(plan.entries.isEmpty)
    }
}

@Suite("ZFSMutation compose — destroyDataset")
struct ZFSDestroyDatasetComposeTests {
    @Test("destroyDataset non-recursive omits -r")
    func destroyNonRecursive() throws {
        let plan = try planZfs(.destroyDataset(name: "tank/data", recursive: false))
        #expect(
            plan.steps.map(\.command) == [
                "zfs destroy tank/data",
                "! zfs list -H -o name -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.delete, .verify])
    }

    @Test("destroyDataset recursive appends -r")
    func destroyRecursive() throws {
        let plan = try planZfs(.destroyDataset(name: "tank/data", recursive: true))
        #expect(plan.steps[0].command == "zfs destroy -r tank/data")
        #expect(plan.steps[1].command == "! zfs list -H -o name -- tank/data")
    }

    @Test("destroyDataset quotes spaced name")
    func destroySpacedName() throws {
        let plan = try planZfs(.destroyDataset(name: "tank/my data", recursive: false))
        #expect(plan.steps[0].command == "zfs destroy 'tank/my data'")
        #expect(plan.steps[1].command == "! zfs list -H -o name -- 'tank/my data'")
    }

    @Test("destroyDataset mounted weaves sudo -n zfs unmount ahead of destroy (ho-10.4-AT-02)")
    func destroyMounted() throws {
        let plan = try planZfs(
            .destroyDataset(name: "tank/data", recursive: false), targetMounted: true)
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs unmount tank/data",
                "zfs destroy tank/data",
                "! zfs list -H -o name -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .delete, .verify])
    }

    @Test("destroyDataset unmounted composes unchanged — no unmount step")
    func destroyUnmounted() throws {
        let plan = try planZfs(
            .destroyDataset(name: "tank/data", recursive: false), targetMounted: false)
        #expect(
            plan.steps.map(\.command) == [
                "zfs destroy tank/data",
                "! zfs list -H -o name -- tank/data",
            ])
    }

    @Test("destroyDataset mounted recursive: unmount then zfs destroy -r")
    func destroyMountedRecursive() throws {
        let plan = try planZfs(
            .destroyDataset(name: "tank/data", recursive: true), targetMounted: true)
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs unmount tank/data",
                "zfs destroy -r tank/data",
                "! zfs list -H -o name -- tank/data",
            ])
    }
}

@Suite("ZFSMutation compose — renameDataset")
struct ZFSRenameDatasetComposeTests {
    @Test("renameDataset composes zfs rename and a dual-presence verify")
    func renameSimple() throws {
        let plan = try planZfs(.renameDataset(from: "tank/old", to: "tank/new"))
        #expect(
            plan.steps.map(\.command) == [
                "zfs rename -- tank/old tank/new",
                "zfs list -H -o name -- tank/new && ! zfs list -H -o name -- tank/old",
            ])
        #expect(plan.steps.map(\.role) == [.rename, .verify])
    }

    @Test("renameDataset quotes spaced names")
    func renameSpacedNames() throws {
        let plan = try planZfs(.renameDataset(from: "tank/old name", to: "tank/new name"))
        #expect(
            plan.steps[0].command == "zfs rename -- 'tank/old name' 'tank/new name'")
        #expect(
            plan.steps[1].command
                == "zfs list -H -o name -- 'tank/new name' && ! zfs list -H -o name -- 'tank/old name'"
        )
    }
}

@Suite("ZFSMutation compose — snapshot")
struct ZFSSnapshotComposeTests {
    @Test("snapshot non-recursive composes zfs snapshot without -r")
    func snapshotNonRecursive() throws {
        let plan = try planZfs(.snapshot(dataset: "tank/data", name: "bk-2026", recursive: false))
        // tank/data@bk-2026 — all chars in ShellQuote.safeCharacters (@, - included) → bare
        #expect(
            plan.steps.map(\.command) == [
                "zfs snapshot tank/data@bk-2026",
                "zfs list -H -o name -t snapshot -- tank/data@bk-2026",
            ])
        #expect(plan.steps.map(\.role) == [.snapshot, .verify])
    }

    @Test("snapshot recursive appends -r")
    func snapshotRecursive() throws {
        let plan = try planZfs(.snapshot(dataset: "tank/data", name: "bk-2026", recursive: true))
        #expect(plan.steps[0].command == "zfs snapshot -r tank/data@bk-2026")
        #expect(plan.steps[1].command == "zfs list -H -o name -t snapshot -- tank/data@bk-2026")
    }

    @Test("snapshot with at-free name composes the @-joined form")
    func snapshotDailyName() throws {
        let plan = try planZfs(.snapshot(dataset: "tank/data", name: "daily", recursive: false))
        // tank/data@daily — all safe chars → bare
        #expect(plan.steps[0].command == "zfs snapshot tank/data@daily")
        #expect(plan.steps[1].command == "zfs list -H -o name -t snapshot -- tank/data@daily")
    }
}

@Suite("ZFSMutation compose — destroySnapshot")
struct ZFSDestroySnapshotComposeTests {
    @Test("destroySnapshot composes zfs destroy and an absence verify")
    func destroySnapshot() throws {
        let plan = try planZfs(.destroySnapshot(dataset: "tank/data", name: "bk-2026"))
        // tank/data@bk-2026 → bare
        #expect(
            plan.steps.map(\.command) == [
                "zfs destroy tank/data@bk-2026",
                "! zfs list -H -o name -t snapshot -- tank/data@bk-2026",
            ])
        #expect(plan.steps.map(\.role) == [.delete, .verify])
    }
}

@Suite("ZFSMutation compose — rollback")
struct ZFSRollbackComposeTests {
    @Test("rollback composes zfs rollback and a snapshot-still-lists verify")
    func rollback() throws {
        let plan = try planZfs(.rollback(dataset: "tank/data", name: "bk-2026", destroysNewer: false))
        // tank/data@bk-2026 → bare
        #expect(
            plan.steps.map(\.command) == [
                "zfs rollback tank/data@bk-2026",
                "zfs list -H -o name -t snapshot -- tank/data@bk-2026",
            ])
        #expect(plan.steps.map(\.role) == [.rollback, .verify])
    }

    @Test("rollback with destroysNewer states its -r in the command")
    func rollbackDestroysNewer() throws {
        let plan = try planZfs(.rollback(dataset: "tank/data", name: "bk-2026", destroysNewer: true))
        #expect(plan.steps[0].command == "zfs rollback -r tank/data@bk-2026")
    }
}

@Suite("ZFSMutation compose — setMountpoint")
struct ZFSSetMountpointComposeTests {
    @Test("setMountpoint refuses a relative path — absolute or nothing")
    func setMountpointRelative() {
        #expect(throws: PlanError.zfsMountpointNotAbsolute) {
            _ = try planZfs(.setMountpoint(dataset: "tank/data", path: "~/data"))
        }
    }

    @Test("setMountpoint composes zfs set -u mountpoint and a get verify")
    func setMountpoint() throws {
        let plan = try planZfs(.setMountpoint(dataset: "tank/data", path: "/mnt/data"))
        #expect(
            plan.steps.map(\.command) == [
                "zfs set -u mountpoint=/mnt/data tank/data",
                "zfs get -H -o value mountpoint -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .verify])
    }

    @Test("setMountpoint quotes spaced path and dataset")
    func setMountpointSpaced() throws {
        let plan = try planZfs(.setMountpoint(dataset: "tank/my data", path: "/mnt/my data"))
        #expect(plan.steps[0].command == "zfs set -u mountpoint='/mnt/my data' 'tank/my data'")
        #expect(plan.steps[1].command == "zfs get -H -o value mountpoint -- 'tank/my data'")
    }

    @Test(
        "setMountpoint mounted weaves unmount · set -u · sudo -n zfs mount (ho-10.4-AT-04)")
    func setMountpointMounted() throws {
        let plan = try planZfs(
            .setMountpoint(dataset: "tank/data", path: "/mnt/data"), targetMounted: true)
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs unmount tank/data",
                "zfs set -u mountpoint=/mnt/data tank/data",
                "sudo -n zfs mount tank/data",
                "zfs get -H -o value mountpoint -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .property, .property, .verify])
    }

    @Test("setMountpoint unmounted composes unchanged — set -u only, no remount")
    func setMountpointUnmounted() throws {
        let plan = try planZfs(
            .setMountpoint(dataset: "tank/data", path: "/mnt/data"), targetMounted: false)
        #expect(
            plan.steps.map(\.command) == [
                "zfs set -u mountpoint=/mnt/data tank/data",
                "zfs get -H -o value mountpoint -- tank/data",
            ])
    }
}

@Suite("ZFSMutation compose — clearMountpoint")
struct ZFSClearMountpointComposeTests {
    @Test("clearMountpoint composes zfs inherit mountpoint and a get verify")
    func clearMountpoint() throws {
        let plan = try planZfs(.clearMountpoint(dataset: "tank/data"))
        #expect(
            plan.steps.map(\.command) == [
                "zfs inherit mountpoint tank/data",
                "zfs get -H -o value mountpoint -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .verify])
    }

    @Test("clearMountpoint mounted weaves unmount · inherit · sudo -n zfs mount (ho-10.4-AT-02)")
    func clearMountpointMounted() throws {
        let plan = try planZfs(.clearMountpoint(dataset: "tank/data"), targetMounted: true)
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs unmount tank/data",
                "zfs inherit mountpoint tank/data",
                "sudo -n zfs mount tank/data",
                "zfs get -H -o value mountpoint -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .property, .property, .verify])
    }

    @Test("clearMountpoint unmounted composes unchanged — inherit only, no remount")
    func clearMountpointUnmounted() throws {
        let plan = try planZfs(.clearMountpoint(dataset: "tank/data"), targetMounted: false)
        #expect(
            plan.steps.map(\.command) == [
                "zfs inherit mountpoint tank/data",
                "zfs get -H -o value mountpoint -- tank/data",
            ])
    }
}

@Suite("ZFSMutation compose — mount")
struct ZFSMountComposeTests {
    @Test("mount composes sudo -n zfs mount and an unprivileged verify")
    func mount() throws {
        let plan = try planZfs(.mount(dataset: "tank/data"))
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs mount tank/data",
                "zfs list -H -o name,mounted -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .verify])
    }

    @Test("mount quotes spaced dataset in both the mutating and verify commands")
    func mountSpacedName() throws {
        let plan = try planZfs(.mount(dataset: "tank/my data"))
        #expect(plan.steps[0].command == "sudo -n zfs mount 'tank/my data'")
        #expect(plan.steps[1].command == "zfs list -H -o name,mounted -- 'tank/my data'")
    }

    @Test("mount composes on the pool root — mounting is never destructive")
    func mountPoolRootAllowed() throws {
        let plan = try planZfs(.mount(dataset: "tank"))
        #expect(plan.steps[0].command == "sudo -n zfs mount tank")
        #expect(plan.steps[1].command == "zfs list -H -o name,mounted -- tank")
    }
}

@Suite("ZFSMutation compose — unmount")
struct ZFSUnmountComposeTests {
    @Test("unmount composes sudo -n zfs unmount and an unprivileged verify")
    func unmount() throws {
        let plan = try planZfs(.unmount(dataset: "tank/data"))
        #expect(
            plan.steps.map(\.command) == [
                "sudo -n zfs unmount tank/data",
                "zfs list -H -o name,mounted -- tank/data",
            ])
        #expect(plan.steps.map(\.role) == [.property, .verify])
    }

    @Test("unmount quotes spaced dataset in both the mutating and verify commands")
    func unmountSpacedName() throws {
        let plan = try planZfs(.unmount(dataset: "tank/my data"))
        #expect(plan.steps[0].command == "sudo -n zfs unmount 'tank/my data'")
        #expect(plan.steps[1].command == "zfs list -H -o name,mounted -- 'tank/my data'")
    }

    @Test("unmount composes on the pool root — unmounting is never destructive")
    func unmountPoolRootAllowed() throws {
        let plan = try planZfs(.unmount(dataset: "tank"))
        #expect(plan.steps[0].command == "sudo -n zfs unmount tank")
        #expect(plan.steps[1].command == "zfs list -H -o name,mounted -- tank")
    }
}

@Suite("ZFSMutation validation")
struct ZFSMutationValidationTests {
    @Test("zfs operation without payload throws zfsMutationPayloadRequired")
    func missingPayload() {
        #expect(throws: PlanError.zfsMutationPayloadRequired) {
            _ = try PlanEngine.plan(
                PlanRequest(
                    operation: .zfs,
                    source: jodo,
                    entries: [],
                    zfs: nil),
                facts: PlanFacts())
        }
    }

    @Test("createDataset refuses empty name")
    func createEmptyName() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.createDataset(name: "", mountpoint: nil))
        }
    }

    @Test("destroyDataset refuses empty name")
    func destroyEmptyName() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.destroyDataset(name: "", recursive: false))
        }
    }

    @Test("renameDataset refuses empty from")
    func renameEmptyFrom() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.renameDataset(from: "", to: "tank/new"))
        }
    }

    @Test("renameDataset refuses empty to")
    func renameEmptyTo() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.renameDataset(from: "tank/old", to: ""))
        }
    }

    @Test("renameDataset refuses identical from and to")
    func renameIdentical() {
        #expect(throws: PlanError.zfsRenameNamesIdentical) {
            _ = try planZfs(.renameDataset(from: "tank/data", to: "tank/data"))
        }
    }

    @Test("destroyDataset refuses the pool root")
    func destroyPoolRoot() {
        #expect(throws: PlanError.zfsPoolRootRefused) {
            _ = try planZfs(.destroyDataset(name: "tank", recursive: false))
        }
    }

    @Test("destroyDataset refuses the pool root even recursive")
    func destroyPoolRootRecursive() {
        #expect(throws: PlanError.zfsPoolRootRefused) {
            _ = try planZfs(.destroyDataset(name: "tank", recursive: true))
        }
    }

    @Test("renameDataset refuses the pool root as source")
    func renamePoolRoot() {
        #expect(throws: PlanError.zfsPoolRootRefused) {
            _ = try planZfs(.renameDataset(from: "tank", to: "lake"))
        }
    }

    @Test("snapshot composes on the pool root — only destroy and rename refuse it")
    func snapshotPoolRootAllowed() throws {
        let plan = try planZfs(.snapshot(dataset: "tank", name: "nightly", recursive: false))
        #expect(plan.steps[0].command == "zfs snapshot tank@nightly")
    }

    @Test("snapshot refuses empty dataset name")
    func snapshotEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.snapshot(dataset: "", name: "snap", recursive: false))
        }
    }

    @Test("snapshot refuses empty snapshot name")
    func snapshotEmptyName() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.snapshot(dataset: "tank/data", name: "", recursive: false))
        }
    }

    @Test("snapshot refuses snapshot name containing @")
    func snapshotNameWithAt() {
        #expect(throws: PlanError.zfsSnapshotNameContainsAt) {
            _ = try planZfs(
                .snapshot(dataset: "tank/data", name: "tank/data@bad", recursive: false))
        }
    }

    @Test("destroySnapshot refuses empty dataset name")
    func destroySnapshotEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.destroySnapshot(dataset: "", name: "snap"))
        }
    }

    @Test("destroySnapshot refuses empty snapshot name")
    func destroySnapshotEmptyName() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.destroySnapshot(dataset: "tank/data", name: ""))
        }
    }

    @Test("rollback refuses empty dataset name")
    func rollbackEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.rollback(dataset: "", name: "snap", destroysNewer: false))
        }
    }

    @Test("rollback refuses empty snapshot name")
    func rollbackEmptyName() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.rollback(dataset: "tank/data", name: "", destroysNewer: false))
        }
    }

    @Test("setMountpoint refuses empty dataset name")
    func setMountpointEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.setMountpoint(dataset: "", path: "/mnt"))
        }
    }

    @Test("setMountpoint refuses empty path")
    func setMountpointEmptyPath() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.setMountpoint(dataset: "tank/data", path: ""))
        }
    }

    @Test("clearMountpoint refuses empty dataset name")
    func clearMountpointEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.clearMountpoint(dataset: ""))
        }
    }

    @Test("mount refuses empty dataset name")
    func mountEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.mount(dataset: ""))
        }
    }

    @Test("unmount refuses empty dataset name")
    func unmountEmptyDataset() {
        #expect(throws: PlanError.zfsNameEmpty) {
            _ = try planZfs(.unmount(dataset: ""))
        }
    }
}

@Suite("ZFSMutation Codable")
struct ZFSMutationCodableTests {
    @Test("a .zfs Plan round-trips JSON — PlanOperation raw value is 'zfs'")
    func codableRoundTrip() throws {
        let plan = try planZfs(.createDataset(name: "tank/data", mountpoint: nil))
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded == plan)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"zfs\""), "PlanOperation.zfs raw value is 'zfs'")
        #expect(json.contains("\"zfs mutation\""), "Classification.zfsMutation raw value is 'zfs mutation'")
    }

    @Test("ZFSMutation itself round-trips Codable")
    func zfsMutationCodable() throws {
        let mutations: [ZFSMutation] = [
            .createDataset(name: "tank/a", mountpoint: "/mnt/a"),
            .destroyDataset(name: "tank/b", recursive: true),
            .renameDataset(from: "tank/c", to: "tank/d"),
            .snapshot(dataset: "tank/e", name: "snap1", recursive: false),
            .destroySnapshot(dataset: "tank/f", name: "snap2"),
            .rollback(dataset: "tank/g", name: "snap3", destroysNewer: true),
            .setMountpoint(dataset: "tank/h", path: "/mnt/h"),
            .clearMountpoint(dataset: "tank/i"),
            .mount(dataset: "tank/j"),
            .unmount(dataset: "tank/k"),
        ]
        for mutation in mutations {
            let data = try JSONEncoder().encode(mutation)
            let decoded = try JSONDecoder().decode(ZFSMutation.self, from: data)
            #expect(decoded == mutation)
        }
    }
}
