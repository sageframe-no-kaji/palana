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

@Suite("DropDecision onto a folder row (ho-14)")
struct DropDecisionOntoFolderTests {
    /// A one-file drag from `koan:/tank/media`.
    private func drag(
        host: String = "koan",
        directory: String = "/tank/media",
        names: [Data] = [Data("file.mkv".utf8)]
    ) -> DraggedSelection {
        DraggedSelection(host: host, directory: directory, names: names)
    }

    // MARK: - Destination resolves to the folder, not the pane cwd

    @Test("the destination is the folder path, so a drag that would refuse at the pane cwd composes")
    func folderPathBeatsPaneCwd() {
        // Source and the target pane share host + directory — a pane-level drop
        // here refuses (same place). Dropping onto a subfolder must NOT refuse:
        // its destination is /tank/media/sub, a genuine elsewhere.
        let decision = DropDecision.decideOntoFolder(
            payload: drag(),
            targetHost: "koan",
            folderPath: "/tank/media/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }

    @Test("a plain pane-level drop of the same drag refuses — proving the folder path is what differs")
    func paneCwdRefusesWhereFolderComposes() {
        let decision = DropDecision.decide(
            payload: drag(),
            targetHost: "koan",
            targetDirectory: "/tank/media",
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("option held onto a folder → compose(.move)")
    func optionHeldOntoFolderMoves() {
        let decision = DropDecision.decideOntoFolder(
            payload: drag(),
            targetHost: "koan",
            folderPath: "/tank/media/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: true
        )
        #expect(decision == .compose(.move))
    }

    @Test("a folder on a different host → compose(.copy)")
    func differentHostFolderComposes() {
        let decision = DropDecision.decideOntoFolder(
            payload: drag(),
            targetHost: "jodo",
            folderPath: "/rpool/cold/incoming",
            folderNameData: Data("incoming".utf8),
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }

    // MARK: - Refusals

    @Test("dropping onto a folder that is itself in the selection → refuseSamePlace")
    func folderInSelectionRefuses() {
        // The drag carries the folder "sub" (from /tank/media); dropping it onto
        // its own "sub" row is a self-into-self drop.
        let decision = DropDecision.decideOntoFolder(
            payload: drag(names: [Data("sub".utf8), Data("other.txt".utf8)]),
            targetHost: "koan",
            folderPath: "/tank/media/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("the folder is in the selection but the pane's dir differs — not a self-drop, composes")
    func folderNameMatchesButDifferentParent() {
        // A folder named "sub" is dragged from /tank/media, but the target pane
        // sits at /tank/backup showing a different "sub" — different parent, so
        // it is a real destination, not the dragged folder itself.
        let decision = DropDecision.decideOntoFolder(
            payload: drag(names: [Data("sub".utf8)]),
            targetHost: "koan",
            folderPath: "/tank/backup/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: false
        )
        #expect(decision == .compose(.copy))
    }

    @Test("files already living in the folder → refuseSamePlace (delegated same-place check)")
    func filesAlreadyInFolderRefuses() {
        // Source is /tank/media/sub; dropping onto the "sub" folder shown in the
        // pane at /tank/media resolves to /tank/media/sub — the source itself.
        let decision = DropDecision.decideOntoFolder(
            payload: drag(directory: "/tank/media/sub"),
            targetHost: "koan",
            folderPath: "/tank/media/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("self-in-selection check is byte-honest — a trailing slash on the parent still refuses")
    func selfCheckNormalizesParent() {
        let decision = DropDecision.decideOntoFolder(
            payload: drag(directory: "/tank/media/", names: [Data("sub".utf8)]),
            targetHost: "koan",
            folderPath: "/tank/media/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }

    @Test("empty names onto a folder → refuseEmpty")
    func emptyNamesOntoFolderRefuses() {
        let decision = DropDecision.decideOntoFolder(
            payload: drag(names: []),
            targetHost: "koan",
            folderPath: "/tank/media/sub",
            folderNameData: Data("sub".utf8),
            optionHeld: false
        )
        #expect(decision == .refuseEmpty)
    }

    @Test("a non-UTF-8 folder name matches by bytes, not by string")
    func nonUTF8FolderNameMatches() {
        let weird = Data([0xFF, 0xFE, 0x41])
        let decision = DropDecision.decideOntoFolder(
            payload: drag(names: [weird]),
            targetHost: "koan",
            folderPath: "/tank/media/\u{FFFD}",
            folderNameData: weird,
            optionHeld: false
        )
        #expect(decision == .refuseSamePlace)
    }
}
