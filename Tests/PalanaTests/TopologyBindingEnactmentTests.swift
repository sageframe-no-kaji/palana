// The operation model's side of topology truth. A zfs gather reads the
// host before it composes; Enter re-reads before the first step; the
// snapshot-context read belongs to the gather that started it. Every
// host here is a stand-in answered by a sequenced conduit — the wire
// is the queue, and the only commands that run for real run on this
// Mac and touch a marker file.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class TopologyBindingEnactmentTests: XCTestCase {
    private static let host = "fixture"
    private static let probe = """
        palana:kernel:Linux
        palana:flavor:GNU
        palana:zfs:zfs-2.2.2
        palana:rsync:
        """
    private static let sudoProbe = "sudo -n true 2>/dev/null || sudo -n -l zfs mount"
    private static let doorRefused = "ssh: connect to host fixture port 22: Connection refused"

    private var directory = URL(fileURLWithPath: "/")
    private var marker: URL { directory.appendingPathComponent("marker") }
    private let zfsTool = ZFSMutationTool()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-topology-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixture

    /// A conduit answering the fixture host's discovery, topology given
    /// per read; the probe, mounts, and sudo answers repeat.
    private func conduit(topologies: [String], probes: [SequencedConduit.Answer]? = nil) -> SequencedConduit {
        let conduit = SequencedConduit()
        conduit.enqueue(Self.host, CapabilityProbe.command, probes ?? [.init(stdout: Self.probe)])
        conduit.enqueue(Self.host, ZFSTopology.listCommand, topologies.map { .init(stdout: $0) })
        conduit.enqueue(Self.host, MountTable.command(forKernel: "Linux"), [.init(stdout: "/dev/sda1 / ext4 rw 0 0")])
        conduit.enqueue(Self.host, Self.sudoProbe, [.init(stdout: "")])
        return conduit
    }

    private func makeOperation(
        conduit: SequencedConduit, remembered: [ZFSDataset]? = nil
    ) throws -> OperationModel {
        let cache = FieldCache(url: directory.appendingPathComponent("field-cache.json"))
        if let remembered {
            let stamp = Date(timeIntervalSince1970: 1)
            try cache.save([
                Self.host: HostFacts(
                    capability: Dated(
                        value: HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil),
                        discoveredAt: stamp),
                    zfsTopology: Dated(value: remembered, discoveredAt: stamp))
            ])
        }
        let configuration = SSHConfiguration()
        let field = Field(conduit: conduit, hosts: [Self.host], cache: cache)
        let engine = Engine(
            conduit: SSHConduit(configuration: configuration),
            field: field,
            listing: Listing(conduit: conduit))
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        settings.confirmDestroyTyped = false
        return OperationModel(
            engine: engine,
            configuration: configuration,
            settings: settings,
            log: OperationLog(url: directory.appendingPathComponent("operations.log")))
    }

    private func verb(_ id: String) throws -> WorkbenchVerb {
        try XCTUnwrap(zfsTool.verbs.first { $0.id == id })
    }

    private func transcript(_ operation: OperationModel) -> [String] {
        operation.echo.lines.map(\.text)
    }

    @discardableResult
    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Opens a field-less destroy gather on `dataset` and commits it,
    /// then waits for the compose to land somewhere.
    private func composeDestroy(_ operation: OperationModel, dataset: String, mounted: Bool = false) async throws {
        operation.beginZFSMutation(
            try verb("zfs-destroy"), tool: zfsTool, host: Self.host, dataset: dataset, mounted: mounted)
        XCTAssertEqual(operation.phase, .naming)
        operation.commitNaming("")
        XCTAssertEqual(operation.phase, .gathering, "the compose reads the host before it composes")
        await waitUntil { operation.phase == .ready || operation.phase == .failed }
    }

    private func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A plan whose one real step runs here and leaves a marker, bound
    /// to a dataset on the fixture host as read at `generation`.
    private func boundPlan(
        _ bound: [TopologyBinding.Bound], destination: Locus? = nil
    ) -> Plan {
        Plan(
            operation: .zfs,
            classification: .zfsMutation,
            entries: [],
            totalSize: 0,
            source: Locus(host: Self.host, directory: "tank/data"),
            destination: destination,
            transport: .local,
            steps: [
                PlanStep(
                    runsOn: .host(PalanaCore.localHostName),
                    command: "touch \(quote(marker.path))",
                    role: .delete)
            ],
            topologyBinding: TopologyBinding(bound: bound))
    }

    private static let dataAtData = ZFSDataset(name: "tank/data", mountpoint: "/data", mounted: true)
    private static let topologyA = "tank\t/tank\tyes\ntank/data\t/data\tyes\n"
    private static let topologyMoved = "tank\t/tank\tyes\ntank/data\t/aside\tyes\ntank/new\t/data\tyes\n"

    // MARK: - Compose reads fresh

    func testComposeReadsTheHostFreshAndBindsThePlanToThatRead() async throws {
        let operation = try makeOperation(conduit: conduit(topologies: [Self.topologyA]))
        // The surface's remembered mounted flag is false; the read says yes.
        try await composeDestroy(operation, dataset: "tank/data", mounted: false)

        XCTAssertEqual(operation.phase, .ready)
        let plan = try XCTUnwrap(operation.plan)
        XCTAssertEqual(
            plan.topologyBinding,
            TopologyBinding(bound: [
                TopologyBinding.Bound(host: Self.host, role: .target, dataset: Self.dataAtData, generation: 1)
            ]))
        XCTAssertEqual(
            plan.steps.map(\.command),
            ["sudo -n zfs unmount tank/data", "zfs destroy tank/data", "! zfs list -H -o name -- tank/data"],
            "the unmount weave follows the fresh mounted fact, not the surface's memory")
        XCTAssertTrue(transcript(operation).contains("reading zfs on fixture…"))
    }

    func testComposeRefusesADatasetThatMovedSinceItWasShown() async throws {
        // Memory mapped /data to tank/data; the wire now says tank/data
        // sits at /aside and /data belongs to tank/new.
        let operation = try makeOperation(
            conduit: conduit(topologies: [Self.topologyMoved]), remembered: [Self.dataAtData])
        try await composeDestroy(operation, dataset: "tank/data", mounted: true)

        XCTAssertEqual(operation.phase, .failed)
        XCTAssertNil(operation.plan)
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(failure.text.contains("tank/data on fixture changed since it was shown"), failure.text)
        XCTAssertTrue(failure.text.contains("mountpoint /data → /aside"), failure.text)
        let memory = await operation.engine.field.facts(for: Self.host)?.zfsTopology?.value
        XCTAssertEqual(
            memory?.first { $0.name == "tank/data" }?.mountpoint,
            "/aside",
            "memory now carries the read, so the next choice is made on the truth")
    }

    func testComposeRefusesWhenTheTopologyReadFailsInsteadOfUsingMemory() async throws {
        let conduit = SequencedConduit()
        conduit.enqueue(Self.host, CapabilityProbe.command, [.init(stdout: Self.probe)])
        conduit.enqueue(
            Self.host, ZFSTopology.listCommand, [.init(stderr: "cannot open 'tank': permission denied", exit: 1)])
        conduit.enqueue(Self.host, MountTable.command(forKernel: "Linux"), [.init(stdout: "")])
        conduit.enqueue(Self.host, Self.sudoProbe, [.init(stdout: "")])
        let operation = try makeOperation(conduit: conduit, remembered: [Self.dataAtData])
        try await composeDestroy(operation, dataset: "tank/data")

        XCTAssertEqual(operation.phase, .failed)
        XCTAssertNil(operation.plan)
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(
            failure.text.hasPrefix("the zfs topology on fixture could not be read — cannot open 'tank'"), failure.text)
        let memory = await operation.engine.field.facts(for: Self.host)
        XCTAssertNil(memory?.zfsTopology, "the failed read cleared the remembered list")
        XCTAssertEqual(memory?.zfsTopologyUnavailable?.value.detail, "cannot open 'tank': permission denied")
    }

    func testComposeRefusesAnUnreachableHostInsteadOfUsingMemory() async throws {
        let conduit = conduit(topologies: [], probes: [.init(stderr: Self.doorRefused, exit: 255)])
        let operation = try makeOperation(conduit: conduit, remembered: [Self.dataAtData])
        try await composeDestroy(operation, dataset: "tank/data")

        XCTAssertEqual(operation.phase, .failed)
        XCTAssertNil(operation.plan)
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(failure.text.hasPrefix("fixture could not be read for this plan"), failure.text)
    }

    func testComposeRefusesADatasetTheReadDoesNotHold() async throws {
        let operation = try makeOperation(conduit: conduit(topologies: [Self.topologyA]))
        try await composeDestroy(operation, dataset: "tank/gone")

        XCTAssertEqual(operation.phase, .failed)
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(
            failure.text.hasPrefix("tank/gone on fixture no longer exists — the topology changed since it was shown"),
            failure.text)
    }

    // MARK: - Enter re-reads

    func testEnactmentRefusesWhenTheTopologyChangedSinceThePlan() async throws {
        let operation = try makeOperation(conduit: conduit(topologies: [Self.topologyA, Self.topologyMoved]))
        try await composeDestroy(operation, dataset: "tank/data")
        XCTAssertEqual(operation.phase, .ready)

        operation.enact()
        XCTAssertEqual(operation.phase, .enacting)
        await waitUntil { operation.phase != .enacting }

        XCTAssertEqual(operation.phase, .failed)
        let lines = transcript(operation)
        XCTAssertTrue(lines.contains("re-reading zfs on fixture before anything runs…"))
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(failure.text.contains("tank/data on fixture changed since the plan was read"), failure.text)
        XCTAssertTrue(failure.text.contains("nothing ran"), failure.text)
        XCTAssertFalse(lines.contains { $0.hasPrefix("$ ") }, "no step was started")
        XCTAssertTrue(operation.panelShowing)
    }

    func testEnactmentRefusesWhenTheReReadIsUnavailable() async throws {
        let conduit = conduit(
            topologies: [Self.topologyA],
            probes: [.init(stdout: Self.probe), .init(stderr: Self.doorRefused, exit: 255)])
        let operation = try makeOperation(conduit: conduit)
        try await composeDestroy(operation, dataset: "tank/data")
        XCTAssertEqual(operation.phase, .ready)

        operation.enact()
        await waitUntil { operation.phase != .enacting }

        XCTAssertEqual(operation.phase, .failed)
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(
            failure.text.hasPrefix("the zfs topology on fixture could not be re-read — nothing ran"), failure.text)
        XCTAssertFalse(transcript(operation).contains { $0.hasPrefix("$ ") })
    }

    func testCachedTopologyAloneCannotAuthorizeEnactment() async throws {
        // The plan's bound dataset matches memory exactly; the wire never
        // answers. Memory is not a re-read, so nothing runs.
        let operation = try makeOperation(conduit: SequencedConduit(), remembered: [Self.dataAtData])
        operation.plan = boundPlan([
            TopologyBinding.Bound(host: Self.host, role: .target, dataset: Self.dataAtData, generation: 0)
        ])
        operation.phase = .ready
        operation.enact()
        await waitUntil { operation.phase != .enacting }

        XCTAssertEqual(operation.phase, .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the step never ran")
        XCTAssertFalse(transcript(operation).contains { $0.hasPrefix("$ ") })
    }

    func testEnactmentProceedsWhenTheFreshReadConfirmsThePlan() async throws {
        let operation = try makeOperation(conduit: conduit(topologies: [Self.topologyA]))
        operation.plan = boundPlan([
            TopologyBinding.Bound(host: Self.host, role: .target, dataset: Self.dataAtData, generation: 0)
        ])
        operation.phase = .ready
        // On screen, so a finished run keeps its transcript instead of closing its books.
        operation.panelShowing = true
        operation.enact()
        await waitUntil { operation.phase != .enacting }

        XCTAssertEqual(operation.phase, .finished)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let lines = transcript(operation)
        XCTAssertTrue(lines.contains("re-reading zfs on fixture before anything runs…"))
        XCTAssertTrue(lines.contains("tank/data — as read when the plan composed"))
    }

    func testEnactmentRefusesWhenTheDestinationNoLongerHoldsTheDirectory() async throws {
        // A send-shaped binding: the receiving dataset must still be the
        // one whose mountpoint holds the destination directory.
        let operation = try makeOperation(conduit: conduit(topologies: [Self.topologyA]))
        let backup = ZFSDataset(name: "tank/backup", mountpoint: "/backup", mounted: true)
        operation.plan = boundPlan(
            [TopologyBinding.Bound(host: Self.host, role: .destination, dataset: backup, generation: 0)],
            destination: Locus(host: Self.host, directory: "/backup"))
        operation.phase = .ready
        operation.enact()
        await waitUntil { operation.phase != .enacting }

        XCTAssertEqual(operation.phase, .failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let failure = try XCTUnwrap(operation.echo.lines.last { $0.kind == .failure })
        XCTAssertTrue(
            failure.text.contains("tank/backup on fixture no longer holds the destination directory"), failure.text)
    }

    func testCancelDuringTheReReadLandsCancelledWithNothingRun() async throws {
        let conduit = conduit(topologies: [Self.topologyA])
        conduit.hold(Self.host, CapabilityProbe.command)
        let operation = try makeOperation(conduit: conduit)
        operation.plan = boundPlan([
            TopologyBinding.Bound(host: Self.host, role: .target, dataset: Self.dataAtData, generation: 0)
        ])
        operation.phase = .ready
        operation.enact()
        await waitUntil { conduit.isWaiting(Self.host, CapabilityProbe.command) }

        operation.cancelEnactment()
        XCTAssertEqual(operation.phase, .enacting)
        conduit.release(Self.host, CapabilityProbe.command)
        await waitUntil { operation.phase == .cancelled }

        XCTAssertEqual(operation.phase, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}

/// A command the sequenced conduit was never given an answer for.
struct Unqueued: Error {
    let host: String
    let command: String
}

/// A conduit that answers each `(host, command)` from a queue, in order,
/// and can hold a command until the test releases it.
///
/// The last answer repeats; a command with no queue throws ``Unqueued``,
/// the way playback throws for an unrecorded one.
final class SequencedConduit: Conduit, @unchecked Sendable {
    struct Answer {
        var stdout = ""
        var stderr = ""
        var exit: Int32 = 0
    }

    private let lock = NSLock()
    private var queues: [String: [Answer]] = [:]
    private var held: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    func enqueue(_ host: String, _ command: String, _ answers: [Answer]) {
        lock.withLock { queues[Self.key(host, command)] = answers }
    }

    /// The next run of this command waits until ``release(_:_:)``.
    func hold(_ host: String, _ command: String) {
        lock.withLock { _ = held.insert(Self.key(host, command)) }
    }

    /// Whether a run of this command is currently held.
    func isWaiting(_ host: String, _ command: String) -> Bool {
        lock.withLock { !(waiting[Self.key(host, command)] ?? []).isEmpty }
    }

    func release(_ host: String, _ command: String) {
        let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
            let key = Self.key(host, command)
            held.remove(key)
            let waiters = waiting[key] ?? []
            waiting[key] = []
            return waiters
        }
        for waiter in resumed {
            waiter.resume()
        }
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        let key = Self.key(host, command)
        let mustWait = lock.withLock { held.contains(key) }
        if mustWait {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting[key, default: []].append(continuation) }
            }
        }
        let answer: Answer? = lock.withLock {
            guard var queue = queues[key], !queue.isEmpty else { return nil }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            queues[key] = queue
            return next
        }
        guard let answer else { throw Unqueued(host: host, command: command) }
        return RunningCommand(
            replayingStdout: Data(answer.stdout.utf8),
            stderr: Data(answer.stderr.utf8),
            exitStatus: answer.exit)
    }

    func close(host: String) async {}

    func closeAll() async {}

    private static func key(_ host: String, _ command: String) -> String {
        "\(host)\n\(command)"
    }
}
