// Recursive size facts against real trees — known bytes on both
// userland paths, and a refused subtree proving the completeness flag
// cannot be silenced. Same fixtures, same gating, same .serialized
// discipline as the listing's own integration.

import Foundation
import Testing

@testable import PalanaCore

/// A tree with known sizes: 5 + 10 + 3 readable bytes, plus 2 bytes
/// locked inside a mode-000 directory the walk must get refused by.
private let sizedSetup = """
    rm -rf %DIR% && mkdir -p %DIR%/deep/deeper %DIR%/refused && \
    printf 12345 > %DIR%/a.bin && \
    printf 1234567890 > %DIR%/deep/b.bin && \
    printf 123 > %DIR%/deep/deeper/c.bin && \
    printf 12 > %DIR%/refused/locked.bin && \
    chmod 000 %DIR%/refused
    """

private let sizedTeardown = "chmod 755 %DIR%/refused 2>/dev/null; rm -rf %DIR%"

private func assertSizeFacts(_ facts: [RecursiveSize]) {
    #expect(facts.count == 2)
    #expect(facts[0].bytes == 18, "5 + 10 + 3 readable bytes, the locked 2 excluded")
    #expect(!facts[0].complete, "the refused subtree must mark the floor")
    #expect(facts[1] == RecursiveSize(bytes: 13, complete: true), "deep/ alone is whole")
}

@Suite("TreeSize local Darwin — the BSD path, live")
struct TreeSizeLocalDarwinTests {
    private static let dir = "/tmp/palana-treesize-bsd-\(ProcessInfo.processInfo.processIdentifier)"

    @Test("known bytes sum and a refused subtree marks the floor")
    func knownTree() async throws {
        let conduit = LocalConduit()
        let setupCommand = sizedSetup.replacingOccurrences(of: "%DIR%", with: Self.dir)
        let setup = try await conduit.run(on: "local", setupCommand).collect()
        #expect(setup.exitStatus == 0, "setup failed: \(setup.stderrText)")
        defer {
            let teardown = sizedTeardown.replacingOccurrences(of: "%DIR%", with: Self.dir)
            Task { _ = try? await conduit.run(on: "local", teardown).collect() }
        }

        let listing = Listing(conduit: conduit)
        let facts = try await listing.treeSizes(
            on: "local", paths: [Self.dir, Self.dir + "/deep"], flavor: .bsd)
        assertSizeFacts(facts)
    }
}

@Suite("TreeSize integration: sshd fixture", .enabled(if: SSHFixture.available), .serialized)
struct TreeSizeSSHIntegrationTests {
    private static let dir = "/tmp/palana-treesize-\(ProcessInfo.processInfo.processIdentifier)"

    @Test("known bytes sum over the wire on the probed flavor")
    func knownTree() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }

        let probe = try await conduit.run(on: host, CapabilityProbe.command).collect()
        let flavor = try CapabilityProbe.parse(probe.stdoutText).flavor

        let setupCommand = sizedSetup.replacingOccurrences(of: "%DIR%", with: Self.dir)
        let setup = try await conduit.run(on: host, setupCommand).collect()
        #expect(setup.exitStatus == 0, "setup failed: \(setup.stderrText)")
        defer {
            let teardown = sizedTeardown.replacingOccurrences(of: "%DIR%", with: Self.dir)
            Task { _ = try? await conduit.run(on: host, teardown).collect() }
        }

        let listing = Listing(conduit: conduit)
        let facts = try await listing.treeSizes(
            on: host, paths: [Self.dir, Self.dir + "/deep"], flavor: flavor)
        assertSizeFacts(facts)
    }
}
