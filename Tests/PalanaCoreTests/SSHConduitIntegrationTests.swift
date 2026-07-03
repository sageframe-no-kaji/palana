// Integration against a real sshd — the container fixture locally, the
// runner's own sshd in CI. Skips, visibly, when .fixtures/sshd.env is
// absent. Never a live homelab host: the hard limit has no exceptions.

import Foundation
import Testing

@testable import PalanaCore

// Serialized: parallel connections trip sshd's startup throttling and the
// drops surface as connectionLost — observed against the fixture.
@Suite("SSHConduit integration", .enabled(if: SSHFixture.available), .serialized)
struct SSHConduitIntegrationTests {
    @Test("a command round-trips: stdout, stderr, exit status")
    func roundTrip() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }
        let result = try await conduit.run(on: host, "echo palana && echo warn >&2").collect()
        #expect(result.stdoutText == "palana\n")
        #expect(result.stderrText.contains("warn"))
        #expect(result.exitStatus == 0)
    }

    @Test("sessions are reused: the master socket exists and the reused trip is faster")
    func sessionReuse() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        let clock = ContinuousClock()

        let coldStart = clock.now
        _ = try await conduit.run(on: host, "true").collect()
        let cold = coldStart.duration(to: clock.now)

        let sockets = try FileManager.default.contentsOfDirectory(
            atPath: configuration.controlDirectory)
        #expect(!sockets.isEmpty, "ControlMaster socket should exist after first use")

        let warmStart = clock.now
        _ = try await conduit.run(on: host, "true").collect()
        let warm = warmStart.duration(to: clock.now)

        print("session-reuse timing — cold: \(cold), multiplexed: \(warm)")
        #expect(warm < cold, "multiplexed trip should beat the cold connection")

        await conduit.closeAll()
        let after =
            (try? FileManager.default.contentsOfDirectory(
                atPath: configuration.controlDirectory)) ?? []
        #expect(after.isEmpty, "closeAll should remove the master socket")
    }

    @Test("a nonzero remote exit is data, not a thrown error")
    func remoteFailureIsData() async throws {
        let (configuration, host) = try SSHFixture.configuration()
        let conduit = SSHConduit(configuration: configuration)
        defer { Task { await conduit.closeAll() } }
        let result = try await conduit.run(on: host, "exit 7").collect()
        #expect(result.exitStatus == 7)
    }

    @Test("an unauthorized key surfaces as authenticationDenied")
    func authDenied() async throws {
        let (configuration, host) = try SSHFixture.configuration(
            identityKey: "PALANA_FIXTURE_IDENTITY_DENIED")
        let conduit = SSHConduit(configuration: configuration)
        await #expect(throws: ConduitError.self) {
            _ = try await conduit.run(on: host, "true").collect()
        }
        do {
            _ = try await conduit.run(on: host, "true").collect()
        } catch let error as ConduitError {
            guard case .authenticationDenied = error else {
                Issue.record("expected authenticationDenied, got \(error)")
                return
            }
        }
    }

    @Test("a refused port surfaces as hostUnreachable")
    func unreachable() async throws {
        let (configuration, host) = try SSHFixture.configuration(portOverride: "2")
        let conduit = SSHConduit(configuration: configuration)
        do {
            _ = try await conduit.run(on: host, "true").collect()
            Issue.record("expected hostUnreachable")
        } catch let error as ConduitError {
            guard case .hostUnreachable = error else {
                Issue.record("expected hostUnreachable, got \(error)")
                return
            }
        }
    }

    @Test("strict checking with no known key surfaces as hostKeyVerificationFailed")
    func hostKeyFails() async throws {
        let (configuration, host) = try SSHFixture.configuration(knownHostsMode: .emptyStrict)
        let conduit = SSHConduit(configuration: configuration)
        do {
            _ = try await conduit.run(on: host, "true").collect()
            Issue.record("expected hostKeyVerificationFailed")
        } catch let error as ConduitError {
            guard case .hostKeyVerificationFailed = error else {
                Issue.record("expected hostKeyVerificationFailed, got \(error)")
                return
            }
        }
    }

    @Test(
        "capture the failure corpus for the unit battery",
        .enabled(if: ProcessInfo.processInfo.environment["PALANA_RECORD_FIXTURES"] == "1"))
    func captureFailureCorpus() async throws {
        var entries: [ConduitTranscript.Entry] = []

        func capture(_ configuration: SSHConfiguration, _ host: String, _ command: String) async {
            let recorder = RecordingConduit(wrapping: SSHConduit(configuration: configuration))
            if let running = try? await recorder.run(on: host, command) {
                _ = try? await running.collect()
            }
            let transcript = await recorder.transcript()
            entries.append(contentsOf: transcript.entries.filter { $0.exit == 255 })
        }

        let denied = try SSHFixture.configuration(identityKey: "PALANA_FIXTURE_IDENTITY_DENIED")
        await capture(denied.configuration, denied.host, "true")
        let refused = try SSHFixture.configuration(portOverride: "2")
        await capture(refused.configuration, refused.host, "true")
        let strict = try SSHFixture.configuration(knownHostsMode: .emptyStrict)
        await capture(strict.configuration, strict.host, "true")

        let url = SSHFixture.repoRoot.appendingPathComponent(
            "Tests/PalanaCoreTests/Fixtures/failure-corpus.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConduitTranscript(entries: entries).write(to: url)
        #expect(entries.count >= 3)
    }
}
