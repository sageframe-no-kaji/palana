// The launch decision, pinned without a PTY: what process a fresh
// terminal session runs for a local pane and for a remote one, and how
// the summoning pane's directory rides along. The hands finding
// (2026-09-07): "opening the terminal should open it in the directory
// you are in! not just ssh!" No test here launches ssh — the remote
// case is a string, never a process.

import PalanaCore
import Testing

@testable import Palana

@Suite("TerminalLaunch: where a fresh session opens")
struct TerminalLaunchTests {
    private static let remoteCommandTail = #"&& exec sh -c 'exec "${SHELL:-sh}" -l'"#

    @Test("local uses $SHELL with -l and the pane's directory as the working directory")
    func localUsesShellInPaneDirectory() {
        let launch = TerminalLaunch.plan(
            host: PalanaCore.localHostName,
            directory: "/Users/op/Projects/palana",
            environment: ["SHELL": "/opt/homebrew/bin/fish"]
        )
        #expect(launch.executable == "/opt/homebrew/bin/fish")
        #expect(launch.args == ["-l"])
        #expect(launch.currentDirectory == "/Users/op/Projects/palana")
    }

    @Test("local falls back to /bin/zsh when $SHELL is unset")
    func localFallsBackToZsh() {
        let launch = TerminalLaunch.plan(host: PalanaCore.localHostName, directory: "/tmp", environment: [:])
        #expect(launch.executable == "/bin/zsh")
        #expect(launch.args == ["-l"])
        #expect(launch.currentDirectory == "/tmp")
    }

    @Test("remote builds ssh -t <alias> -- cd <dir> && exec the login shell, exact string")
    func remoteBuildsSSHWithCD() {
        let launch = TerminalLaunch.plan(
            host: "kanyo", directory: "/srv/kanyo/captures", environment: ["SHELL": "/opt/homebrew/bin/fish"])
        #expect(launch.executable == "/usr/bin/ssh")
        #expect(launch.args == ["-t", "kanyo", "--", "cd /srv/kanyo/captures \(Self.remoteCommandTail)"])
        #expect(launch.currentDirectory == nil, "the remote directory rides in the command, not the local cwd")
    }

    @Test("a remote directory with a space and a single quote is quoted for the remote shell")
    func remoteDirectoryIsQuoted() {
        let launch = TerminalLaunch.plan(
            host: "mandala", directory: "/srv/it's a dir", environment: [:])
        let expected = #"cd '/srv/it'\''s a dir' "# + Self.remoteCommandTail
        #expect(launch.args == ["-t", "mandala", "--", expected])
    }

    @Test("the alias is passed as a bare argument — no -F, no user, no options")
    func aliasIsBare() {
        let launch = TerminalLaunch.plan(host: "jodo", directory: "/", environment: [:])
        #expect(launch.args[1] == "jodo")
        #expect(!launch.args.contains { $0.hasPrefix("-F") })
        #expect(launch.args.count == 4, "-t, alias, --, command — nothing else")
    }

    @Test("the remote command names cd, the quoted directory, and exec, in that order")
    func remoteCommandShape() {
        let command = TerminalLaunch.remoteCommand(directory: "/var/log")
        #expect(command == "cd /var/log \(Self.remoteCommandTail)")
    }
}
