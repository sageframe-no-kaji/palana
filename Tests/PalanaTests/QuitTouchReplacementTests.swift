// Review Q03, pass 4: Touch composes straight to `.ready`, so it must
// itself clear the exemption of an upload it replaces. Otherwise its own
// plan inherits the upload's permission to run while a quit waits.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Quit When Finished: Touch replacing an upload", .serialized)
struct QuitTouchReplacementTests {
    private static let old = Date(timeIntervalSince1970: 1_000_000_000)

    /// A local stand-in for an upload's plan.
    private func uploadPlan(in directory: URL) -> Plan {
        let here = Locus(host: PalanaCore.localHostName, directory: directory.path)
        return Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: here,
            destination: here,
            transport: .local,
            steps: [PlanStep(runsOn: .host(PalanaCore.localHostName), command: "true", role: .copy)])
    }

    /// The focused pane on a folder holding one file with an old modification time.
    private func paneOnFile(_ rig: TestSession) async throws -> (pane: PaneModel, file: URL) {
        let folder = rig.directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("operator.txt")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Self.old], ofItemAtPath: file.path)
        let pane = rig.session.left
        pane.point(host: PalanaCore.localHostName, path: folder.path)
        try await poll(message: "the pane lists the file") {
            pane.status == .ready && pane.state.path == folder.path && pane.operationSubjects.count == 1
        }
        return (pane, file)
    }

    private func modified(_ file: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    }

    @Test("Q03 (pass 4): Touch replacing an upload awaiting Enter takes no upload exemption")
    func touchReplacingReadyUpload() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let (pane, file) = try await paneOnFile(rig)
        var terminations = 0
        rig.session.quit.requestTermination = { terminations += 1 }
        let operation = rig.session.operation
        operation.plan = uploadPlan(in: rig.directory)
        operation.phase = .ready
        operation.roundTripUploadActive = true

        operation.beginTouch(source: pane)
        #expect(operation.phase == .ready)
        #expect(operation.plan?.operation == .touch, "Touch replaced the upload's plan")
        #expect(!operation.roundTripUploadActive, "the displaced upload's flag went with it")
        #expect(!rig.session.quitNeedsConfirmation, "an unstarted Touch is not work in progress")

        // While a quit waits, Enter on the Touch is refused.
        operation.quitPending = true
        operation.enact()
        #expect(operation.phase == .ready)
        #expect(try modified(file) == Self.old, "the file was not touched")
        operation.quitPending = false

        // Choosing to wait sets the Touch aside and quits once.
        rig.session.applyQuitChoice(.quitWhenFinished)
        #expect(operation.phase != .ready, "the unstarted Touch was set aside")
        var looks = 0
        while !rig.session.settleQuitWhenFinished(), looks < 100 {
            looks += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(terminations == 1)
        #expect(try modified(file) == Self.old)
    }

    @Test("Q03 (pass 4): Touch during an upload's gather cancels it and takes no exemption")
    func touchReplacingGatheringUpload() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let (pane, file) = try await paneOnFile(rig)
        let operation = rig.session.operation
        let gathering = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        defer { gathering.cancel() }
        operation.phase = .gathering
        operation.roundTripUploadActive = true
        operation.gatherTask = gathering

        operation.beginTouch(source: pane)
        #expect(gathering.isCancelled, "the upload's gather was replaced")
        #expect(operation.phase == .ready)
        #expect(operation.plan?.operation == .touch)
        #expect(!operation.roundTripUploadActive)

        operation.quitPending = true
        operation.enact()
        #expect(operation.phase == .ready, "Enter did not start the Touch while the quit waits")
        #expect(try modified(file) == Self.old)
        operation.quitPending = false
    }
}
