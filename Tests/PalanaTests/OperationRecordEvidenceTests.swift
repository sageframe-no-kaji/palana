// The operation model's side of the record. A run that ran and checked
// out is `.finished` whether or not its record landed; a record that
// did not land is said — in the transcript as a note, and persistently
// as `recordWarning` for the panel — and never read as the transfer's
// outcome. Completion flushes; the quit path closes.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class OperationRecordEvidenceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/")
    private var logURL: URL { directory.appendingPathComponent("operations.log") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-record-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// An operation model whose enactments run on this machine and whose
    /// record goes through `log` — a scripted sink or a real temp file.
    private func makeOperation(log: OperationLog) -> OperationModel {
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
        let operation = OperationModel(engine: engine, configuration: configuration, settings: settings, log: log)
        // Keep the transcript: a run that finishes off-screen resets it.
        operation.panelShowing = true
        return operation
    }

    private func scriptedOperation(_ sink: ScriptedLogSink) -> OperationModel {
        makeOperation(log: OperationLog(url: logURL) { _ in sink })
    }

    /// A one-step local plan running `command`.
    private func localPlan(_ command: String) -> Plan {
        let step = PlanStep(runsOn: .host(PalanaCore.localHostName), command: command, role: .copy)
        return Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: Locus(host: PalanaCore.localHostName, directory: directory.path),
            destination: Locus(host: PalanaCore.localHostName, directory: directory.path),
            transport: .local,
            steps: [step])
    }

    private func enact(_ operation: OperationModel, _ command: String) {
        operation.plan = localPlan(command)
        operation.phase = .ready
        operation.enact()
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

    private func recordNotes(_ operation: OperationModel) -> [EchoBuffer.Line] {
        operation.echo.lines.filter { $0.text.hasPrefix("record: ") }
    }

    // MARK: - Outcome stands

    func testFinishedRunStaysFinishedWhenTheRecordFails() async throws {
        let sink = ScriptedLogSink()
        sink.failWrite = true
        let operation = scriptedOperation(sink)
        enact(operation, "true")
        let finished = await waitUntil { operation.phase == .finished }
        XCTAssertTrue(finished)

        let warning = try XCTUnwrap(operation.recordWarning)
        XCTAssertTrue(warning.contains("write failed"))
        XCTAssertTrue(warning.hasSuffix(logURL.path))
        let notes = recordNotes(operation)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.kind, .note)
        XCTAssertFalse(operation.echo.lines.contains { $0.kind == .failure })
        XCTAssertTrue(operation.echo.lines.contains { $0.text.hasPrefix("done") })
    }

    func testFailedRunReportsTheFailureAndTheRecordSeparately() async throws {
        let sink = ScriptedLogSink()
        sink.failSeek = true
        let operation = scriptedOperation(sink)
        enact(operation, "exit 3")
        let failed = await waitUntil { operation.phase == .failed }
        XCTAssertTrue(failed)

        XCTAssertEqual(operation.recordWarning?.contains("seek failed"), true)
        XCTAssertEqual(recordNotes(operation).count, 1)
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(failure.text.hasPrefix("step 1 failed"))
        XCTAssertFalse(failure.text.contains("record"))
    }

    func testHealthyRunWarnsNothingAndFlushesAtCompletion() async throws {
        let sink = ScriptedLogSink()
        let operation = scriptedOperation(sink)
        enact(operation, "true")
        let finished = await waitUntil { operation.phase == .finished }
        XCTAssertTrue(finished)

        XCTAssertNil(operation.recordWarning)
        XCTAssertTrue(recordNotes(operation).isEmpty)
        XCTAssertEqual(sink.synchronizeCount, 1)
        XCTAssertTrue(sink.text.contains("── "))
        XCTAssertTrue(sink.text.contains("$ true\n"))
        XCTAssertTrue(sink.text.hasSuffix("# done — every step ran and checked out\n"))
    }

    func testFailedRunFlushesTheRecordWithTheFailureLine() async throws {
        let sink = ScriptedLogSink()
        let operation = scriptedOperation(sink)
        enact(operation, "echo nope >&2; exit 2")
        let failed = await waitUntil { operation.phase == .failed }
        XCTAssertTrue(failed)
        XCTAssertNil(operation.recordWarning)
        XCTAssertEqual(sink.synchronizeCount, 1)
        XCTAssertTrue(sink.text.contains("\n! step 1 failed (2): nope\n"))
    }

    func testFlushFailureAtCompletionIsSurfacedWithoutChangingTheOutcome() async throws {
        let sink = ScriptedLogSink()
        sink.failFlush = true
        let operation = scriptedOperation(sink)
        enact(operation, "true")
        let finished = await waitUntil { operation.phase == .finished }
        XCTAssertTrue(finished)
        XCTAssertEqual(operation.recordWarning?.contains("flush failed"), true)
        XCTAssertEqual(recordNotes(operation).count, 1)
    }

    func testCancelledRunFlushesTheRecord() async throws {
        let sink = ScriptedLogSink()
        let operation = scriptedOperation(sink)
        enact(operation, "sleep 30")
        await waitUntil { sink.text.contains("$ sleep 30\n") }
        operation.cancelEnactment()
        let cancelled = await waitUntil { operation.phase == .cancelled }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(sink.synchronizeCount, 1)
        XCTAssertNil(operation.recordWarning)
    }

    // MARK: - The real file

    func testRealRecordLandsOnDiskAtCompletion() async throws {
        let operation = makeOperation(log: OperationLog(url: logURL))
        enact(operation, "true")
        let finished = await waitUntil { operation.phase == .finished }
        XCTAssertTrue(finished)
        XCTAssertNil(operation.recordWarning)
        let text = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("\n── "))
        XCTAssertTrue(text.contains("\n$ true\n"))
        XCTAssertTrue(text.hasSuffix("# done — every step ran and checked out\n"))
    }

    func testCloseRecordClosesTheHandleOnce() async throws {
        let sink = ScriptedLogSink()
        let operation = scriptedOperation(sink)
        enact(operation, "true")
        await waitUntil { operation.phase == .finished }
        operation.closeRecord()
        operation.closeRecord()
        XCTAssertEqual(sink.closeCount, 1)
        XCTAssertNil(operation.recordWarning)
    }

    func testCloseRecordFailureIsSurfaced() async throws {
        let sink = ScriptedLogSink()
        sink.failClose = true
        let operation = scriptedOperation(sink)
        enact(operation, "true")
        await waitUntil { operation.phase == .finished }
        XCTAssertNil(operation.recordWarning)
        operation.closeRecord()
        XCTAssertEqual(operation.recordWarning?.contains("close failed"), true)
        XCTAssertEqual(operation.phase, .finished)
    }
}
