// The enactment vocabulary. The system design's claim — "these are the
// commands," checkable by watching them run — is this stream. Every
// command, every byte of real output, every verification, live.

import Foundation

/// Which output stream a chunk came from.
public enum OutputChannel: String, Sendable, Codable {
    /// The command's standard output.
    case stdout
    /// The command's standard error.
    case stderr
}

/// A progress observation during a transfer step.
public struct ProgressReport: Sendable, Equatable {
    /// Bytes moved so far, as the transport reports or counts them.
    public var bytesTransferred: Int64
    /// Completed fraction, when it can be stated honestly — an
    /// indeterminate bar beats a wrong one.
    public var fraction: Double?
    /// The raw progress line, when a tool emitted one.
    public var rawLine: String

    /// Assembles a report.
    public init(bytesTransferred: Int64, fraction: Double? = nil, rawLine: String = "") {
        self.bytesTransferred = bytesTransferred
        self.fraction = fraction
        self.rawLine = rawLine
    }
}

/// The count check that releases gated steps.
public struct VerificationReport: Sendable, Equatable {
    /// Entries found under the source selection.
    public var sourceCount: Int
    /// Entries found under the transplanted names at the destination.
    public var destinationCount: Int

    /// Assembles a report.
    public init(sourceCount: Int, destinationCount: Int) {
        self.sourceCount = sourceCount
        self.destinationCount = destinationCount
    }

    /// The gate's condition.
    public var matched: Bool { sourceCount == destinationCount }
}

/// What enactment emits, in order, as it happens.
public enum EnactmentEvent: Sendable, Equatable {
    /// A plan step is starting — the exact command rides along.
    case stepBegan(index: Int, step: PlanStep)
    /// Real output from a running step, live. The panel's echo.
    case outputChunk(stepIndex: Int, channel: OutputChannel, data: Data)
    /// A progress observation.
    case progress(ProgressReport)
    /// A verification command running — visible like everything else.
    case verifying(host: String, command: String)
    /// The count check's result.
    case verified(VerificationReport)
    /// A step finished with this status.
    case stepEnded(index: Int, exitStatus: Int32)
    /// The whole plan enacted.
    case finished
}

/// Why enactment stopped.
public enum EnactmentError: Error, Sendable, Equatable {
    /// A step exited nonzero. Gated steps stay closed.
    case stepFailed(index: Int, exitStatus: Int32, stderrTail: String)
    /// Counts did not match. Gated steps never ran — a move that cannot
    /// prove its copy landed does not delete anything.
    case verificationFailed(VerificationReport)
    /// The plan's shape was not one enactment knows — typed, loud.
    case malformedPlan(String)
    /// A count command itself failed — the gate cannot decide, so it
    /// stays closed.
    case verificationUnavailable(host: String, detail: String)
    /// A transport this half does not carry. ho-06.2 lifts it.
    case unsupportedTransport(Transport)
}
