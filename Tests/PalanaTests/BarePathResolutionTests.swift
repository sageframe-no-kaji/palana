// BarePathResolutionTests — where a colon-free absolute path lands. Local
// first is the decided order, so these pin both the order and the promise
// that the remote probe never runs on a local hit. Existence checks are
// injected; no wire, no filesystem.

import Foundation
import Testing

@testable import Palana

@Suite("bare path — local first resolution")
@MainActor
struct BarePathResolutionTests {
    // MARK: - Order

    @Test("a path that exists here points here")
    func localHit() async {
        let resolved = await PaneModel.resolveBarePath(
            "/Users/atm/notes",
            remoteHost: "koan",
            existsHere: { _ in true },
            existsThere: { _ in false })
        #expect(resolved == .here("/Users/atm/notes"))
    }

    @Test("a path absent here but present on the pane's host points there")
    func remoteHit() async {
        let resolved = await PaneModel.resolveBarePath(
            "/tank/media",
            remoteHost: "koan",
            existsHere: { _ in false },
            existsThere: { _ in true })
        #expect(resolved == .there(host: "koan", path: "/tank/media"))
    }

    @Test("a path that exists in both places resolves local — the decided order")
    func bothExistLocalWins() async {
        let resolved = await PaneModel.resolveBarePath(
            "/tmp",
            remoteHost: "koan",
            existsHere: { _ in true },
            existsThere: { _ in true })
        #expect(resolved == .here("/tmp"))
    }

    @Test("a path in neither place refuses, carrying both places looked")
    func neitherExists() async {
        let resolved = await PaneModel.resolveBarePath(
            "/nowhere",
            remoteHost: "koan",
            existsHere: { _ in false },
            existsThere: { _ in false })
        #expect(resolved == .nowhere(path: "/nowhere", remoteHost: "koan"))
    }

    @Test("a local pane has no second place to look")
    func localPaneHasNoRemote() async {
        let resolved = await PaneModel.resolveBarePath(
            "/nowhere",
            remoteHost: nil,
            existsHere: { _ in false },
            existsThere: { _ in false })
        #expect(resolved == .nowhere(path: "/nowhere", remoteHost: nil))
    }

    // MARK: - No round trip before a local hit

    @Test("the remote probe never runs when the local check succeeds")
    func localHitSkipsTheWire() async {
        var probed = false
        _ = await PaneModel.resolveBarePath(
            "/tmp",
            remoteHost: "koan",
            existsHere: { _ in true },
            existsThere: { _ in
                probed = true
                return true
            })
        #expect(!probed, "local-first means no network round trip precedes a local hit")
    }

    @Test("the path handed to both checks is the one that was typed")
    func checksSeeTheTypedPath() async {
        var sawHere: String?
        var sawThere: String?
        _ = await PaneModel.resolveBarePath(
            "/tank/a b",
            remoteHost: "koan",
            existsHere: { path in
                sawHere = path
                return false
            },
            existsThere: { path in
                sawThere = path
                return false
            })
        #expect(sawHere == "/tank/a b")
        #expect(sawThere == "/tank/a b")
    }

    // MARK: - The refusal line

    @Test("the refusal names this Mac and the pane's host")
    func refusalNamesBoth() async {
        #expect(
            PaneModel.bareRefusal(path: "/nowhere", remoteHost: "koan")
                == "not found on this Mac or koan: /nowhere")
    }

    @Test("on a local pane the refusal names this Mac alone")
    func refusalNamesThisMac() async {
        #expect(
            PaneModel.bareRefusal(path: "/nowhere", remoteHost: nil)
                == "not found on this Mac: /nowhere")
    }
}
