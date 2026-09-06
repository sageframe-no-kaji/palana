// The control directory's lifecycle: refused unless it is a private
// directory of this user's, swept of what a crashed run left before the
// first master is born, and cleared of dead sockets on the way out.
// Sockets here are planted by the test; the fake ssh plays the master
// that leaves when asked. Never the app's own directory.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SSH control directory")
struct SSHControlDirectoryTests {
    private let directory: URL
    private let log: URL
    private let fakeSSH: String

    init() throws {
        directory = try ProcessFixture.makeDirectory()
        log = directory.appendingPathComponent("argv.log")
        fakeSSH = try ControlSocketFixture.recordingSSH(in: directory, log: log)
    }

    private func conduit(controlDirectory: String) -> SSHConduit {
        SSHConduit(
            configuration: SSHConfiguration(
                sshExecutablePath: fakeSSH, controlDirectory: controlDirectory))
    }

    private func invocations() -> [[String]] {
        ControlSocketFixture.invocations(in: log)
    }

    private func isExit(_ argv: [String]) -> Bool {
        argv.contains("-O") && argv.contains("exit")
    }

    @Test("the wrong-owner case is refused — pure, since a second user is not on hand")
    func wrongOwner() {
        let foreign = getuid() &+ 1
        let problem = SSHConduit.controlDirectoryProblem(
            uid: foreign, mode: 0o40700, isDirectory: true)
        #expect(problem?.contains("owned by uid \(foreign)") == true)
        #expect(SSHConduit.controlDirectoryProblem(uid: getuid(), mode: 0o40700, isDirectory: true) == nil)
    }

    @Test("a directory others can reach fails closed before ssh is spawned")
    func wrongMode() async throws {
        let control = try ControlSocketFixture.makeControlDirectory(mode: 0o750)
        defer { try? FileManager.default.removeItem(atPath: control) }
        let door = conduit(controlDirectory: control)
        await #expect(throws: ConduitError.self) {
            _ = try await door.run(on: "jodo", "true")
        }
        do {
            _ = try await door.run(on: "jodo", "true")
        } catch let error as ConduitError {
            guard case .launchFailed(let detail) = error else {
                Issue.record("expected launchFailed, got \(error)")
                return
            }
            #expect(detail.contains("control directory"))
            #expect(detail.contains("open to others"))
        }
        #expect(invocations().isEmpty)
    }

    @Test("a file or a symlink where the directory should be fails closed")
    func notADirectory() async throws {
        let filePath = SSHFixture.freshControlDirectory()
        try Data().write(to: URL(fileURLWithPath: filePath))
        defer { try? FileManager.default.removeItem(atPath: filePath) }
        let realDirectory = try ControlSocketFixture.makeControlDirectory()
        defer { try? FileManager.default.removeItem(atPath: realDirectory) }
        let linkPath = SSHFixture.freshControlDirectory()
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: realDirectory)
        defer { try? FileManager.default.removeItem(atPath: linkPath) }

        for path in [filePath, linkPath] {
            do {
                _ = try await conduit(controlDirectory: path).run(on: "jodo", "true")
                Issue.record("expected a refusal for \(path)")
            } catch let error as ConduitError {
                guard case .launchFailed(let detail) = error else {
                    Issue.record("expected launchFailed, got \(error)")
                    return
                }
                #expect(detail.contains("is not a directory"))
            }
        }
        #expect(invocations().isEmpty)
    }

    @Test("a pipeline half checks the directory the same way")
    func pipelineHalfChecksDirectory() throws {
        let control = try ControlSocketFixture.makeControlDirectory(mode: 0o755)
        defer { try? FileManager.default.removeItem(atPath: control) }
        let configuration = SSHConfiguration(sshExecutablePath: fakeSSH, controlDirectory: control)
        #expect(throws: ConduitError.self) {
            try SSHPipeline.spawnHalf(host: "jodo", command: "true", configuration: configuration)
        }
        #expect(invocations().isEmpty)
    }

    @Test("the first use is created private and reused as it is")
    func firstUseCreatesPrivateDirectory() async throws {
        let control = SSHFixture.freshControlDirectory()
        defer { try? FileManager.default.removeItem(atPath: control) }
        let door = conduit(controlDirectory: control)
        _ = try await door.run(on: "jodo", "true").collect()
        var status = stat()
        #expect(lstat(control, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o700)
        #expect(status.st_uid == getuid())
    }

    @Test("stale sockets are swept once, before the first master: dead ones unlinked, live ones asked to exit")
    func staleSocketsSweptOnFirstUse() async throws {
        let control = try ControlSocketFixture.makeControlDirectory()
        defer { try? FileManager.default.removeItem(atPath: control) }
        let dead = "\(control)/dead"
        let live = "\(control)/live"
        try ControlSocketFixture.plantDeadSocket(at: dead)
        let listener = try ControlSocketFixture.plantLiveSocket(at: live)
        defer { close(listener) }

        let door = conduit(controlDirectory: control)
        _ = try await door.run(on: "jodo", "true").collect()

        #expect(!FileManager.default.fileExists(atPath: dead))
        #expect(!FileManager.default.fileExists(atPath: live))
        let calls = invocations()
        let exits = calls.filter(isExit)
        #expect(exits.count == 1)
        #expect(exits.first?.contains("ControlPath=\(live)") == true)
        #expect(!exits.contains { $0.contains("ControlPath=\(dead)") })
        // The sweep precedes the run; the run's argv is the last line.
        #expect(calls.first.map(isExit) == true)
        #expect(calls.last?.suffix(2) == ["jodo", "sh -c true"])

        _ = try await door.run(on: "koan", "true").collect()
        #expect(invocations().count == calls.count + 1)
        #expect(invocations().filter(isExit).count == 1)
    }

    @Test("normal shutdown asks every opened master to exit and clears what is left dead")
    func shutdownCleanup() async throws {
        let control = try ControlSocketFixture.makeControlDirectory()
        defer { try? FileManager.default.removeItem(atPath: control) }
        let door = conduit(controlDirectory: control)
        _ = try await door.run(on: "jodo", "true").collect()
        _ = try await door.run(on: "koan", "true").collect()
        let leftover = "\(control)/leftover"
        try ControlSocketFixture.plantDeadSocket(at: leftover)

        await door.closeAll()

        let exits = invocations().filter(isExit)
        #expect(exits.count == 2)
        #expect(Set(exits.compactMap(\.last)) == ["jodo", "koan"])
        #expect(!FileManager.default.fileExists(atPath: leftover))
        #expect(SSHConduit.controlSockets(in: control).isEmpty)
    }
}
