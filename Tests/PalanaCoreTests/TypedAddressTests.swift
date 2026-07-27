// TypedAddressTests — the three-way classification behind every address the
// operator types: host:path, a bare absolute path, or a bare host alias. A
// host alias cannot begin with "/", which is what makes the split honest.

import Foundation
import Testing

@testable import PalanaCore

@Suite("TypedAddress: classification")
struct TypedAddressTests {
    // MARK: - Bare paths

    @Test("a pasted Mac path with spaces and @ and no colon is a bare path")
    func googleDrivePath() {
        let path =
            "/Users/atmarcus/Library/CloudStorage/"
            + "GoogleDrive-atmarcus@gmail.com/My Drive/Job Search/2026/57"
        #expect(TypedAddress.classify(path) == .barePath(path))
    }

    @Test("root alone is a bare path")
    func rootIsBarePath() {
        #expect(TypedAddress.classify("/") == .barePath("/"))
    }

    @Test(
        "any /-leading colon-free input is a bare path",
        arguments: ["/tank", "/etc/hosts", "/Volumes/My Book/photos", "/tmp/a b c"])
    func leadingSlashIsBarePath(path: String) {
        #expect(TypedAddress.classify(path) == .barePath(path))
    }

    @Test("surrounding whitespace is trimmed before classifying")
    func trimsWhitespace() {
        #expect(TypedAddress.classify("  /tank/media  ") == .barePath("/tank/media"))
    }

    // MARK: - host:path

    @Test("a colon splits into host and path")
    func hostPathSplits() {
        #expect(TypedAddress.classify("koan:/tank") == .hostPath(host: "koan", path: "/tank"))
    }

    @Test("an explicit local: prefix is still host:path, not a bare path")
    func localPrefixIsHostPath() {
        #expect(TypedAddress.classify("local:/Users") == .hostPath(host: "local", path: "/Users"))
    }

    @Test("the split takes the first colon — a path may carry more")
    func splitsOnFirstColon() {
        #expect(
            TypedAddress.classify("koan:/tank/a:b") == .hostPath(host: "koan", path: "/tank/a:b"))
    }

    @Test("a host with an empty path means that host's home")
    func emptyPathMeansHome() {
        #expect(TypedAddress.classify("koan:") == .hostPath(host: "koan", path: "~"))
    }

    @Test("a tilde path after a host stays a tilde path")
    func tildeAfterHost() {
        #expect(TypedAddress.classify("koan:~/notes") == .hostPath(host: "koan", path: "~/notes"))
    }

    // MARK: - Bare host aliases

    @Test("a bare alias is a host")
    func bareAliasIsHost() {
        #expect(TypedAddress.classify("koan") == .host("koan"))
    }

    @Test("a tilde path names no host of its own — it is not a bare path")
    func tildePathIsNotBarePath() {
        #expect(TypedAddress.classify("~/notes") == .host("~/notes"))
        #expect(TypedAddress.classify("~") == .host("~"))
    }

    @Test(
        "dots and @ in colon-free input infer nothing — still a host alias",
        arguments: ["mandala.sageframe.net", "atm@koan", "koan-2"])
    func noInferenceFromPunctuation(input: String) {
        #expect(TypedAddress.classify(input) == .host(input))
    }

    // MARK: - Nothing to point at

    @Test("empty and whitespace-only input classify to nil")
    func emptyIsNil() {
        #expect(TypedAddress.classify("") == nil)
        #expect(TypedAddress.classify("    ") == nil)
    }

    @Test("a colon with no host before it classifies to nil — the pane no-ops")
    func emptyHostIsNil() {
        #expect(TypedAddress.classify(":/tank") == nil)
        #expect(TypedAddress.classify(":") == nil)
    }
}
