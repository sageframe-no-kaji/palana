// The proxied pipeline's two halves as owned processes. The fake ssh
// runs each half on this machine, so both halves are real children
// with pids the tests can watch die: a consumer that fails to launch
// takes the producer down, a cancelled task stops and awaits both, and
// a consumer that dies ends the pump instead of wedging it.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SSHPipeline")
struct SSHPipelineTests {
    private let directory: URL
    private let configuration: SSHConfiguration
    private let producerPid: URL
    private let consumerPid: URL

    init() throws {
        directory = try ProcessFixture.makeDirectory()
        configuration = SSHConfiguration(
            sshExecutablePath: try ProcessFixture.fakeSSH(in: directory),
            controlDirectory: directory.path)
        producerPid = directory.appendingPathComponent("producer.pid")
        consumerPid = directory.appendingPathComponent("consumer.pid")
    }

    private func pipeline(from fromCommand: String, to toCommand: String) -> Pipeline {
        Pipeline(fromHost: "a", fromCommand: fromCommand, toHost: "b", toCommand: toCommand)
    }

    /// The real spawner — what `SSHPipeline.run` uses when none is injected.
    private static let realSpawn: SSHPipeline.HalfSpawner = { host, command, configuration, pipedInput in
        try SSHPipeline.spawnHalf(
            host: host, command: command, configuration: configuration, pipedInput: pipedInput)
    }

    private func run(
        _ pipeline: Pipeline,
        spawn: SSHPipeline.HalfSpawner = Self.realSpawn
    ) async throws -> (status: Int32, events: [EnactmentEvent]) {
        let sink = EventSink()
        let status = try await SSHPipeline.run(
            pipeline,
            configuration: configuration,
            stepIndex: 0,
            emit: { sink.record($0) },
            spawn: spawn)
        return (status, sink.events)
    }

    @Test("bytes are counted between two local halves and land whole")
    func countsBytes() async throws {
        let landed = directory.appendingPathComponent("landed")
        let (status, events) = try await run(
            pipeline(
                from: "head -c 300000 /dev/zero",
                to: "cat > \(ShellQuote.quote(landed.path))"))
        #expect(status == 0)
        let counted = events.compactMap { event -> Int64? in
            if case .progress(let report) = event { return report.bytesTransferred }
            return nil
        }
        #expect(counted.last == 300_000)
        let size = try FileManager.default.attributesOfItem(atPath: landed.path)[.size] as? Int
        #expect(size == 300_000)
    }

    @Test("the failing half's status is reported, producer first")
    func failingHalf() async throws {
        let producerFails = try await run(pipeline(from: "echo x; exit 3", to: "cat > /dev/null"))
        #expect(producerFails.status == 3)
        let consumerFails = try await run(pipeline(from: "echo x", to: "cat > /dev/null; exit 4"))
        #expect(consumerFails.status == 4)
        let stderrChunks = try await run(pipeline(from: "echo warn >&2", to: "cat > /dev/null"))
        #expect(
            stderrChunks.events.contains(
                .outputChunk(stepIndex: 0, channel: .stderr, data: Data("warn\n".utf8))))
    }

    @Test("a consumer that cannot launch leaves no producer running")
    func consumerLaunchFailureStopsProducer() async throws {
        // The producer's pid is taken from the spawn itself: the half
        // is stopped too quickly for its shell to have written one.
        let spawned = PidBox()
        let refuseConsumer: SSHPipeline.HalfSpawner = { host, command, configuration, pipedInput in
            guard !pipedInput else {
                throw ConduitError.launchFailed("consumer refused by the test")
            }
            let half = try SSHPipeline.spawnHalf(
                host: host, command: command, configuration: configuration, pipedInput: pipedInput)
            spawned.record(half.process.pid)
            return half
        }
        await #expect(throws: ConduitError.launchFailed("consumer refused by the test")) {
            _ = try await run(pipeline(from: "sleep 30", to: "cat > /dev/null"), spawn: refuseConsumer)
        }
        // The producer was launched before the consumer refused — and
        // had been reaped by the time the failure was reported.
        let producer = try #require(spawned.pid)
        #expect(!ProcessFixture.isAlive(producer))
    }

    @Test("cancelling the task stops and awaits both halves")
    func cancellationStopsBothHalves() async throws {
        let pipeline = pipeline(
            from: "\(ProcessFixture.recordPid(at: producerPid)); sleep 30",
            to: "\(ProcessFixture.recordPid(at: consumerPid)); cat > /dev/null")
        let configuration = configuration
        let task = Task { () throws -> Int32 in
            try await SSHPipeline.run(pipeline, configuration: configuration, stepIndex: 0) { _ in }
        }
        let producer = try #require(await ProcessFixture.awaitPid(at: producerPid))
        let consumer = try #require(await ProcessFixture.awaitPid(at: consumerPid))
        #expect(ProcessFixture.isAlive(producer))
        #expect(ProcessFixture.isAlive(consumer))

        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await ProcessFixture.awaitDeath(of: producer))
        #expect(await ProcessFixture.awaitDeath(of: consumer))
    }

    @Test("a consumer that dies ends the pump — the producer is stopped, not drained forever")
    func consumerDeathEndsThePump() async throws {
        // `yes` writes until something stops it; the consumer exits at
        // once, so the pump's next write fails, the producer is
        // terminated, and its read end closes under it.
        let (status, _) = try await run(pipeline(from: "yes", to: "exit 5"))
        #expect(status != 0)
        #expect([5, 128 + SIGPIPE, 128 + SIGTERM].contains(status))
    }
}

/// Holds a pid recorded inside a Sendable spawner.
final class PidBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: pid_t?

    func record(_ pid: pid_t) {
        lock.withLock { stored = pid }
    }

    var pid: pid_t? {
        lock.withLock { stored }
    }
}

/// Collects emitted events across the pipeline's queues.
final class EventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [EnactmentEvent] = []

    func record(_ event: EnactmentEvent) {
        lock.withLock { stored.append(event) }
    }

    var events: [EnactmentEvent] {
        lock.withLock { stored }
    }
}
