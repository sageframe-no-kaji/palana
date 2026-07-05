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

    // MARK: - Hide parsing

    /// The set of aliases whose ``Host`` block carries a `# palana: hide`
    /// marker line.
    ///
    /// Follows ``Include`` directives through the injected resolver, matching
    /// the behaviour of ``hosts(in:including:)``. Every alias a marked block
    /// declares is included — shared blocks are all-or-nothing. The canonical
    /// marker form is `# palana: hide` (exact lowercase), but leading and
    /// interior whitespace is tolerated as well as CRLF line endings.
    public static func hiddenHosts(
        in text: String,
        including resolve: (String) -> [String] = { _ in [] }
    ) -> Set<String> {
        var hidden = Set<String>()
        collectHidden(text, depth: 0, resolve: resolve, into: &hidden)
        return hidden
    }

    // MARK: - Hide transform

    /// Returns new config text with a `# palana: hide` marker inserted as
    /// the first line inside the named alias's ``Host`` block.
    ///
    /// The marker is indented to match the block's existing option
    /// indentation, or four spaces when the block is empty. Returns `nil`
    /// when:
    /// - the alias is not found in the top-level text (for example it is
    ///   declared inside an ``Include``'d file — the caller surfaces
    ///   "managed in an included file" rather than writing somewhere
    ///   surprising);
    /// - the block already carries the marker (nothing to do).
    ///
    /// Everything outside the inserted line is byte-for-byte identical to
    /// the input, including line endings and comments.
    public static func hiding(alias: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let block = findBlock(for: alias, in: lines) else { return nil }
        for i in block.hostLine + 1..<block.end
        where isHideMarker(lines[i].trimmingCharacters(in: .whitespacesAndNewlines)) {
            return nil
        }
        let indent = blockIndent(lines: lines, block: block)
        let cr = text.contains("\r\n") ? "\r" : ""
        lines.insert("\(indent)# palana: hide\(cr)", at: block.hostLine + 1)
        return lines.joined(separator: "\n")
    }

    /// Returns new config text with all `# palana: hide` marker lines
    /// removed from the named alias's ``Host`` block.
    ///
    /// Returns `nil` when:
    /// - the alias is not found in the top-level text;
    /// - the block carries no marker (nothing to do).
    ///
    /// Everything outside the removed line is byte-for-byte identical to
    /// the input.
    public static func showing(alias: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let block = findBlock(for: alias, in: lines) else { return nil }
        var markerIndices: [Int] = []
        for i in block.hostLine + 1..<block.end
        where isHideMarker(lines[i].trimmingCharacters(in: .whitespacesAndNewlines)) {
            markerIndices.append(i)
        }
        guard !markerIndices.isEmpty else { return nil }
        for i in markerIndices.reversed() {
            lines.remove(at: i)
        }
        return lines.joined(separator: "\n")
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

    // MARK: - Hide private helpers

    /// The half-open index range [hostLine, end) describing a ``Host`` block.
    ///
    /// `hostLine` is the index of the `Host` keyword line; `end` is the
    /// index of the next `Host` line or `lines.count` when the block runs
    /// to EOF.
    private struct BlockRange {
        var hostLine: Int
        var end: Int
    }

    private static func collectHidden(
        _ text: String,
        depth: Int,
        resolve: (String) -> [String],
        into hidden: inout Set<String>
    ) {
        guard depth <= maxIncludeDepth else { return }
        // Normalize CRLF and bare CR to LF before parsing so the marker check
        // and keyword recognition see clean lines regardless of the file's
        // original line-ending convention.
        let normalized =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var currentAliases: [String] = []
        var blockIsHidden = false
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if isHideMarker(trimmed) {
                blockIsHidden = true
                continue
            }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = tokenize(trimmed)
            guard let keyword = tokens.first?.lowercased() else { continue }
            let arguments = Array(tokens.dropFirst())
            switch keyword {
            case "host":
                flushHiddenBlock(currentAliases, isHidden: blockIsHidden, into: &hidden)
                currentAliases = arguments.filter(isAlias)
                blockIsHidden = false
            case "include":
                flushHiddenBlock(currentAliases, isHidden: blockIsHidden, into: &hidden)
                currentAliases = []
                blockIsHidden = false
                expandHiddenIncludes(arguments, depth: depth, resolve: resolve, into: &hidden)
            default:
                continue
            }
        }
        flushHiddenBlock(currentAliases, isHidden: blockIsHidden, into: &hidden)
    }

    /// Inserts ``aliases`` into ``hidden`` when the block was marked hidden.
    private static func flushHiddenBlock(
        _ aliases: [String], isHidden: Bool, into hidden: inout Set<String>
    ) {
        guard isHidden else { return }
        for alias in aliases { hidden.insert(alias) }
    }

    /// Follows ``Include`` ``paths`` and collects hidden hosts recursively.
    private static func expandHiddenIncludes(
        _ paths: [String],
        depth: Int,
        resolve: (String) -> [String],
        into hidden: inout Set<String>
    ) {
        for path in paths {
            for included in resolve(path) {
                collectHidden(included, depth: depth + 1, resolve: resolve, into: &hidden)
            }
        }
    }

    /// `true` when ``trimmed`` (already stripped of outer whitespace) matches
    /// the marker grammar: `#` then optional whitespace then `palana:` then
    /// optional whitespace then `hide`.
    ///
    /// Uses `.whitespacesAndNewlines` for interior trimming so that a
    /// trailing `\r` on a CRLF line (which may survive outer trimming in
    /// some Foundation runtimes) doesn't break the comparison.
    private static func isHideMarker(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("#") else { return false }
        let afterHash = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard afterHash.hasPrefix("palana:") else { return false }
        let afterColon = afterHash.dropFirst("palana:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return afterColon == "hide"
    }

    /// Finds the ``BlockRange`` for the ``Host`` block that declares
    /// ``alias`` in the top-level ``lines``.
    ///
    /// Returns `nil` when the alias is not found — the caller surfaces the
    /// "managed in an included file" boundary rather than writing somewhere
    /// surprising.
    private static func findBlock(for alias: String, in lines: [String]) -> BlockRange? {
        for (i, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = tokenize(trimmed)
            guard tokens.first?.lowercased() == "host" else { continue }
            let arguments = Array(tokens.dropFirst())
            guard arguments.contains(alias) else { continue }
            return BlockRange(hostLine: i, end: findBlockEnd(from: i + 1, in: lines))
        }
        return nil
    }

    /// The index of the first `Host` line at or after ``startIndex``, or
    /// ``lines.count`` when no further block begins.
    private static func findBlockEnd(from startIndex: Int, in lines: [String]) -> Int {
        for i in startIndex..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = tokenize(trimmed)
            guard let keyword = tokens.first?.lowercased() else { continue }
            if keyword == "host" { return i }
        }
        return lines.count
    }

    /// The leading-whitespace string from the first non-empty option line
    /// in ``block``, or four spaces when the block is empty.
    private static func blockIndent(lines: [String], block: BlockRange) -> String {
        for i in block.hostLine + 1..<block.end {
            let raw = lines[i]
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var indent = ""
            for ch in raw {
                guard ch == " " || ch == "\t" else { break }
                indent.append(ch)
            }
            return indent.isEmpty ? "    " : indent
        }
        return "    "
    }
}
