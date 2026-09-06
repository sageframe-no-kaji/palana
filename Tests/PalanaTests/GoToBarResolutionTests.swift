// GoToBarResolutionTests — what the go-to sheet says before Go. One address
// field, one grammar: the resolved scope reads `this Mac · …`, `koan · …`,
// or `current pane: koan · …`; a refusal reads in place; an empty field
// says nothing. Go is possible only when the text resolves.

import PalanaCore
import Testing

@testable import Palana

@Suite("go-to sheet — resolution shown before Go")
struct GoToBarResolutionTests {
    @Test("a bare path shows this Mac, whatever pane is focused")
    func barePathShowsThisMac() {
        for currentHost in ["koan", Engine.localHost, nil] {
            let resolution = GoToBar.resolution(of: "/Users/atm/notes", currentHost: currentHost)
            #expect(
                resolution
                    == .address(
                        ResolvedAddress(host: "local", path: "/Users/atm/notes"), line: "this Mac · /Users/atm/notes"))
        }
    }

    @Test("a pasted, quoted local path replacing the prefilled remote address shows this Mac")
    func pastedLocalReplacesRemoteScope() {
        let prefilled = GoToBar.resolution(of: "koan:/srv/media", currentHost: "koan")
        #expect(prefilled == .address(ResolvedAddress(host: "koan", path: "/srv/media"), line: "koan · /srv/media"))
        let pasted = GoToBar.resolution(of: "\"/Users/atm/My Folder\"\n", currentHost: "koan")
        #expect(
            pasted
                == .address(
                    ResolvedAddress(host: "local", path: "/Users/atm/My Folder"),
                    line: "this Mac · /Users/atm/My Folder"))
    }

    @Test("a named host shows that host")
    func namedHostShows() {
        #expect(
            GoToBar.resolution(of: "koan:/tank", currentHost: nil).resolved
                == ResolvedAddress(host: "koan", path: "/tank"))
        #expect(GoToBar.scopeLine(for: ResolvedAddress(host: "koan", path: "/tank")) == "koan · /tank")
        #expect(GoToBar.scopeLine(for: ResolvedAddress(host: "koan", path: "~")) == "koan · ~")
    }

    @Test("the : shorthand names the pane's host as such")
    func currentHostShows() {
        let remote = GoToBar.resolution(of: ":/srv", currentHost: "koan")
        #expect(
            remote
                == .address(
                    ResolvedAddress(host: "koan", path: "/srv", usesCurrentHost: true),
                    line: "current pane: koan · /srv"))
        let local = GoToBar.resolution(of: ":/srv", currentHost: Engine.localHost)
        #expect(
            local
                == .address(
                    ResolvedAddress(host: "local", path: "/srv", usesCurrentHost: true),
                    line: "current pane: this Mac · /srv"))
    }

    @Test("the : shorthand on an unpointed pane is a refusal, not a silent no-op")
    func currentHostAbsentRefuses() {
        #expect(
            GoToBar.resolution(of: ":/srv", currentHost: nil) == .refusal(AddressParseError.noCurrentHost.description))
    }

    @Test("an empty field says nothing and offers no address")
    func emptyIsQuiet() {
        #expect(GoToBar.resolution(of: "", currentHost: "koan") == .empty)
        #expect(GoToBar.resolution(of: "  \n", currentHost: "koan") == .empty)
        #expect(GoToBar.resolution(of: "", currentHost: "koan").resolved == nil)
    }

    @Test(
        "a malformed address reads as its refusal and offers no address",
        arguments: ["\"/tank", "/a\n/b", "smb://nas/x", "koan:notes", "$(id):/x", "atm@koan:/tank"])
    func refusalShows(input: String) {
        let resolution = GoToBar.resolution(of: input, currentHost: "koan")
        guard case .failure(let refusal) = PaneModel.resolveAddress(input, currentHost: "koan") else {
            Issue.record("\(input) was expected to refuse")
            return
        }
        #expect(resolution == .refusal(refusal.description))
        #expect(resolution.resolved == nil)
    }
}
