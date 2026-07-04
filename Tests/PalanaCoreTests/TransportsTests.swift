// The Transports' gate logic over RecordedConduit playback. The
// transcript is the network: a gated step missing from the transcript
// that gets attempted surfaces as UnrecordedCommand, so a gate leak
// cannot hide behind a passing test.

import Foundation
import Testing

@testable import PalanaCore

/// A tiny mailbox for values captured inside Sendable closures.
private actor Box<Value: Sendable> {
    private(set) var value: Value?

    func set(_ newValue: Value) {
        value = newValue
    }
}

private func makeEntry(_ name: String, size: Int64 = 0) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .file,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

@Suite("Transports")
struct TransportsTests {
    private static let entries = [makeEntry("f1", size: 1), makeEntry("f2", size: 2)]

    private static func crossDatasetMove() throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank/a"),
                entries: entries,
                destination: Locus(host: "j", directory: "/tank/b"),
                token: "t1"),
            facts: PlanFacts())
    }

    private static func tarProxyMove() throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank/a"),
                entries: entries,
                destination: Locus(host: "k", directory: "/rpool/b"),
                token: "t1"),
            facts: PlanFacts())
    }

    private static func entry(
        _ host: String,
        _ command: String,
        stdout: String = "",
        stderr: String = "",
        exit: Int32 = 0
    ) -> ConduitTranscript.Entry {
        ConduitTranscript.Entry(
            host: host, command: command, stdout: stdout, stderr: stderr, exit: exit)
    }

    private static func transports(
        _ transcriptEntries: [ConduitTranscript.Entry],
        pipelineRunner: Transports.PipelineRunner? = nil
    ) -> Transports {
        Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript(entries: transcriptEntries)),
            pipelineRunner: pipelineRunner ?? { _, _, _ in
                Issue.record("pipeline runner should not have been called")
                return -1
            })
    }

    private static func collect(
        _ stream: AsyncThrowingStream<EnactmentEvent, Error>
    ) async throws -> [EnactmentEvent] {
        var events: [EnactmentEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    @Test("a gated move enacts in order: copy, visible verify, then the release")
    func gatedMoveEnacts() async throws {
        let plan = try Self.crossDatasetMove()
        let transports = Self.transports([
            Self.entry("j", "cp -a /tank/a/f1 /tank/a/f2 /tank/b/"),
            Self.entry("j", "find /tank/a/f1 /tank/a/f2 | wc -l", stdout: "2\n"),
            Self.entry("j", "find /tank/b/f1 /tank/b/f2 | wc -l", stdout: "2\n"),
            Self.entry("j", "rm -rf /tank/a/f1 /tank/a/f2"),
        ])
        let events = try await Self.collect(transports.enact(plan))

        #expect(events.first == .stepBegan(index: 0, step: plan.steps[0]))
        #expect(events.contains(.stepEnded(index: 0, exitStatus: 0)))
        #expect(
            events.contains(
                .verifying(host: "j", command: "find /tank/a/f1 /tank/a/f2 | wc -l")))
        #expect(
            events.contains(.verified(VerificationReport(sourceCount: 2, destinationCount: 2))))
        #expect(events.contains(.stepBegan(index: 1, step: plan.steps[1])))
        #expect(events.last == .finished)

        // Verification strictly precedes the gated step.
        let verifiedAt = try #require(
            events.firstIndex(of: .verified(VerificationReport(sourceCount: 2, destinationCount: 2))))
        let gateAt = try #require(events.firstIndex(of: .stepBegan(index: 1, step: plan.steps[1])))
        #expect(verifiedAt < gateAt)
    }

    @Test("a count mismatch closes the gate — the delete is never attempted")
    func mismatchHoldsGate() async throws {
        let plan = try Self.crossDatasetMove()
        // No rm entry in the transcript: an attempted gate leak would
        // surface as UnrecordedCommand, not verificationFailed.
        let transports = Self.transports([
            Self.entry("j", "cp -a /tank/a/f1 /tank/a/f2 /tank/b/"),
            Self.entry("j", "find /tank/a/f1 /tank/a/f2 | wc -l", stdout: "2\n"),
            Self.entry("j", "find /tank/b/f1 /tank/b/f2 | wc -l", stdout: "1\n"),
        ])
        let expected = EnactmentError.verificationFailed(
            VerificationReport(sourceCount: 2, destinationCount: 1))
        await #expect(throws: expected) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }

    @Test("a failed step halts enactment with its stderr, gates unreleased")
    func stepFailureHalts() async throws {
        let plan = try Self.crossDatasetMove()
        let transports = Self.transports([
            Self.entry(
                "j",
                "cp -a /tank/a/f1 /tank/a/f2 /tank/b/",
                stderr: "cp: cannot stat '/tank/a/f1'",
                exit: 1)
        ])
        let expected = EnactmentError.stepFailed(
            index: 0,
            exitStatus: 1,
            stderrTail: "cp: cannot stat '/tank/a/f1'")
        await #expect(throws: expected) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }

    @Test("a door failure mid-enactment stays typed as the Conduit's")
    func doorFailureStaysTyped() async throws {
        let plan = try Self.crossDatasetMove()
        let transports = Self.transports([
            Self.entry(
                "j",
                "cp -a /tank/a/f1 /tank/a/f2 /tank/b/",
                stderr: "Connection closed by remote host",
                exit: 255)
        ])
        await #expect(throws: ConduitError.self) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }

    @Test("a proxied plan hands the structured pipeline to the runner")
    func pipelineRunnerReceivesHalves() async throws {
        let plan = try Self.tarProxyMove()
        let received = Box<Pipeline>()
        let transports = Self.transports(
            [
                Self.entry("j", "find /tank/a/f1 /tank/a/f2 | wc -l", stdout: "2\n"),
                Self.entry("k", "find /rpool/b/f1 /rpool/b/f2 | wc -l", stdout: "2\n"),
                Self.entry("j", "rm -rf /tank/a/f1 /tank/a/f2"),
            ]
        ) { pipeline, stepIndex, emit in
            await received.set(pipeline)
            emit(.progress(ProgressReport(bytesTransferred: 3)))
            emit(
                .outputChunk(
                    stepIndex: stepIndex, channel: .stderr, data: Data("noise".utf8)))
            return 0
        }
        let events = try await Self.collect(transports.enact(plan))

        let pipeline = try #require(await received.value)
        #expect(pipeline.fromHost == "j")
        #expect(pipeline.toHost == "k")
        #expect(pipeline.fromCommand.hasPrefix("tar -cf"))
        #expect(pipeline.toCommand.hasPrefix("tar -xpf"))
        #expect(events.contains(.progress(ProgressReport(bytesTransferred: 3))))
        #expect(events.last == .finished)
    }

    @Test("an operator-machine step without a pipeline is a typed refusal")
    func missingPipelineRefused() async throws {
        var plan = try Self.tarProxyMove()
        plan.steps[0].pipeline = nil
        let transports = Self.transports([])
        await #expect(throws: EnactmentError.self) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }

    @Test("zfs transports refuse in this half, typed for ho-06.2")
    func zfsUnsupportedHere() async throws {
        let dataset = ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true)
        let capability = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil)
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank"),
                entries: [makeEntry("media")],
                destination: Locus(host: "k", directory: "/rpool/cold"),
                token: "t1"),
            facts: PlanFacts(
                destinationDataset: ZFSDataset(
                    name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
                selectionWholeDataset: dataset,
                sourceCapability: capability,
                destinationCapability: capability,
                agentForwarding: .available))
        let transports = Self.transports([])
        let expected = EnactmentError.unsupportedTransport(.zfsSendReceiveForwarded)
        await #expect(throws: expected) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }
}
