// The cache is deletable memory — that is its contract and this is the
// contract's battery. Missing reads empty, corrupt reads empty, writes
// are atomic, and the directory is created on first save.

import Foundation
import Testing

@testable import PalanaCore

@Suite("FieldCache")
struct FieldCacheTests {
    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-cache-\(UUID().uuidString)")
            .appendingPathComponent("field-cache.json")
    }

    private static let stamp = Date(timeIntervalSince1970: 1_000_000)

    private static let sampleCapability = HostCapability(
        kernel: "Linux",
        flavor: .gnu,
        zfs: "zfs-2.2.2",
        rsync: "rsync  version 3.2.7  protocol version 31"
    )

    private static let sampleFacts = HostFacts(
        reachability: Dated(value: .reachable, discoveredAt: stamp),
        capability: Dated(value: sampleCapability, discoveredAt: stamp),
        zfsTopology: Dated(
            value: [ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)],
            discoveredAt: stamp)
    )

    @Test("facts round-trip through the file, timestamps intact")
    func roundTrip() throws {
        let cache = FieldCache(url: Self.temporaryURL())
        defer { try? FileManager.default.removeItem(at: cache.url) }
        try cache.save(["jodo": Self.sampleFacts])
        let loaded = cache.load()
        #expect(loaded == ["jodo": Self.sampleFacts])
    }

    @Test("a missing file reads as empty")
    func missingReadsEmpty() {
        #expect(FieldCache(url: Self.temporaryURL()).load().isEmpty)
    }

    @Test("a corrupt file reads as empty — deleting is always safe, so is mangling")
    func corruptReadsEmpty() throws {
        let url = Self.temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FieldCache(url: url).load().isEmpty)
    }

    @Test("an unreachable fact's detail survives the round trip")
    func unreachableRoundTrip() throws {
        let cache = FieldCache(url: Self.temporaryURL())
        defer { try? FileManager.default.removeItem(at: cache.url) }
        let facts = HostFacts(
            reachability: Dated(
                value: .unreachable(detail: "unreachable: connection refused"),
                discoveredAt: Date(timeIntervalSince1970: 2_000_000))
        )
        try cache.save(["koan": facts])
        #expect(cache.load()["koan"] == facts)
    }

    @Test("a save overwrites the previous memory whole")
    func overwrite() throws {
        let cache = FieldCache(url: Self.temporaryURL())
        defer { try? FileManager.default.removeItem(at: cache.url) }
        try cache.save(["jodo": Self.sampleFacts])
        try cache.save(["chumon": HostFacts()])
        let loaded = cache.load()
        #expect(loaded["jodo"] == nil)
        #expect(loaded["chumon"] == HostFacts())
    }

    @Test("the default location sits under Application Support/palana")
    func defaultLocation() {
        let path = FieldCache.defaultURL.path
        #expect(path.hasSuffix("palana/field-cache.json"))
        #expect(path.contains("Application Support"))
    }
}
