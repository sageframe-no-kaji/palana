// The version-bound commit for round-trip send-back — the guard a plan
// carries out of the destination check, and the POSIX-sh program that
// proves the destination is still that exact version before a byte of
// it is replaced.
//
// Reading a digest and then composing an ordinary copy is not a
// binding: the destination can change in the gap, and the upload then
// overwrites work nobody approved for replacement (2026-09-08 audit).
// Here the bytes land in a staging directory of the operation's own on
// the destination's filesystem, the commit re-reads the destination,
// and promotion is a rename followed by `ln` — the version standing
// there is always set aside under a named recovery entry before the
// new one takes the pathname, `ln` refuses atomically if the pathname
// was taken in between, and the set-aside version is removed only
// after it proves to be the one that was checked.

import Foundation

/// The exact remote version a send-back is authorised to replace.
///
/// Carried from the destination check into the plan and re-proved at
/// commit. A plan without one has no authority to replace anything.
public struct RemoteVersionGuard: Codable, Sendable, Equatable {
    /// The host the destination lives on.
    public var host: String

    /// The full destination path, byte-exact — never passed through `String`.
    public var pathData: Data

    /// Lowercase SHA-256 hex of the version being replaced, or `nil`
    /// when the check found nothing there and the send-back creates it.
    public var expectedDigest: String?

    /// The operation token — makes every staging and recovery entry unique.
    public var token: String

    /// Binds a send-back to one remote version.
    ///
    /// - Parameters:
    ///   - host: The host the destination lives on.
    ///   - pathData: The full destination path, byte-exact.
    ///   - expectedDigest: SHA-256 hex of the version being replaced; nil for absence.
    ///   - token: The operation token.
    public init(host: String, pathData: Data, expectedDigest: String?, token: String) {
        self.host = host
        self.pathData = pathData
        self.expectedDigest = expectedDigest
        self.token = token
    }

    /// The destination path for display — lossy when the bytes are not UTF-8.
    public var path: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: pathData, as: UTF8.self)  // display only — messages, never composition
    }

    /// `host:path` — how every refusal names what it refused.
    public var target: String { "\(host):\(path)" }

    /// True when the check found no entry at the destination.
    public var expectsAbsence: Bool { expectedDigest == nil }
}

// MARK: - Composition

extension RemoteVersionGuard {
    /// The staging directory's bare name, unique to the operation.
    public static func stagingName(token: String) -> String { "palana-send-\(token)" }

    /// The displaced version's bare name, unique to the operation.
    public static func displacedName(token: String) -> String { "palana-replaced-\(token)" }

    /// The staging directory's full path under a destination directory.
    public static func stagingDirectory(in destination: String, token: String) -> String {
        join(destination, stagingName(token: token))
    }

    /// Joins a directory and a bare name.
    static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/\(name)" : "\(directory)/\(name)"
    }

    /// The commit program — the one step that may touch the destination path.
    ///
    /// Runs in the destination directory. Refuses unless the current
    /// version is exactly ``expectedDigest`` (or absent when that is
    /// nil), sets the standing version aside under a named recovery
    /// entry, takes the pathname with `ln` — which fails rather than
    /// clobber — and removes the set-aside copy only after proving it
    /// was the version that was checked. Every exit path clears the
    /// operation's staging directory or names what it retained.
    ///
    /// - Parameters:
    ///   - directory: The destination directory the send-back commits into.
    ///   - name: The destination entry's bare name.
    /// - Returns: One POSIX-sh program.
    func commitProgram(directory: String, name: String) -> String {
        let stage = ShellQuote.quote(Self.stagingName(token: token))
        let staged = ShellQuote.quote("\(Self.stagingName(token: token))/\(name)")
        let entry = ShellQuote.quote(name)
        let keptName = Self.displacedName(token: token)
        let kept = ShellQuote.quote(keptName)
        let keptPath = Self.join(directory, keptName)
        let stagePath = Self.join(directory, Self.stagingName(token: token))
        return [
            "PALANA_EXPECT=\(ShellQuote.quote(expectedDigest ?? ""))",
            "cd \(ShellQuote.quote(directory)) || \(bareRefusal("the destination directory could not be entered", code: 3))",
            "[ -f \(staged) ] && [ ! -L \(staged) ] || \(refusal("the upload did not land", stage: stage, code: 3))",
            TransferManifest.digestToolResolution(
                orElse: refusalBody(
                    "no sha256 tool here, so the version cannot be proved", stage: stage, code: 4)),
            currentVersionRead(entry: entry, stage: stage),
            "[ \"$PALANA_CURRENT\" = \"$PALANA_EXPECT\" ] || "
                + refusal("it is not the version that was checked", stage: stage, code: 5),
            promotion(entry: entry, staged: staged, kept: kept, keptPath: keptPath, stage: stage),
            "rm -rf -- \(stage) || \(retention("the staged copy could not be removed", path: stagePath))",
        ].joined(separator: "; ")
    }

    /// Reads what stands at the destination now, into `PALANA_CURRENT`.
    ///
    /// Empty for absence, the digest for a regular file, and the
    /// literal `other` for anything else — a directory, a symlink, a
    /// device — which no expectation can ever equal.
    private func currentVersionRead(entry: String, stage: String) -> String {
        [
            "if [ -e \(entry) ] || [ -L \(entry) ]",
            "then if [ -f \(entry) ] && [ ! -L \(entry) ]",
            "then PALANA_CURRENT=$($PALANA_DG < \(entry)) || "
                + refusal("the destination could not be read", stage: stage, code: 5),
            "PALANA_CURRENT=${PALANA_CURRENT#*= }; PALANA_CURRENT=${PALANA_CURRENT%% *}",
            "else PALANA_CURRENT=other; fi",
            "else PALANA_CURRENT=; fi",
        ].joined(separator: "; ")
    }

    /// Sets the standing version aside, takes the pathname, then rules
    /// on what was set aside.
    private func promotion(
        entry: String, staged: String, kept: String, keptPath: String, stage: String
    ) -> String {
        let restored =
            "echo "
            + ShellQuote.quote(
                "palana-restored: \(target) — the send could not be committed"
                    + "; the version that was there is back where it was") + " >&2"
        return [
            "if [ -n \"$PALANA_EXPECT\" ]",
            "then mv -- \(entry) \(kept) || "
                + refusal("the version standing there could not be set aside", stage: stage, code: 6),
            "if ln -- \(staged) \(entry) 2>/dev/null",
            "then rm -f -- \(staged)",
            "PALANA_KEPT=$($PALANA_DG < \(kept) 2>/dev/null); PALANA_KEPT=${PALANA_KEPT#*= }"
                + "; PALANA_KEPT=${PALANA_KEPT%% *}",
            "if [ \"$PALANA_KEPT\" = \"$PALANA_EXPECT\" ]; then rm -f -- \(kept)",
            "else "
                + retention(
                    "the version replaced was not the one checked, so it is kept here", path: keptPath)
                + "; fi",
            "else if ln -- \(kept) \(entry) 2>/dev/null; then rm -f -- \(kept); \(restored)",
            "else "
                + retention(
                    "the destination was taken while the send was committing, so the version"
                        + " you were replacing is kept here", path: keptPath) + "; fi",
            "rm -rf -- \(stage); exit 7; fi",
            "else ln -- \(staged) \(entry) 2>/dev/null || "
                + refusal("something now stands there", stage: stage, code: 7),
            "rm -f -- \(staged); fi",
        ].joined(separator: "; ")
    }

    /// A refusal that also clears the operation's staging directory.
    private func refusal(_ reason: String, stage: String, code: Int) -> String {
        "{ \(refusalBody(reason, stage: stage, code: code)); }"
    }

    private func refusalBody(_ reason: String, stage: String, code: Int) -> String {
        "echo \(ShellQuote.quote("palana-refused: \(target) — \(reason); nothing was replaced")) >&2"
            + "; rm -rf -- \(stage); exit \(code)"
    }

    /// A refusal from before the staging directory can be reached.
    private func bareRefusal(_ reason: String, code: Int) -> String {
        "{ echo \(ShellQuote.quote("palana-refused: \(target) — \(reason); nothing was replaced")) >&2"
            + "; exit \(code); }"
    }

    /// A line naming data this operation left behind, and exactly where.
    private func retention(_ reason: String, path: String) -> String {
        "echo \(ShellQuote.quote("palana-retained: \(host):\(path) — \(reason)")) >&2"
    }
}
