// The 2026-11-18 final review's F05 and F07: what happens to a running
// enactment when the app quits, and what a cancelled progressive move
// still tells the operator.
//
// F05: quitting stops and awaits a running local command before the
// record closes — a local command's process group is not tied to the app.
// F07: ⌃C on a progressive move still delivers the retained-source report
// the core runs after the transfer stops; the receiver no longer dies with
// the cancelled task.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("Final review F05/F07 — operation lifetime", .serialized)
struct FinalReviewOperationLifetimeTests {
    private let directory: URL
    private var pidFile: URL { directory.appendingPathComponent("pid") }
    private var marker: URL { directory.appendingPathComponent("marker") }
    private var logURL: URL { directory.appendingPathComponent("operations.log") }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-lifetime-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeOperation() -> OperationModel {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let engine = Engine(
            conduit: recorded,
            field: Field(conduit: recorded, hosts: [], cache: FieldCache()),
            listing: Listing(conduit: recorded))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        return OperationModel(
            engine: engine,
            configuration: SSHConfiguration(),
            settings: settings,
            log: OperationLog(url: logURL))
    }

    private func slowStep() -> PlanStep {
        PlanStep(
            runsOn: .host(PalanaCore.localHostName),
            command: "echo $$ > \(ShellQuote.quote(pidFile.path)); sleep 30; touch \(ShellQuote.quote(marker.path))",
            role: .copy)
    }

    private func slowPlan() -> Plan {
        let here = Locus(host: PalanaCore.localHostName, directory: directory.path)
        return Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: here,
            destination: here,
            transport: .local,
            steps: [slowStep()])
    }

    private func pid() -> pid_t? {
        (try? String(contentsOf: pidFile, encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    private func lines(_ operation: OperationModel) -> [String] { operation.echo.lines.map(\.text) }

    @Test("quitting mid-run stops and awaits the local command, then seals the record as stopped")
    func quitStopsRunningLocalCommand() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = makeOperation()
        operation.plan = slowPlan()
        operation.phase = .ready
        operation.enact()
        try await poll(message: "the command starts") { pid() != nil }
        let child = try #require(pid())
        #expect(isAlive(child))

        await operation.stopOwnedWork()
        operation.closeRecord()

        #expect(!isAlive(child), "the command was gone before the quit path went on")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(operation.phase == .cancelled)
        #expect(lines(operation).contains { $0.hasPrefix("quit — the running command was stopped") })
        let record = try String(contentsOf: logURL, encoding: .utf8)
        #expect(record.contains("! quit — the run was stopped before it finished"))
    }

    @Test("quit while ⌃C is already stopping the run waits for it, and the cancelled outcome stands once")
    func quitDuringCancel() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = makeOperation()
        operation.plan = slowPlan()
        operation.phase = .ready
        operation.enact()
        try await poll(message: "the command starts") { pid() != nil }
        let child = try #require(pid())
        operation.cancelEnactment()
        await operation.stopOwnedWork()
        #expect(!isAlive(child))
        #expect(operation.phase == .cancelled)
        try await Task.sleep(for: .milliseconds(50))
        let outcomes = lines(operation).filter { $0.hasPrefix("quit —") || $0.hasPrefix("cancelled —") }
        #expect(outcomes.count == 1, "\(outcomes)")
    }

    @Test("quitting with nothing running, or after a run finished, changes nothing")
    func quitAtRest() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let idle = makeOperation()
        await idle.stopOwnedWork()
        #expect(idle.phase == .idle)
        #expect(idle.isClosing, "a stopped model stays closed")

        // A separate model: quitting closes admission, so a model that
        // quit can never run again (pass 2, F05).
        let operation = makeOperation()
        let here = Locus(host: PalanaCore.localHostName, directory: directory.path)
        operation.plan = Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: here,
            destination: here,
            transport: .local,
            steps: [PlanStep(runsOn: .host(PalanaCore.localHostName), command: "true", role: .copy)])
        operation.phase = .ready
        operation.panelShowing = true
        operation.enact()
        try await poll(message: "the run finishes") { operation.phase == .finished }
        await operation.stopOwnedWork()
        #expect(operation.phase == .finished)
        #expect(!lines(operation).contains { $0.hasPrefix("quit —") })
    }

    @Test("⌃C on a progressive move still shows which sources remain, then the cancelled outcome")
    func cancelledMoveReportsRetainedSources() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("from")
        let target = directory.appendingPathComponent("to")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appendingPathComponent("kept.txt"))
        let entry = FileEntry(
            nameData: Data("kept.txt".utf8),
            kind: .file,
            size: 1,
            modified: Date(),
            permissions: "644",
            owner: "op",
            group: "op")
        let rsync = HostCapability(kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "rsync  version 3.4.1")
        var plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: source.path),
                entries: [entry],
                destination: Locus(host: PalanaCore.localHostName, directory: target.path)),
            facts: PlanFacts(sourceCapability: rsync, destinationCapability: rsync))
        #expect(plan.usesProgressiveRsyncMove)
        // The transfer is held long enough to be cancelled; it still names
        // the source-removal option the move carries.
        let transfer = try #require(plan.steps.firstIndex { $0.command.contains("--remove-source-files") })
        plan.steps[transfer].command =
            "echo $$ > \(ShellQuote.quote(pidFile.path)); sleep 30 && rsync --remove-source-files /nonexistent /nowhere"

        let operation = makeOperation()
        operation.plan = plan
        operation.phase = .ready
        operation.enact()
        try await poll(message: "the transfer starts") { pid() != nil }
        operation.cancelEnactment()
        try await poll(message: "the cancel lands") { operation.phase == .cancelled }

        let shown = lines(operation)
        let retained = try #require(shown.firstIndex { $0.hasPrefix("retained:") && $0.contains("kept.txt") })
        let cancelled = try #require(shown.lastIndex { $0.hasPrefix("cancelled —") })
        #expect(retained < cancelled, "the report arrives before the cancelled outcome is sealed")
        let record = try String(contentsOf: logURL, encoding: .utf8)
        #expect(record.contains("# retained:"))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("kept.txt").path))
    }
}

// MARK: - F05, pass 2: shutdown closes admission

/// Shutdown closes admission before it awaits anything.
///
/// Pass 2 found the queue could start an upload after quit stopped the
/// current run: `.cancelled` reads as a free panel. Shutdown now closes
/// admission first, stops the upload producers, and never reopens.
@MainActor
@Suite("Final review F05 (pass 2) — nothing starts once shutdown begins", .serialized)
struct FinalReviewShutdownAdmissionTests {
    /// A one-step local plan in `directory`.
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

    @Test("a save queued behind a running plan is not delivered during or after shutdown, and its copy is kept")
    func queuedSaveNeverStarts() async throws {
        let rig = try TestSession()
        defer { rig.tearDown() }
        let session = rig.session
        let operation = session.operation
        let center = session.roundTripCenter
        let pidFile = rig.directory.appendingPathComponent("pid")
        operation.plan = localPlan("echo $$ > \(ShellQuote.quote(pidFile.path)); sleep 30", in: rig.directory)
        operation.phase = .ready
        operation.enact()
        try await poll(message: "the run starts") { FileManager.default.fileExists(atPath: pidFile.path) }

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
        let production = center.deliverUpload
        var delivered = 0
        center.deliverUpload = { record in
            delivered += 1
            production(record)
        }
        try Data("unsent".utf8).write(to: url)
        center.offerOrQueue(record: record)
        #expect(center.pendingRecordIDs == [record.id], "queued behind the running plan")

        await session.closeDoors()
        #expect(operation.phase == .cancelled)
        // Three poll intervals past the end of shutdown: the gate stays shut.
        try await Task.sleep(for: .milliseconds(1_000))
        #expect(delivered == 0, "no upload is delivered once shutdown has begun")
        #expect(operation.phase == .cancelled)
        #expect(center.pendingRecordIDs.isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "unsent", "the unsent edit stays on disk")

        // Late callbacks and keys land nowhere.
        center.offerOrQueue(record: record)
        #expect(center.drainOneIfFree())
        operation.plan = localPlan("true", in: rig.directory)
        operation.phase = .ready
        operation.enact()
        operation.beginRoundTripUpload(record: record)
        #expect(operation.phase == .ready, "Enter and an upload both refuse once closing")
        #expect(delivered == 0)
    }
}
