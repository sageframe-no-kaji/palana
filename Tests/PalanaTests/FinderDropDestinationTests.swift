// Finder drops bind to the destination that received them. The drop's
// host and directory are read synchronously at the drop; the source
// listing that resolves the cohort is an await, and a pane that moves
// during it must not move the plan. Local temp directories only — the
// source listing is this Mac's `find`, read-only.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// A box the injected closures can write to across the `@Sendable` boundary.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// What the begin seam received.
private struct Resolved {
    var source: Locus
    var destination: Locus
    var entries: [FileEntry]
}

@MainActor
@Suite("Finder drop — destination bound at the drop")
struct FinderDropDestinationTests {
    private let root: URL
    private let sourceDirectory: URL
    private let destinationDirectory: URL
    private let dropped: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-finder-drop-\(UUID().uuidString.prefix(8))", isDirectory: true)
        sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        destinationDirectory = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        dropped = sourceDirectory.appendingPathComponent("dropped.txt")
        try Data("payload".utf8).write(to: dropped)
    }

    private func makeEngine() -> Engine {
        let recorded = RecordedConduit(transcript: ConduitTranscript())
        let field = Field(conduit: recorded, hosts: ["test-host"], cache: FieldCache())
        return Engine(
            conduit: SSHConduit(configuration: SSHConfiguration()),
            field: field,
            listing: Listing(conduit: recorded))
    }

    private func makeOperation(engine: Engine) -> OperationModel {
        let settings = SettingsModel(
            configURL: URL(fileURLWithPath: "/dev/null/impossible/config"),
            settingsURL: URL(fileURLWithPath: "/dev/null/impossible/settings.json"))
        return OperationModel(
            engine: engine,
            configuration: SSHConfiguration(),
            settings: settings,
            log: OperationLog(url: root.appendingPathComponent("operations.log")))
    }

    @Test("the plan targets where the drop landed, not where the pane went during resolution")
    func destinationSurvivesNavigation() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = makeEngine()
        let operation = makeOperation(engine: engine)
        let pane = PaneModel(engine: engine)
        pane.point(host: PalanaCore.localHostName, path: destinationDirectory.path)
        try await poll(message: "the destination pane never became ready") {
            pane.status == .ready && pane.state.path == destinationDirectory.path
        }

        let captured = Box<Resolved?>(nil)
        routeFinderDrop(
            urls: [dropped],
            targetPane: pane,
            engine: engine,
            operation: operation,
            moveHeld: false
        ) { _, source, destination, entries in
            captured.value = Resolved(source: source, destination: destination, entries: entries)
        }
        // The pane moves on before the source listing has resolved.
        pane.state.path = "/somewhere/else"

        try await poll(message: "the drop never resolved") { captured.value != nil }
        let resolved = try #require(captured.value)
        #expect(
            resolved.destination == Locus(host: PalanaCore.localHostName, directory: destinationDirectory.path),
            "the destination is the one that received the drop")
        #expect(resolved.source == Locus(host: PalanaCore.localHostName, directory: sourceDirectory.path))
        #expect(resolved.entries.map(\.nameData) == [Data("dropped.txt".utf8)])
    }

    @Test("a folder-row drop binds to the folder's path at the drop")
    func folderRowDestinationBound() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = makeEngine()
        let operation = makeOperation(engine: engine)
        let pane = PaneModel(engine: engine)
        pane.point(host: PalanaCore.localHostName, path: destinationDirectory.path)
        try await poll(message: "the destination pane never became ready") { pane.status == .ready }

        let folder = destinationDirectory.appendingPathComponent("inside").path
        let captured = Box<Locus?>(nil)
        routeFinderDrop(
            urls: [dropped],
            targetPane: pane,
            engine: engine,
            operation: operation,
            moveHeld: true,
            destinationDirectory: folder
        ) { planOperation, _, destination, _ in
            #expect(planOperation == .move, "⌘ held escalates to a move")
            captured.value = destination
        }
        pane.state.path = "/elsewhere"

        try await poll(message: "the drop never resolved") { captured.value != nil }
        #expect(captured.value == Locus(host: PalanaCore.localHostName, directory: folder))
    }

    @Test("a pane that is not ready offers no destination, and the drop says so")
    func unreadyPaneRefuses() {
        let engine = makeEngine()
        let pane = PaneModel(engine: engine)
        #expect(finderDropDestination(targetPane: pane, destinationDirectory: nil) == nil)

        let operation = makeOperation(engine: engine)
        let began = Box(false)
        routeFinderDrop(
            urls: [dropped],
            targetPane: pane,
            engine: engine,
            operation: operation,
            moveHeld: false
        ) { _, _, _, _ in began.value = true }
        #expect(!began.value)
        try? FileManager.default.removeItem(at: root)
    }

    /// Bounded main-actor poll — records an issue on timeout rather than hanging.
    private func poll(
        timeout: TimeInterval = 5,
        message: String,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("\(message)")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
