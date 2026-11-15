// The surface side of the rename commit: which failure offers it, that
// the offer withdraws with its failure, and that one click runs the same
// send-back committed by rename. The run is real, on this Mac, through
// the local door.

import Foundation
import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class RenameCommitOfferTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/")
    private var edit: URL { root.appendingPathComponent("edit") }
    private var remote: URL { root.appendingPathComponent("remote") }
    private let fileName = "note.txt"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-rename-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: edit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: edit.appendingPathComponent(fileName))
        try Data("checked".utf8).write(to: remote.appendingPathComponent(fileName))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeOperation() -> OperationModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let field = Field(conduit: recorded, hosts: [], cache: FieldCache())
        let engine = Engine(conduit: recorded, field: field, listing: Listing(conduit: recorded))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        return OperationModel(
            engine: engine,
            configuration: SSHConfiguration(),
            settings: settings,
            log: OperationLog(url: root.appendingPathComponent("operations.log")))
    }

    /// A link-mode send-back of the edit over the checked version, local to local.
    private func sendBack() throws -> Plan {
        let entry = FileEntry(
            nameData: Data(fileName.utf8),
            kind: .file,
            size: 4,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
        let versionGuard = RemoteVersionGuard(
            host: PalanaCore.localHostName,
            pathData: RemoteIdentity.pathData(directory: remote.path, name: Data(fileName.utf8)),
            expectedDigest: RoundTrip.hex(RoundTrip.digest(of: Data("checked".utf8))),
            token: "t1")
        return try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: PalanaCore.localHostName, directory: edit.path),
                entries: [entry],
                destination: Locus(host: PalanaCore.localHostName, directory: remote.path),
                token: "t1",
                versionGuard: versionGuard),
            facts: PlanFacts())
    }

    private func promoteIndex(_ plan: Plan) throws -> Int {
        try XCTUnwrap(plan.steps.firstIndex { $0.role == .promote })
    }

    @discardableResult
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func testOnlyTheNoHardLinkRefusalOfTheCommitOffersRename() throws {
        let plan = try sendBack()
        let promote = try promoteIndex(plan)
        let refused = EnactmentError.stepFailed(
            index: promote, exitStatus: RemoteVersionGuard.noHardLinkExitStatus, stderrTail: "")
        XCTAssertEqual(OperationModel.renameCommitOffer(for: plan, after: refused), plan.renameCommitted())
        XCTAssertNotNil(OperationModel.renameCommitOffer(for: plan, after: refused))

        let otherStatus = EnactmentError.stepFailed(index: promote, exitStatus: 7, stderrTail: "")
        XCTAssertNil(OperationModel.renameCommitOffer(for: plan, after: otherStatus))
        let otherStep = EnactmentError.stepFailed(
            index: 0, exitStatus: RemoteVersionGuard.noHardLinkExitStatus, stderrTail: "")
        XCTAssertNil(OperationModel.renameCommitOffer(for: plan, after: otherStep))
        XCTAssertNil(OperationModel.renameCommitOffer(for: plan, after: CancellationError()))
        XCTAssertNil(OperationModel.renameCommitOffer(for: nil, after: refused))
    }

    func testTheOfferWithdrawsWhenTheFailureIsLeft() throws {
        let operation = makeOperation()
        let plan = try sendBack()
        operation.plan = plan
        operation.phase = .failed
        operation.renameCommitOffer = plan.renameCommitted()
        operation.phase = .idle
        XCTAssertNil(operation.renameCommitOffer)
    }

    func testOneClickRunsTheSendBackCommittedByRename() async throws {
        let operation = makeOperation()
        let plan = try sendBack()
        let offer = try XCTUnwrap(plan.renameCommitted())
        operation.requested = .copy
        operation.plan = plan
        operation.phase = .failed
        // A failure always brings the panel forward; the offer lives there.
        operation.panelShowing = true
        operation.renameCommitOffer = offer

        operation.acceptRenameCommit()

        XCTAssertEqual(operation.plan, offer)
        XCTAssertNil(operation.renameCommitOffer)
        await waitUntil { operation.phase != .enacting }
        XCTAssertEqual(operation.phase, .finished, operation.echo.lines.map(\.text).joined(separator: "\n"))
        let landed = try Data(contentsOf: remote.appendingPathComponent(fileName))
        XCTAssertEqual(String(bytes: landed, encoding: .utf8), "mine")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: remote.path)
        XCTAssertEqual(leftovers, [fileName])
    }

    func testAcceptDoesNothingWithoutAnOffer() throws {
        let operation = makeOperation()
        operation.plan = try sendBack()
        operation.phase = .failed
        operation.acceptRenameCommit()
        XCTAssertEqual(operation.phase, .failed)
    }
}
