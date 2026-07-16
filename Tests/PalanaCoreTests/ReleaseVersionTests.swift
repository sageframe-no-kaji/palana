// ReleaseVersionTests — the update-check compare (ho-12). An announce fires only
// on a version we're sure is newer, so the parse and the ordering are pinned:
// v-prefix and bundle forms, missing trailing components as zero, pre-release
// below release, and unparseable → never newer (no false positives).

import Testing

@testable import PalanaCore

@Suite("ReleaseVersion — the update compare")
struct ReleaseVersionTests {
    @Test("a higher minor or patch is newer")
    func higherIsNewer() {
        #expect(ReleaseVersion.isNewer("v1.1", than: "v1.0"))
        #expect(ReleaseVersion.isNewer("v1.0.1", than: "v1.0.0"))
        #expect(ReleaseVersion.isNewer("v2.0", than: "v1.9"))
    }

    @Test("the same version is not newer")
    func sameIsNotNewer() {
        #expect(!ReleaseVersion.isNewer("v1.0", than: "v1.0"))
    }

    @Test("v-prefixed tag and dotted bundle version compare equal (v1.0 == 1.0.0)")
    func tagVsBundleForm() {
        #expect(!ReleaseVersion.isNewer("v1.0", than: "1.0.0"))
        #expect(!ReleaseVersion.isNewer("1.0.0", than: "v1.0"))
        #expect(ReleaseVersion.isNewer("v1.0.1", than: "1.0.0"))
    }

    @Test("an older running version sees the newer release")
    func olderSeesNewer() {
        #expect(ReleaseVersion.isNewer("v1.0", than: "0.6"))
        #expect(!ReleaseVersion.isNewer("v0.6", than: "1.0.0"))
    }

    @Test("a pre-release sorts below the same final release")
    func prereleaseBelowRelease() {
        #expect(ReleaseVersion.isNewer("v1.0", than: "v1.0-beta"))
        #expect(!ReleaseVersion.isNewer("v1.0-beta", than: "v1.0"))
        #expect(!ReleaseVersion.isNewer("v0.4-beta", than: "v0.4-beta"))
    }

    @Test("an unparseable version is never newer — no false announce")
    func unparseableNeverNewer() {
        #expect(!ReleaseVersion.isNewer("nightly", than: "v1.0"))
        #expect(!ReleaseVersion.isNewer("v1.0", than: "unknown"))
        #expect(!ReleaseVersion.isNewer("", than: "v1.0"))
    }

    @Test("parsing tolerates whitespace and uppercase V")
    func parsingTolerant() {
        #expect(ReleaseVersion(" V1.2.3 ")?.components == [1, 2, 3])
        #expect(ReleaseVersion("v1.0-rc1")?.isPrerelease == true)
        #expect(ReleaseVersion("garbage") == nil)
    }
}
