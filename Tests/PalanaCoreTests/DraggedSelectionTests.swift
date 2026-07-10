// DraggedSelection + DropDecision battery — payload Codable round-trip
// (including non-UTF-8 names), Equatable sanity, and the full decision
// matrix: same-place, differing host, differing path, option on/off,
// and empty names.

import Foundation
import Testing

@testable import PalanaCore

@Suite("DraggedSelection")
struct DraggedSelectionTests {
    // MARK: - Codable round-trip

    @Test("round-trip preserves host, directory, and ASCII name bytes")
    func roundTripASCII() throws {
        let sel = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("movie.mkv".utf8), Data("readme.txt".utf8)]
        )
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(DraggedSelection.self, from: data)
        #expect(decoded == sel)
    }

    @Test("round-trip preserves names that are not valid UTF-8")
    func roundTripNonUTF8() throws {
        // 0xFF 0xFE is not valid UTF-8 — the bytes must survive the trip.
        let badBytes = Data([0xFF, 0xFE, 0x41, 0x42])
        let sel = DraggedSelection(
            host: "jodo",
            directory: "/srv",
            names: [badBytes, Data("clean.txt".utf8)]
        )
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(DraggedSelection.self, from: data)
        #expect(decoded.names[0] == badBytes)
        #expect(decoded.names[1] == Data("clean.txt".utf8))
    }

    @Test("round-trip with an empty names array")
    func roundTripEmptyNames() throws {
        let sel = DraggedSelection(host: "local", directory: "/", names: [])
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(DraggedSelection.self, from: data)
        #expect(decoded == sel)
    }

    @Test("JSONEncoder base64-encodes the byte names in the JSON output")
    func jsonUsesBase64() throws {
        let sel = DraggedSelection(
            host: "koan",
            directory: "/tmp",
            names: [Data("abc".utf8)]
        )
        let data = try JSONEncoder().encode(sel)
        let json = try #require(String(data: data, encoding: .utf8))
        // "abc" base64-encodes to "YWJj"
        #expect(json.contains("YWJj"), "base64 encoding of 'abc' must appear in the JSON")
    }

    // MARK: - Equatable

    @Test("equal payloads compare equal")
    func equalPayloads() {
        let lhs = DraggedSelection(host: "koan", directory: "/tank", names: [Data("f.txt".utf8)])
        let rhs = DraggedSelection(host: "koan", directory: "/tank", names: [Data("f.txt".utf8)])
        #expect(lhs == rhs)
    }

    @Test("payloads differing by host are not equal")
    func differByHost() {
        let lhs = DraggedSelection(host: "koan", directory: "/tank", names: [Data("f.txt".utf8)])
        let rhs = DraggedSelection(host: "jodo", directory: "/tank", names: [Data("f.txt".utf8)])
        #expect(lhs != rhs)
    }

    @Test("payloads differing by directory are not equal")
    func differByDirectory() {
        let lhs = DraggedSelection(host: "koan", directory: "/tank", names: [Data("f.txt".utf8)])
        let rhs = DraggedSelection(host: "koan", directory: "/rpool", names: [Data("f.txt".utf8)])
        #expect(lhs != rhs)
    }

    @Test("payloads differing by names are not equal")
    func differByNames() {
        let lhs = DraggedSelection(host: "koan", directory: "/tank", names: [Data("a.txt".utf8)])
        let rhs = DraggedSelection(host: "koan", directory: "/tank", names: [Data("b.txt".utf8)])
        #expect(lhs != rhs)
    }
}

@Suite("DropDecision")
struct DropDecisionTests {
    // MARK: - Empty names

    @Test("empty names → refuseEmpty")
    func emptyNamesRefuses() {
        let payload = DraggedSelection(host: "koan", directory: "/tank", names: [])
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "jodo",
            targetDirectory: "/rpool",
            optionHeld: false
        )
        #expect(decision == .refuseEmpty)
    }

    @Test("empty names with option held still → refuseEmpty, not compose")
    func emptyNamesOptionHeldRefuses() {
        let payload = DraggedSelection(host: "koan", directory: "/tank", names: [])
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "jodo",
            targetDirectory: "/rpool",
            optionHeld: true
        )
        #expect(decision == .refuseEmpty)
    }

    // MARK: - Same-place refusals

    @Test("same host and same directory → refuseSamePlace")
    func samePlaceRefuses() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/media",
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("same host, source has trailing slash — still same place after normalization")
    func samePlaceSourceTrailingSlash() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media/",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/media",
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("same host, target has trailing slash — still same place after normalization")
    func samePlaceTargetTrailingSlash() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/media/",
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("same host, both paths have trailing slashes — same place")
    func samePlaceBothTrailingSlashes() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media/",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/media/",
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("same host, root path / — same place (root normalization edge case)")
    func samePlaceRootPath() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/",
            names: [Data("file.txt".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/",
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    // MARK: - Composing decisions

    @Test("different hosts, same path, no option → compose(.copy)")
    func differentHostSamePath() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "jodo",
            targetDirectory: "/tank/media",
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }

    @Test("same host, different paths, no option → compose(.copy)")
    func sameHostDifferentPath() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/backup",
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }

    @Test("different hosts, different paths, no option → compose(.copy)")
    func differentHostDifferentPath() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "jodo",
            targetDirectory: "/rpool/archive",
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }

    @Test("option held → compose(.move)")
    func optionHeldComposeMove() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "jodo",
            targetDirectory: "/rpool/archive",
            optionHeld: true
        )
        #expect(decision == .compose(.move))
    }

    @Test("option held, same host different path → compose(.move)")
    func optionHeldSameHostDifferentPath() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/archive",
            optionHeld: true
        )
        #expect(decision == .compose(.move))
    }

    @Test("no option held, same host different path → compose(.copy) not .move")
    func noOptionSameHostDifferentPath() {
        let payload = DraggedSelection(
            host: "koan",
            directory: "/tank/media",
            names: [Data("file.mkv".utf8)]
        )
        let decision = DropDecision.decide(
            payload: payload,
            targetHost: "koan",
            targetDirectory: "/tank/archive",
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }
}
