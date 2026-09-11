// The rsync capability boundary for progressive moves.

import Foundation
import Testing

@testable import PalanaCore

@Suite("rsync move release")
struct RsyncMoveReleaseTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")
    private let sameHostDestination = Locus(host: "jodo", directory: "/tank/other")
    private let crossHostDestination = Locus(host: "koan", directory: "/rpool/cold")

    private static let modern = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")

    private func entry(_ name: String = "a.txt") -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: .file,
            size: 100,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    private func plan(to destination: Locus, facts: PlanFacts) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: .move,
                source: source,
                entries: [entry()],
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    @Test("GNU rsync 3 and openrsync support progressive removal")
    func supportedFamilies() throws {
        let openrsync = HostCapability(
            kernel: "Darwin",
            flavor: .bsd,
            zfs: nil,
            rsync: "openrsync: protocol version 29")
        for capability in [Self.modern, openrsync] {
            let result = try plan(
                to: sameHostDestination,
                facts: PlanFacts(sourceCapability: capability))
            #expect(result.steps[0].command.contains("--remove-source-files"))
        }
    }

    @Test("an old or unrecognized rsync refuses source removal")
    func unsupportedFamiliesRefuse() {
        let unsupported = [
            HostCapability(
                kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 2.6.9"),
            HostCapability(
                kernel: "Unknown", flavor: .bsd, zfs: nil, rsync: "mystery sync tool"),
        ]
        for capability in unsupported {
            #expect(throws: PlanError.moveReleaseUnavailable) {
                try plan(
                    to: sameHostDestination,
                    facts: PlanFacts(sourceCapability: capability))
            }
        }
    }

    @Test("a direct pull requires supported rsync at both ends")
    func directPullNeedsBothEnds() throws {
        let local = HostCapability(
            kernel: "Darwin",
            flavor: .bsd,
            zfs: nil,
            rsync: "openrsync: protocol version 29")
        let request = PlanRequest(
            operation: .move,
            source: source,
            entries: [entry()],
            destination: Locus(host: PalanaCore.localHostName, directory: "/Users/op/files"),
            token: "t1")
        let result = try PlanEngine.plan(
            request,
            facts: PlanFacts(sourceCapability: Self.modern, destinationCapability: local))
        #expect(result.transport == .rsyncDirect)
        #expect(result.steps[0].command.contains("--remove-source-files"))

        #expect(throws: PlanError.moveReleaseUnavailable) {
            try PlanEngine.plan(
                request,
                facts: PlanFacts(sourceCapability: Self.modern))
        }
    }

    @Test("copy plans never advertise progressive move semantics")
    func copyIsNotProgressiveMove() throws {
        let plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: source,
                entries: [entry()],
                destination: crossHostDestination,
                token: "t1"),
            facts: PlanFacts(
                sourceCapability: Self.modern,
                destinationCapability: Self.modern,
                agentForwarding: .available))
        #expect(!plan.usesProgressiveRsyncMove)
        #expect(!plan.steps[0].command.contains("--remove-source-files"))
    }

    @Test("operator flags cannot turn a copy into a source-removing operation")
    func copyRejectsSourceRemovalFlags() {
        let facts = PlanFacts(
            sourceCapability: Self.modern,
            destinationCapability: Self.modern,
            agentForwarding: .available,
            rsyncOperatorFlags: "--remove-source-files")
        #expect(throws: PlanError.rsyncFlagsControlSourceRemoval) {
            try PlanEngine.plan(
                PlanRequest(
                    operation: .copy,
                    source: source,
                    entries: [entry()],
                    destination: crossHostDestination,
                    token: "t1"),
                facts: facts)
        }
    }

    @Test("operator flags cannot disable or replace move source removal")
    func moveRejectsSourceRemovalFlags() {
        for flag in ["--no-remove-source-files", "--remove-sent", "--remove-source"] {
            var facts = PlanFacts(
                sourceCapability: Self.modern,
                destinationCapability: Self.modern,
                agentForwarding: .available)
            facts.rsyncOperatorFlags = flag
            #expect(throws: PlanError.rsyncFlagsControlSourceRemoval) {
                try plan(to: crossHostDestination, facts: facts)
            }
        }
    }

    @Test("move-owned checksum follows operator flags that could disable it")
    func moveChecksumCannotBeDisabled() throws {
        let facts = PlanFacts(
            sourceCapability: Self.modern,
            destinationCapability: Self.modern,
            agentForwarding: .available,
            rsyncOperatorFlags: "--no-checksum")
        let result = try plan(to: crossHostDestination, facts: facts)
        let command = result.steps[0].command
        let operatorOption = try #require(command.range(of: "--no-checksum"))
        let ownedOption = try #require(command.range(of: "--checksum --remove-source-files"))
        #expect(operatorOption.upperBound < ownedOption.lowerBound)
    }
}
