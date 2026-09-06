// The parser's policy boundaries: OpenSSH inline comments, Match as a
// block end, shared Host lines, the reserved local name, and the alias
// grammar. Each suite reproduces a failure the 2026-09-06 review named —
// a comment enumerated as a host, a Match block deleted with the host
// before it, a sibling alias deleted with its sibling, a real `Host local`
// routed to this Mac. Pure text — no ssh, no filesystem.

import Testing

@testable import PalanaCore

// MARK: - Inline comments

@Suite("SSHConfigParser inline comments")
struct SSHConfigParserCommentTests {
    @Test("an unquoted # on a Host line ends the aliases")
    func hostLineComment() {
        #expect(SSHConfigParser.hosts(in: "Host jodo # production box") == ["jodo"])
        #expect(SSHConfigParser.excludedAliases(in: "Host jodo # production box").isEmpty)
    }

    @Test("a # inside a token is literal, per OpenSSH")
    func hashInsideToken() {
        #expect(SSHConfigParser.tokenize("Host jodo#1 chumon") == ["Host", "jodo#1", "chumon"])
    }

    @Test("a quoted # is text, not a comment")
    func quotedHash() {
        #expect(SSHConfigParser.tokenize("Host \"a # b\" c") == ["Host", "a # b", "c"])
        #expect(SSHConfigParser.tokenize("Host 'a # b' c") == ["Host", "a # b", "c"])
    }

    @Test("escapes resolve to the escaped character")
    func escapes() {
        #expect(
            SSHConfigParser.tokenize(#"Host a\"b c\'d e\\f g\ h i\x"#)
                == ["Host", "a\"b", "c'd", "e\\f", "g h", "i\\x"])
    }

    @Test("an unterminated quote runs to the end of the line")
    func unterminatedQuote() {
        #expect(SSHConfigParser.tokenize("Host \"odd host") == ["Host", "odd host"])
    }

    @Test("= splits the keyword once; a later = is literal")
    func equalsSeparator() {
        #expect(SSHConfigParser.tokenize("Host=jodo") == ["Host", "jodo"])
        #expect(SSHConfigParser.tokenize("Host = jodo") == ["Host", "jodo"])
        #expect(SSHConfigParser.tokenize("Host =jodo chumon") == ["Host", "jodo", "chumon"])
        #expect(SSHConfigParser.tokenize("SetEnv FOO=bar") == ["SetEnv", "FOO=bar"])
    }

    @Test("token spans cover the token as written, quotes included")
    func tokenSpans() {
        let line = "Host \"jodo\"\tchumon"
        let tokens = SSHConfigParser.tokens(in: line)
        #expect(tokens.map(\.text) == ["Host", "jodo", "chumon"])
        #expect(tokens.map { String(line[$0.range]) } == ["Host", "\"jodo\"", "chumon"])
    }

    @Test("commented text after Include is not an include path")
    func includeComment() {
        var requested: [String] = []
        let hosts = SSHConfigParser.hosts(in: "Include config.d/* # extra hosts") { path in
            requested.append(path)
            return ["Host included"]
        }
        #expect(requested == ["config.d/*"])
        #expect(hosts == ["included"])
    }

    @Test("a commented User line still yields the user")
    func userComment() {
        let config = "Host jodo\n    User admin # ops login\n"
        #expect(SSHConfigParser.user(for: "jodo", in: config) == "admin")
    }

    @Test("hidden hosts read the Host line through the same tokenizer")
    func hiddenComment() {
        let config = "Host jodo # prod\n    # palana: hide\n    HostName x\n"
        #expect(SSHConfigParser.hiddenHosts(in: config) == ["jodo"])
    }

    @Test("hiding finds a block whose Host line carries a comment")
    func hideCommentedHost() throws {
        let config = "Host jodo # prod\n    HostName x\n"
        let hidden = try #require(SSHConfigParser.hiding(alias: "jodo", in: config))
        #expect(hidden == "Host jodo # prod\n    # palana: hide\n    HostName x\n")
    }
}

// MARK: - Match boundaries

@Suite("SSHConfigParser Match boundaries")
struct SSHConfigParserMatchTests {
    private let config = """
        Host jodo
            HostName 192.168.1.20

        Match host jodo user root
            ForwardAgent no

        Host chumon
            HostName 192.168.1.21
        """

    @Test("removing a host leaves the Match block that follows it")
    func removeKeepsMatch() throws {
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: config))
        #expect(
            result == """
                Match host jodo user root
                    ForwardAgent no

                Host chumon
                    HostName 192.168.1.21
                """)
    }

    @Test("a marker under a Match block hides no alias")
    func markerUnderMatch() {
        let text = "Host jodo\n    HostName x\nMatch host jodo\n    # palana: hide\n    ForwardAgent no\n"
        #expect(SSHConfigParser.hiddenHosts(in: text).isEmpty)
        #expect(SSHConfigParser.showing(alias: "jodo", in: text) == nil)
    }

    @Test("hiding stops at the Match line — the marker lands in the Host block")
    func hideStopsAtMatch() throws {
        let text = "Host jodo\nMatch host jodo\n    ForwardAgent no\n"
        let hidden = try #require(SSHConfigParser.hiding(alias: "jodo", in: text))
        // An empty block takes the four-space default, not the Match block's indent.
        #expect(hidden == "Host jodo\n    # palana: hide\nMatch host jodo\n    ForwardAgent no\n")
    }

    @Test("User under a following Match is not the alias's own")
    func userStopsAtMatch() {
        let text = "Host jodo\n    HostName x\nMatch host jodo\n    User root\n"
        #expect(SSHConfigParser.user(for: "jodo", in: text) == nil)
    }
}

// MARK: - Shared Host lines

@Suite("SSHConfigParser shared Host lines")
struct SSHConfigParserSharedAliasTests {
    @Test("removing one alias keeps the other and the shared options")
    func removeOneOfTwo() throws {
        let text = "Host jodo jodo-old\n    HostName 192.168.1.20\n    User admin\n\nHost chumon\n    HostName x\n"
        let result = try #require(SSHConfigParser.removing(alias: "jodo-old", from: text))
        #expect(result == "Host jodo\n    HostName 192.168.1.20\n    User admin\n\nHost chumon\n    HostName x\n")
    }

    @Test("removing the first of two aliases keeps the second")
    func removeFirstOfTwo() throws {
        let text = "Host jodo jodo-old\n    HostName x\n"
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: text))
        #expect(result == "Host jodo-old\n    HostName x\n")
    }

    @Test("a pattern sharing the line survives — Host * is policy")
    func patternSurvives() throws {
        let text = "Host jodo *\n    ServerAliveInterval 60\n"
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: text))
        #expect(result == "Host *\n    ServerAliveInterval 60\n")
    }

    @Test("an inline comment on the shared line stays")
    func commentSurvives() throws {
        let text = "Host jodo jodo-old # both\n    HostName x\n"
        let result = try #require(SSHConfigParser.removing(alias: "jodo-old", from: text))
        #expect(result == "Host jodo # both\n    HostName x\n")
    }

    @Test("tabs and repeated tokens are cut with their leading whitespace")
    func tabsAndRepeats() throws {
        let text = "Host\tjodo\tjodo\tchumon\n"
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: text))
        #expect(result == "Host\tchumon\n")
    }

    @Test("a CRLF shared line loses only the alias and keeps its line ending")
    func crlfSharedLine() throws {
        let text = "Host jodo alt\r\n    HostName x\r\n"
        let result = try #require(SSHConfigParser.removing(alias: "alt", from: text))
        #expect(result == "Host jodo\r\n    HostName x\r\n")
        #expect(SSHConfigParser.user(for: "jodo", in: "Host jodo\r\n    User admin\r\n") == "admin")
    }

    @Test("a quoted alias is cut with its quotes")
    func quotedAliasCut() throws {
        let text = "Host \"jodo\" chumon\n    HostName x\n"
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: text))
        #expect(result == "Host chumon\n    HostName x\n")
    }

    @Test("the block goes only when the alias was the last token")
    func lastTokenRemovesBlock() throws {
        let text = "Host jodo jodo-old\n    HostName x\n\nHost chumon\n    HostName y\n"
        let once = try #require(SSHConfigParser.removing(alias: "jodo-old", from: text))
        let twice = try #require(SSHConfigParser.removing(alias: "jodo", from: once))
        #expect(twice == "Host chumon\n    HostName y\n")
    }
}

// MARK: - Reserved name and grammar

@Suite("SSHConfigParser reserved name and grammar")
struct SSHConfigParserAliasPolicyTests {
    @Test("Host local never enumerates, in any case, and is named as refused")
    func reservedLocal() {
        let text = "Host local\n    HostName 127.0.0.1\nHost LOCAL jodo\n"
        #expect(SSHConfigParser.hosts(in: text) == ["jodo"])
        #expect(
            SSHConfigParser.excludedAliases(in: text) == [
                ExcludedAlias(token: "local", reason: .reserved),
                ExcludedAlias(token: "LOCAL", reason: .reserved),
            ])
    }

    @Test("tokens outside the grammar are refused and named")
    func outsideGrammar() {
        let text = "Host -flag user@box \"odd host\" jödo a:b jodo"
        #expect(SSHConfigParser.hosts(in: text) == ["jodo"])
        let excluded = SSHConfigParser.excludedAliases(in: text)
        #expect(excluded.map(\.token) == ["-flag", "user@box", "odd host", "jödo", "a:b"])
        #expect(excluded.allSatisfy { $0.reason == .outsideGrammar })
    }

    @Test("the grammar admits letters, digits, dot, hyphen, underscore")
    func grammarAdmits() {
        let text = "Host jodo kanyo-prod github.com 192.168.1.20 my_box A1"
        #expect(
            SSHConfigParser.hosts(in: text)
                == ["jodo", "kanyo-prod", "github.com", "192.168.1.20", "my_box", "A1"])
        #expect(SSHConfigParser.exclusion(of: "jodo") == nil)
    }

    @Test("patterns and empty tokens are neither aliases nor diagnostics")
    func patternsSilent() {
        #expect(SSHConfigParser.exclusion(of: "*") == nil)
        #expect(SSHConfigParser.exclusion(of: "!jodo") == nil)
        #expect(SSHConfigParser.exclusion(of: "") == nil)
        #expect(SSHConfigParser.excludedAliases(in: "Host * !jodo ??-probe").isEmpty)
        #expect(SSHConfigParser.hosts(in: "Host * !jodo ??-probe").isEmpty)
    }

    @Test("refused tokens are found through includes and deduplicated")
    func excludedThroughIncludes() {
        let excluded = SSHConfigParser.excludedAliases(in: "Host local\nInclude extra") { path in
            path == "extra" ? ["Host local -x", "Host -x"] : []
        }
        #expect(
            excluded == [
                ExcludedAlias(token: "local", reason: .reserved),
                ExcludedAlias(token: "-x", reason: .outsideGrammar),
            ])
    }

    @Test("the reserved name can still be removed, so the operator can clean it up")
    func reservedRemovable() throws {
        let text = "Host local\n    HostName 127.0.0.1\nHost jodo\n"
        let result = try #require(SSHConfigParser.removing(alias: "local", from: text))
        #expect(result == "Host jodo\n")
    }
}
