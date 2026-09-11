// The app's side of the local-move repair: this Mac's mount table is
// read for the same-filesystem proof, remote hosts keep their
// remembered table, and the panel's sentences name a manifest
// difference and a kind-clash refusal.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class LocalPlacementTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/")

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-placement-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A bare operation model whose log lands in the test directory.
    private func makeOperation() -> OperationModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let configuration = SSHConfiguration()
        let field = Field(conduit: recorded, hosts: ["test-host"], cache: FieldCache())
        let engine = Engine(
            conduit: recorded,
            field: field,
            listing: Listing(conduit: recorded))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        return OperationModel(
            engine: engine,
            configuration: configuration,
            settings: settings,
            log: OperationLog(url: directory.appendingPathComponent("operations.log")))
    }

    func testLocalMountsAreReadFromThisMac() async throws {
        let operation = makeOperation()
        let read = await operation.localMounts()
        let mounts = try XCTUnwrap(read)
        XCTAssertEqual(MountTable.mountContaining("/", in: mounts), "/")
        // The temporary directory lives on some mounted volume — the
        // proof the engine needs is that a target contains it at all.
        XCTAssertNotNil(MountTable.mountContaining(directory.path, in: mounts))
    }

    func testPlacementMountsReadThisMacAndRememberRemotes() async throws {
        let operation = makeOperation()
        let local = Locus(host: PalanaCore.localHostName, directory: "/Users/op")
        let placed = await operation.placementMounts(for: local, remembered: nil)
        let localMounts = try XCTUnwrap(placed)
        XCTAssertTrue(localMounts.contains { $0.target == "/" })

        let remembered = HostFacts(
            mounts: Dated(
                value: [Mount(source: "tank/data", target: "/tank/data", fstype: "zfs", readOnly: false)],
                discoveredAt: Date()))
        let remote = Locus(host: "jodo", directory: "/tank/data/x")
        let remoteMounts = await operation.placementMounts(for: remote, remembered: remembered)
        XCTAssertEqual(remoteMounts?.map(\.target), ["/tank/data"])
        let unmet = await operation.placementMounts(for: remote, remembered: nil)
        XCTAssertNil(unmet)
    }

    func testManifestReportSentencesNameTheDifference() throws {
        let hello = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let world = "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7"
        let source = TransferManifest(entries: [
            TransferManifest.Entry(name: Data("f1".utf8), kind: .file, size: 5, digest: hello),
            TransferManifest.Entry(name: Data("f2".utf8), kind: .file, size: 5, digest: hello),
        ])
        let tampered = TransferManifest(entries: [
            TransferManifest.Entry(name: Data("f1".utf8), kind: .file, size: 5, digest: hello),
            TransferManifest.Entry(name: Data("f2".utf8), kind: .file, size: 5, digest: world),
        ])
        XCTAssertEqual(
            OperationModel.describe(.manifests(source: source, destination: source)),
            "checked 2 at source, 2 at destination — identical")
        XCTAssertEqual(
            OperationModel.describe(.manifests(source: source, destination: tampered)),
            "checked 2 at source, 2 at destination — DIFFERENT at f2")
        let merged = TransferManifest(
            entries: source.entries + [
                TransferManifest.Entry(name: Data("old".utf8), kind: .file, size: 5, digest: hello)
            ])
        XCTAssertEqual(
            OperationModel.describe(.manifests(source: source, destination: merged)),
            "checked 2 at source, 3 at destination — every source entry landed · 1 already there, kept")
        let shorter = TransferManifest(entries: [source.entries[0]])
        XCTAssertEqual(
            OperationModel.describe(.manifests(source: source, destination: shorter)),
            "checked 2 at source, 1 at destination — DIFFERENT at f2")
        XCTAssertEqual(
            OperationModel.describe(
                EnactmentError.verificationUnavailable(host: "jodo", detail: "manifest exited 3: missing: ./f2")),
            "the check on jodo could not run — the gate stays closed: manifest exited 3: missing: ./f2")
    }

    func testKindClashRefusalSentence() {
        let clash = Collision(
            nameData: Data("notes".utf8),
            standingKind: .directory,
            standingSize: 0,
            standingModified: .distantPast,
            arrivingKind: .file)
        let report = CollisionReport(items: [clash], gathered: true)
        XCTAssertEqual(
            OperationModel.describe(PlanError.kindClash(report)),
            "won't work — notes is a folder here and a file there")
    }

    func testProgressiveMoveLanguageStatesTheOperatingContract() {
        XCTAssertEqual(
            OperationModel.progressiveMoveNotice,
            "files are removed from the source after transfer · do not modify either location "
                + "during the move · interruption may split files between them")
        XCTAssertEqual(
            OperationModel.describe(PlanError.moveReleaseUnavailable),
            "that move has no supported rsync path — copy it, then delete the source separately")
        XCTAssertEqual(
            OperationModel.describe(PlanError.rsyncFlagsControlSourceRemoval),
            "source removal belongs to the move command — remove that option from rsync flags")
    }
}
