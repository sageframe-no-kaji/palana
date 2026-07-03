// Minimal SSH execution for the spike. One command, streams drained
// concurrently per the ho-00 primer. Not the Conduit — ho-02 builds that.

import Foundation

public enum SpikeError: Error {
    case commandFailed(Int32, String)
}

public struct SpikeConduit {
    public init(identity: String, knownHosts: String, port: Int, destination: String) {
        self.identity = identity
        self.knownHosts = knownHosts
        self.port = port
        self.destination = destination
    }

    public let identity: String
    let knownHosts: String
    let port: Int
    let destination: String

    public func run(_ command: String) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-i", identity,
            "-p", String(port),
            "-o", "BatchMode=yes",
            "-o", "UserKnownHostsFile=\(knownHosts)",
            "-o", "StrictHostKeyChecking=accept-new",
            destination,
            command,
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Termination handler set before run — no race against a fast exit.
        let (exitStream, exitCont) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { proc in
            exitCont.yield(proc.terminationStatus)
            exitCont.finish()
        }
        try process.run()

        // Drain both pipes concurrently BEFORE awaiting exit — pipe buffers
        // are ~64KB and the listing is larger. See ho-00 primer.
        async let outData = Self.readAll(stdout.fileHandleForReading)
        async let errData = Self.readAll(stderr.fileHandleForReading)

        var status: Int32 = -1
        for await code in exitStream { status = code }
        let out = await outData
        let err = await errData

        guard status == 0 else {
            throw SpikeError.commandFailed(status, String(data: err, encoding: .utf8) ?? "")
        }
        return out
    }

    // NOT FileHandle.bytes: its iterator issues a blocking read() on a
    // cooperative-pool thread, and with two pipes to drain the second
    // reader starved while ssh blocked writing into a full pipe —
    // observed deadlock, ho-01. readabilityHandler runs on its own
    // dispatch queue and EOF arrives as empty availableData.
    private static func readAll(_ handle: FileHandle) async -> Data {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(chunk)
            }
        }
        var data = Data()
        for await chunk in stream {
            data.append(chunk)
        }
        return data
    }
}
