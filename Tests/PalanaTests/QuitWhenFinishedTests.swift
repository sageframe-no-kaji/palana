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
            self.run("sleep 0.3; touch \(ShellQuote.quote(uploaded.path))", in: rig)
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
