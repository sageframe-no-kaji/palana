// The router, pinned — the reserved name reaches this machine's shell,
// every other name reaches the wire door, and close never crosses the
// seam. Mixed plans ride this without knowing there are two doors.

import Foundation
import Testing

@testable import PalanaCore

@Suite("RoutingConduit")
struct RoutingConduitTests {
    private func makeRemote() -> RecordedConduit {
        RecordedConduit(
            transcript: ConduitTranscript(entries: [
                .init(host: "koan", command: "echo wire", stdout: "wire\n", stderr: "", exit: 0)
            ])
        )
    }

    @Test("the reserved name runs in the local shell")
    func localNameRunsLocally() async throws {
        let router = RoutingConduit(remote: makeRemote())
        let result = try await router.run(on: "local", "printf here").collect()
        #expect(result.exitStatus == 0)
        #expect(result.stdoutText == "here")
    }

    @Test("every other name goes to the wire door")
    func remoteNameRoutes() async throws {
        let router = RoutingConduit(remote: makeRemote())
        let result = try await router.run(on: "koan", "echo wire").collect()
        #expect(result.stdoutText == "wire\n")
    }

    @Test("a custom reserved name governs the split")
    func customReservedName() async throws {
        let router = RoutingConduit(remote: makeRemote(), localName: "this-mac")
        let result = try await router.run(on: "this-mac", "printf custom").collect()
        #expect(result.stdoutText == "custom")
    }

    @Test("close on the reserved name never crosses to the wire")
    func closeLocalIsNoOp() async {
        let router = RoutingConduit(remote: makeRemote())
        await router.close(host: "local")
        await router.close(host: "koan")
        await router.closeAll()
    }
}
