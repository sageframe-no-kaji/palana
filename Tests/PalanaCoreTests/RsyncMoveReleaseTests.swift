// Which rsync may carry a move's deletion, and which may not.
//
// A move that copies has to delete, and it deletes through
// `--remove-source-files` — so the binary doing the removing has to
// belong to a family whose refusal to remove a changed source has been
// proved live in RsyncSourceRemovalTests. openrsync qualifies by name
// and carries no dotted version; GNU rsync qualifies from 3.0. Anything
// older, and anything that is neither, has no release and the move is
// refused rather than composed over an untested promise.

import Foundation
import Testing

@testable import PalanaCore

@Suite("rsync move release")
struct RsyncMoveReleaseTests {
    private let source = Locus(host: "jodo", directory: "/tank/media")
    private let sameHostDest = Locus(host: "jodo", directory: "/tank/other")
    private let crossHostDest = Locus(host: "koan", directory: "/rpool/cold")

    private static let rsyncHost = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")

    private func entry(_ name: String) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: .file,
            size: 100,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    private func plan(_ operation: PlanOperation, to destination: Locus, facts: PlanFacts) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: source,
                entries: [entry("a.txt")],
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    @Test("an rsync too old to have been proved refuses the move")
    func unprovenRsyncRefuses() {
        let ancient = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 2.6.9")
        let facts = PlanFacts(
            sourceCapability: ancient,
            destinationCapability: Self.rsyncHost,
            agentForwarding: .available)
        #expect(throws: PlanError.moveReleaseUnavailable) {
            try plan(.move, to: crossHostDest, facts: facts)
        }
    }

    @Test("openrsync is a proved family even with no dotted version")
    func openrsyncComposesTheMove() throws {
        let openrsync = HostCapability(
            kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "openrsync: protocol version 29")
        let facts = PlanFacts(sourceCapability: openrsync)
        let plan = try plan(.move, to: sameHostDest, facts: facts)
        #expect(plan.steps[0].command.contains("--remove-source-files"))
        #expect(!plan.steps[0].command.contains("-s "), "openrsync refuses -s")
    }

    @Test("a same-host move refuses when the host has no rsync — cp -a cannot release")
    func sameHostMoveWithoutRsyncRefuses() {
        #expect(throws: PlanError.moveReleaseUnavailable) {
            try plan(.move, to: sameHostDest, facts: PlanFacts())
        }
    }
}
