// The Field against real userlands — the sshd container (or the CI
// runner's own sshd) and the Lima VM's throwaway pool. Serialized, as all
// suites against one fixture must be. Never a live homelab host: the hard
// limit has no exceptions.

import Foundation
import Testing

@testable import PalanaCore

// Serialized: parallel connections trip sshd's startup throttling —
// observed against the fixture in ho-02.
@Suite("Field integration: sshd fixture", .enabled(if: SSHFixture.available), .serialized)
struct FieldSSHIntegrationTests {
    @Test("the probe learns a zfs-less host's shape in one round trip")
    func probeAgainstContainer() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }
        let field = Field(conduit: conduit, hosts: [host], cache: temporaryCache())
        let facts = try await field.discover(host)
        #expect(facts.reachability?.value == .reachable)
        #expect(facts.capability?.value.kernel != nil)
        #expect(facts.capability?.value.zfs == nil, "no zfs in either sshd fixture")
        #expect(facts.zfsTopology == nil, "no zfs, no topology read")
    }

    @Test("discover records a non-empty mounts fact; targets include /")
    func mountsAgainstContainer() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }
        let field = Field(conduit: conduit, hosts: [host], cache: temporaryCache())
        let facts = try await field.discover(host)
        guard let mounts = facts.mounts else {
            Issue.record("expected mounts fact, got nil")
            return
        }
        #expect(!mounts.value.isEmpty, "fixture is Linux — /proc/mounts is always non-empty")
        let targets = MountTable.targetSet(in: mounts.value)
        #expect(targets.contains("/"), "every Linux host mounts /")
    }

    @Test("a refused door records as an unreachable fact, not a thrown error")
    func unreachableRecordsAsFact() async throws {
        let (configuration, host) = try SSHFixture.configuration(portOverride: "2")
        let conduit = SSHConduit(configuration: configuration)
        let field = Field(conduit: conduit, hosts: [host], cache: temporaryCache())
        let facts = try await field.discover(host)
        guard case .unreachable(let detail) = facts.reachability?.value else {
            Issue.record("expected unreachable, got \(String(describing: facts.reachability))")
            return
        }
        #expect(!detail.isEmpty)
    }

    @Test(
        "capture the container probe for the corpus",
        .enabled(if: ProcessInfo.processInfo.environment["PALANA_RECORD_FIXTURES"] == "1"))
    func captureContainerProbe() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let recorder = RecordingConduit(wrapping: SSHConduit(configuration: configuration))
        defer { Task { await recorder.closeAll() } }
        _ = try await recorder.run(on: host, CapabilityProbe.command).collect()
        try await recorder.write(to: corpusURL("probe-container.json"))
    }

    private func temporaryCache() -> FieldCache {
        FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-int-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
    }
}

// Serialized for the same reason; gated on the Lima fixture, which CI does
// not run — the recorded transcripts carry this truth into every
// environment via FieldCorpusTests.
@Suite("Field integration: zfs fixture", .enabled(if: ZFSFixture.available), .serialized)
struct FieldZFSIntegrationTests {
    @Test("discovery reads the whole shape: probe, then topology")
    func discoverThePool() async throws {
        let (configuration, host) = try ZFSFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }
        let field = Field(conduit: conduit, hosts: [host], cache: temporaryCache())
        let facts = try await field.discover(host)

        #expect(facts.capability?.value.kernel == "Linux")
        #expect(facts.capability?.value.flavor == .gnu)
        #expect(facts.capability?.value.zfsVersion != nil)
        #expect(facts.capability?.value.rsyncVersion != nil, "ho-06 needs this fact")

        let names = Set((facts.zfsTopology?.value ?? []).map(\.name))
        #expect(names.isSuperset(of: ["palana", "palana/tank/media/photos", "palana/svc"]))
    }

    @Test("dataset boundaries resolve correctly against the real pool")
    func boundariesAgainstRealPool() async throws {
        let (configuration, host) = try ZFSFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }
        let field = Field(conduit: conduit, hosts: [host], cache: temporaryCache())
        try await field.discover(host)

        let nested = await field.datasetContaining(
            path: "/palana/tank/media/photos/2026/img.raw", on: host)
        #expect(nested?.name == "palana/tank/media/photos")

        let outOfTree = await field.datasetContaining(
            path: "/opt/services/baserow/data.db", on: host)
        #expect(outOfTree?.name == "palana/svc/baserow")

        // detached is created but unmounted — its path belongs to the parent.
        let detached = await field.datasetContaining(path: "/palana/detached/x", on: host)
        #expect(detached?.name == "palana")

        let outside = await field.datasetContaining(path: "/var/log/syslog", on: host)
        #expect(outside == nil)
    }

    @Test(
        "capture the pool's probe and topology for the corpus",
        .enabled(if: ProcessInfo.processInfo.environment["PALANA_RECORD_FIXTURES"] == "1"))
    func capturePoolTruth() async throws {
        let (configuration, host) = try ZFSFixture.configuration()
        let recorder = RecordingConduit(wrapping: SSHConduit(configuration: configuration))
        defer { Task { await recorder.closeAll() } }
        _ = try await recorder.run(on: host, CapabilityProbe.command).collect()
        _ = try await recorder.run(on: host, ZFSTopology.listCommand).collect()
        try await recorder.write(to: corpusURL("zfs-pool.json"))
    }

    private func temporaryCache() -> FieldCache {
        FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-int-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
    }
}

/// Committed corpus files live beside the failure corpus from ho-02.
private func corpusURL(_ name: String) -> URL {
    SSHFixture.repoRoot.appendingPathComponent("Tests/PalanaCoreTests/Fixtures/\(name)")
}

// Local conduit reads `mount` from this machine — always enabled, always reads-only.
// Darwin is the host machine; the BSD parser covers it.
@Suite("Mounts: local machine parse")
struct MountsLocalIntegrationTests {
    @Test("local mount output parses to a non-empty list with / present")
    func localMountsReadable() async throws {
        let result = try await LocalConduit().run(on: "local", "mount").collect()
        guard result.exitStatus == 0 else {
            Issue.record("mount exited \(result.exitStatus): \(result.stderrText)")
            return
        }
        let mounts = MountTable.parseBSD(result.stdoutText)
        #expect(!mounts.isEmpty, "this machine has at least one mount")
        let targets = MountTable.targetSet(in: mounts)
        #expect(targets.contains("/"), "every macOS host mounts /")
        let root = mounts.first { $0.target == "/" }
        #expect(root?.fstype.isEmpty == false, "root has a non-empty fstype")
    }
}
