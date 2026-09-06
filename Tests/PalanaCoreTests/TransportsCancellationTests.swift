// Cancellation through the Transports: a host step's process group and
// a proxied pipeline's halves stop when the enacting task is cancelled,
// the later steps never start, and CancellationError surfaces only
// after the processes have exited. Every step here runs on this
// machine through the local door or the fake ssh.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Transports cancellation")
struct TransportsCancellationTests {
    private let directory: URL
    private let pidFile: URL
    private let marker: URL
    private let nextStepMarker: URL

    init() throws {
        directory = try ProcessFixture.makeDirectory()
        pidFile = directory.appendingPathComponent("pid")
        marker = directory.appendingPathComponent("marker")
        nextStepMarker = directory.appendingPathComponent("next-step")
    }

    private func plan(steps: [PlanStep], transport: Transport = .local) -> Plan {
        Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: Locus(host: "local", directory: directory.path),
            destination: Locus(host: "local", directory: directory.path),
            transport: transport,
            steps: steps)
    }

    private var slowStep: PlanStep {
        PlanStep(
            runsOn: .host("local"),
            command:
                "\(ProcessFixture.recordPid(at: pidFile)); sleep 30; touch \(ShellQuote.quote(marker.path))",
            role: .copy)
    }

    private var nextStep: PlanStep {
        PlanStep(
            runsOn: .host("local"),
            command: "touch \(ShellQuote.quote(nextStepMarker.path))",
            role: .copy)
    }

    @Test("cancelling the enacting task stops the host step's group; the next step never runs")
    func cancelledHostStep() async throws {
        let transports = Transports(conduit: LocalConduit())
        let plan = plan(steps: [slowStep, nextStep])
        let sink = EventSink()
        let task = Task {
            try await transports.run(plan) { sink.record($0) }
        }
        let pid = try #require(await ProcessFixture.awaitPid(at: pidFile))

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        // The leader had been reaped before the cancellation surfaced.
        #expect(!ProcessFixture.isAlive(pid))
        #expect(!ProcessFixture.exists(marker), "the interrupted step's side effect never landed")
        #expect(!ProcessFixture.exists(nextStepMarker), "the next step never started")
        #expect(!sink.events.contains(.stepBegan(index: 1, step: nextStep)))
    }

    @Test("ending the event stream early stops the step's process")
    func abandonedStream() async throws {
        let transports = Transports(conduit: LocalConduit())
        let plan = plan(steps: [slowStep])
        var pid: pid_t?
        for try await event in transports.enact(plan) {
            if case .stepBegan = event {
                // Let the shell record itself, then walk away from the stream.
                pid = await ProcessFixture.awaitPid(at: pidFile)
                break
            }
        }
        let leader = try #require(pid)
        #expect(await ProcessFixture.awaitDeath(of: leader))
        #expect(!ProcessFixture.exists(marker))
    }

    @Test("cancelling a proxied pipeline stops and awaits both halves")
    func cancelledPipeline() async throws {
        let producerPid = directory.appendingPathComponent("producer.pid")
        let consumerPid = directory.appendingPathComponent("consumer.pid")
        let configuration = SSHConfiguration(
            sshExecutablePath: try ProcessFixture.fakeSSH(in: directory),
            controlDirectory: directory.path)
        let transports = Transports(conduit: LocalConduit(), configuration: configuration)
        let pipeline = Pipeline(
            fromHost: "a",
            fromCommand: "\(ProcessFixture.recordPid(at: producerPid)); sleep 30",
            toHost: "b",
            toCommand: "\(ProcessFixture.recordPid(at: consumerPid)); cat > /dev/null")
        let step = PlanStep(
            runsOn: .operatorMachine,
            command: "ssh a … | ssh b …",
            role: .transfer,
            pipeline: pipeline)
        let plan = plan(steps: [step, nextStep], transport: .tarStreamProxied)
        let task = Task {
            try await transports.run(plan) { _ in }
        }
        let producer = try #require(await ProcessFixture.awaitPid(at: producerPid))
        let consumer = try #require(await ProcessFixture.awaitPid(at: consumerPid))

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await ProcessFixture.awaitDeath(of: producer))
        #expect(await ProcessFixture.awaitDeath(of: consumer))
        #expect(!ProcessFixture.exists(nextStepMarker))
    }
}
