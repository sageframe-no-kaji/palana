// Pre-1.0 safety rules (review 2026-11-15, findings 1, 2, 5, 6, 10).
//
// Three places a move could destroy what it claimed to carry:
//   - the destination is the source directory itself (a folder "merged"
//     into itself, then released as already-transferred);
//   - the destination sits inside a selected directory (the tree nests
//     into itself before the release refuses);
//   - custom rsync flags change what lands (--append, --compare-dest,
//     --dry-run, an excluded directory) while the engine still removes
//     the source.
// The first two are refused at plan time by path, and again on the host
// by a resolved-path guard that sees symlinks and bind mounts. The third
// is closed by giving a move no operator flags at all, and by refusing
// abbreviated or quoted spellings of the source-removal options on copies.

import Foundation

extension PlanEngine {
    // MARK: - Place

    /// Refuses a same-host copy or move whose destination is the source
    /// directory or lies inside one of the selected directories.
    ///
    /// Lexical — the host-side ``placeGuardStep(_:)`` catches the aliases
    /// (symlinks, bind mounts) that a path comparison cannot see.
    static func validatePlace(_ request: PlanRequest) throws {
        guard request.operation == .move || request.operation == .copy,
            let destination = request.destination,
            destination.host == request.source.host
        else { return }
        let source = Self.trimmed(request.source.directory)
        let target = Self.trimmed(destination.directory)
        guard source != target else { throw PlanError.sourceIsDestination }
        for entry in request.entries where entry.kind == .directory {
            let selected = source == "/" ? "/\(entry.name)" : "\(source)/\(entry.name)"
            if target == selected || target.hasPrefix(selected + "/") {
                throw PlanError.destinationInsideSelection
            }
        }
    }

    /// The host-side place guard for a same-host progressive move.
    ///
    /// Runs before the transfer, on the one host both ends live on, and
    /// fails the run when the resolved destination is the source
    /// directory or inside a selected entry, or when an entry's target is
    /// the entry itself (`-ef`: same device and inode). Nothing has
    /// moved when it fails.
    static func placeGuardStep(_ request: PlanRequest) -> PlanStep? {
        guard request.operation == .move,
            let destination = request.destination,
            destination.host == request.source.host
        else { return nil }
        let source = ShellQuote.quote(Self.trimmed(request.source.directory))
        let target = ShellQuote.quote(Self.trimmed(destination.directory))
        let names = request.entries.map { ShellQuote.quote($0.name) }.joined(separator: " ")
        let script = [
            "s=$(cd -P -- \(source) && pwd -P) && d=$(cd -P -- \(target) && pwd -P) || exit 1",
            "[ \"$s\" != \"$d\" ] || { echo 'palana-refused: the destination is the source folder' >&2; exit 1; }",
            "for n in \(names); do"
                + " case \"$d/\" in \"${s%/}/$n/\"*) echo \"palana-refused: the destination is inside $n\" >&2; exit 1;; esac;"
                + " if [ -e \"$d/$n\" ] && [ \"$s/$n\" -ef \"$d/$n\" ]; then"
                + " echo \"palana-refused: $n would be moved onto itself\" >&2; exit 1; fi;"
                + " done",
        ].joined(separator: "; ")
        return PlanStep(runsOn: Runner.host(request.source.host), command: script, role: .verify)
    }

    private static func trimmed(_ path: String) -> String {
        guard path != "/" else { return "/" }
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    // MARK: - Operator flags

    /// The long options that make rsync delete source files.
    private static let sourceRemovalOptions = ["--remove-source-files", "--remove-sent-files"]

    /// Refuses custom rsync flags that could delete source files on a
    /// copy, including the unambiguous abbreviations openrsync accepts
    /// (`--rem`), and any quoting or escaping, which the shell would
    /// resolve into an option this check never saw.
    ///
    /// On a copy — the only operation that takes operator flags — flags
    /// that decide how an interrupted transfer is kept are refused too:
    /// `.palana-partial` is what lets a stopped copy resume without a
    /// fragment under the file's own name (review Q06). A move drops
    /// operator flags, so they cannot reach it.
    static func validateRsyncOperatorFlags(_ flags: String?, copying: Bool = true) throws {
        guard let flags else { return }
        if flags.contains(where: { "'\"\\`$".contains($0) }) {
            throw PlanError.rsyncFlagsQuoted
        }
        let tokens = flags.lowercased().split(whereSeparator: \.isWhitespace)
        if tokens.contains(where: { Self.namesSourceRemoval(String($0)) }) {
            throw PlanError.rsyncFlagsControlSourceRemoval
        }
        let written = flags.split(whereSeparator: \.isWhitespace).map(String.init)
        if copying, written.contains(where: Self.controlsInterruptedCopies) {
            throw PlanError.rsyncFlagsControlInterruptedCopies
        }
    }

    /// The long options that decide where an interrupted transfer's bytes
    /// go, or whether they are reused (review Q06).
    private static let interruptedCopyOptions = [
        "--partial", "--partial-dir", "--no-partial", "--inplace", "--append", "--append-verify",
        "--delay-updates", "--whole-file", "--no-whole-file",
        // Forwards options to the other rsync process, where this check
        // cannot see them (review Q06, pass 2).
        "--remote-option",
    ]

    /// Short options whose value follows in the same token: the rest of the
    /// token is that value, not more options (`-T/tmp/Work` is a temp dir).
    private static let shortOptionsTakingValues: Set<Character> = ["B", "e", "f", "T", "@"]

    /// True when a flag token would change how an interrupted copy is kept.
    ///
    /// One of those long options, or an abbreviation rsync could read as
    /// one, or a short-option cluster holding `P` (`--partial --progress`),
    /// `W` (`--whole-file`) or `M` (`--remote-option`), read up to an option
    /// that takes the rest of the token as its value. The token is read as
    /// written: `-p` keeps permissions and is allowed.
    static func controlsInterruptedCopies(_ token: String) -> Bool {
        if token.hasPrefix("--") {
            let option = token.lowercased().split(separator: "=", maxSplits: 1).first.map(String.init) ?? token
            return option.count > 2 && Self.interruptedCopyOptions.contains { $0.hasPrefix(option) }
        }
        guard token.hasPrefix("-"), token.count > 1 else { return false }
        for option in token.dropFirst() {
            if option == "P" || option == "W" || option == "M" { return true }
            if Self.shortOptionsTakingValues.contains(option) { return false }
        }
        return false
    }

    /// True when a whitespace-delimited command token is a source-removal
    /// option, written out in full or abbreviated to at least `--rem`.
    ///
    /// Quoted tokens are paths, never options, so a file named
    /// `Remove-Sent-Items.pst` is not one.
    static func namesSourceRemoval(_ token: String) -> Bool {
        let lowered = token.lowercased()
        guard lowered.hasPrefix("--rem"), !lowered.contains(where: { "'\"\\".contains($0) })
        else { return false }
        let option = lowered.split(separator: "=", maxSplits: 1).first.map(String.init) ?? lowered
        return Self.sourceRemovalOptions.contains { $0.hasPrefix(option) }
    }
}
