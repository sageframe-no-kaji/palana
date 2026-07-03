// RunningCommand and the collect path — drain, exit, taxonomy application.

import Foundation
import Testing

@testable import PalanaCore

@Suite("RunningCommand")
struct RunningCommandTests {
    private func chunked(_ pieces: [String]) -> AsyncStream<Data> {
        AsyncStream { continuation in
            for piece in pieces {
                continuation.yield(Data(piece.utf8))
            }
            continuation.finish()
        }
    }

    @Test("collect drains multi-chunk streams in order")
    func collectDrains() async throws {
        let command = RunningCommand(
            stdout: chunked(["hello ", "palana", "\n"]),
            stderr: chunked(["warning: ", "noise"])
        ) { 0 }
        let result = try await command.collect()
        #expect(result.stdoutText == "hello palana\n")
        #expect(result.stderrText == "warning: noise")
        #expect(result.exitStatus == 0)
    }

    @Test("a nonzero remote exit collects as data, not error")
    func nonzeroIsData() async throws {
        let command = RunningCommand(replayingStdout: Data(), stderr: Data(), exitStatus: 7)
        let result = try await command.collect()
        #expect(result.exitStatus == 7)
    }

    @Test("a 255 with recognizable stderr throws the classified error")
    func collectAppliesTaxonomy() async {
        let command = RunningCommand(
            replayingStdout: Data(),
            stderr: Data("ssh: connect to host jodo port 22: Connection refused".utf8),
            exitStatus: 255
        )
        await #expect(throws: ConduitError.self) {
            _ = try await command.collect()
        }
    }

    @Test("replay init yields the exact bytes")
    func replayInit() async throws {
        let stdout = Data("exact bytes\n".utf8)
        let command = RunningCommand(replayingStdout: stdout, stderr: Data(), exitStatus: 0)
        let result = try await command.collect()
        #expect(result.stdout == stdout)
        #expect(result.stderr.isEmpty)
    }
}
