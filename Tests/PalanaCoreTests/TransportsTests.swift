import Foundation
import Testing

@testable import PalanaCore

private func transportEntry(_ name: String) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .directory,
        size: 0,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "755",
        owner: "op",
        group: "op")
}

private actor TransportBox<Value: Sendable> {
    private(set) var value: Value?

    func set(_ newValue: Value) {
        value = newValue
    }
}

@Suite("Transports")
struct TransportsTests {
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

    private static func transports(_ entries: [ConduitTranscript.Entry]) -> Transports {
        Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript(entries: entries))
        ) { _, _, _ in -1 }
    }

    private static func collect(
        _ stream: AsyncThrowingStream<EnactmentEvent, Error>
    ) async throws -> [EnactmentEvent] {
        var events: [EnactmentEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private static func zfsMove() throws -> Plan {
        let capability = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil)
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank"),
                entries: [transportEntry("media")],
                destination: Locus(host: "k", directory: "/rpool/cold"),
                token: "t1"),
            facts: PlanFacts(
                destinationDataset: ZFSDataset(
                    name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
                selectionWholeDataset: ZFSDataset(
                    name: "tank/media", mountpoint: "/tank/media", mounted: true),
                sourceCapability: capability,
                destinationCapability: capability,
                agentForwarding: .available))
    }

    private static func proxiedCopy() throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: "j", directory: "/tank/a"),
                entries: [transportEntry("media")],
                destination: Locus(host: "k", directory: "/rpool/b"),
                token: "t1"),
            facts: PlanFacts())
    }

    @Test("a ZFS move releases its destroys only after the dataset exists")
    func zfsMoveEnacts() async throws {
        let plan = try Self.zfsMove()
        let transports = Self.transports([
            Self.entry("j", "zfs snapshot -r tank/media@t1"),
            Self.entry(
                "j", "zfs send -R -v tank/media@t1 | ssh k 'zfs receive -u rpool/cold/media'"),
            Self.entry("k", "zfs list -H -o name rpool/cold/media", stdout: "rpool/cold/media\n"),
            Self.entry("k", "zfs destroy -r rpool/cold/media@t1"),
            Self.entry("j", "zfs destroy -r tank/media"),
        ])

        let events = try await Self.collect(transports.enact(plan))
        let verified = EnactmentEvent.verified(
            .datasetReceived(name: "rpool/cold/media", exists: true))
        let verifiedAt = try #require(events.firstIndex(of: verified))
        let firstGate = try #require(
            events.firstIndex(of: .stepBegan(index: 2, step: plan.steps[2])))
        #expect(verifiedAt < firstGate)
        #expect(events.last == .finished)
    }

    @Test("a missing received dataset keeps every ZFS destroy unrun")
    func zfsMissingDatasetHoldsGate() async throws {
        let plan = try Self.zfsMove()
        let transports = Self.transports([
            Self.entry("j", "zfs snapshot -r tank/media@t1"),
            Self.entry(
                "j", "zfs send -R -v tank/media@t1 | ssh k 'zfs receive -u rpool/cold/media'"),
            Self.entry("k", "zfs list -H -o name rpool/cold/media", exit: 1),
        ])

        await #expect(throws: EnactmentError.self) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }

    @Test("a changed ZFS destroy is refused before the snapshot runs")
    func changedZFSReleaseRefused() async throws {
        var plan = try Self.zfsMove()
        plan.steps[3] = PlanStep(
            runsOn: .host("j"),
            command: "zfs destroy -r tank/other",
            role: .delete,
            gatedOnVerification: true)

        await #expect(throws: EnactmentError.self) {
            _ = try await Self.collect(Self.transports([]).enact(plan))
        }
    }

    @Test("a decoded ZFS plan without its release binding is refused before execution")
    func missingZFSReleaseRefused() async throws {
        var plan = try Self.zfsMove()
        plan.zfsReleaseGuard = nil

        await #expect(throws: EnactmentError.self) {
            _ = try await Self.collect(Self.transports([]).enact(plan))
        }
    }

    @Test("a proxied copy hands its structured pipeline to the runner")
    func pipelineRunnerReceivesHalves() async throws {
        let plan = try Self.proxiedCopy()
        let received = TransportBox<Pipeline>()
        let transports = Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript())
        ) { pipeline, stepIndex, emit in
            await received.set(pipeline)
            emit(.progress(ProgressReport(bytesTransferred: 3)))
            emit(.outputChunk(stepIndex: stepIndex, channel: .stderr, data: Data("noise".utf8)))
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
        var plan = try Self.proxiedCopy()
        plan.steps[0].pipeline = nil

        await #expect(throws: EnactmentError.self) {
            _ = try await Self.collect(Self.transports([]).enact(plan))
        }
    }

    @Test("progress parsing recognizes rsync by binary name")
    func rsyncPredicate() {
        #expect(Transports.isRsyncCommand("rsync -a --partial a b"))
        #expect(Transports.isRsyncCommand("/opt/homebrew/bin/rsync -a a b"))
        #expect(Transports.isRsyncCommand("'/Volumes/My Tools/bin/rsync' -a a b"))
        #expect(!Transports.isRsyncCommand("rsyncd --daemon"))
        #expect(!Transports.isRsyncCommand("myrsync -a a b"))
        #expect(!Transports.isRsyncCommand("/usr/local/bin/myrsync -a a b"))
        #expect(!Transports.isRsyncCommand("tar -cf - a"))
        #expect(!Transports.isRsyncCommand("'unterminated -a a b"))
        #expect(!Transports.isRsyncCommand(""))
    }
}
