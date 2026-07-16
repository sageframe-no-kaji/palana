// SudoGuidanceTests — the security-sensitive sudoers line and the User prefill
// (ho-17). The sudo-explainer tells an operator what to put in their sudoers
// file; a line that drifted toward a blanket `zfs` grant would be a root-
// escalation footgun, so the exact string is pinned here — narrow to mount and
// unmount, absolute path, nothing more.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SudoGuidance — the narrow sudoers grant")
struct SudoGuidanceTests {
    @Test("the line grants exactly zfs mount and unmount, and nothing else")
    func exactLine() {
        let line = SudoGuidance.sudoersLine(user: "bob")
        #expect(line == "bob ALL=(root) NOPASSWD: /usr/sbin/zfs mount *, /usr/sbin/zfs unmount *")
    }

    @Test("the grant is narrow — mount and unmount only, never a blanket zfs")
    func narrowness() {
        let line = SudoGuidance.sudoersLine(user: "bob")
        #expect(line.contains("/usr/sbin/zfs mount *"))
        #expect(line.contains("/usr/sbin/zfs unmount *"))
        // No bare `zfs *` blanket that would grant every subcommand.
        #expect(!line.contains("/usr/sbin/zfs *"))
        // Runs as root, passwordless (that is the whole point of -n).
        #expect(line.contains("(root)"))
        #expect(line.contains("NOPASSWD:"))
    }

    @Test("the placeholder is an obvious fill-in, never a wrong guess")
    func placeholder() {
        let line = SudoGuidance.sudoersLine(user: SudoGuidance.userPlaceholder)
        #expect(line.hasPrefix("<user> ALL=(root)"))
    }

    @Test("a non-default zfs path threads through both commands")
    func customPath() {
        let line = SudoGuidance.sudoersLine(user: "root", zfsPath: "/sbin/zfs")
        #expect(line == "root ALL=(root) NOPASSWD: /sbin/zfs mount *, /sbin/zfs unmount *")
    }
}

@Suite("SSHConfigParser.user — the prefill lookup")
struct SSHConfigUserTests {
    @Test("reads User from the alias's own block")
    func explicitUser() {
        let config = """
            Host koan
                HostName 10.0.0.2
                User operator
            """
        #expect(SSHConfigParser.user(for: "koan", in: config) == "operator")
    }

    @Test("no User in the block → nil (the caller uses the placeholder)")
    func noUser() {
        let config = """
            Host koan
                HostName 10.0.0.2
            """
        #expect(SSHConfigParser.user(for: "koan", in: config) == nil)
    }

    @Test("a User in a different block is not returned for this alias")
    func userFromOtherBlock() {
        let config = """
            Host jodo
                User admin
            Host koan
                HostName 10.0.0.2
            """
        #expect(SSHConfigParser.user(for: "koan", in: config) == nil)
        #expect(SSHConfigParser.user(for: "jodo", in: config) == "admin")
    }

    @Test("the alias can be one of several on the Host line")
    func multiAliasLine() {
        let config = """
            Host koan koan.local
                User me
            """
        #expect(SSHConfigParser.user(for: "koan.local", in: config) == "me")
    }

    @Test("the keyword=value form parses")
    func equalsForm() {
        let config = """
            Host koan
                User = me
            """
        #expect(SSHConfigParser.user(for: "koan", in: config) == "me")
    }

    @Test("first value wins, as ssh resolves")
    func firstWins() {
        let config = """
            Host koan
                User first
                User second
            """
        #expect(SSHConfigParser.user(for: "koan", in: config) == "first")
    }

    @Test("a User inside an included file is followed")
    func followsInclude() {
        let main = """
            Include work/*
            """
        let included = """
            Host koan
                User included-user
            """
        let user = SSHConfigParser.user(for: "koan", in: main) { _ in [included] }
        #expect(user == "included-user")
    }
}
