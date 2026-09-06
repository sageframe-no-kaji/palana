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

    /// Enumerates host aliases: `Host` tokens that are names, not machinery.
    ///
    /// Patterns with `*` or `?` and negations with `!` are matching
    /// machinery, not named hosts — they are skipped silently. Tokens
    /// outside the alias grammar and the reserved `local` are refused and
    /// reported by ``excludedAliases(in:including:)``. Aliases keep
    /// first-seen order, deduplicated. Lines are tokenized to OpenSSH's
    /// rules, so an inline `# comment` never becomes an alias.
    public static func hosts(
        in text: String,
        including resolve: (String) -> [String] = { _ in [] }
    ) -> [String] {
        var seen = Set<String>()
        var aliases: [String] = []
        walk(text, depth: 0, resolve: resolve) { pattern in
            guard isAlias(pattern), seen.insert(pattern).inserted else { return }
            aliases.append(pattern)
        }
        return aliases
    }

    /// The `Host` tokens ``hosts(in:including:)`` refused, with reasons —
    /// the surface's diagnostic, so a refusal is never silent.
    ///
    /// Follows `Include`s the same way. First-seen order, deduplicated.
    public static func excludedAliases(
        in text: String,
        including resolve: (String) -> [String] = { _ in [] }
    ) -> [ExcludedAlias] {
        var seen = Set<String>()
        var excluded: [ExcludedAlias] = []
        walk(text, depth: 0, resolve: resolve) { pattern in
            guard let reason = exclusion(of: pattern), seen.insert(pattern).inserted else { return }
            excluded.append(ExcludedAlias(token: pattern, reason: reason))
        }
        return excluded
    }

    /// Reads `~/.ssh/config` as a document — ``SSHConfigDocument/absent``
    /// when there is none, a typed error when it exists but cannot be read.
    public static func systemConfig(
        sshDirectory: URL = defaultSSHDirectory
    ) throws(SSHConfigReadError) -> SSHConfigDocument {
        try SSHConfigDocument.read(at: sshDirectory.appendingPathComponent("config"))
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

    /// Visits every `Host` token in `text` and its includes, in order.
    private static func walk(
        _ text: String,
        depth: Int,
        resolve: (String) -> [String],
        visit: (String) -> Void
    ) {
        guard depth <= maxIncludeDepth else { return }
        for rawLine in lines(of: text) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let tokens = tokenize(line)
            guard let keyword = tokens.first?.lowercased() else { continue }
            let arguments = Array(tokens.dropFirst())
            switch keyword {
            case "host":
                for pattern in arguments { visit(pattern) }
            case "include":
                for path in arguments {
                    for included in resolve(path) {
                        walk(included, depth: depth + 1, resolve: resolve, visit: visit)
                    }
                }
            default:
                continue
            }
        }
    }

    /// The lines of `text`, with CRLF and bare CR read as line ends.
    ///
    /// Swift treats `\r\n` as one `Character`, so splitting on `\n` alone
    /// would leave a CRLF file as a single line. readconf strips `\r` as
    /// trailing whitespace; normalizing first names the same hosts it does.
    static func lines(of text: String) -> [Substring] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
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
    /// index of the next `Host` or `Match` line, or `lines.count` when the
    /// block runs to EOF.
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
        var currentAliases: [String] = []
        var blockIsHidden = false
        for rawLine in lines(of: text) {
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
            case "match":
                // A Match block ends the Host block before it; a marker
                // under Match belongs to no alias.
                flushHiddenBlock(currentAliases, isHidden: blockIsHidden, into: &hidden)
                currentAliases = []
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

    /// The index of the first `Host` or `Match` line at or after
    /// ``startIndex``, or ``lines.count`` when no further block begins.
    ///
    /// `Match` is a boundary too: ssh_config(5) ends a `Host` block at
    /// either keyword, and a `Match` block is policy that no host edit may
    /// take with it.
    private static func findBlockEnd(from startIndex: Int, in lines: [String]) -> Int {
        for i in startIndex..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = tokenize(trimmed)
            guard let keyword = tokens.first?.lowercased() else { continue }
            if keyword == "host" || keyword == "match" { return i }
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

    // MARK: - Add and remove transforms

    /// Returns new config text with ``block`` appended as a top-level `Host`
    /// block, or `nil` when the alias already exists in ``text``.
    ///
    /// The composed block is separated from any preceding content by exactly
    /// one blank line. An empty or whitespace-only ``text`` receives the block
    /// with no leading blank line. Adding a duplicate alias is a refusal so
    /// the surface can route the operator to remove-first or choose a
    /// different alias — it is not a silent second block.
    ///
    /// Validation is the caller's gate: the block is composed and appended
    /// regardless of whether it passes ``HostBlock/validate()``. Write only
    /// validated blocks.
    public static func adding(_ block: HostBlock, to text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        // Refuse to add a duplicate alias.
        if findBlock(for: block.alias, in: lines) != nil { return nil }

        let composed = block.compose()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return composed
        }
        // Preserve the input's line endings; append after one blank separator.
        let stripped = text.hasSuffix("\n") ? String(text.dropLast()) : text
        return stripped + "\n\n" + composed
    }

    /// Returns new config text with the named alias removed, or `nil` when
    /// the alias is not present in ``text``.
    ///
    /// When the alias shares its `Host` line with other tokens (`Host jodo
    /// jodo-old`, `Host jodo *`), only the alias token is cut — the other
    /// names, any pattern, the shared options, and an inline comment stay
    /// byte-for-byte. The whole block goes only when the alias was the
    /// line's last token. Block boundaries are found via the same
    /// ``findBlock``/``findBlockEnd`` machinery used by ``hiding(alias:in:)``
    /// and ``showing(alias:in:)``, so a following `Match` block is never
    /// taken along. Surrounding blocks and `Include` lines are left intact.
    /// The double blank line that would otherwise appear where a block was
    /// is collapsed to a single blank line.
    ///
    /// Returns `nil` when the alias is absent — the surface can distinguish
    /// "already gone" from "written" rather than silently succeeding.
    public static func removing(alias: String, from text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let block = findBlock(for: alias, in: lines) else { return nil }

        let hostLine = lines[block.hostLine]
        let hostTokens = tokens(in: hostLine)
        if hostTokens.dropFirst().contains(where: { $0.text != alias }) {
            lines[block.hostLine] = dropping(alias: alias, from: hostLine, tokens: hostTokens)
            return lines.joined(separator: "\n")
        }

        // Remove the block's lines (half-open: hostLine..<end).
        lines.removeSubrange(block.hostLine..<block.end)

        // Collapse any double blank lines left by the removal.
        // A run of two or more consecutive empty lines becomes one.
        var result: [String] = []
        var consecutiveBlanks = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                consecutiveBlanks += 1
                if consecutiveBlanks <= 1 { result.append(line) }
            } else {
                consecutiveBlanks = 0
                result.append(line)
            }
        }

        // Strip a leading blank line that would appear when the removed block
        // was the first entry in the file.
        while result.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            result.removeFirst()
        }

        return result.joined(separator: "\n")
    }

    /// The `Host` line with every `alias` token cut out — each with the
    /// whitespace run before it — and every other byte as it was.
    ///
    /// Works on UTF-8 offsets from the original line so the cuts never
    /// depend on string indices surviving a mutation.
    private static func dropping(alias: String, from line: String, tokens: [Token]) -> String {
        let bytes = Array(line.utf8)
        var keep = [Bool](repeating: true, count: bytes.count)
        for token in tokens.dropFirst() where token.text == alias {
            var start = line.utf8.distance(from: line.startIndex, to: token.range.lowerBound)
            let end = line.utf8.distance(from: line.startIndex, to: token.range.upperBound)
            while start > 0, bytes[start - 1] == UInt8(ascii: " ") || bytes[start - 1] == UInt8(ascii: "\t") {
                start -= 1
            }
            for offset in start..<end { keep[offset] = false }
        }
        let kept = bytes.indices.filter { keep[$0] }.map { bytes[$0] }
        // Every cut starts and ends on a character boundary of a string that
        // was valid UTF-8, so the remainder is too — nothing to fail on.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: kept, as: UTF8.self)
    }
}
