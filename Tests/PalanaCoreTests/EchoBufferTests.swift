// The echo's line folder, pinned synthetically — newline commits, CR
// repaints, UTF-8 partials held across chunk seams, the cap and its
// honest drop count. rsync's real progress shape is here in miniature;
// the recorded corpus proves it again at transport level.

import Foundation
import Testing

@testable import PalanaCore

@Suite("EchoBuffer")
struct EchoBufferTests {
    private func chunk(_ text: String) -> Data {
        Data(text.utf8)
    }

    @Test("newline commits a line to the transcript")
    func newlineCommits() {
        var buffer = EchoBuffer()
        buffer.append(chunk("hello\n"), channel: .stdout)
        #expect(buffer.transcript.map(\.text) == ["hello"])
        #expect(buffer.liveLines.isEmpty)
    }

    @Test("an unterminated tail stays live, not in the transcript")
    func unterminatedTailIsLive() {
        var buffer = EchoBuffer()
        buffer.append(chunk("building "), channel: .stdout)
        #expect(buffer.transcript.isEmpty)
        #expect(buffer.liveLines.map(\.text) == ["building "])
    }

    @Test("a line split across chunks assembles whole")
    func splitLineAssembles() {
        var buffer = EchoBuffer()
        buffer.append(chunk("first ha"), channel: .stdout)
        buffer.append(chunk("lf second half\n"), channel: .stdout)
        #expect(buffer.transcript.map(\.text) == ["first half second half"])
    }

    @Test("carriage return repaints the live line in place, id stable")
    func carriageReturnRepaints() {
        var buffer = EchoBuffer()
        buffer.append(chunk("      1,024   2%\r"), channel: .stderr)
        let firstID = buffer.liveLines[0].id
        buffer.append(chunk("     10,240  25%\r"), channel: .stderr)
        #expect(buffer.liveLines.map(\.text) == ["     10,240  25%"])
        #expect(buffer.liveLines[0].id == firstID)
        #expect(buffer.transcript.isEmpty)
    }

    @Test("CR LF is one newline, not a blanked line")
    func carriageReturnNewline() {
        var buffer = EchoBuffer()
        buffer.append(chunk("done\r\nnext\r\n"), channel: .stdout)
        #expect(buffer.transcript.map(\.text) == ["done", "next"])
    }

    @Test("a CR pending at a chunk seam still repaints")
    func pendingReturnAcrossChunks() {
        var buffer = EchoBuffer()
        buffer.append(chunk("old line\r"), channel: .stderr)
        buffer.append(chunk("new"), channel: .stderr)
        #expect(buffer.liveLines.map(\.text) == ["new"])
    }

    @Test("a multibyte rune split across chunks decodes whole")
    func splitRuneDecodes() {
        var buffer = EchoBuffer()
        let bytes = [UInt8]("pālana\n".utf8)
        // ā is two bytes — split between them.
        let seam = 2
        buffer.append(Data(bytes[..<seam]), channel: .stdout)
        buffer.append(Data(bytes[seam...]), channel: .stdout)
        #expect(buffer.transcript.map(\.text) == ["pālana"])
    }

    @Test("a four-byte rune split three ways decodes whole")
    func fourByteRuneSplit() {
        var buffer = EchoBuffer()
        let bytes = [UInt8]("a😀b\n".utf8)
        buffer.append(Data(bytes[..<2]), channel: .stdout)
        buffer.append(Data(bytes[2..<4]), channel: .stdout)
        buffer.append(Data(bytes[4...]), channel: .stdout)
        #expect(buffer.transcript.map(\.text) == ["a😀b"])
    }

    @Test("genuinely invalid bytes replace instead of refusing the stream")
    func invalidBytesReplace() {
        var buffer = EchoBuffer()
        buffer.append(Data([0x68, 0x69, 0xFF, 0x0A]), channel: .stdout)
        #expect(buffer.transcript.count == 1)
        #expect(buffer.transcript[0].text.hasPrefix("hi"))
    }

    @Test("channels assemble independently and land in completion order")
    func channelsIndependent() {
        var buffer = EchoBuffer()
        buffer.append(chunk("out part "), channel: .stdout)
        buffer.append(chunk("err whole\n"), channel: .stderr)
        buffer.append(chunk("done\n"), channel: .stdout)
        #expect(buffer.transcript.map(\.text) == ["err whole", "out part done"])
        #expect(buffer.transcript.map(\.kind) == [.stderr, .stdout])
    }

    @Test("appendLine narrates without stealing a live repaint")
    func appendLineLeavesLiveAlone() {
        var buffer = EchoBuffer()
        buffer.append(chunk("  50%\r"), channel: .stderr)
        buffer.appendLine("$ rsync …", kind: .command)
        #expect(buffer.transcript.map(\.text) == ["$ rsync …"])
        #expect(buffer.transcript[0].kind == .command)
        #expect(buffer.liveLines.map(\.text) == ["  50%"])
    }

    @Test("flush commits an unterminated line at a step boundary")
    func flushCommits() {
        var buffer = EchoBuffer()
        buffer.append(chunk("no newline at end"), channel: .stdout)
        buffer.flushAll()
        #expect(buffer.transcript.map(\.text) == ["no newline at end"])
        #expect(buffer.liveLines.isEmpty)
    }

    @Test("the cap drops the oldest lines and counts them honestly")
    func capDropsAndCounts() {
        var buffer = EchoBuffer(cap: 3)
        for index in 0..<5 {
            buffer.append(chunk("line \(index)\n"), channel: .stdout)
        }
        #expect(buffer.transcript.map(\.text) == ["line 2", "line 3", "line 4"])
        #expect(buffer.droppedLines == 2)
    }

    @Test("line ids stay unique across kinds and channels")
    func idsUnique() {
        var buffer = EchoBuffer()
        buffer.appendLine("note", kind: .note)
        buffer.append(chunk("a\nb\n"), channel: .stdout)
        buffer.append(chunk("c"), channel: .stderr)
        let ids = buffer.lines.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("the revision bumps on every mutation — repaints and commits above the tail included")
    func revisionCountsMutations() {
        var buffer = EchoBuffer()
        #expect(buffer.revision == 0)
        buffer.appendLine("$ touch a", kind: .command)
        #expect(buffer.revision == 1)
        buffer.append(chunk("  2%\r"), channel: .stderr)
        #expect(buffer.revision == 2)
        // A repaint changes no line count and no line id — only this moves.
        buffer.append(chunk(" 25%\r"), channel: .stderr)
        #expect(buffer.revision == 3)
        // A commit above the live tail leaves lines.last untouched — the
        // shape a last-line watch misses entirely.
        buffer.appendLine("step 1 exited 0", kind: .note)
        #expect(buffer.revision == 4)
        #expect(buffer.lines.last?.text == " 25%")
        buffer.flushAll()
        #expect(buffer.revision == 5)
        // Flushing with nothing live commits nothing and claims nothing.
        buffer.flushAll()
        #expect(buffer.revision == 5)
    }

    @Test("lines renders transcript then live, stderr nearest the eye")
    func linesOrder() {
        var buffer = EchoBuffer()
        buffer.appendLine("$ tar …", kind: .command)
        buffer.append(chunk("partial out"), channel: .stdout)
        buffer.append(chunk("  12%\r"), channel: .stderr)
        let kinds = buffer.lines.map(\.kind)
        #expect(kinds == [.command, .stdout, .stderr])
    }
}
