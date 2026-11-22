// ⌘Q while pālana is still working: the prompt's decision logic and the
// "Quit When Finished" watch. The NSAlert itself is not driven here; the
// session's answers to it are, against real local processes.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Quit When Finished", .serialized)
struct QuitWhenFinishedTests {
    private func localPlan(_ command: String, in directory: URL) -> Plan {
        let here = Locus(host: PalanaCore.localHostName, directory: directory.path)
        return Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: here,
            destination: here,
            transport: .local,
            steps: [PlanStep(runsOn: .host(PalanaCore.localHostName), command: command, role: .copy)])
    }

    /// Starts `command` as a running plan on the session's operation model.
    private func run(_ command: String, in rig: TestSession) {
        rig.session.operation.plan = localPlan(command, in: rig.directory)
        rig.session.operation.phase = .ready
        rig.session.operation.panelShowing = true
        rig.session.operation.enact()
    }

    /// Stands in for a round-trip upload's plan: a local run the operation
    /// model knows is an upload, as `beginRoundTripUpload` marks one.
    private func upload(_ command: String, in rig: TestSession) {
        rig.session.operation.plan = localPlan(command, in: rig.directory)
        rig.session.operation.phase = .ready
        rig.session.operation.roundTripUploadActive = true
        rig.session.operation.enact()
    }

    /// A registered record whose local copy holds an unsent edit.
    private func editedRecord(_ rig: TestSession) throws -> RoundTripRecord {
        let directory = try RoundTripRecord.makeOpenDirectory()
        let url = directory.appendingPathComponent("edit.txt")
        try Data("v0".utf8).write(to: url)
        let record = RoundTripRecord(
            host: TestSession.host,
            remoteDirectory: "/srv",
            fetched: FileEntry(
                nameData: Data("edit.txt".utf8),
                kind: .file,
                size: 2,
                modified: Date(timeIntervalSince1970: 1),
                permissions: "644",
                owner: "op",
                group: "op"),
            digest: RoundTrip.digest(of: Data("v0".utf8)),
            localURL: url)
        rig.session.roundTripCenter.register(record: record)
        try Data("edited".utf8).write(to: url)
        return record
    }

    /// Counts termination requests instead of quitting the test runner.
    private func counter(_ rig: TestSession) -> () -> Int {
        var count = 0
        rig.session.quit.requestTermination = { count += 1 }
        return { count }
    }

    /// Pumps the watch until it ends (or a bounded number of looks).
    private func settle(_ rig: TestSession) async throws {
        for _ in 0..<100 {
            if rig.session.settleQuitWhenFinished() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("the quit watch never ended")
    }

    private func lines(_ rig: TestSession) -> [String] { rig.session.operation.echo.lines.map(\.text) }

    @Test("nothing running: ⌘Q quits without asking; a running plan asks")
    func asksOnlyWhenWorking() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        #expect(!rig.session.quitNeedsConfirmation)
        run("sleep 5", in: rig)
        #expect(rig.session.quitNeedsConfirmation)
        #expect(rig.session.quitPromptDetail.hasPrefix("A transfer is running."))
        #expect(rig.session.applyQuitChoice(.stopAndQuit), "Stop and Quit proceeds to the shutdown path")
        await rig.session.closeDoors()
        #expect(rig.session.operation.phase == .cancelled)
    }

    @Test("Quit When Finished quits once the run finishes, and refuses new work meanwhile")
    func quitsAfterSuccess() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        run("sleep 0.4", in: rig)
        #expect(!rig.session.applyQuitChoice(.quitWhenFinished), "the app does not quit yet")
        #expect(rig.session.operation.quitPending)
        #expect(!rig.session.operation.admitsOperatorWork)
        #expect(!rig.session.settleQuitWhenFinished(), "still running")
        #expect(terminations() == 0)

        try await settle(rig)
        #expect(terminations() == 1)
        #expect(rig.session.operation.phase == .finished)
    }

    @Test("queued saves go back before the quit: the watch waits for each upload to finish")
    func waitsForQueuedSaves() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        let center = rig.session.roundTripCenter
        let directory = try RoundTripRecord.makeOpenDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("edit.txt")
        try Data("v0".utf8).write(to: url)
        let record = RoundTripRecord(
            host: TestSession.host,
            remoteDirectory: "/srv",
            fetched: FileEntry(
                nameData: Data("edit.txt".utf8),
                kind: .file,
                size: 2,
                modified: Date(timeIntervalSince1970: 1),
                permissions: "644",
                owner: "op",
                group: "op"),
            digest: RoundTrip.digest(of: Data("v0".utf8)),
            localURL: url)
        center.register(record: record)
        // The upload stands in as a short local run: no ssh in this suite.
        let uploaded = rig.directory.appendingPathComponent("uploaded")
        var deliveries = 0
        center.deliverUpload = { _ in
            deliveries += 1
            self.upload("sleep 0.3; touch \(ShellQuote.quote(uploaded.path))", in: rig)
        }

        run("sleep 0.3", in: rig)
        try Data("edited".utf8).write(to: url)
        center.offerOrQueue(record: record)
        #expect(center.pendingCount == 1)
        #expect(rig.session.quitPromptDetail.contains("1 saved edit is waiting"))
        rig.session.applyQuitChoice(.quitWhenFinished)

        try await settle(rig)
        #expect(deliveries == 1, "the queued save was delivered, not dropped")
        #expect(FileManager.default.fileExists(atPath: uploaded.path), "and its upload finished before the quit")
        #expect(terminations() == 1)
    }

    @Test("a failed run cancels the quit: pālana stays open and work can start again")
    func failureStaysOpen() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        run("sleep 0.2; exit 3", in: rig)
        rig.session.applyQuitChoice(.quitWhenFinished)
        try await settle(rig)
        #expect(terminations() == 0)
        #expect(!rig.session.operation.quitPending)
        #expect(rig.session.operation.admitsOperatorWork)
        #expect(lines(rig).contains { $0.hasPrefix("quit cancelled — something failed") })
        #expect(rig.session.operation.panelShowing, "the failure stays on screen")
    }

    @Test("⌃C on the run cancels the quit too")
    func cancelStaysOpen() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        run("sleep 30", in: rig)
        rig.session.applyQuitChoice(.quitWhenFinished)
        try await Task.sleep(for: .milliseconds(100))
        rig.session.operation.cancelEnactment()
        try await settle(rig)
        #expect(terminations() == 0)
        #expect(lines(rig).contains { $0.hasPrefix("quit cancelled — the run was stopped") })
    }

    @Test("⌘Q again and Keep Running: the pending quit is cancelled and the run continues")
    func keepRunningCancelsPending() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        run("sleep 0.5", in: rig)
        rig.session.applyQuitChoice(.quitWhenFinished)
        #expect(rig.session.quitNeedsConfirmation, "a second ⌘Q asks again")
        #expect(!rig.session.applyQuitChoice(.keepRunning))
        #expect(!rig.session.operation.quitPending)
        #expect(rig.session.quit.watchTask == nil)
        try await poll(message: "the run finishes") { rig.session.operation.phase == .finished }
        try await Task.sleep(for: .milliseconds(400))
        #expect(terminations() == 0, "no quit after Keep Running")
        rig.session.operation.cancelEnactment()
    }
}

// The review cycle palana-quit-followup-2026-11-19, finding by finding.
extension QuitWhenFinishedTests {
    // MARK: - Pass-1 findings (cycle palana-quit-followup-2026-11-19)

    @Test("Q01: a failure cancels the quit at once, and a queued save waits until the failure is dismissed")
    func failureHoldsQueuedSaves() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        let center = rig.session.roundTripCenter
        let record = try editedRecord(rig)
        defer { try? FileManager.default.removeItem(at: record.localDirectory) }
        var deliveries = 0
        center.deliverUpload = { _ in
            deliveries += 1
            self.upload("true", in: rig)
        }
        run("sleep 0.2; exit 3", in: rig)
        center.offerOrQueue(record: record)
        rig.session.applyQuitChoice(.quitWhenFinished)

        try await poll(message: "the run fails") { rig.session.operation.phase == .failed }
        #expect(!rig.session.operation.quitPending, "the failure cancelled the quit when it happened")
        // Several queue polls later, the failure is still what is on screen.
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(deliveries == 0, "no queued save replaced the failure")
        #expect(rig.session.operation.phase == .failed)
        #expect(lines(rig).contains { $0.hasPrefix("quit cancelled — something failed") })
        #expect(terminations() == 0)

        rig.session.operation.dismissOrCancel()  // Esc: the operator has seen it
        try await poll(message: "the queued save goes once the failure is dismissed") { deliveries == 1 }
        try await poll(message: "the upload finishes") { !rig.session.operation.roundTripUploadActive }
        #expect(terminations() == 0, "the quit stayed cancelled")
    }

    @Test("Q02: an upload that failed in its gather is over: no prompt, and a pending quit can finish")
    func failedUploadIsNotInProgress() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        let record = try editedRecord(rig)
        defer { try? FileManager.default.removeItem(at: record.localDirectory) }
        // The real delivery: the local copy is gone, so the gather fails.
        try FileManager.default.removeItem(at: record.localURL)
        rig.session.roundTripCenter.offerOrQueue(record: record)
        try await poll(message: "the gather fails") { rig.session.operation.phase == .failed }
        #expect(!rig.session.operation.roundTripUploadActive)
        rig.session.operation.dismissOrCancel()
        #expect(rig.session.operation.phase == .idle)
        #expect(!rig.session.quitNeedsConfirmation, "nothing is in progress, so ⌘Q quits without asking")

        // A quit chosen while some other run is going still finishes.
        run("sleep 0.2", in: rig)
        rig.session.applyQuitChoice(.quitWhenFinished)
        try await settle(rig)
        #expect(terminations() == 1)
    }

    @Test("Q03: Quit When Finished sets aside an unstarted plan; Enter cannot start one while the quit waits")
    func readyPlanIsSetAside() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        let center = rig.session.roundTripCenter
        let record = try editedRecord(rig)
        defer { try? FileManager.default.removeItem(at: record.localDirectory) }
        let uploaded = rig.directory.appendingPathComponent("uploaded")
        center.deliverUpload = { _ in self.upload("touch \(ShellQuote.quote(uploaded.path))", in: rig) }
        // An operator plan waits for Enter; a save queues behind it.
        rig.session.operation.plan = localPlan("true", in: rig.directory)
        rig.session.operation.phase = .ready
        center.offerOrQueue(record: record)
        #expect(rig.session.quitNeedsConfirmation)

        rig.session.applyQuitChoice(.quitWhenFinished)
        #expect(rig.session.operation.phase != .ready, "the unstarted plan was set aside")
        // Enter on an operator plan is refused while the quit waits.
        let stray = rig.directory.appendingPathComponent("stray")
        rig.session.operation.plan = localPlan("touch \(ShellQuote.quote(stray.path))", in: rig.directory)
        rig.session.operation.phase = .ready
        rig.session.operation.enact()
        #expect(rig.session.operation.phase == .ready, "Enter did not start an operator plan")
        rig.session.operation.dismissOrCancel()

        try await settle(rig)
        #expect(FileManager.default.fileExists(atPath: uploaded.path), "the queued save went first")
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(terminations() == 1)
    }

    @Test("Q05: selecting pālana's partial folder says rsync will skip it")
    func reservedFolderIsNamed() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        var facts = PlanFacts()
        let entry = FileEntry(
            nameData: Data(PlanEngine.partialDirName.utf8),
            kind: .directory,
            size: 0,
            modified: Date(),
            permissions: "755",
            owner: "op",
            group: "op")
        await rig.session.operation.gatherCollisionsIfNeeded(
            destination: Locus(host: PalanaCore.localHostName, directory: rig.directory.path),
            subjects: [entry],
            into: &facts)
        #expect(lines(rig).contains { $0.hasPrefix(".palana-partial is pālana's folder for interrupted copies") })
    }

    // MARK: - Pass-2 findings

    @Test("Q01 (pass 2): choosing to wait again over a held failure sends the waiting save, then quits")
    func waitAgainAfterFailure() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        let center = rig.session.roundTripCenter
        let record = try editedRecord(rig)
        defer { try? FileManager.default.removeItem(at: record.localDirectory) }
        let uploaded = rig.directory.appendingPathComponent("uploaded")
        center.deliverUpload = { _ in self.upload("touch \(ShellQuote.quote(uploaded.path))", in: rig) }
        run("sleep 0.2; exit 3", in: rig)
        center.offerOrQueue(record: record)
        rig.session.applyQuitChoice(.quitWhenFinished)
        try await poll(message: "the run fails") { rig.session.operation.phase == .failed }
        #expect(rig.session.operation.holdsUploadsForFailure)
        #expect(rig.session.quitNeedsConfirmation, "the waiting save makes ⌘Q ask again")

        rig.session.applyQuitChoice(.quitWhenFinished)  // seen it; finish the rest
        #expect(!rig.session.operation.holdsUploadsForFailure)
        try await settle(rig)
        #expect(FileManager.default.fileExists(atPath: uploaded.path), "the save went before the quit")
        #expect(terminations() == 1)
    }

    @Test("Q01 (pass 2): a later quit request is watched once; the earlier watch never acts on it")
    func staleWatchNeverActs() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        run("sleep 0.1; exit 3", in: rig)
        rig.session.applyQuitChoice(.quitWhenFinished)
        try await poll(timeout: 2, message: "the first run fails") { rig.session.operation.phase == .failed }
        // Before the first watch's next look, a second run and request.
        rig.session.operation.dismissOrCancel()
        run("sleep 0.6", in: rig)
        rig.session.applyQuitChoice(.quitWhenFinished)
        try await poll(timeout: 5, message: "the second run finishes") { rig.session.operation.phase == .finished }
        try await Task.sleep(for: .milliseconds(1_000))
        #expect(terminations() == 1, "one request, one quit")
    }

    @Test("Q03 (pass 2): an operator copy that replaces an upload awaiting Enter gets no upload exemption")
    func replacedUploadLeavesNoExemption() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let terminations = counter(rig)
        let operation = rig.session.operation
        // A round-trip upload waiting for Enter (ask before sending).
        operation.plan = localPlan("true", in: rig.directory)
        operation.phase = .ready
        operation.roundTripUploadActive = true
        // The operator replaces it with a copy from Finder.
        let source = rig.directory.appendingPathComponent("from")
        let target = rig.directory.appendingPathComponent("to")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appendingPathComponent("a.txt"))
        let entry = FileEntry(
            nameData: Data("a.txt".utf8),
            kind: .file,
            size: 1,
            modified: Date(),
            permissions: "644",
            owner: "op",
            group: "op")
        operation.beginFromFinderDrop(
            .copy,
            source: Locus(host: PalanaCore.localHostName, directory: source.path),
            destination: Locus(host: PalanaCore.localHostName, directory: target.path),
            entries: [entry])
        #expect(!operation.roundTripUploadActive, "the displaced upload's flag went with it")
        try await poll(message: "the copy is ready") { operation.phase == .ready }
        #expect(!rig.session.quitNeedsConfirmation, "an unstarted operator copy is not work in progress")

        // Even if a quit were pending, Enter on this copy is refused.
        operation.quitPending = true
        operation.enact()
        #expect(operation.phase == .ready)
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("a.txt").path))
        operation.quitPending = false
        #expect(terminations() == 0)
    }

    // MARK: - Pass-3 finding

    /// An upload waiting for Enter, and the focused pane on an empty folder.
    private func uploadAwaitingApproval(_ rig: TestSession) async throws -> (pane: PaneModel, plan: Plan?) {
        let empty = rig.directory.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let pane = rig.session.left
        pane.point(host: PalanaCore.localHostName, path: empty.path)
        try await poll(message: "the empty pane lists") { pane.status == .ready && pane.state.path == empty.path }
        let operation = rig.session.operation
        operation.plan = localPlan("true", in: rig.directory)
        operation.phase = .ready
        operation.roundTripUploadActive = true
        return (pane, operation.plan)
    }

    @Test("Q03 (pass 3): a command with nothing to act on leaves a waiting upload exactly as it was")
    func noOpCommandsKeepUploadIdentity() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let (pane, waiting) = try await uploadAwaitingApproval(rig)
        let operation = rig.session.operation
        #expect(pane.operationSubjects.isEmpty)
        operation.begin(.copy, source: pane, destination: rig.session.right)
        operation.beginTouch(source: pane)
        operation.beginNaming(.rename, source: pane)
        operation.beginFromFinderDrop(
            .copy,
            source: Locus(host: PalanaCore.localHostName, directory: rig.directory.path),
            destination: Locus(host: PalanaCore.localHostName, directory: rig.directory.path),
            entries: [])
        #expect(operation.phase == .ready)
        #expect(operation.plan == waiting, "the same upload plan")
        #expect(operation.roundTripUploadActive, "still an upload")
        #expect(rig.session.quitNeedsConfirmation, "so ⌘Q still asks")

        // And it is still the work a pending quit lets through.
        let terminations = counter(rig)
        operation.quitPending = true
        operation.enact()
        #expect(operation.phase == .enacting || operation.phase == .finished, "the upload was approved")
        try await poll(message: "the upload finishes") { !operation.roundTripUploadActive }
        operation.quitPending = false
        #expect(terminations() == 0)
    }

    @Test("Q03 (pass 3): an empty-pane verb during an upload's gather does not cancel it")
    func noOpCommandKeepsGatheringUpload() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let (pane, _) = try await uploadAwaitingApproval(rig)
        let operation = rig.session.operation
        // The upload is still composing: its gather is a task that has not finished.
        let gathering = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        defer { gathering.cancel() }
        operation.phase = .gathering
        operation.roundTripUploadActive = true
        operation.gatherTask = gathering
        operation.begin(.copy, source: pane, destination: rig.session.right)
        #expect(operation.phase == .gathering)
        #expect(operation.roundTripUploadActive)
        #expect(!gathering.isCancelled, "nothing to copy, so the upload's gather goes on")
    }
}
