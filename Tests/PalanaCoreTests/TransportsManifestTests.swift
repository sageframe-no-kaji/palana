// The gate under adversarial evidence. Every case here passed the old
// count gate — two objects each end, or a masked find answering 0 —
// and every one must now keep the delete closed. The transcript is the
// network: no rm entry exists, so a leak surfaces as UnrecordedCommand
// rather than hiding behind a passing test.

import Foundation
import Testing

@testable import PalanaCore

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

@Suite("Transports manifest gate")
struct TransportsManifestTests {
    private static let entries = [makeEntry("f1", size: 5), makeEntry("f2", size: 5)]
    private static let sourceCommand = ManifestFixture.command("/tank/a", ["f1", "f2"])
    private static let destinationCommand = ManifestFixture.command("/tank/b", ["f1", "f2"])
    private static let copy = ConduitTranscript.Entry(
        host: "j", command: "cp -a /tank/a/f1 /tank/a/f2 /tank/b/", stdout: "", stderr: "", exit: 0)

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

    private static func entry(
        _ host: String, _ command: String, stdout: String = "", stderr: String = "", exit: Int32 = 0
    ) -> ConduitTranscript.Entry {
        ConduitTranscript.Entry(host: host, command: command, stdout: stdout, stderr: stderr, exit: exit)
    }

    /// Enacts over the transcript and returns the thrown error, nil on success.
    private static func enact(
        _ plan: Plan, over transcriptEntries: [ConduitTranscript.Entry]
    ) async -> (error: (any Error)?, events: [EnactmentEvent]) {
        let transports = Transports(
            conduit: RecordedConduit(transcript: ConduitTranscript(entries: transcriptEntries))
        ) { _, _, _ in 0 }
        var events: [EnactmentEvent] = []
        do {
            for try await event in transports.enact(plan) {
                events.append(event)
            }
            return (nil, events)
        } catch {
            return (error, events)
        }
    }

    private static func isVerificationFailed(_ error: (any Error)?) -> Bool {
        if case EnactmentError.verificationFailed(let report)? = error { return !report.matched }
        return false
    }

    private static func unavailableDetail(_ error: (any Error)?) -> String? {
        if case EnactmentError.verificationUnavailable(_, let detail)? = error { return detail }
        return nil
    }

    @Test("equal counts, changed bytes — same sizes, one digest differs — never release the delete")
    func equalCountsDifferentBytes() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.file("f2")
        let landed = ManifestFixture.file("f1") + ManifestFixture.file("f2", digest: ManifestFixture.worldDigest)
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stdout: landed),
            ])
        #expect(Self.isVerificationFailed(outcome.error))
        #expect(!outcome.events.contains(.stepBegan(index: 1, step: plan.steps[1])))
    }

    @Test("equal counts, a size change under the same digest length — refused")
    func equalCountsDifferentSize() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1", size: 5) + ManifestFixture.file("f2", size: 5)
        let landed = ManifestFixture.file("f1", size: 5) + ManifestFixture.file("f2", size: 4)
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stdout: landed),
            ])
        #expect(Self.isVerificationFailed(outcome.error))
    }

    @Test("equal counts, a type change — a file here, a directory there — refused")
    func typeChange() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.file("f2")
        let landed = ManifestFixture.file("f1") + ManifestFixture.directory("f2")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stdout: landed),
            ])
        #expect(Self.isVerificationFailed(outcome.error))
    }

    @Test("equal counts, a symlink whose target changed — refused")
    func symlinkTargetChanged() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.symlink("f2", target: "f1")
        let landed = ManifestFixture.file("f1") + ManifestFixture.symlink("f2", target: "/etc/passwd")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stdout: landed),
            ])
        #expect(Self.isVerificationFailed(outcome.error))
    }

    @Test("a masked find — status 0, a selected name absent from the manifest — is unavailable, not a match")
    func maskedFindIsUnavailable() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.file("f2")
        // The old gate read `find … | wc -l` as 0 with status 0 when
        // find failed. A manifest that omits f2 is the same shape.
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stdout: ManifestFixture.file("f1")),
            ])
        let detail = try #require(Self.unavailableDetail(outcome.error))
        #expect(detail.contains("omitted f2"))
        #expect(
            !outcome.events.contains {
                guard case .verified = $0 else { return false }
                return true
            })
    }

    @Test("an empty manifest with status 0 on both ends is unavailable — two nothings agree about nothing")
    func emptyManifestsAreUnavailable() async throws {
        let plan = try Self.crossDatasetMove()
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: ""),
                Self.entry("j", Self.destinationCommand, stdout: ""),
            ])
        #expect(Self.unavailableDetail(outcome.error)?.contains("omitted f1, f2") == true)
    }

    @Test("a missing path fails the manifest command — unavailable, with the command's own reason")
    func missingPathIsUnavailable() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.file("f2")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stderr: "missing: ./f2\n", exit: 3),
            ])
        let detail = try #require(Self.unavailableDetail(outcome.error))
        #expect(detail == "manifest exited 3: missing: ./f2")
    }

    @Test("an unreadable file fails the manifest command — unavailable")
    func unreadableIsUnavailable() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.file("f2")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry(
                    "j",
                    Self.destinationCommand,
                    stdout: ManifestFixture.file("f1"),
                    stderr: "unreadable: f2\n",
                    exit: 3),
            ])
        #expect(Self.unavailableDetail(outcome.error) == "manifest exited 3: unreadable: f2")
    }

    @Test("no SHA-256 tool on the source — unavailable, and the destination is never asked")
    func noDigestToolIsUnavailable() async throws {
        let plan = try Self.crossDatasetMove()
        // No destination entry: asking would surface UnrecordedCommand,
        // so the typed error proves the source's failure stopped the check.
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry(
                    "j",
                    Self.sourceCommand,
                    stderr: "no sha256 tool (tried sha256sum, shasum, openssl)\n",
                    exit: 3),
            ])
        let detail = try #require(Self.unavailableDetail(outcome.error))
        #expect(detail.hasSuffix("no sha256 tool (tried sha256sum, shasum, openssl)"))
    }

    @Test("bytes that are not a manifest are unavailable, never a match")
    func malformedManifestIsUnavailable() async throws {
        let plan = try Self.crossDatasetMove()
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: "2\n"),
                Self.entry("j", Self.destinationCommand, stdout: "2\n"),
            ])
        #expect(Self.unavailableDetail(outcome.error)?.hasPrefix("manifest unreadable") == true)
    }

    @Test("pre-existing destination entries under a moved directory break exact agreement")
    func preExistingDestinationEntries() async throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "j", directory: "/tank/a"),
                entries: [makeEntry("dir")],
                destination: Locus(host: "j", directory: "/tank/b"),
                token: "t1"),
            facts: PlanFacts())
        let source = ManifestFixture.directory("dir") + ManifestFixture.file("dir/x")
        let landed = source + ManifestFixture.file("dir/old")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.entry("j", "cp -a /tank/a/dir /tank/b/"),
                Self.entry("j", ManifestFixture.command("/tank/a", ["dir"]), stdout: source),
                Self.entry("j", ManifestFixture.command("/tank/b", ["dir"]), stdout: landed),
            ])
        #expect(Self.isVerificationFailed(outcome.error))
        if case EnactmentError.verificationFailed(.manifests(let src, let dst))? = outcome.error {
            #expect(src.firstDifference(from: dst) == "dir/old")
        }
    }

    @Test("walk order does not matter — the same tree in two orders is one manifest")
    func walkOrderIrrelevant() async throws {
        let plan = try Self.crossDatasetMove()
        let source = ManifestFixture.file("f1") + ManifestFixture.file("f2")
        let landed = ManifestFixture.file("f2") + ManifestFixture.file("f1")
        let outcome = await Self.enact(
            plan,
            over: [
                Self.copy,
                Self.entry("j", Self.sourceCommand, stdout: source),
                Self.entry("j", Self.destinationCommand, stdout: landed),
                Self.entry("j", "rm -rf /tank/a/f1 /tank/a/f2"),
            ])
        #expect(outcome.error == nil)
        #expect(outcome.events.last == .finished)
    }

    /// One move per file transport, each ending in a gated delete.
    private static func movePlans() throws -> [(plan: Plan, label: String)] {
        let rsync = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")
        let localRsync = HostCapability(kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "rsync  version 3.4.1")
        let remote = Locus(host: "k", directory: "/rpool/b")
        func move(from source: Locus, facts: PlanFacts) throws -> Plan {
            try PlanEngine.plan(
                PlanRequest(
                    operation: .move,
                    source: source,
                    entries: entries,
                    destination: remote,
                    token: "t1"),
                facts: facts)
        }
        let jodo = Locus(host: "j", directory: "/tank/a")
        let here = Locus(host: "local", directory: "/Users/op/a")
        return try [
            (
                move(
                    from: jodo,
                    facts: PlanFacts(
                        sourceCapability: rsync,
                        destinationCapability: rsync,
                        agentForwarding: .available)),
                "rsync forwarded"
            ),
            (move(from: jodo, facts: PlanFacts()), "tar proxied"),
            (
                move(from: here, facts: PlanFacts(sourceCapability: localRsync, destinationCapability: rsync)),
                "rsync direct"
            ),
        ]
    }

    @Test("the gate is the same across transports — rsync-forwarded, tar-proxied, rsync-direct")
    func sameGateEveryTransport() async throws {
        for (plan, label) in try Self.movePlans() {
            let sourceHost = plan.source.host
            let sourceCommand = ManifestFixture.command(plan.source.directory, ["f1", "f2"])
            let destinationCommand = ManifestFixture.command("/rpool/b", ["f1", "f2"])
            let transfer = plan.steps[0]
            let hostSteps: [ConduitTranscript.Entry] =
                transfer.runsOn == .operatorMachine
                ? [] : [Self.entry(sourceHost, transfer.command)]
            // Bytes differ at f2 — every transport must keep its delete closed.
            let outcome = await Self.enact(
                plan,
                over: hostSteps + [
                    Self.entry(
                        sourceHost,
                        sourceCommand,
                        stdout: ManifestFixture.file("f1") + ManifestFixture.file("f2")),
                    Self.entry(
                        "k",
                        destinationCommand,
                        stdout: ManifestFixture.file("f1")
                            + ManifestFixture.file("f2", digest: ManifestFixture.worldDigest)),
                ])
            #expect(Self.isVerificationFailed(outcome.error), "\(label): the delete stayed closed")
            #expect(plan.steps.last?.role == .delete, "\(label): the plan ends in the gated delete")
        }
    }
}
