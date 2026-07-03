// Host enumeration. The parser reads the operator's ssh config and returns
// the named aliases — nothing more. No HostName lookup, no port, no user:
// resolution belongs to ssh itself, applied through the Conduit exactly as
// the terminal would. A parallel resolver would be a parallel identity,
// which the seed forbids.

import Foundation

/// Pure enumeration of `Host` aliases from ssh config text.
///
/// `Include` directives are followed through an injected resolver, so the
/// parse stays pure — tests hand in a dictionary, the app hands in the
/// filesystem.
public enum SSHConfigParser {
    /// ssh's own include-depth cap, mirrored here.
    static let maxIncludeDepth = 16

    /// Enumerates host aliases: `Host` tokens carrying no wildcard.
    ///
    /// Patterns with `*` or `?` and negations with `!` are matching
    /// machinery, not named hosts — they are skipped. Aliases keep
    /// first-seen order, deduplicated.
    public static func hosts(
        in text: String,
        including resolve: (String) -> [String] = { _ in [] }
    ) -> [String] {
        var seen = Set<String>()
        var aliases: [String] = []
        collect(text, depth: 0, resolve: resolve, seen: &seen, into: &aliases)
        return aliases
    }

    /// Reads `~/.ssh/config`, or empty when absent — an unconfigured
    /// machine is a field with no named hosts, not an error.
    public static func systemConfigText(
        sshDirectory: URL = defaultSSHDirectory
    ) -> String {
        let url = sshDirectory.appendingPathComponent("config")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// A filesystem resolver for `Include` paths.
    ///
    /// Relative paths resolve against the ssh directory per ssh_config(5);
    /// `~` and glob patterns expand the way ssh expands them.
    public static func systemInclude(
        relativeTo sshDirectory: URL = defaultSSHDirectory
    ) -> (String) -> [String] {
        { path in
            let pattern: String
            if path.hasPrefix("/") || path.hasPrefix("~") {
                pattern = path
            } else {
                pattern = sshDirectory.appendingPathComponent(path).path
            }
            return expand(pattern).compactMap { file in
                try? String(contentsOf: URL(fileURLWithPath: file), encoding: .utf8)
            }
        }
    }

    /// `~/.ssh`.
    public static var defaultSSHDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    }

    private static func collect(
        _ text: String,
        depth: Int,
        resolve: (String) -> [String],
        seen: inout Set<String>,
        into aliases: inout [String]
    ) {
        guard depth <= maxIncludeDepth else { return }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let tokens = tokenize(line)
            guard let keyword = tokens.first?.lowercased() else { continue }
            let arguments = Array(tokens.dropFirst())
            switch keyword {
            case "host":
                for pattern in arguments where isAlias(pattern) {
                    if seen.insert(pattern).inserted {
                        aliases.append(pattern)
                    }
                }
            case "include":
                for path in arguments {
                    for included in resolve(path) {
                        collect(
                            included,
                            depth: depth + 1,
                            resolve: resolve,
                            seen: &seen,
                            into: &aliases)
                    }
                }
            default:
                continue
            }
        }
    }

    /// A token names a host when it carries no matching machinery.
    private static func isAlias(_ token: String) -> Bool {
        !token.isEmpty && !token.hasPrefix("!")
            && !token.contains("*") && !token.contains("?")
    }

    /// Splits a config line on whitespace or `=`, honoring double quotes —
    /// `Host "my host"` is one token.
    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        var sawKeywordSeparator = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if !quoted, character == " " || character == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if !quoted, character == "=", !sawKeywordSeparator, tokens.count <= 1 {
                // ssh_config allows `Keyword = value` — one separator, once.
                sawKeywordSeparator = true
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Glob expansion via the system's own glob(3), tilde included.
    private static func expand(_ pattern: String) -> [String] {
        var globResult = glob_t()
        defer { globfree(&globResult) }
        guard glob(pattern, GLOB_TILDE, nil, &globResult) == 0 else { return [] }
        return (0..<Int(globResult.gl_pathc)).compactMap { index in
            globResult.gl_pathv[index].flatMap { String(cString: $0) }
        }
    }
}
