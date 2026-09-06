// The door's last check before launch: a host that is not a plain alias
// never reaches an argv, on the Conduit's route or the pipeline's. The
// parser already refuses these at the registry (Task 5); this is the
// same grammar enforced where restored or legacy data would otherwise
// slip past it. Every process here is a fake ssh on this machine.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SSH destinations")
struct SSHDestinationTests {
    private let configuration = SSHConfiguration(controlDirectory: "/tmp/palana-cm-test")

    @Test(
        "an alias outside the grammar is refused before argv assembly",
        arguments: [
            "jodo;touch /tmp/pwned", "jodo$(id)", "jodo|cat", "jodo koan", "jodo\n", "jödo",
            "-oProxyCommand=evil", "-", "", "local", "LOCAL", "*.lan", "!jodo", "op@jodo", "[::1]",
        ])
    func refused(alias: String) {
        #expect(throws: ConduitError.self) {
            try SSHConduit.arguments(host: alias, command: "true", configuration: configuration)
        }
        do {
            try SSHConduit.validateDestination(alias)
        } catch let error as ConduitError {
            guard case .launchFailed(let detail) = error else {
                Issue.record("expected launchFailed, got \(error)")
                return
            }
            #expect(detail.hasPrefix("refused ssh destination"))
        } catch {
            Issue.record("expected a ConduitError, got \(error)")
        }
    }

    @Test(
        "an alias inside the grammar rides as its own argv element, right before the command",
        arguments: ["jodo", "koan.lan", "host_1", "a-b", "10.0.0.5", "Fixture-Self"])
    func accepted(alias: String) throws {
        let args = try SSHConduit.arguments(host: alias, command: "true", configuration: configuration)
        #expect(args.suffix(2) == [alias, "sh -c true"])
    }

    @Test("a run against a hostile alias throws before anything spawns or the directory exists")
    func runRefusesBeforeLaunch() async throws {
        let directory = try ProcessFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("argv.log")
        let controlDirectory = SSHFixture.freshControlDirectory()
        let conduit = SSHConduit(
            configuration: SSHConfiguration(
                sshExecutablePath: try ControlSocketFixture.recordingSSH(in: directory, log: log),
                controlDirectory: controlDirectory))
        await #expect(throws: ConduitError.self) {
            _ = try await conduit.run(on: "-oProxyCommand=evil", "true")
        }
        await #expect(throws: ConduitError.self) {
            _ = try await conduit.run(on: "jodo;touch /tmp/pwned", "true")
        }
        #expect(ControlSocketFixture.invocations(in: log).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: controlDirectory))
    }

    @Test("a pipeline with a hostile half is refused before either half spawns")
    func pipelineRefusesBeforeAnySpawn() async throws {
        let spawns = SpawnCounter()
        let counting: SSHPipeline.HalfSpawner = { host, command, configuration, pipedInput in
            spawns.increment()
            return try SSHPipeline.spawnHalf(
                host: host, command: command, configuration: configuration, pipedInput: pipedInput)
        }
        let hostile = [
            Pipeline(fromHost: "jodo", fromCommand: "true", toHost: "-oProxyCommand=evil", toCommand: "cat"),
            Pipeline(fromHost: "jodo;id", fromCommand: "true", toHost: "koan", toCommand: "cat"),
        ]
        for pipeline in hostile {
            await #expect(throws: ConduitError.self) {
                _ = try await SSHPipeline.run(
                    pipeline, configuration: configuration, stepIndex: 0, emit: { _ in }, spawn: counting)
            }
        }
        #expect(spawns.total == 0)
    }

    @Test("a spawned half hands ssh the alias and the command as two argv elements")
    func halfPassesAliasAsArgument() async throws {
        let directory = try ProcessFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("argv.log")
        let controlDirectory = try ControlSocketFixture.makeControlDirectory()
        defer { try? FileManager.default.removeItem(atPath: controlDirectory) }
        let configuration = SSHConfiguration(
            sshExecutablePath: try ControlSocketFixture.recordingSSH(in: directory, log: log),
            controlDirectory: controlDirectory)
        let half = try SSHPipeline.spawnHalf(
            host: "jodo", command: "echo hi; echo there", configuration: configuration)
        _ = await half.process.exit()
        OwnedProcess.closeQuietly(half.stdoutRead)
        let argv = try #require(ControlSocketFixture.invocations(in: log).first)
        #expect(argv.suffix(2) == ["jodo", "sh -c 'echo hi; echo there'"])
        #expect(!argv.contains { $0.contains("ssh jodo") })
    }

    @Test("ControlPersist is a finite interval, never yes")
    func controlPersistIsFinite() throws {
        let value = SSHConfiguration().controlPersist
        #expect(value != "yes")
        let digits = value.prefix { $0.isNumber }
        let unit = value.dropFirst(digits.count)
        let seconds = try #require(Int(digits))
        #expect(seconds > 0)
        #expect(["", "s", "m", "h", "d", "w"].contains(String(unit)))
        let args = try SSHConduit.arguments(host: "jodo", command: "true", configuration: configuration)
        #expect(args.contains("ControlPersist=\(value)"))
    }
}

/// Counts spawner calls across the pipeline's queues.
final class SpawnCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    func increment() {
        lock.withLock { stored += 1 }
    }

    var total: Int {
        lock.withLock { stored }
    }
}
