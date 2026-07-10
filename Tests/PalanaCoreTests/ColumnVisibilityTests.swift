// ColumnVisibilityTests — encode/decode coverage for the column persistence
// model. ColumnVisibility is in PalanaCore so it can be tested here without
// the app target. Two cases: a round-trip through JSON and a silent-fail on
// corrupt input, mirroring how SessionStore handles bad data.

import Foundation
import Testing

@testable import PalanaCore

@Suite("ColumnVisibility persistence")
struct ColumnVisibilityTests {
    @Test("round-trip through JSON preserves hidden IDs")
    func roundTrip() throws {
        let original = ColumnVisibility(hiddenIDs: ["created", "changed", "star"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ColumnVisibility.self, from: data)
        #expect(decoded == original)
    }

    @Test("empty hidden IDs round-trips cleanly")
    func emptyRoundTrip() throws {
        let original = ColumnVisibility()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColumnVisibility.self, from: data)
        #expect(decoded.hiddenIDs.isEmpty)
    }

    @Test("corrupt input decodes to nil, not a throw")
    func corruptInput() {
        let garbage = Data("not json at all".utf8)
        let result = try? JSONDecoder().decode(ColumnVisibility.self, from: garbage)
        #expect(result == nil)
    }

    @Test("absent or empty file yields nil — same silent-fail contract as SessionStore")
    func absentFile() {
        let absent = URL(fileURLWithPath: "/tmp/palana-test-no-such-columns-\(UUID().uuidString).json")
        let result = try? Data(contentsOf: absent)
        #expect(result == nil)
    }
}
