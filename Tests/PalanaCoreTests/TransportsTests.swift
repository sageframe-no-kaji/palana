// The Transports' gate logic over RecordedConduit playback. The
// transcript is the network: a gated step missing from the transcript
// that gets attempted surfaces as UnrecordedCommand, so a gate leak
// cannot hide behind a passing test. The adversarial manifest cases
// live in TransportsManifestTests.

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

    private static let twoFiles =
        ManifestFixture.file("f1", size: 1)
        + ManifestFixture.file("f2", size: 2, digest: ManifestFixture.worldDigest)

    @Test("a gated move enacts in order: copy, visible verify both ends, then the release")
    func gatedMoveEnacts() async throws {
        let plan = try Self.crossDatasetMove()
        let sourceCommand = ManifestFixture.command(MoveFixture.directory("/tank/a", "t1"), ["f1", "f2"])
        let destinationCommand = ManifestFixture.command("/tank/b", ["f1", "f2"])
        let transports = Self.transports([
            Self.entry("j", "cp -a /tank/a/f1 /tank/a/f2 /tank/b/"),
            Self.entry("j", MoveFixture.quarantine("j", "/tank/a", ["f1", "f2"], "t1")),
            Self.entry("j", sourceCommand, stdout: Self.twoFiles),
            Self.entry("j", destinationCommand, stdout: Self.twoFiles),
            Self.entry("j", MoveFixture.remove("/tank/a", "t1")),
        ])
        let events = try await Self.collect(transports.enact(plan))

        #expect(events.first == .stepBegan(index: 0, step: plan.steps[0]))
        #expect(events.contains(.stepEnded(index: 0, exitStatus: 0)))
        #expect(events.contains(.verifying(host: "j", command: sourceCommand)))
        #expect(events.contains(.verifying(host: "j", command: destinationCommand)))
        let manifest = try TransferManifest.parse(Data(Self.twoFiles.utf8))
        let verified = EnactmentEvent.verified(.manifests(source: manifest, destination: manifest))
        #expect(events.contains(verified))
        #expect(events.contains(.stepBegan(index: 2, step: plan.steps[2])))
        #expect(events.last == .finished)

        // The freeze strictly precedes verification, and verification
        // strictly precedes the gated step it authorises.
        let frozenAt = try #require(events.firstIndex(of: .stepEnded(index: 1, exitStatus: 0)))
        let verifiedAt = try #require(events.firstIndex(of: verified))
        let gateAt = try #require(events.firstIndex(of: .stepBegan(index: 2, step: plan.steps[2])))
        #expect(frozenAt < verifiedAt)
        #expect(verifiedAt < gateAt)
        let released = events.contains {
            guard case .released(let authorization) = $0 else { return false }
            return authorization.release == plan.moveRelease && authorization.firstUnmatched == nil
        }
        #expect(released, "the delete named the frozen source it was authorised over")
    }

    @Test("a manifest mismatch closes the gate — the delete is never attempted")
    func mismatchHoldsGate() async throws {
        let plan = try Self.crossDatasetMove()
        // No rm entry in the transcript: an attempted gate leak would
        // surface as UnrecordedCommand, not verificationFailed.
        let landed = ManifestFixture.file("f1", size: 1)
        let transports = Self.transports([
            Self.entry("j", "cp -a /tank/a/f1 /tank/a/f2 /tank/b/"),
            Self.entry("j", MoveFixture.quarantine("j", "/tank/a", ["f1", "f2"], "t1")),
            Self.entry(
                "j",
                ManifestFixture.command(MoveFixture.directory("/tank/a", "t1"), ["f1", "f2"]),
                stdout: Self.twoFiles),
            Self.entry(
                "j",
                ManifestFixture.command("/tank/b", ["f1", "f2"]),
                stdout: landed + ManifestFixture.file("f2", size: 2)),
        ])
        let expected = EnactmentError.verificationFailed(
            .manifests(
                source: try TransferManifest.parse(Data(Self.twoFiles.utf8)),
                destination: try TransferManifest.parse(
                    Data((landed + ManifestFixture.file("f2", size: 2)).utf8))))
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
                Self.entry("j", MoveFixture.quarantine("j", "/tank/a", ["f1", "f2"], "t1")),
                Self.entry(
                    "j",
                    ManifestFixture.command(MoveFixture.directory("/tank/a", "t1"), ["f1", "f2"]),
                    stdout: Self.twoFiles),
                Self.entry("k", ManifestFixture.command("/rpool/b", ["f1", "f2"]), stdout: Self.twoFiles),
                Self.entry("j", MoveFixture.remove("/tank/a", "t1")),
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

    private static func zfsMove(forwarding: ForwardingFact) throws -> Plan {
        let capability = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil)
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank"),
                entries: [makeEntry("media")],
                destination: Locus(host: "k", directory: "/rpool/cold"),
                token: "t1"),
            facts: PlanFacts(
                destinationDataset: ZFSDataset(
                    name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
                selectionWholeDataset: ZFSDataset(
                    name: "tank/media", mountpoint: "/tank/media", mounted: true),
                sourceCapability: capability,
                destinationCapability: capability,
                agentForwarding: forwarding))
    }

    @Test("a zfs move gates its destroys on the dataset having been received")
    func zfsMoveEnacts() async throws {
        let plan = try Self.zfsMove(forwarding: .available)
        #expect(plan.receivedDataset == "rpool/cold/media")
        let transports = Self.transports([
            Self.entry("j", "zfs snapshot -r tank/media@t1"),
            Self.entry(
                "j", "zfs send -R -v tank/media@t1 | ssh k 'zfs receive -u rpool/cold/media'"),
            Self.entry(
                "k", "zfs list -H -o name rpool/cold/media", stdout: "rpool/cold/media\n"),
            Self.entry("k", "zfs destroy -r rpool/cold/media@t1"),
            Self.entry("j", "zfs destroy -r tank/media"),
        ])
        let events = try await Self.collect(transports.enact(plan))

        let verified = EnactmentEvent.verified(
            .datasetReceived(name: "rpool/cold/media", exists: true))
        #expect(events.contains(verified))
        #expect(events.last == .finished)
        let verifiedAt = try #require(events.firstIndex(of: verified))
        let firstGate = try #require(
            events.firstIndex(of: .stepBegan(index: 2, step: plan.steps[2])))
        #expect(verifiedAt < firstGate)
    }

    @Test("a receive that did not land keeps every destroy unrun")
    func zfsMissingDatasetHoldsGate() async throws {
        let plan = try Self.zfsMove(forwarding: .available)
        // No destroy entries: a gate leak would surface as UnrecordedCommand.
        let transports = Self.transports([
            Self.entry("j", "zfs snapshot -r tank/media@t1"),
            Self.entry(
                "j", "zfs send -R -v tank/media@t1 | ssh k 'zfs receive -u rpool/cold/media'"),
            Self.entry(
                "k",
                "zfs list -H -o name rpool/cold/media",
                stderr: "cannot open 'rpool/cold/media': dataset does not exist",
                exit: 1),
        ])
        let expected = EnactmentError.verificationFailed(
            .datasetReceived(name: "rpool/cold/media", exists: false))
        await #expect(throws: expected) {
            _ = try await Self.collect(transports.enact(plan))
        }
    }

    @Test("progress parsing recognizes rsync by binary name, bare or absolute")
    func rsyncPredicate() {
        #expect(Transports.isRsyncCommand("rsync -a --partial a b"))
        #expect(Transports.isRsyncCommand("/opt/homebrew/bin/rsync -a -s --partial --info=progress2 a b"))
        #expect(Transports.isRsyncCommand("'/Volumes/My Tools/bin/rsync' -a a b"))
        #expect(!Transports.isRsyncCommand("rsyncd --daemon"))
        #expect(!Transports.isRsyncCommand("myrsync -a a b"))
        #expect(!Transports.isRsyncCommand("/usr/local/bin/myrsync -a a b"))
        #expect(!Transports.isRsyncCommand("tar -cf - a | ssh k 'tar -xf -'"))
        #expect(!Transports.isRsyncCommand("'unterminated -a a b"))
        #expect(!Transports.isRsyncCommand(""))
    }
}
