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
        operatorFlags: String? = nil
    ) -> String {
        let base =
            Self.modernRsync(capability)
            ? "-a -s --partial --info=progress2"
            : "-a --partial"
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
        operatorFlags: String? = nil
    ) -> String {
        let binary = capability?.rsyncPath.map(ShellQuote.quote) ?? "rsync"
        return "\(binary) \(rsyncFlags(runningOn: capability, operatorFlags: operatorFlags))"
    }
}
