// AddressRoutingTests — where a typed address lands, from the pane's side.
// A bare path is this Mac by grammar: no probe of the pane's remote host,
// no fallback when the local read misses. `:` borrows the pane's host, a
// named host is pointed at — its existence probe and its listing, on that
// host and no other — and a malformed paste is refused in place with the
// pane exactly where it was. The rig is AddressRig: a recording remote
// door, temp directories for the local reads.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@MainActor
@Suite("address routing — one grammar, no remote fallback")
struct AddressRoutingTests {
    private let host = AddressRig.host

    // MARK: - Bare local means local only

    @Test("a bare path that misses locally is refused for this Mac — the remote host is never asked")
    func bareMissNeverProbesRemote() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let missing = "/nowhere-\(UUID().uuidString)"

        rig.pane.pointAddress(missing)
        try await poll(message: "the local miss never reported") { rig.pane.lastError != nil }

        let refusal = AddressRecoveryError.notFound(ResolvedAddress(host: Engine.localHost, path: missing))
        #expect(rig.pane.lastError == refusal.description)
        #expect(rig.pane.state.host == host, "the pane stays on its host")
        #expect(rig.pane.state.path == "/srv", "the pane stays where it was")
        #expect(rig.pane.isReading == false)
        let commands = await rig.conduit.commands
        #expect(commands.isEmpty, "no probe, no listing, nothing went over the wire: \(commands)")
    }

    @Test("a bare path that exists lands on this Mac even while the pane stands on a remote host")
    func barePathLandsLocally() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let directory = try AddressRig.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.path

        rig.pane.pointAddress(path)
        try await poll(message: "the pane did not land") { rig.pane.state.host == Engine.localHost }

        #expect(rig.pane.state.path == path)
        #expect(rig.pane.status == .ready)
        #expect(rig.pane.addressNotice == nil, "an exact landing posts no notice")
        #expect(await rig.conduit.commands.isEmpty, "nothing went over the wire")
    }

    @Test("a quoted, newline-terminated, escaped paste lands on this Mac exactly where the wrappers said")
    func hostilePasteLandsLocally() async throws {
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let parent = try AddressRig.makeTemporaryDirectory()
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
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }
        let parent = try AddressRig.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("My File", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        rig.pane.pointAddress("file://" + parent.path + "/My%20File\n")
        try await poll(message: "the pane did not land") { rig.pane.state.host == Engine.localHost }

        #expect(rig.pane.state.path == directory.path)
    }

    // MARK: - Explicit hosts

    @Test("host:path points at that host and runs exactly its probe and its listing")
    func namedHostPoints() async throws {
        let (probe, presence) = AddressRig.probe("/tank", .directory)
        let (listing, entries) = AddressRig.listing("/tank")
        let rig = try AddressRig(answers: [probe: presence, listing: entries])
        defer { rig.tearDown() }

        rig.pane.pointAddress("koan:/tank")
        try await poll(message: "the pane did not land") { rig.pane.state.host == host }

        #expect(rig.pane.state.path == "/tank")
        #expect(await rig.conduit.commands == [probe, listing])
        #expect(await rig.conduit.hosts == [host, host])
    }

    @Test(":path borrows the pane's host")
    func currentHostShorthandPoints() async throws {
        let (probe, presence) = AddressRig.probe("/tank", .directory)
        let (listing, entries) = AddressRig.listing("/tank")
        let rig = try AddressRig.remote(answers: [probe: presence, listing: entries])
        defer { rig.tearDown() }

        rig.pane.pointAddress(":/tank")
        try await poll(message: "the pane did not land") { rig.pane.state.path == "/tank" }

        #expect(rig.pane.state.host == host)
        #expect(await rig.conduit.commands == [probe, listing])
    }

    @Test(": on an unpointed pane is refused in place, with no read")
    func currentHostShorthandOnUnpointedPane() async throws {
        let rig = try AddressRig()
        defer { rig.tearDown() }

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
        let rig = try AddressRig.remote()
        defer { rig.tearDown() }

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
}
