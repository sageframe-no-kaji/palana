// What the operator typed or pasted into an address field, normalized and
// parsed before any pointing happens. Pure: text in, one address or one
// specific refusal out. No shell ever sees the text — the clipboard
// wrappers a copy picks up (a trailing newline, enclosing quotes, Terminal's
// backslash escapes, a file:// URL) are removed by a lexer written here,
// and nothing is expanded: `$HOME`, backticks, globs, and pipes stay literal
// where the grammar has already established a path, and are refused as a
// malformed host everywhere else.
//
// The grammar is stable and setting-free: a bare `/path` or `~/path` means
// this Mac on every installation, whatever pane is focused and whether or
// not the path also exists on a remote host. A remote host is always named
// (`koan:/tank`), and `:` alone names the focused pane's host.

import Foundation

/// Why typed or pasted text is not an address.
///
/// Each case is one visible refusal; none is silently repaired.
public enum AddressParseError: Error, Equatable, Sendable {
    /// Nothing remained once the clipboard wrappers came off.
    case empty
    /// The text carries a NUL, which no pathname can.
    case nulCharacter
    /// The text still carries a line break after edge trimming — a paste
    /// of more than one address, never taken as its first line.
    case multipleLines
    /// One edge carries a quote the other edge does not match.
    case unmatchedQuote
    /// A URL with a scheme other than `file`.
    case unsupportedURLScheme(String)
    /// A `file://` URL that did not decode to an absolute path.
    case malformedFileURL
    /// The text before the colon — or the whole colon-free text — is not
    /// a host alias pālana admits.
    case malformedHost(String)
    /// A host was named but the path after the colon is neither absolute
    /// nor `~`-rooted.
    case relativePath(host: String, path: String)
    /// `:` named the pane's host, and the pane points nowhere yet.
    case noCurrentHost
}

extension AddressParseError: CustomStringConvertible {
    /// The one quiet line a pane or sheet shows for the refusal.
    public var description: String {
        switch self {
        case .empty: "nothing to point at"
        case .nulCharacter: "the address carries a NUL character"
        case .multipleLines: "one address per paste — the clipboard held more than one line"
        case .unmatchedQuote: "unmatched quote around the address"
        case .unsupportedURLScheme(let scheme): "only file:// URLs are addresses, not \(scheme)://"
        case .malformedFileURL: "the file:// URL did not decode to a path"
        case .malformedHost(let host): "not a host name: \(host) — \(SSHConfigParser.aliasGrammar)"
        case .relativePath(let host, let path): "\(host): needs an absolute path or ~, not \(path)"
        case .noCurrentHost: "':' means this pane's host, and the pane points nowhere yet"
        }
    }
}

/// A typed address with its host resolved — what a pane points at.
public struct ResolvedAddress: Equatable, Sendable {
    /// The host — ``PalanaCore/localHostName`` for this Mac.
    public let host: String
    /// The path, exactly as it survived normalization.
    public let path: String
    /// True when the `:` shorthand supplied the host from the pane.
    public let usesCurrentHost: Bool

    /// True when the address points at this Mac.
    public var isLocal: Bool { host == PalanaCore.localHostName }

    /// The host as a line names it — `this Mac` for the local host.
    public var scopeName: String { isLocal ? "this Mac" : host }

    /// A resolved address.
    public init(host: String, path: String, usesCurrentHost: Bool = false) {
        self.host = host
        self.path = path
        self.usesCurrentHost = usesCurrentHost
    }
}

/// A typed address, normalized and classified, before any host is resolved.
///
/// Classification order, after normalization:
///
/// 1. `/path`, `~`, `~/path` — this Mac. Checked first, so a colon inside
///    an absolute path (`/tmp/a:b`) never becomes a host prefix.
/// 2. `file:///path` — this Mac, percent-decoded through `URL`. Any other
///    URL scheme is refused.
/// 3. `local:/path`, `local:~/path`, `local:` — this Mac, explicitly.
/// 4. `host:/path`, `host:~/path`, `host:` — that host; an empty path is
///    its home. The host must satisfy the SSH alias grammar.
/// 5. `:/path`, `:~/path`, `:` — the focused pane's host.
/// 6. Colon-free text inside the alias grammar (`koan`) — that host's
///    home, the standing shorthand. Colon-free text outside the grammar
///    is refused; it is never read as a relative local path.
public enum TypedAddress: Equatable, Sendable {
    /// This Mac — a bare path, a `file://` URL, or an explicit `local:`.
    case local(path: String)
    /// A named remote host.
    case host(name: String, path: String)
    /// The focused pane's host, whatever it is — the `:` shorthand.
    case currentHost(path: String)

    /// Parses typed or pasted text into an address, or throws the refusal.
    ///
    /// - Parameter input: The raw text, clipboard wrappers and all.
    /// - Returns: The classified address.
    /// - Throws: ``AddressParseError`` naming what made the text unusable.
    public static func parse(_ input: String) throws(AddressParseError) -> Self {
        let text = try normalize(input)
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return .local(path: text)
        }
        if let scheme = urlScheme(of: text) {
            guard scheme.lowercased() == "file" else { throw .unsupportedURLScheme(scheme) }
            return .local(path: try fileURLPath(text))
        }
        guard let colon = text.firstIndex(of: ":") else {
            return try hostAddress(name: text, path: "~")
        }
        let name = String(text[..<colon])
        let rest = String(text[text.index(after: colon)...])
        let path = rest.isEmpty ? "~" : rest
        guard path.hasPrefix("/") || path.hasPrefix("~") else {
            throw .relativePath(host: name, path: path)
        }
        if name.isEmpty { return .currentHost(path: path) }
        return try hostAddress(name: name, path: path)
    }

    /// Parses and resolves in one call — the funnel every entry point uses.
    ///
    /// - Parameters:
    ///   - input: The raw text.
    ///   - currentHost: The pane's host, for the `:` shorthand; nil when the
    ///     pane points nowhere.
    /// - Returns: The host and path to point at.
    /// - Throws: ``AddressParseError`` for a refusal, including
    ///   ``AddressParseError/noCurrentHost`` when `:` has no host to name.
    public static func resolve(_ input: String, currentHost: String?) throws(AddressParseError) -> ResolvedAddress {
        try parse(input).resolve(currentHost: currentHost)
    }

    /// Resolves the address against the pane's host.
    ///
    /// - Parameter currentHost: The pane's host, nil when it points nowhere.
    /// - Returns: The host and path to point at.
    /// - Throws: ``AddressParseError/noCurrentHost`` when the `:` shorthand
    ///   has no host to name.
    public func resolve(currentHost: String?) throws(AddressParseError) -> ResolvedAddress {
        switch self {
        case .local(let path):
            return ResolvedAddress(host: PalanaCore.localHostName, path: path)
        case .host(let name, let path):
            return ResolvedAddress(host: name, path: path)
        case .currentHost(let path):
            guard let currentHost, !currentHost.isEmpty else { throw .noCurrentHost }
            return ResolvedAddress(host: currentHost, path: path, usesCurrentHost: true)
        }
    }

    // MARK: - Hosts

    /// The reserved local name becomes ``local(path:)``; anything else must
    /// pass the alias grammar the SSH config parser admits.
    private static func hostAddress(name: String, path: String) throws(AddressParseError) -> Self {
        if name.lowercased() == PalanaCore.localHostName { return .local(path: path) }
        guard SSHConfigParser.isAlias(name) else { throw .malformedHost(name) }
        return .host(name: name, path: path)
    }

    // MARK: - URLs

    /// The scheme when the text is `scheme://…` — `[A-Za-z][A-Za-z0-9+.-]*`
    /// followed by `://`. `koan:/tank` has one slash and is not a URL.
    static func urlScheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = text[..<colon]
        guard
            let first = scheme.utf8.first, isLetter(first),
            scheme.utf8.allSatisfy({ isLetter($0) || isDigit($0) || $0 == 0x2B || $0 == 0x2E || $0 == 0x2D }),
            text[colon...].hasPrefix("://")
        else { return nil }
        return String(scheme)
    }

    /// The absolute path a `file://` URL names, percent-decoded by `URL`.
    ///
    /// Only an empty or `localhost` authority is a local file URL; a URL
    /// naming any other host is refused rather than reinterpreted.
    private static func fileURLPath(_ text: String) throws(AddressParseError) -> String {
        guard let url = URL(string: text), url.isFileURL else { throw .malformedFileURL }
        if let host = url.host, !host.isEmpty, host.lowercased() != "localhost" {
            throw .malformedFileURL
        }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/") else { throw .malformedFileURL }
        return path
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}

// MARK: - Clipboard normalization

extension TypedAddress {
    /// The characters a copy leaves at the edges: Unicode whitespace and
    /// line terminators, a byte-order mark, and the zero-width joiners and
    /// spaces rich-text editors attach.
    private static let edgeNoise: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{FEFF}\u{200B}\u{200C}\u{200D}\u{2060}")
        return set
    }()

    /// The enclosing pairs removed once: straight single, straight double,
    /// smart single, smart double.
    private static let quotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""), ("'", "'"), ("\u{2018}", "\u{2019}"), ("\u{201C}", "\u{201D}"),
    ]

    private static let quoteMarks: Set<Character> = ["\"", "'", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}"]

    /// The four characters a backslash escapes.
    ///
    /// Terminal's drag-and-drop set and OpenSSH's readconf set agree on
    /// these. A backslash before anything else is a literal pathname byte
    /// and stays.
    private static let escapable: Set<Character> = [" ", "\"", "'", "\\"]

    /// Removes the documented clipboard wrappers, in order, and nothing else.
    ///
    /// 1. NUL anywhere is refused.
    /// 2. Edge noise is trimmed — whitespace, line terminators, BOM,
    ///    zero-width characters.
    /// 3. A line break that survives trimming is refused: more than one
    ///    address was pasted, and the first is never taken silently.
    /// 4. Exactly one matched pair of enclosing quotes is removed; a leading
    ///    quote the far edge does not close is refused.
    /// 5. Backslash escapes for space, `"`, `'`, and `\` are decoded.
    ///
    /// Internal quotes, apostrophes, colons, spaces, and non-ASCII are
    /// preserved exactly.
    static func normalize(_ input: String) throws(AddressParseError) -> String {
        guard !input.unicodeScalars.contains("\u{0}") else { throw .nulCharacter }
        let trimmed = input.trimmingCharacters(in: edgeNoise)
        guard !trimmed.isEmpty else { throw .empty }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) else {
            throw .multipleLines
        }
        let unquoted = try stripEnclosingQuotes(trimmed)
        guard !unquoted.isEmpty else { throw .empty }
        return decodeEscapes(unquoted)
    }

    /// Removes one matched enclosing pair, or refuses a leading quote that
    /// the far edge does not close.
    ///
    /// Only a leading quote can open a wrapper: text that begins with `/`,
    /// `~`, or a host name is already an address, so a quote that merely
    /// ends it (`/tank/"quoted"`, `/Users/x/say\ \"hi\"`) is content and
    /// stays.
    private static func stripEnclosingQuotes(_ text: String) throws(AddressParseError) -> String {
        guard let first = text.first, quoteMarks.contains(first) else { return text }
        guard
            text.count >= 2, let last = text.last,
            quotePairs.contains(where: { $0.open == first && $0.close == last })
        else { throw .unmatchedQuote }
        return String(text.dropFirst().dropLast())
    }

    /// Decodes `\ `, `\"`, `\'`, and `\\`; every other backslash is kept.
    ///
    /// A pathname that literally contains one of the four sequences is
    /// spelled with its backslash doubled (`a\\ b` for `a\ b`), so every
    /// valid pathname remains expressible and no backslash is ever dropped
    /// by guesswork.
    private static func decodeEscapes(_ text: String) -> String {
        var decoded = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\\", next < text.endIndex, escapable.contains(text[next]) {
                decoded.append(text[next])
                index = text.index(after: next)
                continue
            }
            decoded.append(character)
            index = next
        }
        return decoded
    }
}
