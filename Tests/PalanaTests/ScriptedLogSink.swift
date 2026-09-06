// A log sink whose every step can be told to fail — the disk-full and
// permission failures OperationLog must survive, produced on demand and
// nowhere near the operator's application-support directory.

import Foundation

@testable import Palana

/// A sink that records what the log asked of it and fails where told.
final class ScriptedLogSink: OperationLogSink {
    /// The failure a scripted step throws.
    struct Scripted: Error, LocalizedError {
        let step: String
        var errorDescription: String? { "scripted \(step) failure" }
    }

    var failSeek = false
    var failWrite = false
    var failFlush = false
    var failClose = false

    private(set) var written = Data()
    private(set) var seekCount = 0
    private(set) var synchronizeCount = 0
    private(set) var closeCount = 0

    /// Everything written so far, as text.
    var text: String { String(data: written, encoding: .utf8) ?? "" }

    func seekToEnd() throws -> UInt64 {
        seekCount += 1
        if failSeek { throw Scripted(step: "seek") }
        return UInt64(written.count)
    }

    func write(contentsOf data: Data) throws {
        if failWrite { throw Scripted(step: "write") }
        written.append(data)
    }

    func synchronize() throws {
        synchronizeCount += 1
        if failFlush { throw Scripted(step: "flush") }
    }

    func close() throws {
        closeCount += 1
        if failClose { throw Scripted(step: "close") }
    }
}
