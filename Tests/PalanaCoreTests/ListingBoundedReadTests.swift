// Bounded reads — the ceiling holds on the bytes as they arrive, not on
// what the listing said. A stream that grows past the limit is refused
// at limit plus one byte with its command terminated; a stalled stream
// times out the same way; a cancelled reader stops the process before
// it reports cancellation. One case runs a real child (`cat /dev/zero`)
// so the termination is a process going away, not a flag.

import CryptoKit
import Foundation
import Testing

@testable import PalanaCore

// MARK: - A conduit whose one command streams on demand

/// The producer's shared state — what the test observes.
private actor StreamState {
    private(set) var terminated = false
    private(set) var stalled = false
    private(set) var chunksSent = 0
    private var exitStatus: Int32?
    private var terminateWaiters: [CheckedContinuation<Void, Never>] = []
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []

    func terminate() {
        terminated = true
        for waiter in terminateWaiters { waiter.resume() }
        terminateWaiters.removeAll()
    }

    func waitForTerminate() async {
        stalled = true
        guard !terminated else { return }
        await withCheckedContinuation { terminateWaiters.append($0) }
    }

    func sent() { chunksSent += 1 }

    func finish(status: Int32) {
        exitStatus = status
        for waiter in exitWaiters { waiter.resume(returning: status) }
        exitWaiters.removeAll()
    }

    func awaitExit() async -> Int32 {
        if let exitStatus { return exitStatus }
        return await withCheckedContinuation { exitWaiters.append($0) }
    }
}

/// A conduit that answers every command with one shaped stdout stream.
///
/// `finite` yields `count` chunks and exits 0. `endless` yields the chunk
/// until terminated — a file that never stops growing. `stallAfter` yields
/// `count` chunks and then holds the stream open until terminated — a read
/// that hangs. Termination ends the stream and exits 143, as SIGTERM would.
private struct StreamingConduit: Conduit {
    enum Shape { case finite, endless, stallAfter }

    let chunk: Data
    let count: Int
    let shape: Shape
    let state = StreamState()

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        let state = state
        let chunk = chunk
        let count = count
        let shape = shape
        let stdout = AsyncStream<Data> { continuation in
            Task {
                var sent = 0
                while !(await state.terminated) {
                    if shape != .endless, sent == count { break }
                    continuation.yield(chunk)
                    sent += 1
                    await state.sent()
                    await Task.yield()
                }
                if shape == .stallAfter { await state.waitForTerminate() }
                continuation.finish()
                await state.finish(status: (await state.terminated) ? 128 + SIGTERM : 0)
            }
        }
        let stderr = AsyncStream<Data> { $0.finish() }
        return RunningCommand(
            stdout: stdout,
            stderr: stderr,
            exitStatus: { await state.awaitExit() },
            terminate: { _ in Task { await state.terminate() } })
    }

    func close(host: String) async {}
    func closeAll() async {}
}

/// Wraps a live conduit and keeps the last command it handed out.
private actor SpyConduit: Conduit {
    private let inner: any Conduit
    private(set) var last: RunningCommand?

    init(inner: any Conduit) {
        self.inner = inner
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        let running = try await inner.run(on: host, command)
        last = running
        return running
    }

    func close(host: String) async {}
    func closeAll() async {}
}

// MARK: - The ceiling on the bytes

@Suite("Listing bounded reads")
struct ListingBoundedReadTests {
    private let path = "/srv/grows.bin"
    private let kilobyte = Data(repeating: 0x41, count: 1024)

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-bounded-\(UUID().uuidString)")
    }

    @Test("a stream that keeps growing is refused at the ceiling with its command terminated")
    func growingStreamRefused() async throws {
        let conduit = StreamingConduit(chunk: kilobyte, count: 0, shape: .endless)
        let listing = Listing(conduit: conduit)
        await #expect(throws: ListingError.exceedsLimit(path: path, limit: 4096)) {
            _ = try await listing.readFile(on: "h", path: path, limit: 4096)
        }
        #expect(await conduit.state.terminated, "the command must be stopped, not drained forever")
    }

    @Test("a growing stream fetched to disk leaves no partial file behind")
    func growingFetchLeavesNothing() async throws {
        let conduit = StreamingConduit(chunk: kilobyte, count: 0, shape: .endless)
        let destination = tempFile()
        await #expect(throws: ListingError.exceedsLimit(path: path, limit: 4096)) {
            _ = try await Listing(conduit: conduit).fetchFile(on: "h", path: path, to: destination, limit: 4096)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(await conduit.state.terminated)
    }

    @Test("exactly the ceiling passes; one chunk more is refused even when the command exits cleanly")
    func ceilingIsInclusive() async throws {
        let atLimit = StreamingConduit(chunk: kilobyte, count: 4, shape: .finite)
        let data = try await Listing(conduit: atLimit).readFile(on: "h", path: path, limit: 4096)
        #expect(data.count == 4096)
        #expect(!(await atLimit.state.terminated))

        let past = StreamingConduit(chunk: kilobyte, count: 5, shape: .finite)
        await #expect(throws: ListingError.exceedsLimit(path: path, limit: 4096)) {
            _ = try await Listing(conduit: past).readFile(on: "h", path: path, limit: 4096)
        }
        #expect(await past.state.terminated)
    }

    @Test("a fetch writes the bytes as they arrive and digests them the way a whole read would")
    func fetchWritesAndDigests() async throws {
        let conduit = StreamingConduit(chunk: kilobyte, count: 3, shape: .finite)
        let destination = tempFile()
        defer { try? FileManager.default.removeItem(at: destination) }
        let fetched = try await Listing(conduit: conduit)
            .fetchFile(on: "h", path: path, to: destination, limit: 4096)
        let onDisk = try Data(contentsOf: destination)
        #expect(fetched.byteCount == 3072)
        #expect(onDisk == kilobyte + kilobyte + kilobyte)
        #expect(fetched.digest == RoundTrip.digest(of: onDisk))
    }

    @Test("a stalled read times out with its command terminated")
    func stalledReadTimesOut() async throws {
        let conduit = StreamingConduit(chunk: kilobyte, count: 1, shape: .stallAfter)
        await #expect(throws: ListingError.timedOut(path: path)) {
            _ = try await Listing(conduit: conduit)
                .readFile(on: "h", path: path, limit: 4096, timeout: .milliseconds(150))
        }
        #expect(await conduit.state.terminated)
    }

    @Test("cancelling the reader under the cap terminates the command before reporting cancellation")
    func cancellationTerminates() async throws {
        let conduit = StreamingConduit(chunk: kilobyte, count: 2, shape: .stallAfter)
        let reader = Task {
            try await Listing(conduit: conduit).readFile(on: "h", path: path, limit: 4096)
        }
        var stalled = false
        for _ in 0..<200 where !stalled {
            stalled = await conduit.state.stalled
            if !stalled { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(stalled, "the stream reached its stall under the cap")
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(await conduit.state.terminated, "cancellation must stop the process")
    }

    @Test("a sink that fails mid-stream stops the command instead of streaming into the failure")
    func sinkFailureTerminates() async throws {
        struct DiskFull: Error {}
        let conduit = StreamingConduit(chunk: kilobyte, count: 3, shape: .stallAfter)
        let listing = Listing(conduit: conduit)
        await #expect(throws: DiskFull.self) {
            _ = try await listing.stream(
                on: "h",
                path: path,
                command: Listing.readFileCommand(for: path),
                bounds: Listing.ReadBounds(limit: 65536, timeout: .seconds(30))
            ) { _ in throw DiskFull() }
        }
        #expect(await conduit.state.terminated, "the command must not run on after the sink failed")
    }

    @Test("a nonzero exit still classifies through the stream")
    func nonzeroExitClassifies() async {
        let transcript = ConduitTranscript(entries: [
            .init(
                host: "h",
                command: Listing.readFileCommand(for: path),
                stdout: "",
                stderr: "cat: \(path): Permission denied",
                exit: 1)
        ])
        let listing = Listing(conduit: RecordedConduit(transcript: transcript))
        await #expect(throws: ListingError.permissionDenied(path: path)) {
            _ = try await listing.readFile(on: "h", path: path)
        }
    }

    @Test("a door failure is the conduit's error, not a listing error")
    func doorFailureIsConduitError() async {
        let transcript = ConduitTranscript(entries: [
            .init(
                host: "h",
                command: Listing.readFileCommand(for: path),
                stdout: "",
                stderr: "ssh: connect to host h port 22: Connection refused",
                exit: 255)
        ])
        let listing = Listing(conduit: RecordedConduit(transcript: transcript))
        await #expect(throws: ConduitError.self) {
            _ = try await listing.readFile(on: "h", path: path)
        }
    }

    @Test("a capped head read enforces its limit locally too")
    func headEnforcesLocally() async throws {
        let conduit = StreamingConduit(chunk: kilobyte, count: 2, shape: .finite)
        await #expect(throws: ListingError.exceedsLimit(path: path, limit: 1024)) {
            _ = try await Listing(conduit: conduit).readFileHead(on: "h", path: path, limit: 1024)
        }
    }

    @Test("an oversize read terminates a real child — cat /dev/zero goes away")
    func liveChildTerminated() async throws {
        let spy = SpyConduit(inner: LocalConduit())
        let listing = Listing(conduit: spy)
        let destination = tempFile()
        await #expect(throws: ListingError.exceedsLimit(path: "/dev/zero", limit: 65536)) {
            _ = try await listing.fetchFile(on: "local", path: "/dev/zero", to: destination, limit: 65536)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let running = try #require(await spy.last)
        // Exit resolves only once the process is gone — an un-terminated
        // cat of /dev/zero would hold this open forever.
        let status = await running.exitStatus()
        #expect(status == 128 + SIGTERM, "the child died of the signal the ceiling sent")
    }
}
