// PaneRefreshTests — the panes keep themselves current. A local pane
// watches its directory: a file that appears or vanishes shows up in the
// rows without anyone asking, the cursor stays put or steps to its nearest
// neighbor, and re-pointing or retiring the pane closes the descriptor. A
// remote pane re-lists on a poll, gated: never while the app is behind,
// never over a read in flight, never in zfs mode, never after a failure
// until the app comes back to the front. Every re-read is quiet — no
// `reading…`, no cursor move, no lost selection.
//
// Local cases run on temp directories this file makes and removes; remote
// cases drive the recording conduit, rescripting its answer between polls
// and pumping `pollTick()` directly so nothing waits on the interval.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// One GNU listing record per name — plain files, fixed times.
private func gnuListing(_ names: [String]) -> RecordingConduit.Answer {
    .success(names.map { "\($0)\0f\012\01700000000.0\01700000100.0\0644\0op\0op\0\0" }.joined())
}

private func id(_ name: String) -> Data { Data(name.utf8) }

/// Waits on an async condition — the descriptor counts live on a queue.
@MainActor
private func waitUntil(
    timeout: TimeInterval = 5, message: String, _ condition: () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while await !condition() {
        guard Date() < deadline else {
            Issue.record("\(message)")
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - Local: the directory watcher

@MainActor
@Suite("panes keep themselves current — the local watcher")
struct LocalPaneRefreshTests {
    /// A pane standing ready on a fresh temp directory holding `names`.
    private func pointedRig(names: [String]) async throws -> (AddressRig, URL) {
        let rig = try AddressRig()
        let directory = try AddressRig.makeTemporaryDirectory()
        for name in names {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        rig.pane.point(host: Engine.localHost, path: directory.path)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }
        return (rig, directory)
    }

    @Test("a file created in the watched directory appears within a second, unasked")
    func createdFileAppears() async throws {
        let (rig, directory) = try await pointedRig(names: ["alpha", "beta"])
        defer {
            rig.tearDown()
            try? FileManager.default.removeItem(at: directory)
        }
        #expect(rig.pane.rows.map(\.name) == ["alpha", "beta"])

        try Data("y".utf8).write(to: directory.appendingPathComponent("gamma"))
        try await poll(timeout: 1.5, message: "the new file never appeared") {
            rig.pane.rows.contains { $0.name == "gamma" }
        }

        #expect(rig.pane.rows.map(\.name) == ["alpha", "beta", "gamma"])
        #expect(rig.pane.status == .ready)
        #expect(rig.pane.isReading == false, "a quiet refresh never shows reading…")
        #expect(rig.pane.lastError == nil)
        #expect(await rig.conduit.commands.isEmpty, "nothing went over the wire")
    }

    @Test("deleting the cursor's file moves the cursor to its neighbor and keeps the rest of the selection")
    func deletedCursorFileRefootsCursor() async throws {
        let (rig, directory) = try await pointedRig(names: ["alpha", "beta", "gamma"])
        defer {
            rig.tearDown()
            try? FileManager.default.removeItem(at: directory)
        }
        rig.pane.state.cursor = id("beta")
        rig.pane.state.selection = [id("alpha"), id("beta")]

        try FileManager.default.removeItem(at: directory.appendingPathComponent("beta"))
        try await poll(timeout: 1.5, message: "the deleted file never left") {
            !rig.pane.rows.contains { $0.name == "beta" }
        }

        #expect(rig.pane.rows.map(\.name) == ["alpha", "gamma"])
        #expect(rig.pane.state.cursor == id("gamma"), "the cursor steps to the row that took beta's place")
        #expect(rig.pane.state.selection == [id("alpha")], "the surviving selection stays")
    }

    @Test("a refresh leaves the cursor and the selection exactly where they were")
    func refreshKeepsCursorAndSelection() async throws {
        let (rig, directory) = try await pointedRig(names: ["alpha", "beta", "gamma"])
        defer {
            rig.tearDown()
            try? FileManager.default.removeItem(at: directory)
        }
        rig.pane.state.cursor = id("beta")
        rig.pane.state.selection = [id("alpha"), id("gamma")]

        try Data("y".utf8).write(to: directory.appendingPathComponent("delta"))
        try await poll(timeout: 1.5, message: "the new file never appeared") {
            rig.pane.rows.contains { $0.name == "delta" }
        }

        #expect(rig.pane.state.cursor == id("beta"))
        #expect(rig.pane.state.selection == [id("alpha"), id("gamma")])
    }

    @Test("re-pointing closes the old watcher's descriptor and opens one on the new directory")
    func repointingClosesTheOldWatcher() async throws {
        let (rig, first) = try await pointedRig(names: ["alpha"])
        let second = try AddressRig.makeTemporaryDirectory()
        defer {
            rig.tearDown()
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let old = try #require(rig.pane.refresher.watcher)
        try await waitUntil(message: "the first watcher never opened") { await old.liveDescriptorCount() == 1 }

        rig.pane.point(host: Engine.localHost, path: second.path)
        try await poll(message: "the pane did not move") { rig.pane.state.path == second.path }

        let new = try #require(rig.pane.refresher.watcher)
        #expect(new !== old, "a new directory gets a new watcher")
        try await waitUntil(message: "the old descriptor never closed") { await old.liveDescriptorCount() == 0 }
        try await waitUntil(message: "the new watcher never opened") { await new.liveDescriptorCount() == 1 }
    }

    @Test("pointing at a remote host closes the local watcher")
    func remotePointingClosesTheWatcher() async throws {
        let listing = Listing.command(for: "/srv", flavor: .gnu)
        let rig = try AddressRig(answers: [listing: gnuListing(["alpha"])])
        let directory = try AddressRig.makeTemporaryDirectory()
        defer {
            rig.tearDown()
            try? FileManager.default.removeItem(at: directory)
        }
        rig.pane.point(host: Engine.localHost, path: directory.path)
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }
        let watcher = try #require(rig.pane.refresher.watcher)

        rig.pane.point(host: AddressRig.host, path: "/srv")
        try await poll(message: "the pane did not move") { rig.pane.state.host == AddressRig.host }

        #expect(rig.pane.refresher.watcher == nil)
        #expect(rig.pane.refresher.pollTask != nil, "a remote pane polls instead")
        try await waitUntil(message: "the descriptor never closed") { await watcher.liveDescriptorCount() == 0 }
    }

    @Test("retiring the pane closes its watcher")
    func retirementClosesTheWatcher() async throws {
        let directory = try AddressRig.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The optional is the one strong hold on the pane — dropping it retires the pane.
        var rig: AddressRig? = try AddressRig()
        let cacheURL = try #require(rig?.cacheURL)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        rig?.pane.point(host: Engine.localHost, path: directory.path)
        try await poll(message: "the pane did not land") { rig?.pane.status == .ready }
        let watcher = try #require(rig?.pane.refresher.watcher)
        try await waitUntil(message: "the watcher never opened") { await watcher.liveDescriptorCount() == 1 }

        rig = nil
        try await waitUntil(message: "the retired pane's descriptor never closed") {
            await watcher.liveDescriptorCount() == 0
        }
    }
}

// MARK: - Remote: the poll

@MainActor
@Suite("panes keep themselves current — the remote poll")
struct RemotePaneRefreshTests {
    private let host = AddressRig.host
    private let listing = Listing.command(for: "/srv", flavor: .gnu)

    /// A pane standing ready on the remote host at `/srv`, frontmost.
    private func pointedRig(
        names: [String] = ["alpha", "beta"], interval: Duration = .seconds(10)
    ) async throws -> AddressRig {
        let rig = try AddressRig(answers: [listing: gnuListing(names)])
        rig.pane.refreshPolicy.isAppActive = { true }
        rig.pane.refreshPolicy.pollInterval = interval
        rig.pane.point(host: host, path: "/srv")
        try await poll(message: "the pane did not land") { rig.pane.status == .ready }
        return rig
    }

    private func listings(_ rig: AddressRig) async -> Int {
        await rig.conduit.commands.filter { $0 == listing }.count
    }

    @Test("a poll issues one listing and the rows follow the host")
    func pollRelistsAndUpdatesRows() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }
        #expect(await listings(rig) == 1)

        await rig.conduit.script(listing, gnuListing(["alpha", "beta", "gamma"]))
        rig.pane.pollTick()
        try await poll(message: "the poll never landed") { rig.pane.rows.count == 3 }

        #expect(await listings(rig) == 2, "one poll, one listing")
        #expect(rig.pane.rows.map(\.name) == ["alpha", "beta", "gamma"])
        #expect(rig.pane.status == .ready)
        #expect(rig.pane.isReading == false, "a quiet refresh never shows reading…")
        #expect(rig.pane.lastError == nil)
    }

    @Test("the interval drives the poll on its own")
    func intervalDrivesThePoll() async throws {
        let rig = try await pointedRig(interval: .milliseconds(30))
        defer { rig.tearDown() }

        try await waitUntil(message: "the poll never ticked") { await self.listings(rig) >= 3 }
        #expect(rig.pane.status == .ready)
    }

    @Test("a refresh never moves the cursor while its entry still exists, and keeps the selection")
    func refreshKeepsCursor() async throws {
        let rig = try await pointedRig(names: ["alpha", "beta", "gamma"])
        defer { rig.tearDown() }
        rig.pane.state.cursor = id("beta")
        rig.pane.state.selection = [id("alpha"), id("gamma")]

        await rig.conduit.script(listing, gnuListing(["aardvark", "alpha", "beta", "gamma"]))
        rig.pane.pollTick()
        try await poll(message: "the poll never landed") { rig.pane.rows.count == 4 }

        #expect(rig.pane.state.cursor == id("beta"))
        #expect(rig.pane.state.selection == [id("alpha"), id("gamma")])
    }

    @Test("a vanished cursor entry hands the cursor to its neighbor")
    func vanishedCursorEntryRefoots() async throws {
        let rig = try await pointedRig(names: ["alpha", "beta", "gamma"])
        defer { rig.tearDown() }
        rig.pane.state.cursor = id("gamma")

        await rig.conduit.script(listing, gnuListing(["alpha", "beta"]))
        rig.pane.pollTick()
        try await poll(message: "the poll never landed") { rig.pane.rows.count == 2 }

        #expect(rig.pane.state.cursor == id("beta"), "the last row vanished — the cursor takes the new last")
    }

    @Test("no poll while a read is in flight")
    func noPollWhileReading() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }

        await rig.conduit.script(listing, gnuListing(["alpha", "beta", "gamma"]).delayed(by: .milliseconds(300)))
        rig.pane.apply(.refresh)
        #expect(rig.pane.isReading, "the loud refresh is in flight")
        rig.pane.pollTick()
        try await poll(message: "the loud refresh never settled") { !rig.pane.isReading }

        #expect(await listings(rig) == 2, "the loud refresh alone — the poll stood aside")
        #expect(rig.pane.rows.count == 3)
    }

    @Test("no poll while the app is behind")
    func noPollWhileInactive() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }
        rig.pane.refreshPolicy.isAppActive = { false }

        rig.pane.pollTick()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await listings(rig) == 1, "nothing went over the wire while the app was behind")
    }

    @Test("no poll in zfs mode")
    func noPollInZFSMode() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }
        rig.pane.enterZFSMode()

        rig.pane.pollTick()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await listings(rig) == 1)
    }

    @Test("a failed poll keeps the rows, posts the banner, and stands down until the app comes back")
    func failedPollKeepsRowsAndStandsDown() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }
        rig.pane.state.cursor = id("alpha")

        await rig.conduit.script(listing, .sshFailure("ssh: connect to host koan port 22: No route to host"))
        rig.pane.pollTick()
        try await poll(message: "the failure never posted") { rig.pane.lastError != nil }

        #expect(rig.pane.rows.map(\.name) == ["alpha", "beta"], "the listing stands")
        #expect(rig.pane.status == .ready)
        #expect(rig.pane.state.cursor == id("alpha"))
        #expect(rig.pane.isReading == false)
        #expect(rig.pane.refreshPolicy.suspended)

        rig.pane.pollTick()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await listings(rig) == 2, "no further poll while the failure stands")

        await rig.conduit.script(listing, gnuListing(["alpha", "beta", "gamma"]))
        rig.pane.applicationDidBecomeActive()
        try await poll(message: "the activation never re-listed") { rig.pane.rows.count == 3 }
        #expect(rig.pane.lastError == nil, "the next success clears the banner")
        #expect(rig.pane.refreshPolicy.suspended == false)
    }

    @Test("a loud read after a failed poll lifts the stand-down")
    func loudReadLiftsSuspension() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }

        await rig.conduit.script(listing, .sshFailure("no route"))
        rig.pane.pollTick()
        try await poll(message: "the failure never posted") { rig.pane.lastError != nil }
        #expect(rig.pane.refreshPolicy.suspended)

        await rig.conduit.script(listing, gnuListing(["alpha"]))
        rig.pane.apply(.refresh)
        try await poll(message: "the refresh never landed") { rig.pane.rows.count == 1 }

        #expect(rig.pane.refreshPolicy.suspended == false)
        #expect(rig.pane.lastError == nil)
    }

    @Test("coming to the front re-lists a remote pane once, at once")
    func activationRelistsOnce() async throws {
        let rig = try await pointedRig()
        defer { rig.tearDown() }

        rig.pane.applicationDidBecomeActive()
        try await waitUntil(message: "the activation never re-listed") { await self.listings(rig) == 2 }
        try await Task.sleep(for: .milliseconds(100))

        #expect(await listings(rig) == 2)
    }
}
