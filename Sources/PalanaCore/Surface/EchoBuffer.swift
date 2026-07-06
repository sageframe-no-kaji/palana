// The echo's machinery — deferred decision 7's verdict, the testable
// half. A purpose-built line folder, not a terminal emulator: chunks
// in, lines out, carriage-return repaint for rsync's in-place progress,
// UTF-8 partials held across chunk boundaries. The Surface renders the
// lines and owns only scrolling.

import Foundation

/// One rendered echo line.
public struct EchoLine: Sendable, Equatable, Identifiable {
    /// What the line is — the panel styles by kind, never by parsing.
    public enum Kind: Sendable, Equatable {
        /// A command about to run — the plan's exact string.
        case command
        /// Standard output from a running step.
        case stdout
        /// Standard error from a running step.
        case stderr
        /// The panel's own quiet narration — gathering, verification,
        /// completion.
        case note
        /// A typed failure. Stays on screen.
        case failure
    }

    /// Monotonic identity, stable across repaints.
    public let id: Int
    /// The line's current text.
    public var text: String
    /// What the line is.
    public var kind: Kind
}

/// Folds enactment output into display lines.
///
/// A value, like everything the panel shows. Finished lines land in the
/// transcript in completion order; each channel keeps at most one live
/// line, repainted in place when a carriage return asks for it. The
/// transcript is capped — a million-line tar cannot eat the app — and
/// the drop count keeps the cap honest.
public struct EchoBuffer: Sendable, Equatable {
    /// The line type, named from the buffer as call sites read it.
    public typealias Line = EchoLine

    /// Assembly state for one channel's unfinished line.
    private struct Partial: Sendable, Equatable {
        var held = Data()
        var text = ""
        var pendingReturn = false
        var lineID: Int?

        var isEmpty: Bool { text.isEmpty && lineID == nil }
    }

    /// Finished lines, completion order, capped.
    public private(set) var transcript: [Line] = []
    /// Lines dropped to honor the cap — zero until the cap bites.
    public private(set) var droppedLines = 0
    /// Monotonic mutation count — bumped by every append, repaint, and
    /// committing flush.
    ///
    /// The panel watches this one value to follow the tail. No single
    /// line is a faithful signal that the buffer moved: a CR repaint
    /// keeps the last line's id, and a line committed above a live
    /// partial changes nothing at the tail at all.
    public private(set) var revision = 0

    private var partials: [OutputChannel: Partial] = [:]
    private var nextID = 0
    private let cap: Int

    /// An empty buffer holding at most `cap` finished lines.
    public init(cap: Int = 5000) {
        self.cap = max(cap, 1)
    }

    /// Everything to render: the transcript, then the live lines.
    ///
    /// Live lines come last because they are still moving — stderr after
    /// stdout, so a progress repaint sits nearest the operator's eye.
    public var lines: [Line] {
        transcript + liveLines
    }

    /// The unfinished lines, at most one per channel.
    public var liveLines: [Line] {
        [OutputChannel.stdout, .stderr].compactMap { channel in
            guard let partial = partials[channel], let id = partial.lineID else { return nil }
            return Line(id: id, text: partial.text, kind: channel == .stdout ? .stdout : .stderr)
        }
    }

    /// Appends a whole line of the panel's own — command, note, failure.
    ///
    /// Output partials stay live; narration never steals a repaint.
    public mutating func appendLine(_ text: String, kind: Line.Kind) {
        commit(Line(id: takeID(), text: text, kind: kind))
        revision += 1
    }

    /// Folds one output chunk into the channel's line assembly.
    public mutating func append(_ data: Data, channel: OutputChannel) {
        var partial = partials[channel] ?? Partial()
        partial.held.append(data)
        let text = Self.decodeKeepingTail(&partial.held)
        // Scalars, not Characters — Swift folds "\r\n" into one grapheme
        // cluster, and the fold must see the CR and the LF separately.
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n":
                partial.pendingReturn = false
                finishLive(&partial, channel: channel)
            case "\r":
                partial.pendingReturn = true
            default:
                if partial.pendingReturn {
                    partial.pendingReturn = false
                    partial.text = ""
                }
                partial.text.unicodeScalars.append(scalar)
            }
        }
        if partial.lineID == nil, !partial.text.isEmpty {
            partial.lineID = takeID()
        }
        partials[channel] = partial
        revision += 1
    }

    /// Commits a channel's live line even without a trailing newline —
    /// step boundaries call this so a last unterminated line survives.
    public mutating func flush(channel: OutputChannel) {
        guard var partial = partials[channel] else { return }
        if !partial.text.isEmpty || partial.lineID != nil {
            finishLive(&partial, channel: channel)
            revision += 1
        }
        partials[channel] = partial
    }

    /// Commits both channels' live lines.
    public mutating func flushAll() {
        flush(channel: .stdout)
        flush(channel: .stderr)
    }

    // MARK: - Assembly

    private mutating func finishLive(_ partial: inout Partial, channel: OutputChannel) {
        let id = partial.lineID ?? takeID()
        commit(Line(id: id, text: partial.text, kind: channel == .stdout ? .stdout : .stderr))
        partial.text = ""
        partial.lineID = nil
    }

    private mutating func commit(_ line: Line) {
        transcript.append(line)
        if transcript.count > cap {
            droppedLines += transcript.count - cap
            transcript.removeFirst(transcript.count - cap)
        }
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Decodes the buffer's longest complete UTF-8 prefix, holding an
    /// unfinished trailing sequence for the next chunk.
    ///
    /// Genuinely invalid bytes replace lossily — the echo shows what
    /// arrived, it does not refuse the stream over one bad byte.
    private static func decodeKeepingTail(_ buffer: inout Data) -> String {
        let hold = incompleteTailLength(of: buffer)
        let ready = buffer.prefix(buffer.count - hold)
        let tail = buffer.suffix(hold)
        buffer = Data(tail)
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: ready, as: UTF8.self)  // lossy on purpose — see above
    }

    /// How many trailing bytes belong to an unfinished UTF-8 sequence.
    private static func incompleteTailLength(of buffer: Data) -> Int {
        let bytes = [UInt8](buffer.suffix(4))
        guard !bytes.isEmpty else { return 0 }
        // Walk back over continuation bytes to the nearest lead byte.
        var index = bytes.count - 1
        var continuations = 0
        while index >= 0, bytes[index] & 0b1100_0000 == 0b1000_0000 {
            continuations += 1
            index -= 1
        }
        guard index >= 0 else { return 0 }
        let lead = bytes[index]
        let expected: Int
        switch lead {
        case 0b1100_0000...0b1101_1111: expected = 2
        case 0b1110_0000...0b1110_1111: expected = 3
        case 0b1111_0000...0b1111_0111: expected = 4
        default: return 0  // ASCII or invalid lead — nothing to hold
        }
        let have = continuations + 1
        return have < expected ? have : 0
    }
}
