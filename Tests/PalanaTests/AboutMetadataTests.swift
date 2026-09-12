import Testing

@testable import Palana

@Suite("About metadata")
struct AboutMetadataTests {
    @Test("a release channel follows the numeric bundle version")
    func releaseChannel() {
        #expect(Links.displayVersion("0.8.0", releaseChannel: "beta") == "0.8.0 beta")
    }

    @Test("a final release has no trailing channel")
    func finalRelease() {
        #expect(Links.displayVersion("1.0.0", releaseChannel: nil) == "1.0.0")
        #expect(Links.displayVersion("1.0.0", releaseChannel: "  ") == "1.0.0")
    }
}
