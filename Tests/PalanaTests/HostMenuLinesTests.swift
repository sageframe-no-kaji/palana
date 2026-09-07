// The host menu's composed lines, held as values — what the ▾ menu says
// before AppKit renders it. Two hands findings of 2026-09-07: an
// unreadable ~/.ssh/config left the menu showing only local:~ with no
// word of why, and every favorite carried a scope-toggle row that
// belongs in the favorites panel. No test here touches a real config;
// the diagnostic is handed in as a value.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@Suite("Host menu lines")
struct HostMenuLinesTests {
    private typealias Line = HostMenuLine

    private static let hosts = ["local", "jodo", "chumon"]
    private static let favorites = [
        HostMenuButton.FavoriteEntry(
            id: "jodo:/tank", host: "jodo", path: "/tank", label: "the pool", scope: .global),
        HostMenuButton.FavoriteEntry(
            id: "chumon:/srv", host: "chumon", path: "/srv", label: nil, scope: .host),
    ]

    private static func notices(_ lines: [Line]) -> [Line] {
        lines.filter { $0.kind == .notice }
    }

    @Test("an unreadable config yields one disabled line naming the file and the reason")
    func unreadableConfigYieldsDiagnosticLine() {
        let home = NSHomeDirectory()
        let failure = SSHConfigReadError.unreadable(path: "\(home)/.ssh/config", reason: "permission denied")
        let lines = HostMenuButton.lines(
            hosts: Self.hosts,
            favorites: [],
            diagnostic: HostMenuDiagnostic(readFailure: failure, refusedAliasCount: 0))

        let notices = Self.notices(lines)
        #expect(notices.count == 1)
        #expect(notices.first?.title == "~/.ssh/config could not be read — permission denied")
        #expect(notices.first?.isEnabled == false)
    }

    @Test("the system's trailing full stop is dropped and a foreign path stays as written")
    func reasonTrailingStopDropped() {
        let failure = SSHConfigReadError.unreadable(
            path: "/etc/ssh/ssh_config",
            reason: "The file “ssh_config” couldn’t be opened because you don’t have permission to view it.")
        #expect(
            HostMenuButton.readFailureTitle(failure)
                == "/etc/ssh/ssh_config could not be read — "
                + "The file “ssh_config” couldn’t be opened because you don’t have permission to view it")
    }

    @Test("a config that is not UTF-8 says so in the same shape")
    func notUTF8YieldsDiagnosticLine() {
        let failure = SSHConfigReadError.notUTF8(path: "\(NSHomeDirectory())/.ssh/config")
        let lines = HostMenuButton.lines(
            hosts: Self.hosts,
            favorites: [],
            diagnostic: HostMenuDiagnostic(readFailure: failure, refusedAliasCount: 0))
        #expect(Self.notices(lines).map(\.title) == ["~/.ssh/config could not be read — not UTF-8 text"])
    }

    @Test("a readable config with nothing refused yields no notice line")
    func readableConfigYieldsNoNotice() {
        let lines = HostMenuButton.lines(hosts: Self.hosts, favorites: Self.favorites, diagnostic: .clear)
        #expect(Self.notices(lines).isEmpty)
    }

    @Test(
        "refused aliases yield one count line pointing at settings",
        arguments: [
            (1, "1 host not listed — see settings"),
            (2, "2 hosts not listed — see settings"),
        ])
    func refusedAliasesYieldCountLine(count: Int, title: String) {
        let lines = HostMenuButton.lines(
            hosts: Self.hosts,
            favorites: [],
            diagnostic: HostMenuDiagnostic(readFailure: nil, refusedAliasCount: count))
        let notices = Self.notices(lines)
        #expect(notices.map(\.title) == [title])
        #expect(notices.first?.isEnabled == false)
    }

    @Test("both notices sit right under the host list, before the favorites and the ways in")
    func noticesSitUnderHosts() {
        let failure = SSHConfigReadError.unreadable(path: "/x/config", reason: "no")
        let lines = HostMenuButton.lines(
            hosts: ["local"],
            favorites: Self.favorites,
            diagnostic: HostMenuDiagnostic(readFailure: failure, refusedAliasCount: 3))
        #expect(
            lines.map(\.kind) == [
                .host("local"),
                .notice,
                .notice,
                .separator,
                .favoritesHeader,
                .favorite(id: "jodo:/tank"),
                .favorite(id: "chumon:/srv"),
                .separator,
                .typeAddress,
                .editConfig,
                .reload,
            ])
        #expect(lines.suffix(3).map(\.title) == ["type an address…", "edit ~/.ssh/config…", "reload hosts"])
    }

    @Test("a favorite is one jump line — never a scope-toggle row")
    func favoritesNeverYieldScopeToggle() {
        let lines = HostMenuButton.lines(hosts: Self.hosts, favorites: Self.favorites, diagnostic: .clear)
        let favoriteLines = lines.filter {
            if case .favorite = $0.kind { return true }
            return false
        }
        #expect(favoriteLines.map(\.title) == ["the pool", "chumon:/srv"])
        #expect(favoriteLines.allSatisfy { $0.isEnabled })
        let titles = lines.map(\.title)
        #expect(!titles.contains { $0.contains("promote to global") || $0.contains("move to this host") })
        // One line per favorite, plus header and separator — nothing indented beneath.
        #expect(lines.count == Self.hosts.count + 2 + Self.favorites.count + 4)
    }

    @Test("no favorites means no favorites section at all")
    func noFavoritesNoSection() {
        let lines = HostMenuButton.lines(hosts: ["local"], favorites: [], diagnostic: .clear)
        #expect(!lines.contains { $0.kind == .favoritesHeader })
        #expect(lines.filter { $0.kind == .separator }.count == 1)
    }
}
