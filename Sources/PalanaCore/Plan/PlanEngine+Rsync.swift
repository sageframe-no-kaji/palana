// The rsync composition helpers — extracted from PlanEngine.swift to
// keep that file within the length budget. Which rsync is modern, which
// flags it takes, and which binary the plan names.

import Foundation

extension PlanEngine {
    /// Real rsync, 3.1 or newer — the dotted version is the tell;
    /// openrsync's "protocol version 29" never parses one.
    static func modernRsync(_ capability: HostCapability?) -> Bool {
        guard let version = capability?.rsyncVersion else { return false }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 1)
    }

    /// The rsync flag set: archive, keep partials so an interrupted
    /// transfer resumes — `-s` and progress2 only when the running
    /// side's rsync is modern enough to speak them. openrsync refuses
    /// `-s` outright (CI found it live), so the floor protects remote
    /// paths by inner-quoting instead — see `composeRsyncDirect`.
    ///
    /// When ``operatorFlags`` is non-nil and non-empty after trimming,
    /// the trimmed value is appended after the base set and before the
    /// paths — the panel shows exactly what will run.
    static func rsyncFlags(
        runningOn capability: HostCapability?,
        operatorFlags: String? = nil,
        removingSource: Bool = false
    ) -> String {
        var base =
            Self.modernRsync(capability)
            ? "-a -s --partial --info=progress2"
            : "-a --partial"
        // The back half of a move, carried by rsync itself: each source
        // file is removed after its own copy is confirmed, so the window
        // between proof and deletion is one file wide rather than the
        // whole selection. Both rsync families refuse to remove a file
        // that changed while they read it — proved live, per binary, in
        // RsyncSourceRemovalTests, which gates this flag's existence.
        if removingSource {
            base += " --remove-source-files"
        }
        guard
            let trimmed = operatorFlags?.trimmingCharacters(in: .whitespaces),
            !trimmed.isEmpty
        else { return base }
        return "\(base) \(trimmed)"
    }

    /// The rsync command head — the binary the running side will
    /// actually execute, then its flags.
    ///
    /// A capability carrying ``HostCapability/rsyncPath`` names that
    /// absolute binary, so the plan's text and the process it spawns
    /// agree even when the app's PATH would find a different rsync.
    /// A nil path — every remote capability, and an unresolved local
    /// one — composes bare `rsync`, byte-identical to before the path
    /// existed. The asymmetry is the data's, not a special case here.
    static func rsyncInvocation(
        runningOn capability: HostCapability?,
        operatorFlags: String? = nil,
        removingSource: Bool = false
    ) -> String {
        let binary = capability?.rsyncPath.map(ShellQuote.quote) ?? "rsync"
        let flags = rsyncFlags(
            runningOn: capability, operatorFlags: operatorFlags, removingSource: removingSource)
        return "\(binary) \(flags)"
    }

    /// True when this rsync belongs to a family whose refusal to remove
    /// a changed source has been proved, not assumed.
    ///
    /// Two families qualify. openrsync, which macOS ships, announces
    /// itself by name and carries no dotted version. GNU rsync 3.0 and
    /// newer carries one. Anything else — an rsync too old to have been
    /// tested, or a build neither family recognises — is unproved, and
    /// an unproved binary never gets a flag that deletes.
    ///
    /// ``RsyncSourceRemovalTests`` is where the proof lives, run live
    /// against every rsync on the machine.
    static func provenSourceRemoval(_ capability: HostCapability?) -> Bool {
        guard let line = capability?.rsync else { return false }
        if line.localizedCaseInsensitiveContains("openrsync") { return true }
        guard let version = capability?.rsyncVersion else { return false }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return false }
        return major >= 3
    }

    /// True when this move's back half can ride rsync's own removal.
    ///
    /// Two conditions, both required. The transport has to be one rsync
    /// actually runs — a tar stream and a bare `cp -a` carry no
    /// equivalent to `--remove-source-files`. And the rsync doing the
    /// removing has to be from a proved family. A move that fails
    /// either is refused rather than deleted on evidence that may have
    /// gone stale.
    ///
    /// rsync's sender is what performs the removal, and the sender
    /// always sits on the source side — a push removes with the local
    /// binary, a pull with the remote one. So the capability that has
    /// to be proved is the source host's, on every rsync transport.
    static func carriesSourceRemoval(transport: Transport, facts: PlanFacts) -> Bool {
        switch transport {
        case .rsyncAgentForwarded, .rsyncDirect, .local:
            return provenSourceRemoval(facts.sourceCapability)
        case .tarStreamProxied, .tarStreamDirect, .zfsSendReceiveForwarded, .zfsSendReceiveProxied:
            return false
        }
    }

    /// The empty source directories left behind once rsync has removed
    /// the files, cleared bottom-up with `rmdir` and nothing else.
    ///
    /// `rmdir` removes only an empty directory. A directory still
    /// holding a file rsync declined to remove fails, silently, and
    /// stays — which is the whole point. No recursive deletion appears
    /// anywhere in a move.
    static func emptyDirectorySweep(sources: [String]) -> String {
        let quoted = sources.map(ShellQuote.quote).joined(separator: " ")
        return "for p in \(quoted); do [ -d \"$p\" ] && "
            + "find \"$p\" -depth -type d -exec rmdir {} \\; 2>/dev/null; done; :"
    }

    /// The count of source entries still standing after the move, and
    /// the sentence that names them.
    ///
    /// rsync 3.x exits 23 when it declines to remove a changed file, but
    /// openrsync declines and exits 0. Exit status is therefore not a
    /// signal a move can trust, so what remains is counted directly and
    /// a move that did not finish says so instead of reporting success.
    static func leftoverSourceReport(sources: [String], host: String) -> String {
        let quoted = sources.map(ShellQuote.quote).joined(separator: " ")
        let sentence =
            "palana-retained: source files stayed on \(host) because they changed "
            + "during the transfer — they were copied, not moved"
        return [
            "n=0",
            "for p in \(quoted); do [ -e \"$p\" ] || [ -L \"$p\" ] || continue"
                + "; c=$(find \"$p\" ! -type d 2>/dev/null | wc -l | tr -d ' ')"
                + "; n=$((n + c)); done",
            "[ \"$n\" -eq 0 ] || { echo \(ShellQuote.quote(sentence)) >&2; exit 1; }",
        ].joined(separator: "; ")
    }
}
