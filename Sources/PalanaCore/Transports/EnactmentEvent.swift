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

/// The check that releases gated steps — shaped per transport.
///
/// File transfers manifest both ends — every object's kind, size, link
/// target, and SHA-256 — and the gate opens only when every source
/// entry is carried identically at the destination. A zfs stream is
/// checksummed end to end by zfs itself, so a clean receive IS the
/// byte verification and the gate's question becomes existence.
public enum VerificationReport: Sendable, Equatable {
    /// The selection manifested under the source and its transplanted
    /// names at the destination.
    case manifests(source: TransferManifest, destination: TransferManifest)
    /// The received dataset, present or not, on the destination.
    case datasetReceived(name: String, exists: Bool)

    /// The gate's condition.
    ///
    /// The subset rule: every source entry present at the destination
    /// with the same kind, size, link target, and digest. Entries only
    /// the destination holds — what stood in a merged directory before
    /// the copy — are not a mismatch; the delete still removes nothing
    /// whose bytes were not proven at the destination. An empty source
    /// manifest proves nothing — a selection is never empty, so it is
    /// not a match.
    public var matched: Bool {
        switch self {
        case .manifests(let source, let destination):
            !source.entries.isEmpty && source.firstUnmatched(in: destination) == nil
        case .datasetReceived(_, let exists):
            exists
        }
    }
}

/// Data an operation left behind, or put back, and exactly where.
///
/// Neither an error nor an outcome: the sentence that keeps bytes
/// findable when a commit refused, a quarantine could not be released,
/// or a displaced version turned out not to be the one that was
/// checked. Never swallowed — every note reaches the transcript and
/// the run record.
public struct RecoveryNote: Sendable, Equatable {
    /// What happened to the data.
    public enum Kind: String, Sendable, Equatable {
        /// Kept at a named path, for the operator to recover.
        case retained
        /// Put back where it was before the operation touched it.
        case restored
    }

    /// Retained or restored.
    public var kind: Kind
    /// The host the data lives on.
    public var host: String
    /// The sentence — the path and why it is there.
    public var detail: String

    /// Records one note.
    ///
    /// - Parameters:
    ///   - kind: Retained or restored.
    ///   - host: The host the data lives on.
    ///   - detail: The path and the reason, in a sentence.
    public init(kind: Kind, host: String, detail: String) {
        self.kind = kind
        self.host = host
        self.detail = detail
    }

    /// The marker a composed program writes ahead of a retention line.
    public static let retainedMarker = "palana-retained: "
    /// The marker a composed program writes ahead of a restoration line.
    public static let restoredMarker = "palana-restored: "

    /// The notes a step's standard error carries, in order.
    ///
    /// Composed programs speak their recovery truth through these two
    /// markers so enactment can lift it into a typed event rather than
    /// leaving it in a wall of output.
    ///
    /// - Parameters:
    ///   - text: The step's standard error, decoded.
    ///   - host: The host the step ran on.
    /// - Returns: One note per marked line.
    public static func notes(in text: String, host: String) -> [Self] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(retainedMarker) {
                return Self(kind: .retained, host: host, detail: String(trimmed.dropFirst(retainedMarker.count)))
            }
            if trimmed.hasPrefix(restoredMarker) {
                return Self(kind: .restored, host: host, detail: String(trimmed.dropFirst(restoredMarker.count)))
            }
            return nil
        }
    }
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
    /// The verification's result.
    case verified(VerificationReport)
    /// A step finished with this status.
    case stepEnded(index: Int, exitStatus: Int32)
    /// Data retained for recovery, or put back where it was.
    case recovery(RecoveryNote)
    /// The whole plan enacted.
    case finished
}

/// Why enactment stopped.
public enum EnactmentError: Error, Sendable, Equatable {
    /// A step exited nonzero. Gated steps stay closed.
    case stepFailed(index: Int, exitStatus: Int32, stderrTail: String)
    /// The two ends did not agree. Gated steps never ran — a move that
    /// cannot prove its copy landed does not delete anything.
    case verificationFailed(VerificationReport)
    /// The plan's shape was not one enactment knows — typed, loud.
    case malformedPlan(String)
    /// A verification command itself failed, or its answer could not
    /// be read — the gate cannot decide, so it stays closed.
    case verificationUnavailable(host: String, detail: String)
}
