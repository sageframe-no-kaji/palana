// The gather's side of the version binding. Before this, a save composed
// a plain copy: the digest it had just read went nowhere, so anything
// that changed the destination between the check and the upload was
// overwritten without a word. Every case here reads a real directory on
// this Mac through the local door and asks one question of the composed
// plan — what version is it bound to.

import Foundation
import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class RoundTripCommitGatherTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/")
    private var openDirectory: URL { root.appendingPathComponent("open") }
    private var remote: URL { root.appendingPathComponent("remote") }
    private let fileName = "note.txt"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-gather-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: openDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: openDirectory.appendingPathComponent(fileName))
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: remote.appendingPathComponent(fileName).path)
        try? FileManager.default.removeItem(at: root)
    }

    /// An operation model whose every read runs on this Mac.
    private func makeOperation() -> OperationModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let field = Field(conduit: recorded, hosts: [], cache: FieldCache())
        let engine = Engine(conduit: recorded, field: field, listing: Listing(conduit: recorded))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        // Ask, so the gather arms the plan and stops instead of enacting.
        settings.askBeforeSendingBack = true
        return OperationModel(
            engine: engine,
            configuration: SSHConfiguration(),
            settings: settings,
            log: OperationLog(url: root.appendingPathComponent("operations.log")))
    }

    /// The destination entry as the local listing actually reports it.
    private func remoteEntry() async throws -> FileEntry {
        let entries = try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: remote.path, flavor: .bsd)
        return try XCTUnwrap(entries.first { $0.name == fileName })
    }

    private func record(fetched: FileEntry, digest: Data) -> RoundTripRecord {
        RoundTripRecord(
            host: PalanaCore.localHostName,
            remoteDirectory: remote.path,
            fetched: fetched,
            digest: digest,
            localURL: openDirectory.appendingPathComponent(fileName))
    }

    private func hex(_ text: String) -> String {
        RoundTrip.hex(RoundTrip.digest(of: Data(text.utf8)))
    }

    func testCleanCheckBindsThePlanToTheVersionItRead() async throws {
        try Data("checked".utf8).write(to: remote.appendingPathComponent(fileName))
        let entry = try await remoteEntry()
        let operation = makeOperation()

        await operation.gatherRoundTripUpload(
            record: record(fetched: entry, digest: RoundTrip.digest(of: Data("checked".utf8))))

        XCTAssertEqual(operation.phase, .ready)
        let plan = try XCTUnwrap(operation.plan)
        let bound = try XCTUnwrap(plan.versionGuard)
        XCTAssertEqual(bound.host, PalanaCore.localHostName)
        XCTAssertEqual(bound.pathData, Data(remote.appendingPathComponent(fileName).path.utf8))
        XCTAssertEqual(bound.expectedDigest, hex("checked"))
        XCTAssertEqual(plan.steps.map(\.role), [.stage, .copy, .promote])
        XCTAssertEqual(plan.steps.last?.command.contains(bound.target), true)
    }

    func testAConflictBindsToWhatStandsThereNowNotToTheFetchedBaseline() async throws {
        try Data("theirs, longer".utf8).write(to: remote.appendingPathComponent(fileName))
        var stale = try await remoteEntry()
        // The record remembers a smaller file — the metadata conflict the
        // operator is asked to confirm.
        stale.size = 2
        let operation = makeOperation()

        await operation.gatherRoundTripUpload(
            record: record(fetched: stale, digest: RoundTrip.digest(of: Data("as fetched".utf8))))

        XCTAssertEqual(operation.phase, .ready)
        let bound = try XCTUnwrap(operation.plan?.versionGuard)
        // Enter authorises the version the check read, never the one the
        // record remembers and never whatever arrives later.
        XCTAssertEqual(bound.expectedDigest, hex("theirs, longer"))
    }

    func testAMissingRemoteBindsToAbsence() async throws {
        var stale = try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: openDirectory.path, flavor: .bsd)
            .first { $0.name == fileName }
        stale?.size = 2
        let entry = try XCTUnwrap(stale)
        let operation = makeOperation()

        await operation.gatherRoundTripUpload(
            record: record(fetched: entry, digest: RoundTrip.digest(of: Data("gone".utf8))))

        XCTAssertEqual(operation.phase, .ready)
        let bound = try XCTUnwrap(operation.plan?.versionGuard)
        XCTAssertTrue(bound.expectsAbsence)
    }

    func testAConflictWhoseBytesCannotBeReadComposesNoPlan() async throws {
        let target = remote.appendingPathComponent(fileName)
        try Data("unreadable".utf8).write(to: target)
        var stale = try await remoteEntry()
        stale.size = 2
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: target.path)
        let operation = makeOperation()

        await operation.gatherRoundTripUpload(
            record: record(fetched: stale, digest: RoundTrip.digest(of: Data("as fetched".utf8))))

        XCTAssertEqual(operation.phase, .failed)
        XCTAssertNil(operation.plan, "an unbindable send-back composes nothing")
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(failure.text.contains("couldn't pin what stands at"))
        let size = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int
        XCTAssertEqual(size, 10, "the destination is untouched")
    }
}
