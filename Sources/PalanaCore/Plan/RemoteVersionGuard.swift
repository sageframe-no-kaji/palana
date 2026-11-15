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
// and promotion uses a no-clobber rename — the version standing there
// is always preserved under a named recovery entry before the new one
// takes the pathname, `ln` refuses atomically if that pathname was
// taken, and the preserved version is removed only
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

    /// How the commit takes the pathname. nil is ``CommitMode/link`` —
    /// every guard written before the field existed.
    public var commitMode: CommitMode?

    /// How a send-back's commit puts the edit at the destination path.
    public enum CommitMode: String, Codable, Sendable, Equatable {
        /// `ln`: takes the name only if it is free, in one step. The default.
        case link
        /// `mv -n`, then a content check: for a filesystem with no hard
        /// links, and only when the operator chose it after the link
        /// commit refused. `mv -n` checks the name is free and then
        /// renames, so another writer arriving in between can be
        /// overwritten; the content check catches only a writer that
        /// arrives after the rename.
        case rename
    }

    /// Binds a send-back to one remote version.
    ///
    /// - Parameters:
    ///   - host: The host the destination lives on.
    ///   - pathData: The full destination path, byte-exact.
    ///   - expectedDigest: SHA-256 hex of the version being replaced; nil for absence.
    ///   - token: The operation token.
    ///   - commitMode: How the commit takes the pathname; nil is link.
    public init(
        host: String, pathData: Data, expectedDigest: String?, token: String, commitMode: CommitMode? = nil
    ) {
        self.host = host
        self.pathData = pathData
        self.expectedDigest = expectedDigest
        self.token = token
        self.commitMode = commitMode
    }

    /// True when the commit renames rather than links.
    public var renames: Bool { commitMode == .rename }

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
    /// was the version that was checked. A filesystem that cannot make
    /// the hard link is refused before anything is set aside (exit
    /// ``noHardLinkExitStatus``). Every exit path clears the operation's
    /// staging directory or names what it retained.
    ///
    /// - Parameters:
    ///   - directory: The destination directory the send-back commits into.
    ///   - name: The destination entry's bare name.
    /// - Returns: One POSIX-sh program.
    func commitProgram(directory: String, name: String) -> String {
        let names = CommitNames(directory: directory, name: name, token: token)
        let stage = names.stage
        let staged = names.staged
        let entry = names.entry
        let stagePath = names.stagePath
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
            renames ? sentDigest(names) : linkProbe(names),
            promotion(names),
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

    /// Refuses, before anything is set aside, where a hard link cannot
    /// be made.
    ///
    /// Promotion takes the pathname with `ln`, which refuses atomically
    /// if the name is taken. A filesystem with no hard links (exFAT, FAT,
    /// many FUSE and rclone mounts, some SMB shares) fails every `ln`;
    /// without this probe the standing version was set aside, the edit
    /// could not take its place, and the path was left empty (review
    /// 2026-11-15, finding 8). The probe links the staged file inside
    /// the staging directory — the destination's own filesystem — under
    /// a name that cannot be the staged entry's. Exit 8 is this refusal
    /// alone, so the surface can offer the rename commit instead.
    private func linkProbe(_ names: CommitNames) -> String {
        "if ln -- \(names.staged) \(names.probe) 2>/dev/null; then rm -f -- \(names.probe); else "
            + refusalBody(
                "a hard link could not be made here, so the file cannot be replaced safely",
                stage: names.stage,
                code: Int(Self.noHardLinkExitStatus))
            + "; fi"
    }

    /// The commit's exit status when the destination cannot make a hard link.
    ///
    /// Promotion needs one; nothing was replaced.
    public static let noHardLinkExitStatus: Int32 = 8

    /// Moves the standing version aside without clobbering, takes its
    /// pathname, then rules on what was preserved.
    ///
    /// Once the standing version is set aside, a failed promotion never
    /// deletes the staged edit: it stays in the staging directory and a
    /// retained note names it. A pathname another writer took is left
    /// to them, and both versions are named. A pathname still free gets
    /// the set-aside version back by `mv -n`, which counts only when
    /// the set-aside name is gone afterwards — some `mv` exit 0 when
    /// `-n` skips.
    private func promotion(_ names: CommitNames) -> String {
        let entry = names.entry
        let staged = names.staged
        let kept = names.kept
        let keptPath = names.keptPath
        let stage = names.stage
        let stagedPath = names.stagedPath
        let restored =
            "echo "
            + ShellQuote.quote(
                "palana-restored: \(target) — the send could not be committed"
                    + "; the version that was there is back where it was") + " >&2"
        let taken = "[ -e \(entry) ] || [ -L \(entry) ]"
        let takenNow = "the destination was taken while the send was committing"
        let place = placement(names)
        let editKept = { (reason: String) in
            "{ [ ! -e \(staged) ] || " + retention("\(reason), so your edit is kept here", path: stagedPath) + "; }"
        }
        return [
            "if [ -n \"$PALANA_EXPECT\" ]",
            "then [ ! -d \(kept) ] || "
                + refusal(
                    "the recovery name is already occupied",
                    stage: stage,
                    code: 6),
            "mv -n -- \(entry) \(kept) 2>/dev/null || "
                + refusal("the version standing there could not be set aside", stage: stage, code: 6),
            "[ ! -e \(entry) ] && [ ! -L \(entry) ] || "
                + refusal("the recovery name is already occupied", stage: stage, code: 6),
            "if \(place)",
            "then rm -f -- \(staged)",
            "PALANA_KEPT=$($PALANA_DG < \(kept) 2>/dev/null); PALANA_KEPT=${PALANA_KEPT#*= }"
                + "; PALANA_KEPT=${PALANA_KEPT%% *}",
            "if [ \"$PALANA_KEPT\" = \"$PALANA_EXPECT\" ]; then rm -f -- \(kept) || "
                + retention("the replaced version could not be removed", path: keptPath),
            "else "
                + retention(
                    "the version replaced was not the one checked, so it is kept here", path: keptPath)
                + "; fi",
            "elif \(taken)",
            "then "
                + retention("\(takenNow), so the version you were replacing is kept here", path: keptPath),
            renameStray(names) + editKept(takenNow),
            "exit 7",
            "else if mv -n -- \(kept) \(entry) 2>/dev/null && [ ! -e \(kept) ] && [ ! -L \(kept) ]"
                + "; then \(restored)",
            "else "
                + retention(
                    "the send could not be committed, so the version you were replacing is kept here",
                    path: keptPath) + "; fi",
            renameStray(names) + editKept("the send could not take the pathname"),
            "exit 7; fi",
            "elif \(place)",
            "then rm -f -- \(staged)",
            "elif \(taken)",
            "then " + renameStray(names) + refusal("something now stands there", stage: stage, code: 7),
            "else " + refusal("the send could not take the pathname", stage: stage, code: 7),
            "fi",
        ].joined(separator: "; ")
    }

    /// How the edit takes the pathname — the command whose success is
    /// the commit landing.
    ///
    /// Link mode: one `ln`, atomic. Rename mode: the name is checked
    /// free, `mv -n` renames (a directory there would swallow the file,
    /// so the check comes first), and the commit counts only when the
    /// staged name is gone and the destination holds the sent bytes.
    private func placement(_ names: CommitNames) -> String {
        guard renames else { return "ln -- \(names.staged) \(names.entry) 2>/dev/null" }
        return [
            "[ ! -e \(names.entry) ]", "[ ! -L \(names.entry) ]",
            "mv -n -- \(names.staged) \(names.entry) 2>/dev/null",
            "[ ! -e \(names.staged) ]", "[ ! -L \(names.staged) ]",
            "[ -f \(names.entry) ]", "[ ! -L \(names.entry) ]",
            "PALANA_LANDED=$($PALANA_DG < \(names.entry))",
            "PALANA_LANDED=${PALANA_LANDED#*= }", "PALANA_LANDED=${PALANA_LANDED%% *}",
            "[ \"$PALANA_LANDED\" = \"$PALANA_SENT\" ]",
        ].joined(separator: " && ")
    }

    /// Rename mode: the staged bytes' digest, read before anything is set aside.
    private func sentDigest(_ names: CommitNames) -> String {
        "PALANA_SENT=$($PALANA_DG < \(names.staged)) || "
            + refusal("the upload could not be read", stage: names.stage, code: 3)
            + "; PALANA_SENT=${PALANA_SENT#*= }; PALANA_SENT=${PALANA_SENT%% *}"
    }

    /// Rename mode: names the edit a racing directory swallowed.
    ///
    /// A directory that took the pathname in the instant before the
    /// rename receives the file inside it. Empty in link mode, where
    /// `ln` never moves anything. Always a prefix: it ends with its own
    /// separator.
    private func renameStray(_ names: CommitNames) -> String {
        guard renames else { return "" }
        return "{ [ -e \(names.staged) ] || [ ! -d \(names.entry) ] || [ ! -e \(names.nested) ] || "
            + retention(
                "a directory took the destination as the send renamed, and your edit landed inside it",
                path: names.nestedPath) + "; }; "
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

/// The quoted names and display paths one commit program uses.
///
/// Quoted forms are relative to the destination directory the program
/// enters first; paths are absolute, for retained notes.
struct CommitNames {
    /// The destination entry, quoted.
    let entry: String
    /// The staging directory, quoted.
    let stage: String
    /// The staged upload, quoted.
    let staged: String
    /// The hard-link probe's name in staging, quoted — never the upload's.
    let probe: String
    /// The set-aside version's name, quoted.
    let kept: String
    /// The set-aside version's absolute path.
    let keptPath: String
    /// The staging directory's absolute path.
    let stagePath: String
    /// The staged upload's absolute path.
    let stagedPath: String
    /// The upload's name inside the destination name, quoted — where a
    /// rename lands if a directory took the destination first.
    let nested: String
    /// That nested path, absolute.
    let nestedPath: String

    init(directory: String, name: String, token: String) {
        let stageName = RemoteVersionGuard.stagingName(token: token)
        let keptName = RemoteVersionGuard.displacedName(token: token)
        entry = ShellQuote.quote(name)
        stage = ShellQuote.quote(stageName)
        staged = ShellQuote.quote("\(stageName)/\(name)")
        probe = ShellQuote.quote("\(stageName)/\(name).palana-link")
        kept = ShellQuote.quote(keptName)
        keptPath = RemoteVersionGuard.join(directory, keptName)
        stagePath = RemoteVersionGuard.join(directory, stageName)
        stagedPath = RemoteVersionGuard.join(stagePath, name)
        nested = ShellQuote.quote("\(name)/\(name)")
        nestedPath = RemoteVersionGuard.join(RemoteVersionGuard.join(directory, name), name)
    }
}

extension Plan {
    /// The same send-back, committed by rename instead of by hard link.
    ///
    /// What the surface offers after the link commit refused with
    /// ``RemoteVersionGuard/noHardLinkExitStatus``. Every step but the
    /// commit is unchanged; the guard names the mode, so enactment's
    /// exact check accepts the rename commit only for this plan. The
    /// refusal cleared staging, so the same operation token stages
    /// again. nil when the plan is not a link-mode send-back.
    public func renameCommitted() -> Plan? {
        guard var versionGuard, !versionGuard.renames, let destination, entries.count == 1 else {
            return nil
        }
        versionGuard.commitMode = .rename
        let program = versionGuard.commitProgram(directory: destination.directory, name: entries[0].name)
        var plan = self
        plan.versionGuard = versionGuard
        plan.steps = steps.map { step in
            guard step.role == .promote else { return step }
            return PlanStep(runsOn: step.runsOn, command: program, role: .promote)
        }
        return plan
    }
}
