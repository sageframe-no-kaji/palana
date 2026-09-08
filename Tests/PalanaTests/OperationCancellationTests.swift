// The operation model's side of process ownership. ⌃C on a running
// enactment used to flip the phase to `.cancelled` while the command
// ran on; the phase now waits for the task, which waits for the
// process. Workbench reads drain both channels together and say so
// when the command exits nonzero.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class OperationCancellationTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/")
    private var pidFile: URL { directory.appendingPathComponent("pid") }
    private var marker: URL { directory.appendingPathComponent("marker") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-operation-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A bare operation model whose enactments run on this machine and
    /// whose log lands in the test directory, never the operator's.
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

    private func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A plan whose one step records its pid, waits, and leaves a marker.
    private func slowPlan() -> Plan {
        let step = PlanStep(
            runsOn: .host(PalanaCore.localHostName),
            command: "echo $$ > \(quote(pidFile.path)); sleep 30; touch \(quote(marker.path))",
            role: .copy)
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

    private func pid() -> pid_t? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
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

    private func transcript(_ operation: OperationModel) -> [String] {
        operation.echo.lines.map(\.text)
    }

    func testCancelEnactmentPublishesCancelledOnlyAfterTheProcessExits() async throws {
        let operation = makeOperation()
        operation.plan = slowPlan()
        operation.phase = .ready
        operation.enact()
        XCTAssertEqual(operation.phase, .enacting)
        await waitUntil { self.pid() != nil }
        let pid = try XCTUnwrap(pid())
        XCTAssertTrue(isAlive(pid))

        operation.cancelEnactment()

        // The phase holds while the process is being stopped.
        XCTAssertEqual(operation.phase, .enacting)
        XCTAssertTrue(operation.enactmentStopping)
        XCTAssertTrue(operation.terminalBusy)
        XCTAssertTrue(transcript(operation).contains { $0.hasPrefix("stopping") })

        let cancelled = await waitUntil { operation.phase == .cancelled }
        XCTAssertTrue(cancelled)
        // By the time `.cancelled` was published, the group had exited.
        XCTAssertFalse(isAlive(pid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(operation.enactmentStopping)
        XCTAssertTrue(operation.panelShowing)
        XCTAssertTrue(transcript(operation).contains { $0.hasPrefix("cancelled") })
    }

    func testSecondCancelWhileStoppingChangesNothing() async throws {
        let operation = makeOperation()
        operation.plan = slowPlan()
        operation.phase = .ready
        operation.enact()
        await waitUntil { self.pid() != nil }

        operation.cancelEnactment()
        operation.cancelEnactment()
        operation.cancelCommand()
        XCTAssertEqual(operation.phase, .enacting)
        XCTAssertEqual(transcript(operation).filter { $0.hasPrefix("stopping") }.count, 1)

        let cancelled = await waitUntil { operation.phase == .cancelled }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(transcript(operation).filter { $0.hasPrefix("cancelled") }.count, 1)
    }

    func testRunToolReadSurfacesNonzeroExitWithStderrTail() async throws {
        let operation = makeOperation()
        let running = try await LocalConduit().run(
            on: "local", "echo out; echo 'first warning' >&2; echo 'zfs: no such dataset' >&2; exit 3")
        await operation.runToolRead(header: "zfs list · local", stream: running)

        let lines = transcript(operation)
        XCTAssertTrue(lines.contains("out"))
        XCTAssertTrue(lines.contains("first warning"))
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertEqual(failure.text, "read failed (exit 3): zfs: no such dataset")
    }

    func testRunToolReadReportsNothingExtraOnSuccess() async throws {
        let operation = makeOperation()
        let running = try await LocalConduit().run(on: "local", "echo fine")
        await operation.runToolRead(header: "read", stream: running)
        XCTAssertFalse(operation.echo.lines.contains { $0.kind == .failure })
        XCTAssertTrue(transcript(operation).contains("fine"))
    }

    func testRunToolReadDrainsChannelsIndependently() async throws {
        // stdout cannot finish until stderr has been read — a reader
        // that drains stdout first never returns.
        let operation = makeOperation()
        let gated = GatedRead.make(stderrChunks: 3)
        let finished = expectation(description: "the read returned")
        let read = Task { @MainActor in
            await operation.runToolRead(header: "gated", stream: gated)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)
        read.cancel()

        let lines = transcript(operation)
        XCTAssertTrue(lines.contains("out"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("err") }.count, 3)
        XCTAssertEqual(operation.echo.lines.last?.text, "read failed (exit 2): err 2")
    }
}

/// A command whose stdout ends only after its stderr was consumed.
private enum GatedRead {
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            let resumed = waiters
            waiters = []
            for waiter in resumed {
                waiter.resume()
            }
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private actor Counter {
        private var value = 0

        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }

    static func make(stderrChunks: Int) -> RunningCommand {
        let gate = Gate()
        let stdoutSent = Counter()
        let stdout = AsyncStream<Data> {
            if await stdoutSent.next() == 0 {
                return Data("out\n".utf8)
            }
            await gate.wait()
            return nil
        }
        let stderrSent = Counter()
        let stderr = AsyncStream<Data> {
            let index = await stderrSent.next()
            guard index < stderrChunks else { return nil }
            if index == stderrChunks - 1 {
                await gate.open()
            }
            return Data("err \(index)\n".utf8)
        }
        return RunningCommand(stdout: stdout, stderr: stderr) { 2 }
    }
}
