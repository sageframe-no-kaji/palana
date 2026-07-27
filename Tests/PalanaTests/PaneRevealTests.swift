// PaneRevealTests — the pure resolution behind "open in Finder": which paths
// a right-click on a local pane hands to Finder, and the byte-accurate join
// that carries a name there intact. The NSWorkspace call itself is a one-line
// hand-off; the judgement is all here.

import Foundation
import Testing

@testable import Palana

@Suite("open in Finder — target resolution")
struct PaneRevealTests {
    // MARK: - Helpers

    private func name(_ text: String) -> Data { Data(text.utf8) }

    /// The URL's path exactly as the kernel holds it — no String hop.
    private static func fileSystemBytes(of url: URL) -> Data {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return Data() }
            return Data(bytes: pointer, count: strlen(pointer))
        }
    }

    private func paths(_ target: RevealTarget) -> [String?] {
        guard case .entries(let bytes) = target else { return [] }
        return bytes.map { String(bytes: $0, encoding: .utf8) }
    }

    // MARK: - Selection manners

    @Test("a clicked row inside the selection resolves to the whole selection")
    func clickedInsideSelection() {
        let selection: Set<Data> = [name("alpha"), name("beta"), name("gamma")]
        let target = PaneModel.revealTargets(
            directory: "/tank/media",
            selection: selection,
            ids: [name("beta")])
        #expect(
            paths(target) == [
                "/tank/media/alpha", "/tank/media/beta", "/tank/media/gamma",
            ])
    }

    @Test("a clicked row outside the selection resolves to that row alone")
    func clickedOutsideSelection() {
        let selection: Set<Data> = [name("alpha"), name("beta")]
        let target = PaneModel.revealTargets(
            directory: "/tank/media",
            selection: selection,
            ids: [name("zeta")])
        #expect(paths(target) == ["/tank/media/zeta"])
    }

    @Test("a clicked row with nothing selected resolves to that row alone")
    func clickedWithEmptySelection() {
        let target = PaneModel.revealTargets(
            directory: "/tank/media",
            selection: [],
            ids: [name("zeta")])
        #expect(paths(target) == ["/tank/media/zeta"])
    }

    @Test("an empty click resolves to the pane's own directory")
    func emptySpaceResolvesToDirectory() {
        let target = PaneModel.revealTargets(
            directory: "/tank/media",
            selection: [name("alpha")],
            ids: [])
        #expect(target == .directory("/tank/media"))
    }

    @Test("an empty click at root resolves to root")
    func emptySpaceAtRoot() {
        let target = PaneModel.revealTargets(directory: "/", selection: [], ids: [])
        #expect(target == .directory("/"))
    }

    @Test("entry order is the listing's canonical byte order, not the set's")
    func stableOrder() {
        let selection: Set<Data> = [name("c"), name("a"), name("b")]
        let target = PaneModel.revealTargets(
            directory: "/tmp",
            selection: selection,
            ids: [name("a")])
        #expect(paths(target) == ["/tmp/a", "/tmp/b", "/tmp/c"])
    }

    // MARK: - Byte-accurate joining

    @Test("a non-ASCII name joins byte-for-byte")
    func nonASCIIJoin() {
        let leaf = name("日本語のフォルダ")
        let joined = PaneModel.childPathData(of: "/tank/media", name: leaf)
        #expect(joined == Data("/tank/media/".utf8) + leaf)
        #expect(String(bytes: joined, encoding: .utf8) == "/tank/media/日本語のフォルダ")
    }

    @Test("a name that is not valid UTF-8 survives the join intact")
    func invalidUTF8Join() {
        let leaf = Data([0xFF, 0xFE, 0x80])
        let joined = PaneModel.childPathData(of: "/tank", name: leaf)
        #expect(joined == Data("/tank/".utf8) + leaf)
    }

    @Test("joining at root does not double the slash")
    func rootJoin() {
        let joined = PaneModel.childPathData(of: "/", name: name("etc"))
        #expect(String(bytes: joined, encoding: .utf8) == "/etc")
    }

    @Test("resolution joins through the byte-accurate path, non-ASCII included")
    func resolutionIsByteAccurate() {
        let leaf = Data([0xFF, 0xFE])
        let target = PaneModel.revealTargets(directory: "/tank", selection: [], ids: [leaf])
        #expect(target == .entries([Data("/tank/".utf8) + leaf]))
    }

    // MARK: - URL round-trip

    @Test("path bytes round-trip through the file URL without loss")
    func urlRoundTrip() {
        let bytes = PaneModel.childPathData(of: "/tank/media", name: name("日本語 file.txt"))
        let url = PaneModel.fileURL(forPathBytes: bytes)
        #expect(Self.fileSystemBytes(of: url) == bytes)
    }

    @Test("a path whose name is not valid UTF-8 round-trips through the file URL")
    func urlRoundTripInvalidUTF8() {
        let bytes = PaneModel.childPathData(of: "/tank", name: Data([0xFF, 0xFE, 0x80]))
        let url = PaneModel.fileURL(forPathBytes: bytes)
        #expect(Self.fileSystemBytes(of: url) == bytes)
    }
}
