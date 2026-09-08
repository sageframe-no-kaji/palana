// Workbench reads in the transcript — the strip's read verbs land
// here without a plan or a phase. Both channels drain as they arrive
// and the exit is awaited, so a read that fills stderr cannot wedge
// and a read that fails says so.

import Foundation
import PalanaCore

// MARK: - Tool reads

extension OperationModel {
    /// Writes a Workbench read into the transcript without changing phase.
    ///
    /// The strip's scrollback — successive reads accumulate; `begin` resets
    /// `echo` when a real operation starts so the plan's claim is never blurred.
    ///
    /// Both channels drain as they arrive — neither waits on the other,
    /// so a command that fills stderr while stdout is open cannot wedge
    /// the read. The exit is awaited; a nonzero status is written as a
    /// failure line carrying the tail of what stderr said.
    func runToolRead(header: String, stream: RunningCommand) async {
        showPanel()
        echo.appendLine("── \(header)", kind: .note)
        var errorTail = Data()
        // The exit is awaited inside the cancellation handler, so a
        // cancelled read returns only once its command has gone. Before
        // this the reader walked away and left the child running
        // (2026-09-08 audit).
        let status = await withTaskCancellationHandler {
            for await chunk in stream.output() {
                echo.append(chunk.data, channel: chunk.channel)
                if chunk.channel == .stderr {
                    errorTail.append(chunk.data)
                    if errorTail.count > Self.errorTailLimit {
                        errorTail = errorTail.suffix(Self.errorTailLimit)
                    }
                }
            }
            return await stream.exitStatus()
        } onCancel: {
            stream.terminate()
        }
        echo.flushAll()
        guard !Task.isCancelled else { return }
        guard status != 0 else { return }
        // Lossy decode on purpose: the tail shows what arrived.
        // swiftlint:disable:next optional_data_string_conversion
        let tail = String(decoding: errorTail, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lastLine = tail.split(separator: "\n").last.map(String.init) ?? ""
        echo.appendLine(
            "read failed (exit \(status))\(lastLine.isEmpty ? "" : ": \(lastLine)")",
            kind: .failure)
    }

    /// How much stderr a read keeps for its failure line.
    private static let errorTailLimit = 4096

    /// Writes a tool-level failure into the transcript without changing phase.
    func appendToolError(_ text: String) {
        showPanel()
        echo.appendLine(text, kind: .failure)
    }

    /// ⌘K — clears the terminal transcript, phase untouched.
    func clearTranscript() {
        echo = EchoBuffer()
    }
}
