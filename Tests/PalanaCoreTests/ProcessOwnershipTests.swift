// Process ownership — the review's finding that cancellation changed
// UI state while the operating-system process ran on. Every test here
// starts a shell that would leave a marker if it survived, stops it
// through the command's own lifecycle, and checks the marker never
// lands and the exit was awaited before cancellation was reported.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Process ownership")
struct ProcessOwnershipTests {
    private let directory: URL
    private let pidFile: URL
    private let marker: URL

    init() throws {
        directory = try ProcessFixture.makeDirectory()
        pidFile = directory.appendingPathComponent("pid")
        marker = directory.appendingPathComponent("marker")
    }

    /// A grandchild in the group that records its pid, waits, then
    /// leaves the marker — the delayed side effect cancellation must
    /// prevent. `& wait` puts it one fork below the leader, so a kill
    /// that reached only the leader would let the marker land.
    private var delayedSideEffect: String {
        "sh -c '\(ProcessFixture.recordPid(at: pidFile)); sleep 30; touch \(ShellQuote.quote(marker.path))' & wait"
    }

    @Test("cancel stops the whole group and prevents the delayed side effect")
    func cancelStopsTheGroup() async throws {
        let running = try await LocalConduit().run(on: "local", delayedSideEffect)
        let grandchild = try #require(await ProcessFixture.awaitPid(at: pidFile))
        #expect(ProcessFixture.isAlive(grandchild))

        let status = await running.cancel()

        #expect(status == 128 + SIGTERM, "the leader died of the signal it was sent")
        #expect(await ProcessFixture.awaitDeath(of: grandchild), "the grandchild went with the group")
        #expect(!ProcessFixture.exists(marker), "the side effect never happened")
    }

    @Test("cancel escalates to SIGKILL when the group ignores SIGTERM")
    func cancelEscalatesToKill() async throws {
        // An ignored disposition is inherited — sleep ignores TERM too.
        let stubborn =
            "trap '' TERM; \(ProcessFixture.recordPid(at: pidFile)); sleep 30; "
            + "touch \(ShellQuote.quote(marker.path))"
        let running = try await LocalConduit().run(on: "local", stubborn)
        let pid = try #require(await ProcessFixture.awaitPid(at: pidFile))

        let clock = ContinuousClock()
        let started = clock.now
        let status = await running.cancel(killAfter: .milliseconds(200))
        let elapsed = clock.now - started

        #expect(status == 128 + SIGKILL)
        #expect(elapsed < .seconds(5), "the kill came after the grace, not after the sleep")
        #expect(await ProcessFixture.awaitDeath(of: pid))
        #expect(!ProcessFixture.exists(marker))
    }

    @Test("cancellation is idempotent: repeated and concurrent calls agree, and none follow exit")
    func cancelIsIdempotent() async throws {
        let running = try await LocalConduit().run(on: "local", delayedSideEffect)
        _ = try #require(await ProcessFixture.awaitPid(at: pidFile))

        running.terminate()
        running.terminate()
        async let first = running.cancel()
        async let second = running.cancel()
        let statuses = await [first, second]
        #expect(statuses == [128 + SIGTERM, 128 + SIGTERM])

        // After exit: no signal, no wait, the same answer.
        let again = await running.cancel()
        #expect(again == 128 + SIGTERM)
        running.terminate()
        #expect(await running.exitStatus() == 128 + SIGTERM)
        #expect(!ProcessFixture.exists(marker))
    }

    @Test("a task cancelled inside collect stops the process before CancellationError surfaces")
    func collectUnderCancellation() async throws {
        let command = delayedSideEffect
        let task = Task { () throws -> CommandResult in
            try await LocalConduit().run(on: "local", command).collect()
        }
        let grandchild = try #require(await ProcessFixture.awaitPid(at: pidFile))

        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        // The error surfaced only after exit: the group is already gone.
        #expect(await ProcessFixture.awaitDeath(of: grandchild))
        #expect(!ProcessFixture.exists(marker))
    }

    @Test("a signalled exit reports 128 plus the signal, as a shell would")
    func signalledExit() async throws {
        let result = try await LocalConduit().run(on: "local", "kill -9 $$").collect()
        #expect(result.exitStatus == 128 + SIGKILL)
        #expect(OwnedProcess.exitStatus(fromWaitStatus: 3 << 8) == 3)
        #expect(OwnedProcess.exitStatus(fromWaitStatus: SIGTERM) == 128 + SIGTERM)
    }

    @Test("a launch that fails throws launchFailed naming the executable")
    func launchFailure() {
        #expect(throws: ConduitError.self) {
            _ = try SSHConduit.spawn(executable: "/nonexistent/palana-binary", arguments: [])
        }
    }

    @Test("a replay's cancel is a no-op that still reports its status")
    func replayCancel() async {
        let replay = RunningCommand(replayingStdout: Data(), stderr: Data(), exitStatus: 4)
        replay.terminate()
        #expect(await replay.cancel() == 4)
    }

    @Test("output interleaves both channels — stdout may finish only after stderr was read")
    func outputInterleaves() async throws {
        let command = GatedCommand.make(stderrChunks: 3)
        var seen: [OutputChunk] = []
        for await chunk in command.running.output() {
            seen.append(chunk)
        }
        #expect(seen.filter { $0.channel == .stderr }.count == 3)
        #expect(seen.filter { $0.channel == .stdout }.count == 1)
        #expect(await command.running.exitStatus() == 2)
    }

    @Test("a cancelled output consumer terminates and reaps the whole group")
    func outputCancellationStopsTheGroup() async throws {
        // The merged stream used to cancel only its two pumps: the
        // consumer walked away and the child ran on to its side effect.
        let running = try await LocalConduit().run(on: "local", delayedSideEffect)
        let grandchild = try #require(await ProcessFixture.awaitPid(at: pidFile))
        let consumer = Task {
            for await _ in running.output() {}
        }
        consumer.cancel()
        await consumer.value

        #expect(await ProcessFixture.awaitDeath(of: grandchild), "the group went with the consumer")
        #expect(!ProcessFixture.exists(marker), "the side effect never happened")
        #expect(await running.exitStatus() == 128 + SIGTERM)
    }

    @Test("abandoning the merged stream mid-read stops the command too")
    func abandonedOutputStopsTheCommand() async throws {
        // The pid lands before the first chunk does, so the reader can
        // walk away the instant it has one and still name the child.
        let running = try await LocalConduit().run(
            on: "local",
            "\(ProcessFixture.recordPid(at: pidFile)); echo first; sleep 30; "
                + "touch \(ShellQuote.quote(marker.path))")
        for await chunk in running.output() {
            _ = chunk
            break  // the caller has what it wanted and walks away
        }
        let child = try #require(ProcessFixture.pid(at: pidFile))
        #expect(await ProcessFixture.awaitDeath(of: child))
        #expect(!ProcessFixture.exists(marker))
    }

    @Test("output over a live command carries both channels to end")
    func outputLive() async throws {
        let running = try await LocalConduit().run(on: "local", "echo out; echo err >&2; exit 3")
        var text: [OutputChannel: String] = [:]
        for await chunk in running.output() {
            text[chunk.channel, default: ""] += String(bytes: chunk.data, encoding: .utf8) ?? ""
        }
        #expect(text[.stdout] == "out\n")
        #expect(text[.stderr] == "err\n")
        #expect(await running.exitStatus() == 3)
    }
}

/// A command whose stdout cannot finish until its stderr has been consumed.
///
/// The shape of a child blocked writing stderr while its stdout is
/// still open. A reader that drains stdout to the end before touching
/// stderr never returns.
enum GatedCommand {
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            let resumed = waiters
            waiters = []
            for waiter in resumed {
                waiter.resume()
            }
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    struct Made {
        var running: RunningCommand
    }

    static func make(stderrChunks: Int, exitStatus: Int32 = 2) -> Made {
        let gate = Gate()
        let stdoutSent = Counter()
        let stdout = AsyncStream<Data> {
            if await stdoutSent.next() == 0 {
                return Data("out\n".utf8)
            }
            await gate.wait()
            return nil
        }
        let stderrSent = Counter()
        let stderr = AsyncStream<Data> {
            let index = await stderrSent.next()
            if index < stderrChunks {
                if index == stderrChunks - 1 {
                    await gate.open()
                }
                return Data("err \(index)\n".utf8)
            }
            return nil
        }
        return Made(
            running: RunningCommand(stdout: stdout, stderr: stderr) { exitStatus })
    }

    private actor Counter {
        private var value = 0

        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }
}
