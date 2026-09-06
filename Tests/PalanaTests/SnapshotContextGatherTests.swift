// The snapshot-context read belongs to the gather that started it.
// Two gathers in a row, the first one's answer arriving late: the late
// answer must land nowhere — not under the second gather's field, and
// not as a dismissal of it. Split from TopologyBindingEnactmentTests for
// that class's length budget; same sequenced-conduit fixture.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class SnapshotContextGatherTests: XCTestCase {
    private static let host = "fixture"
    private var directory = URL(fileURLWithPath: "/")
    private let zfsTool = ZFSMutationTool()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-snapshots-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeOperation(conduit: SequencedConduit) -> OperationModel {
        let configuration = SSHConfiguration()
        let field = Field(
            conduit: conduit,
            hosts: [Self.host],
            cache: FieldCache(url: directory.appendingPathComponent("field-cache.json")))
        let engine = Engine(
            conduit: SSHConduit(configuration: configuration),
            field: field,
            listing: Listing(conduit: conduit))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        return OperationModel(
            engine: engine,
            configuration: configuration,
            settings: settings,
            log: OperationLog(url: directory.appendingPathComponent("operations.log")))
    }

    private func verb(_ id: String) throws -> WorkbenchVerb {
        try XCTUnwrap(zfsTool.verbs.first { $0.id == id })
    }

    private func transcript(_ operation: OperationModel) -> [String] {
        operation.echo.lines.map(\.text)
    }

    @discardableResult
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func snapshotCommand(_ dataset: String) -> String {
        "zfs list -H -t snapshot -o name -s creation -- \(dataset)"
    }

    func testLateSnapshotContextCannotAlterAnotherGather() async throws {
        let conduit = SequencedConduit()
        conduit.enqueue(Self.host, snapshotCommand("tank/a"), [.init(stdout: "tank/a@a1\n")])
        conduit.enqueue(Self.host, snapshotCommand("tank/b"), [.init(stdout: "tank/b@b1\n")])
        conduit.hold(Self.host, snapshotCommand("tank/a"))
        let operation = makeOperation(conduit: conduit)

        operation.beginZFSMutation(try verb("zfs-rollback"), tool: zfsTool, host: Self.host, dataset: "tank/a")
        await waitUntil { conduit.isWaiting(Self.host, self.snapshotCommand("tank/a")) }
        operation.beginZFSMutation(try verb("zfs-rollback"), tool: zfsTool, host: Self.host, dataset: "tank/b")
        await waitUntil { operation.namingContextLines == ["b1"] }
        XCTAssertEqual(operation.namingContextLines, ["b1"])

        // Now tank/a's read comes back, late.
        conduit.release(Self.host, snapshotCommand("tank/a"))
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(operation.pendingZFSDataset, "tank/b")
        XCTAssertEqual(operation.namingContextLines, ["b1"], "tank/a's snapshots never show under tank/b's field")
        XCTAssertEqual(operation.phase, .naming)
    }

    func testLateEmptySnapshotContextCannotDismissAnotherGather() async throws {
        let conduit = SequencedConduit()
        conduit.enqueue(Self.host, snapshotCommand("tank/a"), [.init(stdout: "")])
        conduit.enqueue(Self.host, snapshotCommand("tank/b"), [.init(stdout: "tank/b@b1\n")])
        conduit.hold(Self.host, snapshotCommand("tank/a"))
        let operation = makeOperation(conduit: conduit)

        operation.beginZFSMutation(
            try verb("zfs-destroy-snapshot"), tool: zfsTool, host: Self.host, dataset: "tank/a")
        await waitUntil { conduit.isWaiting(Self.host, self.snapshotCommand("tank/a")) }
        operation.beginZFSMutation(
            try verb("zfs-destroy-snapshot"), tool: zfsTool, host: Self.host, dataset: "tank/b")
        await waitUntil { operation.namingContextLines == ["b1"] }

        conduit.release(Self.host, snapshotCommand("tank/a"))
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(operation.phase, .naming, "tank/a's empty list never dismissed tank/b's gather")
        XCTAssertEqual(operation.pendingZFSDataset, "tank/b")
        XCTAssertEqual(operation.namingContextLines, ["b1"])
        XCTAssertFalse(transcript(operation).contains("no snapshots on tank/a — nothing to act on"))
    }

    func testSnapshotContextForTheCurrentGatherStillLands() async throws {
        let conduit = SequencedConduit()
        conduit.enqueue(Self.host, snapshotCommand("tank/a"), [.init(stdout: "tank/a@old\ntank/a@new\n")])
        let operation = makeOperation(conduit: conduit)
        operation.beginZFSMutation(try verb("zfs-rollback"), tool: zfsTool, host: Self.host, dataset: "tank/a")
        await waitUntil { !operation.namingContextLines.isEmpty }
        XCTAssertEqual(operation.namingContextLines, ["old", "new"])

        // An empty list on the current gather still dismisses it, with the note.
        let empty = SequencedConduit()
        empty.enqueue(Self.host, snapshotCommand("tank/bare"), [.init(stdout: "")])
        let bare = makeOperation(conduit: empty)
        bare.beginZFSMutation(try verb("zfs-rollback"), tool: zfsTool, host: Self.host, dataset: "tank/bare")
        await waitUntil { bare.phase == .idle }
        XCTAssertEqual(bare.phase, .idle)
        XCTAssertTrue(bare.panelShowing)
        XCTAssertTrue(transcript(bare).contains("no snapshots on tank/bare — nothing to act on"))
    }

    func testAFileVerbCancelsThePendingSnapshotRead() async throws {
        let conduit = SequencedConduit()
        conduit.enqueue(Self.host, snapshotCommand("tank/a"), [.init(stdout: "tank/a@a1\n")])
        conduit.hold(Self.host, snapshotCommand("tank/a"))
        let operation = makeOperation(conduit: conduit)
        operation.beginZFSMutation(try verb("zfs-rollback"), tool: zfsTool, host: Self.host, dataset: "tank/a")
        await waitUntil { conduit.isWaiting(Self.host, self.snapshotCommand("tank/a")) }
        let task = try XCTUnwrap(operation.snapshotContextTask)

        operation.clearZFSGatherState()
        XCTAssertTrue(task.isCancelled)
        XCTAssertNil(operation.snapshotContextTask)
        conduit.release(Self.host, snapshotCommand("tank/a"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(operation.namingContextLines, [])
    }
}
