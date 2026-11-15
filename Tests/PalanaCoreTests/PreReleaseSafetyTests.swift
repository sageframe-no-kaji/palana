// Pre-1.0 review (2026-11-15) — each test fails against the code the review
// read. Findings 1 and 10 (a move into its own folder or its own subfolder),
// 2 and 5 (operator rsync flags), 6 (paths that merely contain
// "remove-sent"), and 9 (reordering mixed-host Global favorites).

import Foundation
import Testing

@testable import PalanaCore

@Suite("pre-1.0 safety — place, flags, and enactment")
struct PreReleaseSafetyTests {
    private static let rsync = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.4.1")

    private func entry(_ name: String, kind: FileEntry.Kind = .directory) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: 10,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "755",
            owner: "op",
            group: "op")
    }

    private func request(
        _ operation: PlanOperation,
        from source: String,
        to destination: String,
        entries: [FileEntry],
        host: String = "jodo",
        destinationHost: String? = nil
    ) -> PlanRequest {
        PlanRequest(
            operation: operation,
            source: Locus(host: host, directory: source),
            entries: entries,
            destination: Locus(host: destinationHost ?? host, directory: destination),
            token: "t1")
    }

    private func facts(flags: String? = nil) -> PlanFacts {
        var facts = PlanFacts(
            sourceMountTarget: "/tank",
            destinationMountTarget: "/srv",
            sourceCapability: Self.rsync,
            destinationCapability: Self.rsync,
            agentForwarding: .available)
        facts.rsyncOperatorFlags = flags
        return facts
    }

    // MARK: - Finding 1: the destination is the source folder

    @Test(
        "a move or copy into the folder it already sits in is refused",
        arguments: [PlanOperation.move, .copy], ["/tank/media", "/tank/media/"])
    func samePlaceRefused(operation: PlanOperation, destination: String) {
        #expect(throws: PlanError.sourceIsDestination) {
            try PlanEngine.plan(
                request(operation, from: "/tank/media", to: destination, entries: [entry("a")]),
                facts: facts())
        }
    }

    @Test("the same path on another host is a real transfer, not the same place")
    func samePathOtherHostAllowed() throws {
        let plan = try PlanEngine.plan(
            request(
                .move,
                from: "/tank/media",
                to: "/tank/media",
                entries: [entry("a")],
                destinationHost: "koan"),
            facts: facts())
        #expect(plan.classification == .crossHostTransfer)
    }

    // MARK: - Finding 10: the destination is inside the selection

    @Test(
        "a destination inside a selected folder is refused",
        arguments: ["/d/a", "/d/a/sub", "/d/a/sub/deeper"])
    func insideSelectionRefused(destination: String) {
        #expect(throws: PlanError.destinationInsideSelection) {
            try PlanEngine.plan(
                request(.move, from: "/d", to: destination, entries: [entry("a")]),
                facts: facts())
        }
    }

    @Test("a sibling that shares a name prefix is not inside the selection")
    func prefixSiblingAllowed() throws {
        _ = try PlanEngine.plan(
            request(.move, from: "/d", to: "/d/ab", entries: [entry("a")]),
            facts: facts())
    }

    // MARK: - Finding 1, host side: the guard sees through aliases

    /// Runs a composed guard locally in a scratch tree; returns the exit status.
    private func runGuard(source: URL, destination: URL, names: [String]) throws -> Int32 {
        let request = request(
            .move,
            from: source.path,
            to: destination.path,
            entries: names.map { entry($0) },
            host: PalanaCore.localHostName)
        let step = try #require(PlanEngine.placeGuardStep(request))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", step.command]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src/it's a/sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("dst"), withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    @Test("the guard lets an ordinary move through")
    func guardPassesOrdinaryMove() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let status = try runGuard(
            source: root.appendingPathComponent("src"),
            destination: root.appendingPathComponent("dst"),
            names: ["it's a"])
        #expect(status == 0)
    }

    @Test("the guard refuses the source folder reached through a symlink")
    func guardRefusesAliasedSamePlace() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(
            at: alias, withDestinationURL: root.appendingPathComponent("src"))
        let status = try runGuard(
            source: root.appendingPathComponent("src"), destination: alias, names: ["it's a"])
        #expect(status != 0)
    }

    @Test("the guard refuses a destination inside the selection reached through a symlink")
    func guardRefusesAliasedDescendant() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("deep")
        try FileManager.default.createSymbolicLink(
            at: alias, withDestinationURL: root.appendingPathComponent("src/it's a/sub"))
        let status = try runGuard(
            source: root.appendingPathComponent("src"), destination: alias, names: ["it's a"])
        #expect(status != 0)
    }

    @Test("only a same-host move carries the guard")
    func guardOnlySameHostMove() {
        let copy = request(.copy, from: "/a", to: "/b", entries: [entry("x")])
        let crossHost = request(.move, from: "/a", to: "/b", entries: [entry("x")], destinationHost: "koan")
        #expect(PlanEngine.placeGuardStep(copy) == nil)
        #expect(PlanEngine.placeGuardStep(crossHost) == nil)
    }

    // MARK: - Findings 2 and 5: operator flags

    @Test(
        "abbreviated and spelled-out source-removal options are refused",
        arguments: ["--rem", "--remo", "--remove-s", "--remove-sou", "--remove-sent=1", "-z --REMOVE-SOURCE-FILES"])
    func abbreviationsRefused(flags: String) {
        #expect(throws: PlanError.rsyncFlagsControlSourceRemoval) {
            try PlanEngine.validateRsyncOperatorFlags(flags)
        }
    }

    @Test(
        "quoting, escaping, and substitution in flags are refused",
        arguments: ["--remove-'source'-files", "--x=\"a\"", "--remove\\-sent", "$(echo --rem)", "`x`"])
    func quotingRefused(flags: String) {
        #expect(throws: PlanError.rsyncFlagsQuoted) {
            try PlanEngine.validateRsyncOperatorFlags(flags)
        }
    }

    @Test("ordinary flags pass and still ride a copy")
    func ordinaryFlagsRideCopies() throws {
        try PlanEngine.validateRsyncOperatorFlags("-z --bwlimit=5000 --info=stats2")
        let plan = try PlanEngine.plan(
            request(
                .copy,
                from: "/tank/media",
                to: "/rpool/cold",
                entries: [entry("a")],
                destinationHost: "koan"),
            facts: facts(flags: "--bwlimit=5000"))
        #expect(plan.steps[0].command.contains("--bwlimit=5000"))
    }

    // MARK: - Finding 6: paths are not options

    @Test("a copy whose path contains remove-sent is not mistaken for a move")
    func pathIsNotAnOption() throws {
        let plan = try PlanEngine.plan(
            request(
                .copy,
                from: "/tank/remove-source-later",
                to: "/rpool/cold",
                entries: [entry("Remove-Sent-Items.pst", kind: .file)],
                destinationHost: "koan"),
            facts: facts())
        try Transports.validateProgressiveMovePlan(plan)
    }

    @Test("a copy plan that was edited to carry --rem is refused at enactment")
    func editedCopyRefused() throws {
        var plan = try PlanEngine.plan(
            request(
                .copy,
                from: "/tank/media",
                to: "/rpool/cold",
                entries: [entry("a")],
                destinationHost: "koan"),
            facts: facts())
        plan.steps[0].command = plan.steps[0].command.replacingOccurrences(
            of: "rsync -a", with: "rsync --rem -a")
        #expect(throws: EnactmentError.self) {
            try Transports.validateProgressiveMovePlan(plan)
        }
    }

    @Test("a same-host move plan with its guard passes the enactment contract")
    func guardedMovePassesContract() throws {
        let plan = try PlanEngine.plan(
            request(.move, from: "/tank/media", to: "/srv/cold", entries: [entry("a")]),
            facts: facts())
        #expect(plan.steps.first?.command.contains("palana-refused") == true)
        try Transports.validateProgressiveMovePlan(plan)
    }

    @Test("a same-host move plan stripped of its guard fails the enactment contract")
    func unguardedMoveFailsContract() throws {
        var plan = try PlanEngine.plan(
            request(.move, from: "/tank/media", to: "/srv/cold", entries: [entry("a")]),
            facts: facts())
        plan.steps.removeFirst()
        #expect(throws: EnactmentError.self) {
            try Transports.validateProgressiveMovePlan(plan)
        }
    }
}

@Suite("pre-1.0 safety — Global favorites reorder as one group")
struct GlobalFavoritesReorderTests {
    private func list() -> FavoritesList {
        FavoritesList([
            Favorite(host: "local", path: "/a", scope: .global),
            Favorite(host: "nas", path: "/b", scope: .global),
            Favorite(host: "local", path: "/c", scope: .global),
            Favorite(host: "nas", path: "/h", scope: .host),
        ])
    }

    @Test("a global favorite can be dropped before a global from another host")
    func dropAcrossHostsInGlobal() {
        var favorites = list()
        favorites.move(id: "local:/c", before: "nas:/b")
        #expect(favorites.all.map(\.id) == ["local:/a", "local:/c", "nas:/b", "nas:/h"])
    }

    @Test("⌥↓ walks one visible row, past a global from another host")
    func stepPastOtherHost() {
        var favorites = list()
        favorites.move(id: "local:/a", by: 1)
        #expect(favorites.all.map(\.id) == ["nas:/b", "local:/a", "local:/c", "nas:/h"])
    }

    @Test("a host-scoped favorite still cannot join the Global group")
    func hostScopedStaysOut() {
        var favorites = list()
        favorites.move(id: "nas:/h", before: "local:/a")
        #expect(favorites.all.map(\.id) == ["local:/a", "nas:/b", "local:/c", "nas:/h"])
    }
}
