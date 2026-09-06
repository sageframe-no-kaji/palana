// SSHConfigParser+Tokens — the lexical layer. One tokenizer, written to
// OpenSSH's own readconf rules, feeds host enumeration, includes, the user
// lookup, hiding, showing, and removal; and one alias grammar decides which
// `Host` tokens pālana admits into its registry at all. Extracted from
// SSHConfigParser.swift so that file stays within the type-body budget.

import Foundation

/// Why a `Host` token is kept out of pālana's registry.
///
/// Wildcard and negation patterns are not exclusions — they are ssh's
/// matching machinery and are skipped without comment. These two are
/// diagnostics: the surface names the token and the reason.
public enum AliasExclusion: Equatable, Sendable {
    /// The token falls outside ``SSHConfigParser/aliasGrammar`` — it
    /// carries whitespace, shell-significant characters, non-ASCII, or a
    /// leading `-` that ssh would read as an option.
    case outsideGrammar
    /// The token is `local` (any case) — the name pālana reserves for the
    /// operator's own machine. A real `Host local` would be routed to this
    /// Mac instead of over the wire, so it is refused rather than rerouted.
    case reserved
}

/// A `Host` token the parser refused, with the reason.
public struct ExcludedAlias: Equatable, Sendable {
    /// The token as written in the config.
    public let token: String
    /// Why it was refused.
    public let reason: AliasExclusion
}

extension SSHConfigParser {
    /// One token of a config line and where it sits in the raw line.
    ///
    /// `range` spans the token as written — quotes included — so a
    /// transform can cut it out and leave every other byte alone.
    struct Token: Equatable {
        var text: String
        var range: Range<String.Index>
    }

    /// The alias grammar, as a description for diagnostics.
    ///
    /// An alias is `[A-Za-z0-9][A-Za-z0-9._-]*`: ASCII letters, digits,
    /// dot, hyphen, underscore; never a leading hyphen. Everything pālana
    /// hands to a shell as a host name satisfies this, which is what makes
    /// the composed commands safe to run.
    public static let aliasGrammar = "letters, digits, . _ - only; cannot start with -"

    /// Splits a config line the way OpenSSH's readconf does.
    ///
    /// - Spaces and tabs separate tokens, as do a stray `\r` or `\n` —
    ///   readconf strips those as trailing whitespace. One `=` may separate
    ///   the keyword from its first argument (`Host = jodo`, `Host=jodo`);
    ///   a `=` inside an argument is literal.
    /// - Double and single quotes group text into one token. `\"`, `\'`,
    ///   `\\`, and — outside quotes — `\ ` are escapes for the character
    ///   that follows. An unterminated quote runs to the end of the line.
    /// - An unquoted `#` at the start of a token begins a comment: the rest
    ///   of the line is dropped. A `#` inside a token (`jodo#1`) is literal.
    static func tokens(in line: String) -> [Token] {
        var tokens: [Token] = []
        var index = line.startIndex
        var sawKeywordSeparator = false
        while index < line.endIndex {
            let character = line[index]
            if isSeparator(character) {
                index = line.index(after: index)
                continue
            }
            if character == "=", !sawKeywordSeparator, tokens.count == 1 {
                sawKeywordSeparator = true
                index = line.index(after: index)
                continue
            }
            if character == "#" { break }
            let start = index
            let text = scanToken(in: line, from: &index, isKeyword: tokens.isEmpty)
            tokens.append(Token(text: text, range: start..<index))
        }
        return tokens
    }

    /// The token texts of a line — `tokens(in:)` without the spans.
    static func tokenize(_ line: String) -> [String] {
        tokens(in: line).map(\.text)
    }

    /// Scans one token starting at `index`, leaving `index` just past it.
    ///
    /// The keyword token also ends at an unquoted `=`; arguments do not.
    private static func scanToken(in line: String, from index: inout String.Index, isKeyword: Bool) -> String {
        var text = ""
        var quote: Character?
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if quote == nil, isSeparator(character) { break }
            if quote == nil, isKeyword, character == "=" { break }
            if character == "\\", next < line.endIndex {
                let escaped = line[next]
                if escaped == "\"" || escaped == "'" || escaped == "\\" || (quote == nil && escaped == " ") {
                    text.append(escaped)
                    index = line.index(after: next)
                    continue
                }
            }
            if quote == nil, character == "\"" || character == "'" {
                quote = character
            } else if quote == character {
                quote = nil
            } else {
                text.append(character)
            }
            index = next
        }
        return text
    }

    /// Space, tab, or a line-ending character that survived line splitting.
    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\r" || character == "\n" || character == "\r\n"
    }

    // MARK: - Alias grammar

    /// True when a `Host` token is a real host alias pālana admits.
    ///
    /// Patterns (wildcards, negations) are matching machinery, not names;
    /// tokens outside the grammar and the reserved `local` are refused —
    /// see ``exclusion(of:)`` for the reason. Internal so `HostBlock`
    /// validation shares the one rule.
    static func isAlias(_ token: String) -> Bool {
        !isPattern(token) && exclusion(of: token) == nil
    }

    /// True when a token is `Host`-pattern machinery: a wildcard (`*`,
    /// `?`) or a negation (`!`).
    static func isPattern(_ token: String) -> Bool {
        token.hasPrefix("!") || token.contains("*") || token.contains("?")
    }

    /// True when a token is the reserved local name, in any case.
    ///
    /// ssh matches `Host` patterns case-insensitively, so `LOCAL` and
    /// `local` are one host to ssh and both collide with pālana's own.
    static func isReserved(_ token: String) -> Bool {
        token.lowercased() == PalanaCore.localHostName
    }

    /// Why a `Host` token is refused, or `nil` when it is admitted.
    ///
    /// Empty tokens and patterns answer `nil` — they are not aliases, but
    /// they are not diagnostics either.
    public static func exclusion(of token: String) -> AliasExclusion? {
        guard !token.isEmpty, !isPattern(token) else { return nil }
        guard matchesAliasGrammar(token) else { return .outsideGrammar }
        return isReserved(token) ? .reserved : nil
    }

    /// `[A-Za-z0-9][A-Za-z0-9._-]*`, checked byte-wise so non-ASCII fails.
    private static func matchesAliasGrammar(_ token: String) -> Bool {
        guard let first = token.utf8.first, isAlphanumeric(first) else { return false }
        return token.utf8.allSatisfy { byte in
            isAlphanumeric(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
                || byte == UInt8(ascii: "_")
        }
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
