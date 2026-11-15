// The pre-1.0 review's remaining findings, one suite each: what a move
// keeps, what a failed move reports, how a send-back commits where hard
// links are missing, how long reports keep their notes, and what a
// failed send-back says about its staging directory.

import Foundation
import Testing

@testable import PalanaCore

/// One plain file — every request in these suites carries it.
func remainderEntry(_ name: String = "a.txt") -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .file,
        size: 1,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

// MARK: - Finding 4: metadata on moves

@Suite("Review finding 4 — what a move keeps")
struct MoveMetadataTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")
    private let sameHost = Locus(host: "jodo", directory: "/tank/other")
    private let crossHost = Locus(host: "koan", directory: "/rpool/cold")

    /// rsync 3.5.2's list, folded the way the probe folds it.
    static let caps352 =
        "rsync  version 3.5.2  protocol version 33 Copyright (C) 1996-2026 by Andrew Tridgell"
        + " Capabilities:     64-bit files, 64-bit inums, hardlinks, append, ACLs,     ACL-at,"
        + " xattrs, optional secluded-args, iconv, prealloc, stop-at,     no crtimes, IDN"
        + " Optimizations:     no SIMD-roll"

    // swiftlint:disable discouraged_optional_boolean
    // Mirrors HostCapability's three states: nil is an unprobed end.
    static func capability(
        kernel: String,
        xattrs: Bool? = true,
        acls: Bool? = true,
        rsync: String = "rsync  version 3.4.1  protocol version 32"
    ) -> HostCapability {
        HostCapability(
            kernel: kernel,
            flavor: kernel == "Darwin" ? .bsd : .gnu,
            zfs: nil,
            rsync: rsync,
            rsyncXattrs: xattrs,
            rsyncACLs: acls)
    }
    // swiftlint:enable discouraged_optional_boolean

    static let linux = capability(kernel: "Linux")
    static let darwin = capability(kernel: "Darwin")
    static let openrsync = capability(
        kernel: "Darwin", xattrs: false, acls: false, rsync: "openrsync: protocol version 29")

    private func plan(
        _ operation: PlanOperation = .move, to destination: Locus, facts: PlanFacts
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: source,
                entries: [remainderEntry()],
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    private func crossFacts(_ from: HostCapability?, _ to: HostCapability?) -> PlanFacts {
        PlanFacts(sourceCapability: from, destinationCapability: to, agentForwarding: .available)
    }

    // The probe

    @Test("the probe reads xattrs and ACLs from rsync's list; ACL-at is not ACLs")
    func probeReadsList() throws {
        let capability = try CapabilityProbe.parse(
            """
            palana:kernel:Linux
            palana:flavor:GNU
            palana:zfs:
            palana:rsync:rsync  version 3.5.2  protocol version 33
            palana:rsynccaps:\(Self.caps352)
            """)
        #expect(capability.rsyncXattrs == true)
        #expect(capability.rsyncACLs == true)
        #expect(CapabilityProbe.rsyncListed("ACLs", rsync: "r", caps: "append, ACL-at, xattrs") == false)
    }

    @Test("'no xattrs' and 'no ACLs' read false; openrsync's empty list reads false")
    func probeReadsAbsence() {
        let caps = "Capabilities: symlinks, no ACLs, no xattrs, iconv"
        #expect(CapabilityProbe.rsyncListed("xattrs", rsync: "r", caps: caps) == false)
        #expect(CapabilityProbe.rsyncListed("ACLs", rsync: "r", caps: caps) == false)
        #expect(CapabilityProbe.rsyncListed("xattrs", rsync: "openrsync", caps: "") == false)
    }

    @Test("an absent rsync, or output recorded before the list marker, reads nil")
    func probeUnknownIsNil() throws {
        #expect(CapabilityProbe.rsyncListed("xattrs", rsync: nil, caps: "xattrs") == nil)
        let old = try CapabilityProbe.parse(
            "palana:kernel:Linux\npalana:flavor:GNU\npalana:rsync:rsync  version 3.2.7")
        #expect(old.rsyncXattrs == nil)
        #expect(old.rsyncACLs == nil)
    }

    @Test("a capability cached before the fields existed still decodes, as unproven")
    func oldCacheDecodes() throws {
        let json = #"{"kernel":"Linux","flavor":"GNU","rsync":"rsync  version 3.2.7"}"#
        let capability = try JSONDecoder().decode(HostCapability.self, from: Data(json.utf8))
        #expect(capability.rsyncXattrs == nil)
        #expect(capability.rsyncACLs == nil)
    }

    @Test("the recorded container probe carries xattrs and ACLs")
    func recordedProbe() throws {
        let transcript = try ConduitTranscript(
            contentsOf: SSHFixture.repoRoot.appendingPathComponent(
                "Tests/PalanaCoreTests/Fixtures/probe-container.json"))
        let entry = try #require(transcript.entries.first { $0.command == CapabilityProbe.command })
        let capability = try CapabilityProbe.parse(entry.stdout)
        #expect(capability.rsyncXattrs == true)
        #expect(capability.rsyncACLs == true)
    }

    // The plan

    @Test("both ends Linux and capable: the move asks for -X and -A, and warns of nothing")
    func capableSameKernel() throws {
        let result = try plan(to: crossHost, facts: crossFacts(Self.linux, Self.linux))
        #expect(result.steps[0].command.contains(" -X -A --checksum --remove-source-files"))
        #expect(result.metadataNotice == nil)
        try Transports.validateProgressiveMovePlan(result)
    }

    @Test("Darwin to Linux: -X but no -A, and the notice says ACLs do not carry")
    func crossKernelDropsACLs() throws {
        let result = try plan(to: crossHost, facts: crossFacts(Self.darwin, Self.linux))
        let command = result.steps[0].command
        #expect(command.contains(" -X --checksum"))
        #expect(!command.contains(" -A "))
        #expect(
            result.metadataNotice
                == "this move does not keep ACLs — they do not carry between Darwin and Linux")
    }

    @Test("Apple's openrsync: no -X or -A, and the notice names all three")
    func openrsyncEnd() throws {
        let result = try plan(to: sameHost, facts: PlanFacts(sourceCapability: Self.openrsync))
        let command = try #require(result.steps.first { $0.role == .copy }).command
        #expect(!command.contains(" -X"))
        #expect(!command.contains(" -A"))
        #expect(
            result.metadataNotice
                == "this move does not keep extended attributes, Finder tags and ACLs"
                + " — an rsync at one end cannot carry them")
        try Transports.validateProgressiveMovePlan(result)
    }

    @Test("unproven ends — a cache from before the probe read the list — ask for nothing")
    func unprovenEnds() throws {
        let unknown = Self.capability(kernel: "Linux", xattrs: nil, acls: nil)
        let result = try plan(to: crossHost, facts: crossFacts(unknown, Self.linux))
        #expect(!result.steps[0].command.contains(" -X"))
        #expect(result.metadataNotice?.hasPrefix("this move does not keep extended attributes") == true)
    }

    @Test("xattrs at both ends but ACLs at one: -X only, ACLs named")
    func aclsAtOneEnd() throws {
        let noACLs = Self.capability(kernel: "Linux", acls: false)
        let result = try plan(to: crossHost, facts: crossFacts(Self.linux, noACLs))
        #expect(result.steps[0].command.contains(" -X --checksum"))
        #expect(result.metadataNotice == "this move does not keep ACLs — an rsync at one end cannot carry them")
    }

    @Test("ACLs at both ends across kernels, xattrs at one: both clauses, each with its reason")
    func bothClauses() throws {
        let noXattrs = Self.capability(kernel: "Linux", xattrs: false)
        let result = try plan(to: crossHost, facts: crossFacts(Self.darwin, noXattrs))
        #expect(
            result.metadataNotice
                == "this move does not keep extended attributes and Finder tags"
                + " — an rsync at one end cannot carry them"
                + " · ACLs — they do not carry between Darwin and Linux")
    }

    @Test("a same-host move runs one rsync, which is both ends")
    func sameHostOneRsync() throws {
        let result = try plan(to: sameHost, facts: PlanFacts(sourceCapability: Self.darwin))
        let transfer = try #require(result.steps.first { $0.role == .copy })
        #expect(transfer.command.contains(" -X -A --checksum"))
        #expect(result.metadataNotice == nil)
        try Transports.validateProgressiveMovePlan(result)
    }

    @Test("a direct push from this machine reads both ends")
    func directPush() throws {
        let request = PlanRequest(
            operation: .move,
            source: Locus(host: PalanaCore.localHostName, directory: "/Users/op"),
            entries: [remainderEntry()],
            destination: crossHost,
            token: "t1")
        let facts = PlanFacts(sourceCapability: Self.darwin, destinationCapability: Self.openrsync)
        let result = try PlanEngine.plan(request, facts: facts)
        #expect(result.transport == .rsyncDirect)
        #expect(!result.steps[0].command.contains(" -X"))
        #expect(result.metadataNotice != nil)
    }

    @Test("copies are unchanged: no -X, no notice")
    func copiesUnchanged() throws {
        let result = try plan(.copy, to: crossHost, facts: crossFacts(Self.linux, Self.linux))
        #expect(!result.steps[0].command.contains(" -X"))
        #expect(!result.steps[0].command.contains(" -A"))
        #expect(result.metadataNotice == nil)
    }
}

// MARK: - Finding 7: accounting after a failed move

@Suite("Review finding 7 — what a failed move reports")
struct FailedMoveAccountingTests {
    private static let modern = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.4.1  protocol version 32")

    /// Two files and a directory from jodo to koan, forwarded: transfer,
    /// sweep, report.
    private static func crossHostMove() throws -> Plan {
        var photos = remainderEntry("photos")
        photos.kind = .directory
        return try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "jodo", directory: "/tank/media"),
                entries: [remainderEntry("a.txt"), remainderEntry("b.txt"), photos],
                destination: Locus(host: "koan", directory: "/rpool/cold"),
                token: "t1"),
            facts: PlanFacts(
                sourceCapability: modern, destinationCapability: modern, agentForwarding: .available))
    }

    private static func notes(_ events: [EnactmentEvent]) -> [RecoveryNote] {
        events.compactMap { event in
            if case .recovery(let note) = event { return note }
            return nil
        }
    }

    @Test("a transfer that exits 23 partway still reports what remains, and the run still fails")
    func exit23Reports() async throws {
        let plan = try Self.crossHostMove()
        #expect(plan.steps.map(\.role) == [.transfer, .cleanup, .verify])
        let remains = "palana-retained: jodo:/tank/media/b.txt — source entry remains after the progressive move"
        let conduit = RecordedConduit(
            transcript: ConduitTranscript(entries: [
                .init(
                    host: "jodo",
                    command: plan.steps[0].command,
                    stdout: "",
                    stderr: "rsync: [sender] send_files failed to open \"/tank/media/b.txt\": "
                        + "Permission denied (13)\nrsync error: some files/attrs were not transferred"
                        + " (code 23) at main.c(1338) [sender=3.4.1]\n",
                    exit: 23),
                .init(host: "jodo", command: plan.steps[2].command, stdout: "", stderr: remains + "\n", exit: 1),
            ]))
        let sink = EventSink()
        await #expect {
            try await Transports(conduit: conduit) { _, _, _ in -1 }.run(plan) { sink.record($0) }
        } throws: { error in
            guard case EnactmentError.stepFailed(let index, let status, _) = error else { return false }
            return index == 0 && status == 23
        }
        let events = sink.events
        #expect(events.contains(.stepBegan(index: 2, step: plan.steps[2])))
        #expect(events.contains(.stepEnded(index: 2, exitStatus: 1)))
        #expect(!events.contains(.stepBegan(index: 1, step: plan.steps[1])), "the sweep never runs")
        #expect(
            Self.notes(events)
                == [
                    RecoveryNote(
                        kind: .retained,
                        host: "jodo",
                        detail: "jodo:/tank/media/b.txt — source entry remains after the progressive move")
                ])
        #expect(!events.contains(.finished))
    }

    @Test("a failed place guard moved nothing, so no report runs")
    func placeGuardFailureReportsNothing() async throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: "jodo", directory: "/tank/media"),
                entries: [remainderEntry()],
                destination: Locus(host: "jodo", directory: "/tank/other"),
                token: "t1"),
            facts: PlanFacts(sourceCapability: Self.modern))
        let report = try #require(plan.steps.last)
        let conduit = RecordedConduit(
            transcript: ConduitTranscript(entries: [
                .init(host: "jodo", command: plan.steps[0].command, stdout: "", stderr: "refused\n", exit: 3),
                .init(
                    host: "jodo",
                    command: report.command,
                    stdout: "",
                    stderr: "palana-retained: jodo:/tank/media/a.txt — x\n",
                    exit: 1),
            ]))
        let sink = EventSink()
        await #expect(throws: EnactmentError.self) {
            try await Transports(conduit: conduit) { _, _, _ in -1 }.run(plan) { sink.record($0) }
        }
        #expect(Self.notes(sink.events).isEmpty)
    }

    @Test("a cancelled transfer still reports what remains, then surfaces the cancellation")
    func cancelledTransferReports() async throws {
        let directory = try ProcessFixture.makeDirectory()
        let sourceDirectory = directory.appendingPathComponent("src")
        let destinationDirectory = directory.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sourceDirectory.appendingPathComponent("a.txt"))
        let pidFile = directory.appendingPathComponent("pid")
        let openrsync = HostCapability(
            kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "openrsync: protocol version 29")
        var plan = try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: Locus(host: PalanaCore.localHostName, directory: sourceDirectory.path),
                entries: [remainderEntry()],
                destination: Locus(host: PalanaCore.localHostName, directory: destinationDirectory.path),
                token: "t1"),
            facts: PlanFacts(sourceCapability: openrsync))
        // The transfer waits before rsync starts, so cancelling it leaves
        // the source whole: what the report must then name.
        let transfer = try #require(plan.steps.firstIndex { $0.role == .copy })
        plan.steps[transfer].command =
            "\(ProcessFixture.recordPid(at: pidFile)); sleep 30; " + plan.steps[transfer].command
        let sink = EventSink()
        let task = Task {
            try await Transports(conduit: LocalConduit()).run(plan) { sink.record($0) }
        }
        _ = try #require(await ProcessFixture.awaitPid(at: pidFile))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let notes = Self.notes(sink.events)
        #expect(notes.count == 1)
        #expect(notes.first?.detail.contains("/src/a.txt — source entry remains") == true)
    }
}

// MARK: - Finding 11: notes from long reports

@Suite("Review finding 11 — notes from long reports")
struct LongReportNotesTests {
    private static func note(_ index: Int) -> String {
        let path = "/tank/media/" + String(repeating: "deeply-nested-directory/", count: 5) + "file-\(index).bin"
        return "palana-retained: jodo:\(path) — source entry remains after the progressive move"
    }

    @Test("sixty long-path notes, about 10 KB of report, all reach the run")
    func sixtyNotes() async throws {
        let stderr = (0..<60).map { Self.note($0) + "\n" }.joined()
        #expect(stderr.utf8.count > 4096 * 2)
        let step = PlanStep(runsOn: .host("jodo"), command: "report", role: .verify)
        let plan = Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: Locus(host: "jodo", directory: "/tank/media"),
            destination: Locus(host: "jodo", directory: "/tank/other"),
            transport: .local,
            steps: [step])
        let conduit = RecordedConduit(
            transcript: ConduitTranscript(entries: [
                .init(host: "jodo", command: "report", stdout: "", stderr: stderr, exit: 1)
            ]))
        let sink = EventSink()
        await #expect {
            try await Transports(conduit: conduit) { _, _, _ in -1 }.run(plan) { sink.record($0) }
        } throws: { error in
            guard case EnactmentError.stepFailed(_, _, let tail) = error else { return false }
            return !tail.isEmpty
        }
        let notes = sink.events.compactMap { event -> RecoveryNote? in
            if case .recovery(let note) = event { return note }
            return nil
        }
        #expect(notes.count == 60)
        #expect(notes.first?.detail.contains("file-0.bin — source entry remains") == true)
        #expect(notes.last?.detail.contains("file-59.bin — source entry remains") == true)
    }

    @Test("an em dash split across two chunks still reads whole")
    func splitCharacter() {
        let bytes = Data((Self.note(1) + "\n").utf8)
        let dash = bytes.firstRange(of: Data("—".utf8))?.lowerBound ?? bytes.startIndex
        var scanner = RecoveryNoteScanner(host: "jodo")
        scanner.consume(bytes[..<(dash + 1)])
        scanner.consume(bytes[(dash + 1)...])
        scanner.finish()
        #expect(scanner.notes.count == 1)
        #expect(scanner.notes.first?.detail.contains("file-1.bin — source") == true)
    }

    @Test("an undecodable byte costs at most its own line")
    func badByte() {
        var scanner = RecoveryNoteScanner(host: "jodo")
        scanner.consume(Data("palana-retained: jodo:/a\u{2014}x\n".utf8))
        scanner.consume(Data([0x70, 0xFF, 0x0A]))
        var invalidNote = Data("palana-retained: jodo:/b".utf8)
        invalidNote.append(0xC3)
        invalidNote.append(contentsOf: Array(" — kept\n".utf8))
        scanner.consume(invalidNote)
        scanner.finish()
        #expect(scanner.notes.map(\.detail).count == 2)
        #expect(scanner.notes.last?.detail.hasPrefix("jodo:/b") == true)
    }

    @Test("an endless line is dropped, not held; the notes around it stand")
    func overlongLine() {
        var scanner = RecoveryNoteScanner(host: "jodo")
        scanner.consume(Data((Self.note(1) + "\n").utf8))
        scanner.consume(Data(repeating: 0x41, count: RecoveryNoteScanner.lineLimit + 1))
        scanner.consume(Data("palana-retained: jodo:/never — part of the long line\n".utf8))
        scanner.consume(Data((Self.note(2) + "\n").utf8))
        scanner.finish()
        #expect(scanner.notes.count == 2)
        #expect(!scanner.notes.contains { $0.detail.contains("/never") })
    }

    @Test("an unterminated last line still counts")
    func unterminated() {
        var scanner = RecoveryNoteScanner(host: "jodo")
        scanner.consume(Data(Self.note(3).utf8))
        scanner.finish()
        #expect(scanner.notes.count == 1)
    }
}
