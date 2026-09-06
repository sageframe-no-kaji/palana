// RoundTripConflictTests — the pure, fail-closed ruling that decides whether
// a saved edit may go back on its own: the content digest, the three-valued
// destination evaluation (clean / conflict / unavailable), and the
// disposition that lets only a clean result auto-send. All pure functions,
// no I/O — the unit battery beats on them directly, under the coverage floor.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Helpers

private func conflictEntry(size: Int64, mtime: Date) -> FileEntry {
    FileEntry(
        nameData: Data("notes.txt".utf8),
        kind: .file,
        size: size,
        modified: mtime,
        permissions: "644",
        owner: "op",
        group: "op")
}

private func conflictRecord(size: Int64, mtime: Date, digest: Data) -> RoundTripRecord {
    RoundTripRecord(
        host: "koan",
        remoteDirectory: "/tank",
        fetched: conflictEntry(size: size, mtime: mtime),
        digest: digest,
        localURL: URL(fileURLWithPath: "/tmp/a/notes.txt"))
}

// MARK: - RoundTrip.digest

@Suite("RoundTrip.digest")
struct RoundTripDigestTests {
    @Test("identical bytes hash identically; different bytes differ")
    func digestStability() {
        let first = RoundTrip.digest(of: Data("hello world".utf8))
        let same = RoundTrip.digest(of: Data("hello world".utf8))
        let other = RoundTrip.digest(of: Data("hello worlx".utf8))
        #expect(first == same)
        #expect(first != other)
        #expect(first.count == 32, "SHA-256 is 32 bytes")
    }
}

// MARK: - RoundTrip.evaluate — the fail-closed conflict ruling

@Suite("RoundTrip.evaluate")
struct RoundTripEvaluateTests {
    @Test("a missing remote entry is a conflict, not clean")
    func missingIsConflict() {
        let record = conflictRecord(size: 10, mtime: .distantPast, digest: RoundTrip.digest(of: Data("x".utf8)))
        #expect(RoundTrip.evaluate(record: record, current: nil, currentDigest: nil) == .conflict(.missing))
    }

    @Test("changed size or mtime is a metadata conflict — no digest needed")
    func metadataChangeIsConflict() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let record = conflictRecord(size: 10, mtime: mtime, digest: RoundTrip.digest(of: Data("x".utf8)))
        let moved = conflictEntry(size: 20, mtime: mtime)
        #expect(
            RoundTrip.evaluate(record: record, current: moved, currentDigest: nil)
                == .conflict(.metadataChanged(current: moved)))
    }

    @Test("same size and mtime but different bytes is a content conflict")
    func sameMetadataDifferentBytesIsConflict() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let record = conflictRecord(size: 10, mtime: mtime, digest: RoundTrip.digest(of: Data("original!!".utf8)))
        let same = conflictEntry(size: 10, mtime: mtime)
        let otherDigest = RoundTrip.digest(of: Data("changed!!!".utf8))
        #expect(
            RoundTrip.evaluate(record: record, current: same, currentDigest: otherDigest)
                == .conflict(.contentChanged))
    }

    @Test("same size, mtime, and digest is clean")
    func matchIsClean() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let digest = RoundTrip.digest(of: Data("original!!".utf8))
        let record = conflictRecord(size: 10, mtime: mtime, digest: digest)
        let same = conflictEntry(size: 10, mtime: mtime)
        #expect(RoundTrip.evaluate(record: record, current: same, currentDigest: digest) == .clean)
    }

    @Test("metadata matches but bytes unread is unavailable, never clean")
    func unreadableDigestIsUnavailable() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let record = conflictRecord(size: 10, mtime: mtime, digest: RoundTrip.digest(of: Data("original!!".utf8)))
        let same = conflictEntry(size: 10, mtime: mtime)
        guard case .unavailable = RoundTrip.evaluate(record: record, current: same, currentDigest: nil) else {
            Issue.record("expected unavailable when the digest could not be read")
            return
        }
    }
}

// MARK: - RoundTrip.disposition — only clean may auto-send

@Suite("RoundTrip.disposition")
struct RoundTripDispositionTests {
    private func record() -> RoundTripRecord {
        conflictRecord(size: 0, mtime: .distantPast, digest: Data())
    }

    @Test("clean + auto-send sends now")
    func cleanAutoSends() {
        #expect(RoundTrip.disposition(for: .clean, askBeforeSending: false, record: record()) == .sendNow)
    }

    @Test("clean + ask arms the plan for the operator")
    func cleanWithAskArms() {
        guard case .askOperator = RoundTrip.disposition(for: .clean, askBeforeSending: true, record: record()) else {
            Issue.record("clean with ask-before-sending must arm, not send")
            return
        }
    }

    @Test("a metadata conflict always asks, even with auto-send on")
    func conflictAlwaysAsks() {
        let moved = conflictEntry(size: 99, mtime: Date())
        let disposition = RoundTrip.disposition(
            for: .conflict(.metadataChanged(current: moved)), askBeforeSending: false, record: record())
        guard case .askOperator = disposition else {
            Issue.record("a conflict must ask regardless of the auto-send toggle")
            return
        }
    }

    @Test("an unavailable check blocks — no plan, even with auto-send on")
    func unavailableBlocks() {
        let disposition = RoundTrip.disposition(
            for: .unavailable("timeout"), askBeforeSending: false, record: record())
        guard case .blocked = disposition else {
            Issue.record("an unavailable destination must block, never auto-send")
            return
        }
    }
}
