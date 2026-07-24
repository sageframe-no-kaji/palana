// GoToRevealTests — the pure path split behind "point at a file, land in its
// folder with the file revealed" (⌘⇧G / address bar with a file path). When a
// pointed path turns out to be a file (Listing throws `notADirectory`),
// `PaneModel.read` re-points at `parentPath(of:)` and reveals `lastComponent`.
// This pins that split; the async redirect + select is exercised by running.

import Testing

@testable import Palana

@Suite("go-to file reveal — path split")
struct GoToRevealTests {
    @Test(
        "a file path splits into its folder and leaf",
        arguments: [
            ("/Users/me/Desktop/report.pdf", "/Users/me/Desktop", "report.pdf"),
            ("/etc/hosts", "/etc", "hosts"),
            ("/var/log/system.log", "/var/log", "system.log"),
            ("/tank/media/clip.mov", "/tank/media", "clip.mov"),
            ("/top.txt", "/", "top.txt"),
        ])
    func splits(path: String, parent: String, leaf: String) {
        #expect(PaneModel.parentPath(of: path) == parent)
        #expect(PaneModel.lastComponent(of: path) == leaf)
    }

    @Test("a trailing slash does not fool the split")
    func trailingSlash() {
        #expect(PaneModel.parentPath(of: "/a/b/c/") == "/a/b")
        #expect(PaneModel.lastComponent(of: "/a/b/c/") == "c")
    }

    @Test("a root-level leaf lands at root, and root is its own parent (no loop)")
    func rootGuard() {
        #expect(PaneModel.parentPath(of: "/top.txt") == "/")
        // The redirect guard compares parent to the incoming path; "/" is a
        // fixed point, so a bare "/" never redirects again.
        #expect(PaneModel.parentPath(of: "/") == "/")
    }
}
