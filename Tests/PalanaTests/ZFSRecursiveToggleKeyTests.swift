// The recursive toggle's keyboard path (Ho-10.4-AT-03). The hands session
// hit destroy failing on a snapshotted dataset — the -r flag was never
// reachable without the mouse. Space flips `zfsRecursive` while a ZFS
// gather that offers the choice is showing; `r` is out because snapshot
// and rollback take a typed name and `r` is a legal character in one.
// These tests pin the model-level flip (`toggleZFSRecursiveIfOffered`) —
// the routing that swallows space ahead of the field is UI-only (a local
// NSEvent monitor) and is exercised by hand per the task's note.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class ZFSRecursiveToggleKeyTests: XCTestCase {
    /// Builds a bare operation model with no wire traffic.
    ///
    /// `Field` and `Listing` take `RecordedConduit` over an empty transcript
    /// (`PalanaCoreTests`' fixture idiom); `Engine.conduit` is typed
    /// concretely as `SSHConduit` and goes unused by these tests — the
    /// gather/toggle path under test never reaches it. `confirmDestroyTyped`
    /// is forced off so `zfs-destroy` gathers field-less, as the settings
    /// default (`true`) would otherwise grow it a text field and make it
    /// indistinguishable from snapshot/rollback for this suite's purposes.
    private func makeOperation() -> OperationModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let configuration = SSHConfiguration()
        let field = Field(conduit: recorded, hosts: ["test-host"], cache: FieldCache())
        let engine = Engine(
            conduit: SSHConduit(configuration: configuration),
            field: field,
            listing: Listing(conduit: recorded))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        settings.confirmDestroyTyped = false
        return OperationModel(engine: engine, configuration: configuration, settings: settings)
    }

    private let zfsTool = ZFSMutationTool()

    private func verb(_ id: String) throws -> WorkbenchVerb {
        try XCTUnwrap(zfsTool.verbs.first { $0.id == id })
    }

    /// Destroy (field-less, offers recursive): space flips true→false→true.
    func testSpaceFlipsRecursiveForFieldlessOfferingGather() throws {
        let operation = makeOperation()
        operation.beginZFSMutation(
            try verb("zfs-destroy"), tool: zfsTool, host: "test-host", dataset: "pool/data")
        XCTAssertFalse(operation.zfsRecursive)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertTrue(operation.zfsRecursive)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertFalse(operation.zfsRecursive)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertTrue(operation.zfsRecursive)
    }

    /// Snapshot (text gather, offers recursive): same flip, same model call —
    /// the text-gather key route shares `toggleZFSRecursiveIfOffered` with
    /// the field-less route rather than duplicating the flip logic.
    func testSpaceFlipsRecursiveForTextOfferingGather() throws {
        let operation = makeOperation()
        operation.beginZFSMutation(
            try verb("zfs-snapshot"), tool: zfsTool, host: "test-host", dataset: "pool/data")
        XCTAssertTrue(operation.zfsGatherWantsText)
        XCTAssertTrue(operation.isRecursiveOfferingZFSGather)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertTrue(operation.zfsRecursive)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertFalse(operation.zfsRecursive)
    }

    /// Rollback (text gather, offers recursive) — the third verb the spec names.
    func testSpaceFlipsRecursiveForRollback() throws {
        let operation = makeOperation()
        operation.beginZFSMutation(
            try verb("zfs-rollback"), tool: zfsTool, host: "test-host", dataset: "pool/data")

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertTrue(operation.zfsRecursive)
    }

    /// A verb that does NOT offer recursive (create, a text gather): the
    /// flip is a no-op passthrough — recursive stays false.
    func testToggleIsNoOpWhenGatherDoesNotOfferRecursive() throws {
        let operation = makeOperation()
        operation.beginZFSMutation(
            try verb("zfs-create"), tool: zfsTool, host: "test-host", dataset: "pool/data")
        XCTAssertFalse(operation.isRecursiveOfferingZFSGather)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertFalse(operation.zfsRecursive)
    }

    /// No pending ZFS gather at all: the flip touches nothing, no crash.
    func testToggleIsNoOpWithNoPendingVerb() {
        let operation = makeOperation()
        XCTAssertNil(operation.pendingZFSVerb)

        operation.toggleZFSRecursiveIfOffered()
        XCTAssertFalse(operation.zfsRecursive)
    }

    /// `isFieldlessZFSGather` and `isRecursiveOfferingZFSGather` agree for
    /// destroy — the field-less branch in `handleTextEntryPriority` fires
    /// first, so the text-gather branch's guard never double-handles it.
    func testFieldlessOfferingGatherSatisfiesBothPredicates() throws {
        let operation = makeOperation()
        operation.beginZFSMutation(
            try verb("zfs-destroy"), tool: zfsTool, host: "test-host", dataset: "pool/data")

        XCTAssertTrue(operation.isFieldlessZFSGather)
        XCTAssertTrue(operation.isRecursiveOfferingZFSGather)
    }
}
