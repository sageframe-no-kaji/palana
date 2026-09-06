// TypedAddressTests — the one grammar behind every address the operator
// types or pastes. A bare path is this Mac by rule, a remote host is always
// named, `:` borrows the pane's host, and the clipboard's wrappers come off
// without a shell ever seeing the text. The hostile corpus is table-driven:
// each row is one thing a real paste has carried.

import Foundation
import Testing

@testable import PalanaCore

/// One corpus row — the pasted text and what it must parse to.
struct AddressCase: CustomTestStringConvertible, Sendable {
    let input: String
    let expected: TypedAddress
    let note: String

    init(_ input: String, _ expected: TypedAddress, _ note: String) {
        self.input = input
        self.expected = expected
        self.note = note
    }

    var testDescription: String { note }
}

/// One refusal row — the pasted text and the refusal it must draw.
struct RefusalCase: CustomTestStringConvertible, Sendable {
    let input: String
    let expected: AddressParseError
    let note: String

    init(_ input: String, _ expected: AddressParseError, _ note: String) {
        self.input = input
        self.expected = expected
        self.note = note
    }

    var testDescription: String { note }
}

@Suite("TypedAddress: the grammar")
struct TypedAddressGrammarTests {
    // MARK: - This Mac, by rule

    @Test(
        "a bare absolute path is this Mac, colons and all",
        arguments: [
            AddressCase("/tank", .local(path: "/tank"), "plain"),
            AddressCase("/", .local(path: "/"), "root"),
            AddressCase("/tmp/a:b", .local(path: "/tmp/a:b"), "colon inside the path is not a host prefix"),
            AddressCase("/Volumes/My Book/photos", .local(path: "/Volumes/My Book/photos"), "spaces"),
            AddressCase(
                "/Users/atmarcus/Library/CloudStorage/GoogleDrive-atmarcus@gmail.com/My Drive",
                .local(path: "/Users/atmarcus/Library/CloudStorage/GoogleDrive-atmarcus@gmail.com/My Drive"),
                "an @ in the path infers nothing"),
            AddressCase("/tank/it's here", .local(path: "/tank/it's here"), "an internal apostrophe stays"),
            AddressCase("/tank/日本語/写真", .local(path: "/tank/日本語/写真"), "non-ASCII stays"),
        ])
    func barePathIsLocal(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "a tilde path is this Mac, never a host alias",
        arguments: [
            AddressCase("~/notes", .local(path: "~/notes"), "~/path"),
            AddressCase("~", .local(path: "~"), "~ alone"),
            AddressCase("~/a:b", .local(path: "~/a:b"), "colon after the tilde is still a path"),
        ])
    func tildeIsLocal(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "local: is this Mac explicitly; an empty path is home",
        arguments: [
            AddressCase("local:/Users", .local(path: "/Users"), "local:/path"),
            AddressCase("local:~/notes", .local(path: "~/notes"), "local:~/path"),
            AddressCase("local:", .local(path: "~"), "local: alone means home"),
            AddressCase("LOCAL:/Users", .local(path: "/Users"), "the reserved name is case-insensitive, as in ssh"),
            AddressCase("local", .local(path: "~"), "bare local is this Mac's home"),
        ])
    func explicitLocal(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    // MARK: - A named host

    @Test(
        "host: names that host; an empty path is its home",
        arguments: [
            AddressCase("koan:/tank", .host(name: "koan", path: "/tank"), "host:/path"),
            AddressCase("koan:~/notes", .host(name: "koan", path: "~/notes"), "host:~/path"),
            AddressCase("koan:", .host(name: "koan", path: "~"), "host: alone means home"),
            AddressCase("koan:~", .host(name: "koan", path: "~"), "host:~"),
            AddressCase("koan:/tank/a:b", .host(name: "koan", path: "/tank/a:b"), "only the first colon splits"),
            AddressCase(
                "mandala.sageframe.net:/srv",
                .host(name: "mandala.sageframe.net", path: "/srv"),
                "dots in the alias"),
            AddressCase("koan-2:/srv", .host(name: "koan-2", path: "/srv"), "hyphen in the alias"),
        ])
    func namedHost(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "a colon-free alias is that host's home — the standing shorthand",
        arguments: [
            AddressCase("koan", .host(name: "koan", path: "~"), "plain"),
            AddressCase("mandala.sageframe.net", .host(name: "mandala.sageframe.net", path: "~"), "dotted"),
            AddressCase("koan-2", .host(name: "koan-2", path: "~"), "hyphenated"),
            AddressCase(
                "notes.txt",
                .host(name: "notes.txt", path: "~"),
                "colon-free text in the grammar is a host, not a local relative path"),
        ])
    func bareHostIsHome(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    // MARK: - The pane's host

    @Test(
        ": borrows the pane's host",
        arguments: [
            AddressCase(":/tank", .currentHost(path: "/tank"), ":/path"),
            AddressCase(":~/notes", .currentHost(path: "~/notes"), ":~/path"),
            AddressCase(":", .currentHost(path: "~"), ": alone means the pane host's home"),
        ])
    func currentHostShorthand(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(": resolves to a remote pane host")
    func currentHostRemote() throws {
        let resolved = try TypedAddress.resolve(":/tank", currentHost: "koan")
        #expect(resolved == ResolvedAddress(host: "koan", path: "/tank", usesCurrentHost: true))
        #expect(!resolved.isLocal)
    }

    @Test(": resolves to this Mac when the pane is local")
    func currentHostLocal() throws {
        let resolved = try TypedAddress.resolve(":/tank", currentHost: PalanaCore.localHostName)
        #expect(resolved == ResolvedAddress(host: "local", path: "/tank", usesCurrentHost: true))
        #expect(resolved.isLocal)
    }

    @Test(": on a pane that points nowhere is refused by name, not treated as nil")
    func currentHostAbsent() {
        #expect(throws: AddressParseError.noCurrentHost) {
            try TypedAddress.resolve(":/tank", currentHost: nil)
        }
        #expect(throws: AddressParseError.noCurrentHost) {
            try TypedAddress.resolve(":", currentHost: "")
        }
    }

    @Test("named addresses resolve regardless of the pane's host")
    func resolutionIgnoresPaneForNamedScopes() throws {
        #expect(
            try TypedAddress.resolve("/tank", currentHost: "koan")
                == ResolvedAddress(host: "local", path: "/tank"))
        #expect(
            try TypedAddress.resolve("~/notes", currentHost: "koan")
                == ResolvedAddress(host: "local", path: "~/notes"))
        #expect(
            try TypedAddress.resolve("koan:/tank", currentHost: nil)
                == ResolvedAddress(host: "koan", path: "/tank"))
        #expect(
            try TypedAddress.resolve("koan:/tank", currentHost: "jodo")
                == ResolvedAddress(host: "koan", path: "/tank"))
    }
}

@Suite("TypedAddress: the hostile clipboard")
struct TypedAddressClipboardTests {
    // MARK: - Wrappers that come off

    @Test(
        "edge whitespace, line terminators, BOM, and zero-width characters come off",
        arguments: [
            AddressCase("/tank/media\n", .local(path: "/tank/media"), "trailing newline"),
            AddressCase("/tank/media\r\n", .local(path: "/tank/media"), "trailing CRLF"),
            AddressCase("  /tank/media  ", .local(path: "/tank/media"), "spaces both sides"),
            AddressCase("\t/tank/media\n\n", .local(path: "/tank/media"), "tab and two newlines"),
            AddressCase("\u{FEFF}/tank/media", .local(path: "/tank/media"), "byte-order mark"),
            AddressCase("\u{200B}koan:/tank\u{200B}", .host(name: "koan", path: "/tank"), "zero-width spaces"),
            AddressCase("\u{2060}~/notes\u{00A0}", .local(path: "~/notes"), "word joiner and no-break space"),
        ])
    func edgeNoise(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "one matched pair of enclosing quotes comes off — straight or smart, local or remote",
        arguments: [
            AddressCase("\"/Users/atm/My Folder\"", .local(path: "/Users/atm/My Folder"), "straight double, local"),
            AddressCase("'/Users/atm/My Folder'", .local(path: "/Users/atm/My Folder"), "straight single, local"),
            AddressCase("“/Users/atm/My Folder”", .local(path: "/Users/atm/My Folder"), "smart double, local"),
            AddressCase("‘/Users/atm/My Folder’", .local(path: "/Users/atm/My Folder"), "smart single, local"),
            AddressCase("\"koan:/tank/media\"", .host(name: "koan", path: "/tank/media"), "straight double, remote"),
            AddressCase("“koan:/tank/media”", .host(name: "koan", path: "/tank/media"), "smart double, remote"),
            AddressCase("'~/notes'", .local(path: "~/notes"), "quoted tilde path"),
            AddressCase("\"/Users/atm/My Folder\"\n", .local(path: "/Users/atm/My Folder"), "quoted then newline"),
        ])
    func enclosingQuotes(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "matched quotes come off once; internal quotes and apostrophes stay",
        arguments: [
            AddressCase("\"/tank/\"inner\"/x\"", .local(path: "/tank/\"inner\"/x"), "inner double quotes survive"),
            AddressCase("'/tank/it's here'", .local(path: "/tank/it's here"), "inner apostrophe survives"),
            AddressCase(
                "/tank/\"quoted\"", .local(path: "/tank/\"quoted\""), "a trailing quote on a slash-led path is content"),
            AddressCase("/tank'", .local(path: "/tank'"), "a trailing apostrophe on a slash-led path is content"),
            AddressCase(
                "koan:/tank\"", .host(name: "koan", path: "/tank\""), "a trailing quote after a host is content"),
        ])
    func quotesRemovedOnce(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "shell-copy escapes decode: space, quotes, apostrophe, backslash",
        arguments: [
            AddressCase("/Users/atm/My\\ Folder", .local(path: "/Users/atm/My Folder"), "escaped space"),
            AddressCase("/Users/atm/it\\'s", .local(path: "/Users/atm/it's"), "escaped apostrophe"),
            AddressCase("/Users/atm/say\\ \\\"hi\\\"", .local(path: "/Users/atm/say \"hi\""), "escaped double quotes"),
            AddressCase("/Users/atm/back\\\\slash", .local(path: "/Users/atm/back\\slash"), "escaped backslash"),
            AddressCase(
                "/Users/atm/a\\\\\\ b", .local(path: "/Users/atm/a\\ b"), "doubled backslash then escaped space"),
            AddressCase("koan:/tank/My\\ Media", .host(name: "koan", path: "/tank/My Media"), "escaped space, remote"),
            AddressCase("~/My\\ Notes", .local(path: "~/My Notes"), "escaped space after tilde"),
        ])
    func escapesDecode(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "a backslash before anything else is a literal pathname byte",
        arguments: [
            AddressCase("/tmp/a\\b", .local(path: "/tmp/a\\b"), "backslash-b stays"),
            AddressCase("/tmp/a\\", .local(path: "/tmp/a\\"), "trailing backslash stays"),
            AddressCase("/tmp/a\\(b\\)", .local(path: "/tmp/a\\(b\\)"), "parentheses are not in the decoded set"),
            AddressCase("/tmp/a\\~b", .local(path: "/tmp/a\\~b"), "tilde is not in the decoded set"),
        ])
    func literalBackslashes(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "a file:// URL is this Mac, percent-decoded",
        arguments: [
            AddressCase("file:///Users/Andrew/My%20File", .local(path: "/Users/Andrew/My File"), "percent space"),
            AddressCase("file:///tank/a%3Ab", .local(path: "/tank/a:b"), "percent colon"),
            AddressCase("file:///Users/Andrew/%E5%86%99%E7%9C%9F", .local(path: "/Users/Andrew/写真"), "percent UTF-8"),
            AddressCase("FILE:///Users/Andrew", .local(path: "/Users/Andrew"), "scheme case-insensitive"),
            AddressCase("file://localhost/Users/Andrew", .local(path: "/Users/Andrew"), "localhost authority"),
            AddressCase(
                "\"file:///Users/Andrew/My%20File\"\n", .local(path: "/Users/Andrew/My File"), "quoted, newline"),
        ])
    func fileURLs(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    // MARK: - Refusals

    @Test(
        "unmatched quotes, NUL, non-file URLs, and multi-line pastes are refused",
        arguments: [
            RefusalCase("\"/tank", .unmatchedQuote, "leading double quote alone"),
            RefusalCase("\"/tank'", .unmatchedQuote, "mismatched pair"),
            RefusalCase("’/tank’", .unmatchedQuote, "a closing smart quote cannot open"),
            RefusalCase("\"\"/tank\"\"", .malformedHost("\"/tank\""), "one pair off, the remainder is not an address"),
            RefusalCase("“/tank\"", .unmatchedQuote, "smart open, straight close"),
            RefusalCase("\"", .unmatchedQuote, "a lone quote"),
            RefusalCase("/tank\u{0}media", .nulCharacter, "NUL inside"),
            RefusalCase("/tank\n/media", .multipleLines, "two lines"),
            RefusalCase("koan:/tank\nlocal:/Users", .multipleLines, "two addresses"),
            RefusalCase("/tank\r/media", .multipleLines, "bare CR inside"),
            RefusalCase("/tank\u{2028}/media", .multipleLines, "line separator inside"),
            RefusalCase("https://example.com/x", .unsupportedURLScheme("https"), "https"),
            RefusalCase("ssh://koan/tank", .unsupportedURLScheme("ssh"), "ssh"),
            RefusalCase("smb://nas/share", .unsupportedURLScheme("smb"), "smb"),
            RefusalCase("file://koan/tank", .malformedFileURL, "file URL naming another host"),
            RefusalCase("file://", .malformedFileURL, "file URL with no path"),
            RefusalCase("", .empty, "empty"),
            RefusalCase("   \n", .empty, "whitespace only"),
            RefusalCase("\"\"", .empty, "empty quotes"),
            RefusalCase("\u{FEFF}", .empty, "a BOM alone"),
        ])
    func refusals(_ row: RefusalCase) {
        #expect(throws: row.expected) { try TypedAddress.parse(row.input) }
    }

    @Test(
        "shell expressions are never evaluated — literal inside a path, refused as a host otherwise",
        arguments: [
            AddressCase("/tank/$HOME", .local(path: "/tank/$HOME"), "$HOME inside a path stays literal"),
            AddressCase("/tank/$(rm -rf x)", .local(path: "/tank/$(rm -rf x)"), "command substitution stays literal"),
            AddressCase("/tank/`id`", .local(path: "/tank/`id`"), "backticks stay literal"),
            AddressCase("/tank/a|b;c>d<e", .local(path: "/tank/a|b;c>d<e"), "pipes, semicolons, redirects stay"),
            AddressCase("/tank/*.mov", .local(path: "/tank/*.mov"), "a glob stays a glob"),
            AddressCase("koan:/tank/$HOME/*", .host(name: "koan", path: "/tank/$HOME/*"), "remote path stays literal"),
        ])
    func shellTextIsLiteralInPaths(_ row: AddressCase) throws {
        #expect(try TypedAddress.parse(row.input) == row.expected)
    }

    @Test(
        "shell-shaped or malformed host text is refused, never expanded or run",
        arguments: [
            RefusalCase("$HOME/notes", .malformedHost("$HOME/notes"), "$HOME with no scope"),
            RefusalCase("$(hostname):/tank", .malformedHost("$(hostname)"), "substitution before the colon"),
            RefusalCase("`id`", .malformedHost("`id`"), "backticks alone"),
            RefusalCase("koan;rm -rf /:/tank", .malformedHost("koan;rm -rf /"), "semicolon in the host"),
            RefusalCase("koan|cat:/tank", .malformedHost("koan|cat"), "pipe in the host"),
            RefusalCase("-oProxyCommand=x:/tank", .malformedHost("-oProxyCommand=x"), "leading hyphen"),
            RefusalCase("atm@koan:/tank", .malformedHost("atm@koan"), "user@host is outside the alias grammar"),
            RefusalCase("atm@koan", .malformedHost("atm@koan"), "user@host colon-free too"),
            RefusalCase("*:/tank", .malformedHost("*"), "a pattern is not a host"),
            RefusalCase("My Folder", .malformedHost("My Folder"), "spaces are outside the grammar"),
            RefusalCase("kōan:/tank", .malformedHost("kōan"), "non-ASCII is outside the grammar"),
            RefusalCase("koan:notes", .relativePath(host: "koan", path: "notes"), "a relative path after a host"),
            RefusalCase("koan:$HOME", .relativePath(host: "koan", path: "$HOME"), "$HOME after a host is not a path"),
            RefusalCase(":notes", .relativePath(host: "", path: "notes"), "a relative path after the shorthand"),
        ])
    func malformedHosts(_ row: RefusalCase) {
        #expect(throws: row.expected) { try TypedAddress.parse(row.input) }
    }

    // MARK: - The refusal lines

    @Test("every refusal reads as one line naming the cause")
    func refusalLines() {
        #expect(AddressParseError.empty.description == "nothing to point at")
        #expect(AddressParseError.nulCharacter.description.contains("NUL"))
        #expect(AddressParseError.multipleLines.description.contains("more than one line"))
        #expect(AddressParseError.unmatchedQuote.description.contains("unmatched quote"))
        #expect(AddressParseError.unsupportedURLScheme("smb").description.contains("smb://"))
        #expect(AddressParseError.malformedFileURL.description.contains("file://"))
        #expect(AddressParseError.malformedHost("a b").description.hasPrefix("not a host name: a b"))
        #expect(AddressParseError.relativePath(host: "koan", path: "x").description.hasPrefix("koan: needs"))
        #expect(AddressParseError.noCurrentHost.description.contains("points nowhere"))
    }

    @Test("a URL scheme needs letters, then ://; a host with one slash is not a scheme")
    func schemeDetection() {
        #expect(TypedAddress.urlScheme(of: "file:///x") == "file")
        #expect(TypedAddress.urlScheme(of: "git+ssh://x") == "git+ssh")
        #expect(TypedAddress.urlScheme(of: "koan:/tank") == nil)
        #expect(TypedAddress.urlScheme(of: "koan") == nil)
        #expect(TypedAddress.urlScheme(of: "1abc://x") == nil)
        #expect(TypedAddress.urlScheme(of: "a b://x") == nil)
    }
}
