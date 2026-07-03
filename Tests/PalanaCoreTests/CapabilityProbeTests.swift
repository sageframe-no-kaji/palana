// The probe parser's unit battery — marker lines in, capability facts
// out. Synthetic shapes here; the recorded corpus from both fixture
// userlands replays in FieldCorpusTests.

import Foundation
import Testing

@testable import PalanaCore

@Suite("CapabilityProbe")
struct CapabilityProbeTests {
    @Test("a GNU host with zfs and rsync parses whole")
    func gnuFullHouse() throws {
        let stdout = """
            palana:kernel:Linux
            palana:flavor:GNU
            palana:zfs:zfs-2.2.2-0ubuntu9.1
            palana:rsync:rsync  version 3.2.7  protocol version 31
            """
        let capability = try CapabilityProbe.parse(stdout)
        #expect(capability.kernel == "Linux")
        #expect(capability.flavor == .gnu)
        #expect(capability.zfs == "zfs-2.2.2-0ubuntu9.1")
        #expect(capability.zfsVersion == "2.2.2")
        #expect(capability.rsync == "rsync  version 3.2.7  protocol version 31")
        #expect(capability.rsyncVersion == "3.2.7")
    }

    @Test("empty marker values read as absent")
    func absentBinaries() throws {
        let stdout = """
            palana:kernel:Darwin
            palana:flavor:BSD
            palana:zfs:
            palana:rsync:
            """
        let capability = try CapabilityProbe.parse(stdout)
        #expect(capability.flavor == .bsd)
        #expect(capability.zfs == nil)
        #expect(capability.rsync == nil)
        #expect(capability.zfsVersion == nil)
    }

    @Test("markers parse independent of order and stray noise")
    func orderIndependent() throws {
        let stdout = """
            motd: welcome to the machine
            palana:rsync:rsync  version 3.1.3  protocol version 31
            palana:flavor:GNU
            palana:kernel:Linux
            palana:zfs:
            """
        let capability = try CapabilityProbe.parse(stdout)
        #expect(capability.kernel == "Linux")
        #expect(capability.rsyncVersion == "3.1.3")
    }

    @Test("openrsync's protocol number is not a dotted version")
    func openrsyncNotMistaken() throws {
        let stdout = """
            palana:kernel:Darwin
            palana:flavor:BSD
            palana:zfs:
            palana:rsync:openrsync: protocol version 29
            """
        let capability = try CapabilityProbe.parse(stdout)
        #expect(capability.rsync == "openrsync: protocol version 29")
        #expect(capability.rsyncVersion == nil)
    }

    @Test("missing required markers throw, with the stdout carried")
    func missingMarkersThrow() {
        #expect(throws: ProbeParseError(stdout: "total garbage")) {
            try CapabilityProbe.parse("total garbage")
        }
        #expect(throws: ProbeParseError.self) {
            try CapabilityProbe.parse("palana:kernel:Linux")
        }
        #expect(throws: ProbeParseError.self) {
            try CapabilityProbe.parse("palana:kernel:Linux\npalana:flavor:MYSTERY")
        }
        #expect(throws: ProbeParseError.self) {
            try CapabilityProbe.parse("palana:kernel:\npalana:flavor:GNU")
        }
    }

    @Test("the command is one line — one round trip by construction")
    func commandIsOneLine() {
        #expect(!CapabilityProbe.command.contains("\n"))
    }
}
