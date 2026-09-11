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
    /// the trimmed value is appended after the base set. A move's
    /// content check and source-removal flags follow it so custom flags
    /// cannot disable the engine-owned comparison. The paths come last,
    /// and the panel shows exactly what will run.
    static func rsyncFlags(
        runningOn capability: HostCapability?,
        operatorFlags: String? = nil,
        removingSource: Bool = false
    ) -> String {
        var base =
            Self.modernRsync(capability)
            ? "-a -s --partial --info=progress2"
            : "-a --partial"
        if let trimmed = operatorFlags?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty {
            base += " \(trimmed)"
        }
        if removingSource {
            base += " --checksum --remove-source-files"
        }
        return base
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
            runningOn: capability,
            operatorFlags: operatorFlags,
            removingSource: removingSource)
        return "\(binary) \(flags)"
    }

    /// True when the capability names an rsync that supports
    /// `--remove-source-files`.
    static func supportsSourceRemoval(_ capability: HostCapability?) -> Bool {
        guard let line = capability?.rsync else { return false }
        if line.localizedCaseInsensitiveContains("openrsync") { return true }
        guard let version = capability?.rsyncVersion else { return false }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return false }
        return major >= 3
    }

    /// True when the selected route can perform a progressive move.
    ///
    /// The sender removes each file after rsync transfers it. A direct
    /// pull also requires the local rsync to understand the option it
    /// places on the remote sender's command line.
    static func carriesSourceRemoval(
        transport: Transport,
        request: PlanRequest,
        facts: PlanFacts
    ) -> Bool {
        switch transport {
        case .local, .rsyncAgentForwarded:
            return supportsSourceRemoval(facts.sourceCapability)
        case .rsyncDirect:
            guard supportsSourceRemoval(facts.sourceCapability) else { return false }
            let pulling = request.source.host != PalanaCore.localHostName
            return !pulling || supportsSourceRemoval(facts.destinationCapability)
        case .tarStreamProxied, .tarStreamDirect, .zfsSendReceiveForwarded,
            .zfsSendReceiveProxied:
            return false
        }
    }

    /// Refuses custom flags that would let a copy delete source files
    /// or let an operator disable the move semantics shown in the plan.
    static func validateRsyncOperatorFlags(_ flags: String?) throws {
        guard let lowercased = flags?.lowercased() else { return }
        let controlsSourceRemoval =
            lowercased.contains("remove-source")
            || lowercased.contains("remove-sent")
        guard !controlsSourceRemoval else {
            throw PlanError.rsyncFlagsControlSourceRemoval
        }
    }

    /// Removes only empty selected source directories, bottom-up.
    ///
    /// Failures remain visible on stderr, while the final `:` lets the
    /// following accounting step name every selected source still present.
    static func emptyDirectorySweep(sources: [String]) -> String {
        let quoted = sources.map(ShellQuote.quote).joined(separator: " ")
        return "for p in \(quoted); do [ -d \"$p\" ] && "
            + "find \"$p\" -depth -type d -exec rmdir {} \\;; done; :"
    }

    /// Names each selected source still present and fails the run.
    static func leftoverSourceReport(sources: [String], host: String) -> String {
        let quoted = sources.map(ShellQuote.quote).joined(separator: " ")
        return [
            "n=0",
            "for p in \(quoted); do { [ -e \"$p\" ] || [ -L \"$p\" ]; } || continue"
                + "; printf 'palana-retained: %s:%s — source entry remains after the progressive move\\n' "
                + "\(ShellQuote.quote(host)) \"$p\" >&2; n=$((n + 1)); done",
            "[ \"$n\" -eq 0 ]",
        ].joined(separator: "; ")
    }
}
