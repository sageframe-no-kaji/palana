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
