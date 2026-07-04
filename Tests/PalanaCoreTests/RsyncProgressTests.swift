// The progress2 parser's synthetic battery — chunk boundaries are the
// enemy. Real rsync output hardens it in integration and rides the
// recorded corpus after.

import Foundation
import Testing

@testable import PalanaCore

@Suite("RsyncProgress")
struct RsyncProgressTests {
    @Test("a whole progress2 line parses: bytes, fraction, raw")
    func wholeLine() {
        let report = RsyncProgress.parse(
            line: "  1,234,567  45%    1.23MB/s    0:00:07")
        #expect(report?.bytesTransferred == 1_234_567)
        #expect(report?.fraction == 0.45)
        #expect(report?.rawLine.hasPrefix("1,234,567") == true)
    }

    @Test("a line split across chunks parses once, whole")
    func chunkBoundary() {
        var parser = RsyncProgress()
        var reports = parser.consume(Data("      1,2".utf8))
        #expect(reports.isEmpty, "no terminator yet — nothing to report")
        reports = parser.consume(Data("34,567  45%    1.23MB/s    0:00:07\r".utf8))
        #expect(reports.count == 1)
        #expect(reports.first?.bytesTransferred == 1_234_567)
    }

    @Test("carriage-return refreshes yield one report each")
    func refreshSequence() {
        var parser = RsyncProgress()
        let chunk = "  100  1%  1MB/s  0:00\r  200  2%  1MB/s  0:00\r  300  3%  1MB/s  0:00\n"
        let reports = parser.consume(Data(chunk.utf8))
        #expect(reports.map(\.bytesTransferred) == [100, 200, 300])
        #expect(reports.last?.fraction == 0.03)
    }

    @Test("non-progress lines stay out of the reports")
    func noiseIgnored() {
        var parser = RsyncProgress()
        let chunk = "sending incremental file list\nf1\nf2\n"
        #expect(parser.consume(Data(chunk.utf8)).isEmpty)
        #expect(RsyncProgress.parse(line: "total size is 3  speedup is 1.00") == nil)
    }

    @Test("100% parses to fraction 1.0 exactly")
    func completion() {
        let report = RsyncProgress.parse(line: "  3,000  100%    2.86kB/s    0:00:01")
        #expect(report?.fraction == 1.0)
        #expect(report?.bytesTransferred == 3000)
    }

    @Test("the recorded fixture stream parses and finishes at 1.0")
    func recordedStream() throws {
        let url = SSHFixture.repoRoot.appendingPathComponent(
            "Tests/PalanaCoreTests/Fixtures/rsync-progress2-sample.bin")
        let data = try Data(contentsOf: url)
        var parser = RsyncProgress()
        let reports = parser.consume(data)
        #expect(!reports.isEmpty, "real rsync output produced observations")
        #expect(reports.last?.fraction == 1.0)
    }
}
