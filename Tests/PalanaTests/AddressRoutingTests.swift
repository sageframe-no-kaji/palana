// AddressRoutingTests — where a typed address lands, from the pane's side.
// A bare path is this Mac by grammar: no probe of the pane's remote host,
// no fallback when the local read misses. `:` borrows the pane's host, a
// named host is pointed at, and a malformed paste is refused in place with
// the pane exactly where it was. The remote conduit is a fake that records
// every command it is handed; the local reads touch only temp directories.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// A remote door that records everything and answers one listing.
private actor RecordingConduit: Conduit {
    private let listings: [String: Data]
    private(set) var commands: [String] = []

    init(listings: [String: Data] = [:]) {
        self.listings = listings
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        commands.append(command)
        guard let data = listings[command] else {
            return RunningCommand(
                replayingStdout: Data(), stderr: Data("bash: no such file or directory".utf8), exitStatus: 1)
        }
        return RunningCommand(replayingStdout: data, stderr: Data(), exitStatus: 0)
    }

    func close(host: String) async {}
    func closeAll() async {}
}

@MainActor
@Suite("address routing — one grammar, no remote fallback")
struct AddressRoutingTests {
    private let host = "koan"

    private struct Rig {
        let conduit: RecordingConduit
        let pane: PaneModel
        let cacheURL: URL
    }

    /// A pane over a GNU host whose capability is already known, so a
    /// remote pointing runs exactly one listing command and nothing else.
    private func makeRig(remoteListings: [String: Data] = [:]) throws -> Rig {
        let conduit = RecordingConduit(listings: remoteListings)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-address-cache-\(UUID().uuidString).json")
        let cache = FieldCache(url: cacheURL)
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: nil)
        try cache.save([host: HostFacts(capability: Dated(value: capability, discoveredAt: Date()))])
        let field = Field(conduit: conduit, hosts: [host], cache: cache)
        let engine = Engine(
            conduit: SSHConduit(configuration: SSHConfiguration()),
            field: field,
            listing: Listing(conduit: conduit))
        return Rig(conduit: conduit, pane: PaneModel(engine: engine), cacheURL: cacheURL)
    }

    /// A pane standing on the remote host, as after a successful read.
    private func makeRemotePane(remoteListings: [String: Data] = [:]) throws -> Rig {
        let rig = try makeRig(remoteListings: remoteListings)
        rig.pane.state.host = host
        rig.pane.state.path = "/srv"
        return rig
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-address-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Bare local means local only

    @Test("a bare path that misses locally is refused for this Mac — the remote host is never asked")
    func bareMissNeverProbesRemote() async throws {
        let rig = try makeRemotePane()
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        let missing = "/nowhere-\(UUID().uuidString)"

        rig.pane.pointAddress(missing)
        try await poll(message: "the local miss never reported") { rig.pane.lastError != nil }

        #expect(rig.pane.lastError == "no such directory: \(missing)")
        #expect(rig.pane.state.host == host, "the pane stays on its host")
        #expect(rig.pane.state.path == "/srv", "the pane stays where it was")
        let commands = await rig.conduit.commands
        #expect(commands.isEmpty, "no probe, no listing, nothing went over the wire: \(commands)")
    }

    @Test("a bare path that exists lands on this Mac even while the pane stands on a remote host")
    func barePathLandsLocally() async throws {
        let rig = try makeRemotePane()
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.path

        rig.pane.pointAddress(path)
        try await poll(message: "the pane did not land") { rig.pane.state.host == Engine.localHost }

        #expect(rig.pane.state.path == path)
        #expect(rig.pane.status == .ready)
        #expect(await rig.conduit.commands.isEmpty, "nothing went over the wire")
    }

    @Test("a quoted, newline-terminated, escaped paste lands on this Mac exactly where the wrappers said")
    func hostilePasteLandsLocally() async throws {
        let rig = try makeRemotePane()
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("My Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let escaped = parent.path + "/My\\ Folder"

        rig.pane.pointAddress("\"\(escaped)\"\n")
        try await poll(message: "the pane did not land") { rig.pane.state.host == Engine.localHost }

        #expect(rig.pane.state.path == directory.path)
        #expect(await rig.conduit.commands.isEmpty, "nothing went over the wire")
    }

    @Test("a file:// paste lands on this Mac, percent-decoded")
    func fileURLLandsLocally() async throws {
        let rig = try makeRemotePane()
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("My File", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        rig.pane.pointAddress("file://" + parent.path + "/My%20File\n")
        try await poll(message: "the pane did not land") { rig.pane.state.host == Engine.localHost }

        #expect(rig.pane.state.path == directory.path)
    }

    // MARK: - Explicit hosts

    @Test("host:path points at that host and runs exactly its listing")
    func namedHostPoints() async throws {
        let command = Listing.command(for: "/tank", flavor: .gnu)
        let rig = try makeRig(remoteListings: [command: Data()])
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }

        rig.pane.pointAddress("koan:/tank")
        try await poll(message: "the pane did not land") { rig.pane.state.host == host }

        #expect(rig.pane.state.path == "/tank")
        #expect(await rig.conduit.commands == [command])
    }

    @Test(":path borrows the pane's host")
    func currentHostShorthandPoints() async throws {
        let command = Listing.command(for: "/tank", flavor: .gnu)
        let rig = try makeRemotePane(remoteListings: [command: Data()])
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }

        rig.pane.pointAddress(":/tank")
        try await poll(message: "the pane did not land") { rig.pane.state.path == "/tank" }

        #expect(rig.pane.state.host == host)
        #expect(await rig.conduit.commands == [command])
    }

    @Test(": on an unpointed pane is refused in place, with no read")
    func currentHostShorthandOnUnpointedPane() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }

        rig.pane.pointAddress(":/tank")

        #expect(rig.pane.lastError == AddressParseError.noCurrentHost.description)
        #expect(rig.pane.state.host == nil)
        #expect(rig.pane.status == .unpointed)
        #expect(await rig.conduit.commands.isEmpty)
    }

    // MARK: - Refusals

    @Test(
        "a malformed paste is refused in place — the pane stays put, nothing is read",
        arguments: [
            "\"/tank", "/tank\n/media", "smb://nas/share", "koan;rm -rf /:/tank", "$(hostname)",
            "/tank\u{0}x", "koan:notes",
        ])
    func malformedPasteRefused(input: String) async throws {
        let rig = try makeRemotePane()
        defer { try? FileManager.default.removeItem(at: rig.cacheURL) }

        rig.pane.pointAddress(input)

        let expected = PaneModel.resolveAddress(input, currentHost: host)
        guard case .failure(let refusal) = expected else {
            Issue.record("\(input) was expected to refuse")
            return
        }
        #expect(rig.pane.lastError == refusal.description)
        #expect(rig.pane.state.host == host)
        #expect(rig.pane.state.path == "/srv")
        #expect(rig.pane.status == .unpointed, "no read was started")
        #expect(await rig.conduit.commands.isEmpty)
    }

    // MARK: - One funnel

    @Test(
        "the sheet's preview and the pane's pointing come from the same resolution",
        arguments: [
            "/tank/a:b", "~/notes", "\"/Users/atm/My Folder\"\n", "file:///Users/atm/My%20File",
            "local:/Users", "local:", "koan:/tank", "koan:~/notes", "koan:", ":/tank", ":", "koan",
            "/Users/atm/My\\ Folder",
        ])
    func sheetAndPaneAgree(input: String) throws {
        for currentHost in [host, Engine.localHost, nil] {
            let pane = PaneModel.resolveAddress(input, currentHost: currentHost)
            let sheet = GoToBar.resolution(of: input, currentHost: currentHost)
            switch pane {
            case .success(let resolved):
                #expect(sheet.resolved == resolved, "\(input) on \(currentHost ?? "nothing")")
            case .failure(let refusal):
                #expect(sheet == .refusal(refusal.description), "\(input) on \(currentHost ?? "nothing")")
            }
        }
    }

    @Test("resolution is pure: the same text means the same place on any pane, unless it says ':'")
    func bareScopeIgnoresPane() {
        for currentHost in [host, Engine.localHost, nil] {
            #expect(
                PaneModel.resolveAddress("/tank", currentHost: currentHost)
                    == .success(ResolvedAddress(host: Engine.localHost, path: "/tank")))
            #expect(
                PaneModel.resolveAddress("~/notes", currentHost: currentHost)
                    == .success(ResolvedAddress(host: Engine.localHost, path: "~/notes")))
            #expect(
                PaneModel.resolveAddress("koan:/tank", currentHost: currentHost)
                    == .success(ResolvedAddress(host: "koan", path: "/tank")))
        }
    }

    /// Bounded main-actor poll — records an issue on timeout rather than hanging.
    private func poll(
        timeout: TimeInterval = 5,
        message: String,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("\(message)")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
