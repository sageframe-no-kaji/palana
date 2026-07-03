import Testing

@testable import PalanaCore

@Suite("Smoke")
struct SmokeTests {
    @Test("PalanaCore exposes a version string")
    func versionIsSet() {
        #expect(!PalanaCore.version.isEmpty)
    }
}
