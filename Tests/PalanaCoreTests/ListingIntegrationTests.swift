// The Listing against real userlands. The local-shell conduit gives the
// BSD path live Darwin coverage on every run of this suite, no fixture
// required; the sshd suite exercises whichever flavor its fixture
// answers — GNU against the container locally, BSD against the runner's
// own sshd in CI. Never a live homelab host.

import Foundation
import Testing

@testable import PalanaCore

/// A conduit into the local shell — /bin/sh -c, host ignored.
///
/// Exists so the BSD listing path can be exercised and recorded against
/// real Darwin without standing up an sshd. Test infrastructure only.
struct LocalShellConduit: Conduit {
    func run(on host: String, _ command: String) async throws -> RunningCommand {
        try SSHConduit.spawn(executable: "/bin/sh", arguments: ["-c", command])
    }

    func close(host: String) async {}

    func closeAll() async {}
}

/// Builds the hostile-name directory the batteries list.
///
/// One command, POSIX sh, works on every fixture userland.
private let hostileSetup = """
    rm -rf %DIR% && mkdir -p %DIR% && cd %DIR% && \
    touch plain 'with space' 'café' PALANA-LINKS && \
    touch "$(printf 'new\\nline')" && \
    nl=$(printf '\\nX') && nl=${nl%X} && touch "end${nl}" && \
    printf x > sized && \
    ln -s plain alink && ln -s 'with space' 'link with space' && \
    mkdir subdir && mkdir empty
    """

private let hostileNames: Set<String> = [
    "plain", "with space", "café", "PALANA-LINKS", "new\nline", "end\n",
    "sized", "alink", "link with space", "subdir", "empty",
]

private func assertHostileListing(_ entries: [FileEntry]) throws {
    #expect(Set(entries.map(\.name)) == hostileNames)
    #expect(entries.map(\.nameData).contains(Data("new\nline".utf8)), "byte-exact newline name")
    #expect(entries.map(\.nameData).contains(Data("end\n".utf8)), "byte-exact trailing newline")

    let sized = try #require(entries.first { $0.name == "sized" })
    #expect(sized.size == 1)
    #expect(sized.kind == .file)

    let subdir = try #require(entries.first { $0.name == "subdir" })
    #expect(subdir.kind == .directory)

    let alink = try #require(entries.first { $0.name == "alink" })
    #expect(alink.kind == .symlink)
    #expect(alink.symlinkTarget == Data("plain".utf8))

    let spacedLink = try #require(entries.first { $0.name == "link with space" })
    #expect(spacedLink.symlinkTarget == Data("with space".utf8))
}

@Suite("Listing local Darwin — the BSD path, live")
struct ListingLocalDarwinTests {
    private static let dir = "/tmp/palana-listing-bsd-\(ProcessInfo.processInfo.processIdentifier)"

    @Test("the hostile battery survives the BSD path byte for byte")
    func hostileBattery() async throws {
        let conduit = LocalShellConduit()
        let setupCommand = hostileSetup.replacingOccurrences(of: "%DIR%", with: Self.dir)
        let setup = try await conduit.run(on: "local", setupCommand).collect()
        #expect(setup.exitStatus == 0, "setup failed: \(setup.stderrText)")
        defer { Task { _ = try? await conduit.run(on: "local", "rm -rf \(Self.dir)").collect() } }

        let listing = Listing(conduit: conduit)
        let entries = try await listing.list(on: "local", path: Self.dir, flavor: .bsd)
        try assertHostileListing(entries)

        let empty = try await listing.list(on: "local", path: Self.dir + "/empty", flavor: .bsd)
        #expect(empty.isEmpty)
    }

    @Test("read failures classify from a real shell's stderr")
    func realFailures() async throws {
        let listing = Listing(conduit: LocalShellConduit())
        await #expect(throws: ListingError.directoryNotFound(path: "/no/such/palana/dir")) {
            _ = try await listing.list(on: "local", path: "/no/such/palana/dir", flavor: .bsd)
        }
        await #expect(throws: ListingError.notADirectory(path: "/etc/hosts")) {
            _ = try await listing.list(on: "local", path: "/etc/hosts", flavor: .bsd)
        }
    }

    @Test(
        "capture the Darwin listing for the corpus",
        .enabled(if: ProcessInfo.processInfo.environment["PALANA_RECORD_FIXTURES"] == "1"))
    func captureDarwinListing() async throws {
        let recorder = RecordingConduit(wrapping: LocalShellConduit())
        let dir = "/tmp/palana-listing-corpus"
        let setupCommand = hostileSetup.replacingOccurrences(of: "%DIR%", with: dir)
        _ = try await recorder.run(on: "local-darwin", setupCommand).collect()
        let listCommand = Listing.command(for: dir, flavor: .bsd)
        _ = try await recorder.run(on: "local-darwin", listCommand).collect()
        _ = try? await recorder.run(on: "local-darwin", "rm -rf \(dir)").collect()
        try await recorder.write(to: listingCorpusURL("listing-darwin.json"))
    }
}

// Serialized: one sshd fixture, ho-02's observed throttling. The flavor
// is probed live, so this suite runs the GNU path against the container
// and the BSD path against CI's Darwin runner — same test, both worlds.
@Suite("Listing integration: sshd fixture", .enabled(if: SSHFixture.available), .serialized)
struct ListingSSHIntegrationTests {
    private static let dir = "/tmp/palana-listing-\(ProcessInfo.processInfo.processIdentifier)"

    @Test("probe the flavor, then list the hostile battery end to end")
    func endToEnd() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }

        let probe = try await conduit.run(on: host, CapabilityProbe.command).collect()
        let flavor = try CapabilityProbe.parse(probe.stdoutText).flavor

        let setupCommand = hostileSetup.replacingOccurrences(of: "%DIR%", with: Self.dir)
        let setup = try await conduit.run(on: host, setupCommand).collect()
        #expect(setup.exitStatus == 0, "setup failed: \(setup.stderrText)")
        defer { Task { _ = try? await conduit.run(on: host, "rm -rf \(Self.dir)").collect() } }

        let listing = Listing(conduit: conduit)
        let entries = try await listing.list(on: host, path: Self.dir, flavor: flavor)
        try assertHostileListing(entries)

        let empty = try await listing.list(on: host, path: Self.dir + "/empty", flavor: flavor)
        #expect(empty.isEmpty)
    }

    @Test(
        "capture the container listing for the corpus",
        .enabled(if: ProcessInfo.processInfo.environment["PALANA_RECORD_FIXTURES"] == "1"))
    func captureContainerListing() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let recorder = RecordingConduit(wrapping: SSHConduit(configuration: configuration))
        defer { Task { await recorder.closeAll() } }
        let dir = "/tmp/palana-listing-corpus"
        let setupCommand = hostileSetup.replacingOccurrences(of: "%DIR%", with: dir)
        _ = try await recorder.run(on: host, setupCommand).collect()
        _ = try await recorder.run(on: host, Listing.command(for: dir, flavor: .gnu)).collect()
        _ = try? await recorder.run(on: host, "rm -rf \(dir)").collect()
        try await recorder.write(to: listingCorpusURL("listing-container.json"))
    }
}

/// Committed corpus files live beside the rest.
private func listingCorpusURL(_ name: String) -> URL {
    SSHFixture.repoRoot.appendingPathComponent("Tests/PalanaCoreTests/Fixtures/\(name)")
}
