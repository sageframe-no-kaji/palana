// The test seam's own tests: playback fidelity, miss behavior, JSON
// round-trip, and the recorder wrapping a conduit.

import Foundation
import Testing

@testable import PalanaCore

@Suite("RecordedConduit")
struct RecordedConduitTests {
    private let transcript = ConduitTranscript(entries: [
        .init(
            host: "jodo",
            command: "zfs list -H",
            stdout: "tank\t1.2T\t...\n",
            stderr: "",
            exit: 0),
        .init(host: "jodo", command: "false", stdout: "", stderr: "", exit: 1),
        .init(
            host: "gone",
            command: "true",
            stdout: "",
            stderr: "ssh: connect to host gone port 22: Connection refused",
            exit: 255),
    ])

    @Test("playback returns the recorded bytes and status")
    func playback() async throws {
        let conduit = RecordedConduit(transcript: transcript)
        let result = try await conduit.run(on: "jodo", "zfs list -H").collect()
        #expect(result.stdoutText == "tank\t1.2T\t...\n")
        #expect(result.exitStatus == 0)
    }

    @Test("a recorded failure replays through the taxonomy")
    func failureReplays() async throws {
        let conduit = RecordedConduit(transcript: transcript)
        let command = try await conduit.run(on: "gone", "true")
        await #expect(throws: ConduitError.self) {
            _ = try await command.collect()
        }
    }

    @Test("a miss names the unmatched command — no silent fallthrough")
    func missThrows() async {
        let conduit = RecordedConduit(transcript: transcript)
        await #expect(throws: UnrecordedCommand(host: "jodo", command: "uname")) {
            _ = try await conduit.run(on: "jodo", "uname")
        }
    }

    @Test("transcripts round-trip through JSON on disk")
    func jsonRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-transcript-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try transcript.write(to: url)
        let loaded = try ConduitTranscript(contentsOf: url)
        #expect(loaded == transcript)
    }

    @Test("the recorder captures exchanges and re-emits results unchanged")
    func recorderCaptures() async throws {
        let recorder = RecordingConduit(wrapping: RecordedConduit(transcript: transcript))
        let result = try await recorder.run(on: "jodo", "zfs list -H").collect()
        #expect(result.stdoutText == "tank\t1.2T\t...\n")

        let command = try await recorder.run(on: "jodo", "false")
        let failure = try await command.collect()
        #expect(failure.exitStatus == 1)

        let captured = await recorder.transcript()
        #expect(captured.entries.count == 2)
        #expect(captured.entries[0].command == "zfs list -H")
        #expect(captured.entries[1].exit == 1)
    }

    @Test("the recorder records door-level failures before they throw downstream")
    func recorderCapturesFailures() async throws {
        let recorder = RecordingConduit(wrapping: RecordedConduit(transcript: transcript))
        let command = try await recorder.run(on: "gone", "true")
        _ = try? await command.collect()
        let captured = await recorder.transcript()
        #expect(captured.entries.count == 1)
        #expect(captured.entries[0].exit == 255)
    }
}

@Suite("RecordedConduit conveniences")
struct RecordedConduitConvenienceTests {
    @Test("load-from-disk init, recorder write, and the no-op lifecycle paths")
    func conveniences() async throws {
        let transcript = ConduitTranscript(entries: [
            .init(host: "jodo", command: "true", stdout: "", stderr: "", exit: 0)
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-conv-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = RecordingConduit(wrapping: RecordedConduit(transcript: transcript))
        _ = try await recorder.run(on: "jodo", "true").collect()
        try await recorder.write(to: url)
        await recorder.close(host: "jodo")
        await recorder.closeAll()

        let loaded = try RecordedConduit(contentsOf: url)
        let result = try await loaded.run(on: "jodo", "true").collect()
        #expect(result.exitStatus == 0)
        await loaded.close(host: "jodo")
        await loaded.closeAll()
    }
}
