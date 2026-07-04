// The local door — same shape as the wire, no wire. Promoted from
// test infrastructure when the Surface gained a local pane.

import Foundation
import Testing

@testable import PalanaCore

@Suite("LocalConduit")
struct LocalConduitTests {
    @Test("runs a command in the local shell, host ignored")
    func runsLocally() async throws {
        let result = try await LocalConduit().run(on: "anything", "printf %s hello").collect()
        #expect(result.exitStatus == 0)
        #expect(result.stdout == Data("hello".utf8))
    }

    @Test("nonzero exits and stderr come back like any door's")
    func failuresSurface() async throws {
        let result = try await LocalConduit().run(on: "x", "echo oops >&2; exit 3").collect()
        #expect(result.exitStatus == 3)
        #expect(result.stderrText.contains("oops"))
    }

    @Test("close and closeAll are no-ops that do not throw")
    func lifecycleNoops() async {
        let conduit = LocalConduit()
        await conduit.close(host: "x")
        await conduit.closeAll()
    }
}
