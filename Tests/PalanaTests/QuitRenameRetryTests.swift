// Review Q03, pass 5: the rename-commit retry of a failed send-back is
// that upload again. Accepting it while a quit waits must run it, not
// leave a ready plan the quit forbids and the queue cannot pass.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Quit When Finished: the rename-commit retry", .serialized)
struct QuitRenameRetryTests {
    /// A registered upload into a local destination folder: the server copy
    /// holds `old!`, the local copy holds `body`.
    private func localUpload(
        _ rig: TestSession, folder: String, body: String
    ) async throws -> (record: RoundTripRecord, destination: URL) {
        let target = try rig.makeDirectory(folder)
        let destination = target.appendingPathComponent("edit.txt")
        try Data("old!".utf8).write(to: destination)
        let localFolder = try rig.makeDirectory("\(folder)-local")
        let local = localFolder.appendingPathComponent("edit.txt")
        try Data(body.utf8).write(to: local)
        let entries = try await Listing(conduit: LocalConduit())
            .list(on: PalanaCore.localHostName, path: target.path, flavor: .bsd)
        let fetched = try #require(entries.first { $0.name == "edit.txt" })
        let record = RoundTripRecord(
            host: PalanaCore.localHostName,
            remoteDirectory: target.path,
            fetched: fetched,
            digest: RoundTrip.digest(of: Data("old!".utf8)),
            localURL: local)
        rig.session.roundTripCenter.register(record: record)
        return (record, destination)
    }

    private func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The upload's link commit refuses for want of hard links, as
    /// `failEnactment` records it: the panel fails and offers the rename retry.
    private func failAtLinkCommit(_ operation: OperationModel, upload: Plan) throws {
        let commit = try #require(upload.steps.firstIndex { $0.role == .promote })
        operation.phase = .failed
        operation.panelShowing = true
        operation.renameCommitOffer = OperationModel.renameCommitOffer(
            for: upload,
            after: EnactmentError.stepFailed(
                index: commit,
                exitStatus: RemoteVersionGuard.noHardLinkExitStatus,
                stderrTail: "no hard links here"))
        #expect(operation.renameCommitOffer != nil)
    }

    @Test("Q03 (pass 5): accepting the rename retry while a quit waits sends it, then the queue, then quits once")
    func retryDuringPendingQuit() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        var terminations = 0
        rig.session.quit.requestTermination = { terminations += 1 }
        rig.session.settings.askBeforeSendingBack = true
        let operation = rig.session.operation
        let center = rig.session.roundTripCenter

        let (first, firstDestination) = try await localUpload(rig, folder: "first", body: "edit")
        center.offerOrQueue(record: first)
        try await poll(message: "the first upload waits for Enter") { operation.phase == .ready }
        let upload = try #require(operation.plan)
        let (second, secondDestination) = try await localUpload(rig, folder: "second", body: "next")
        center.offerOrQueue(record: second)
        rig.session.applyQuitChoice(.quitWhenFinished)

        // The commit refuses: the quit is cancelled and the queue held (Q01).
        try failAtLinkCommit(operation, upload: upload)
        #expect(!operation.quitPending)
        #expect(operation.holdsUploadsForFailure)

        // The operator waits again, then accepts the retry before the queue moves.
        rig.session.applyQuitChoice(.quitWhenFinished)
        operation.acceptRenameCommit()
        #expect(operation.phase == .enacting, "the retry runs at once")
        #expect(operation.roundTripUploadActive, "as the upload it is")
        try await poll(message: "the retry lands") { contents(firstDestination) == "edit" }

        // The queued save comes up next and, asking first, waits for Enter.
        try await poll(message: "the queued save waits for Enter") {
            operation.phase == .ready && operation.roundTripUploadActive && center.pendingCount == 0
        }
        #expect(terminations == 0)
        operation.enact()
        try await poll(message: "the quit follows the last save") { terminations == 1 }
        #expect(contents(secondDestination) == "next")
        try await Task.sleep(for: .milliseconds(700))
        #expect(terminations == 1, "one quit")
    }

    @Test("Q03 (pass 5): without a quit, the rename retry runs as before")
    func retryWithoutQuit() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        rig.session.settings.askBeforeSendingBack = true
        let operation = rig.session.operation
        let (record, destination) = try await localUpload(rig, folder: "only", body: "edit")
        rig.session.roundTripCenter.offerOrQueue(record: record)
        try await poll(message: "the upload waits for Enter") { operation.phase == .ready }
        try failAtLinkCommit(operation, upload: try #require(operation.plan))
        operation.acceptRenameCommit()
        try await poll(message: "the retry finishes") { operation.phase == .finished }
        #expect(contents(destination) == "edit")
        #expect(!operation.roundTripUploadActive, "a finished upload is over (Q02)")
    }

    @Test("Q03 (pass 5): once shutdown has begun, accepting the retry changes nothing")
    func retryRefusedWhileClosing() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        rig.session.settings.askBeforeSendingBack = true
        let operation = rig.session.operation
        let (record, destination) = try await localUpload(rig, folder: "only", body: "edit")
        rig.session.roundTripCenter.offerOrQueue(record: record)
        try await poll(message: "the upload waits for Enter") { operation.phase == .ready }
        try failAtLinkCommit(operation, upload: try #require(operation.plan))
        operation.isClosing = true
        operation.acceptRenameCommit()
        #expect(operation.phase == .failed)
        #expect(!operation.roundTripUploadActive)
        #expect(operation.renameCommitOffer != nil, "the offer is left as it was")
        #expect(contents(destination) == "old!")
    }
}
