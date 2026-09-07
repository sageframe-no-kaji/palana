// AddressRig — the pane the address suites drive. A remote door that
// records every command it is handed and answers only what the test
// scripted; a Field whose one host is already known GNU, so a remote
// pointing runs its probes and its listing and nothing else; local reads
// touch only temp directories this file makes and its callers remove.

import Foundation
import PalanaCore
import Testing

@testable import Palana

/// A remote door that records everything and answers scripted commands.
///
/// An unscripted command answers exit 1 with a `no such file` stderr —
/// the shape of a listing miss. A scripted one answers as written.
actor RecordingConduit: Conduit {
    /// One scripted answer.
    struct Answer: Sendable {
        let stdout: Data
        let stderr: Data
        let exitStatus: Int32
        /// How long the host takes to answer — nil answers at once.
        var delay: Duration?

        /// A command that succeeded with this output.
        static func success(_ stdout: String = "") -> Self {
            Self(stdout: Data(stdout.utf8), stderr: Data(), exitStatus: 0)
        }

        /// ssh's own failure — exit 255 with its verdict on stderr.
        static func sshFailure(_ stderr: String) -> Self {
            Self(stdout: Data(), stderr: Data(stderr.utf8), exitStatus: 255)
        }

        /// The same answer, arriving after `delay` — a read held in flight.
        func delayed(by delay: Duration) -> Self {
            var slow = self
            slow.delay = delay
            return slow
        }
    }

    private var answers: [String: Answer]
    private(set) var commands: [String] = []
    private(set) var hosts: [String] = []

    init(answers: [String: Answer] = [:]) {
        self.answers = answers
    }

    /// Scripts successful listings by command.
    init(listings: [String: Data]) {
        answers = listings.mapValues { Answer(stdout: $0, stderr: Data(), exitStatus: 0) }
    }

    /// Rescripts one command — what the host answers from now on.
    func script(_ command: String, _ answer: Answer) {
        answers[command] = answer
    }

    func run(on host: String, _ command: String) async throws -> RunningCommand {
        commands.append(command)
        hosts.append(host)
        guard let answer = answers[command] else {
            return RunningCommand(
                replayingStdout: Data(), stderr: Data("bash: no such file or directory".utf8), exitStatus: 1)
        }
        if let delay = answer.delay {
            try await Task.sleep(for: delay)
        }
        return RunningCommand(replayingStdout: answer.stdout, stderr: answer.stderr, exitStatus: answer.exitStatus)
    }

    func close(host: String) async {}
    func closeAll() async {}
}

/// A pane over a scripted remote host, with the cache file to remove after.
@MainActor
struct AddressRig {
    /// Scripted answers by command.
    typealias Answers = [String: RecordingConduit.Answer]

    /// The one remote host the rig knows.
    static let host = "koan"

    let conduit: RecordingConduit
    let pane: PaneModel
    let cacheURL: URL

    /// A pane over a GNU host whose capability is already known.
    init(answers: [String: RecordingConduit.Answer] = [:]) throws {
        let conduit = RecordingConduit(answers: answers)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-address-cache-\(UUID().uuidString).json")
        let cache = FieldCache(url: cacheURL)
        let capability = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: nil)
        try cache.save([Self.host: HostFacts(capability: Dated(value: capability, discoveredAt: Date()))])
        let field = Field(conduit: conduit, hosts: [Self.host], cache: cache)
        let engine = Engine(
            conduit: SSHConduit(configuration: SSHConfiguration()),
            field: field,
            listing: Listing(conduit: conduit))
        self.conduit = conduit
        self.pane = PaneModel(engine: engine)
        self.cacheURL = cacheURL
    }

    /// A pane already standing on the remote host at `/srv`.
    static func remote(answers: [String: RecordingConduit.Answer] = [:]) throws -> Self {
        let rig = try Self(answers: answers)
        rig.pane.state.host = host
        rig.pane.state.path = "/srv"
        return rig
    }

    /// Removes the cache file — call from a `defer`.
    func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    /// A fresh temp directory the caller removes.
    nonisolated static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-address-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The probe's scripted answer for one remote path.
    nonisolated static func probe(_ path: String, _ presence: PathPresence) -> (String, RecordingConduit.Answer) {
        let word =
            switch presence {
            case .directory: "directory"
            case .file: "file"
            case .absent: "absent"
            }
        return (Listing.presenceCommand(for: path), .success(word + "\n"))
    }

    /// A successful, empty GNU listing for one remote directory.
    nonisolated static func listing(_ path: String) -> (String, RecordingConduit.Answer) {
        (Listing.command(for: path, flavor: .gnu), .success())
    }

    /// Scripts probes and listings into one answer table.
    nonisolated static func answers(_ entries: [(String, RecordingConduit.Answer)]) -> Answers {
        Dictionary(entries) { _, last in last }
    }
}

/// Bounded main-actor poll — records an issue on timeout rather than hanging.
@MainActor
func poll(
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
