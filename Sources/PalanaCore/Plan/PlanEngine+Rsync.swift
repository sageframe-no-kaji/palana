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
    /// the trimmed value is appended after the base set — on copies only.
    /// A move takes no operator flags: `--append`, `--compare-dest`,
    /// `--dry-run` or an excluded directory would change what lands
    /// while the engine still removes the source (review 2026-11-15,
    /// finding 2). A move's flags are the base set plus the engine-owned
    /// content check and source removal. The paths come last, and the
    /// panel shows exactly what will run.
    ///
    /// A move also asks for `-X` and `-A` where ``MoveMetadata`` proves
    /// both ends carry them: the source is deleted after the transfer,
    /// so what `-a` leaves behind is lost (review 2026-11-15, finding 4).
    /// Copies are unchanged — the original keeps its metadata.
    static func rsyncFlags(
        runningOn capability: HostCapability?,
        operatorFlags: String? = nil,
        removingSource: Bool = false,
        keeping metadata: MoveMetadata = .none
    ) -> String {
        var base =
            Self.modernRsync(capability)
            ? "-a -s --partial --info=progress2"
            : "-a --partial"
        let trimmed = operatorFlags?.trimmingCharacters(in: .whitespaces) ?? ""
        if !removingSource, !trimmed.isEmpty {
            base += " \(trimmed)"
        }
        if removingSource {
            if metadata.xattrs { base += " -X" }
            if metadata.acls { base += " -A" }
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
        removingSource: Bool = false,
        keeping metadata: MoveMetadata = .none
    ) -> String {
        let binary = capability?.rsyncPath.map(ShellQuote.quote) ?? "rsync"
        let flags = rsyncFlags(
            runningOn: capability,
            operatorFlags: operatorFlags,
            removingSource: removingSource,
            keeping: metadata)
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
    ///
    /// One check per source, composed here rather than looped in the shell,
    /// so each note carries a display path with any line break written as
    /// `\n`: a retained note stays one line even for a path that contains
    /// a newline (#10).
    static func leftoverSourceReport(sources: [String], host: String) -> String {
        let checks = sources.map { source in
            let path = ShellQuote.quote(source)
            let note = ShellQuote.quote(
                "palana-retained: \(host):\(retainedDisplayPath(source))"
                    + " — source entry remains after the progressive move")
            // printf, not echo: dash's echo would turn the written `\n` back
            // into a line break.
            return "if [ -e \(path) ] || [ -L \(path) ]; then printf '%s\\n' \(note) >&2; n=$((n + 1)); fi"
        }
        return (["n=0"] + checks + ["[ \"$n\" -eq 0 ]"]).joined(separator: "; ")
    }

    /// A path as a retained note shows it: line breaks written as `\n` and
    /// `\r`, so one note is always one line.
    static func retainedDisplayPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// What a progressive move can keep beyond `-a`, given both ends.
    ///
    /// The `.local` route runs one rsync, which is both ends. Every
    /// other route runs one rsync at each host: the sender and the
    /// receiver must both list a capability before the flag is asked
    /// for. ACLs also need the same kernel: macOS and Linux ACLs do not
    /// translate, and rsync aborts the transfer with a protocol error
    /// when it tries (Darwin to Linux, rsync 3.4.1 to 3.5.2, verified
    /// 2026-11-15).
    static func moveMetadata(transport: Transport, facts: PlanFacts) -> MoveMetadata {
        let ends =
            transport == .local
            ? [facts.sourceCapability]
            : [facts.sourceCapability, facts.destinationCapability]
        let xattrs = ends.allSatisfy { $0?.rsyncXattrs == true }
        let aclRsyncs = ends.allSatisfy { $0?.rsyncACLs == true }
        let sameKernel = Set(ends.map { $0?.kernel }).count == 1
        return MoveMetadata(
            xattrs: xattrs,
            acls: aclRsyncs && sameKernel,
            kernels: aclRsyncs && !sameKernel ? ends.compactMap { $0?.kernel } : [])
    }

    /// The plan's one line naming what a progressive move will not
    /// keep, or nil when it keeps everything rsync can ask for.
    static func moveMetadataNotice(_ metadata: MoveMetadata) -> String? {
        let cannot = "an rsync at one end cannot carry them"
        var clauses: [String] = []
        switch (metadata.xattrs, metadata.acls, metadata.kernels.isEmpty) {
        case (true, true, _):
            return nil
        case (false, false, true):
            clauses.append("extended attributes, Finder tags and ACLs — \(cannot)")
        case (false, _, _):
            clauses.append("extended attributes and Finder tags — \(cannot)")
        case (true, false, _):
            break
        }
        if !metadata.acls, !metadata.kernels.isEmpty {
            let between = metadata.kernels.joined(separator: " and ")
            clauses.append("ACLs — they do not carry between \(between)")
        } else if metadata.xattrs, !metadata.acls {
            clauses.append("ACLs — \(cannot)")
        }
        return "this move does not keep " + clauses.joined(separator: " · ")
    }
}

/// What a progressive move keeps beyond `rsync -a`.
struct MoveMetadata: Equatable, Sendable {
    /// Both ends carry extended attributes — the move asks for `-X`.
    var xattrs: Bool
    /// Both ends carry ACLs on the same kernel — the move asks for `-A`.
    var acls: Bool
    /// The two kernels, when both rsyncs carry ACLs but the kernels
    /// differ; empty otherwise.
    var kernels: [String]

    /// Keeps nothing beyond `-a` — every copy, and any move whose ends
    /// are unproven.
    static let none = Self(xattrs: false, acls: false, kernels: [])
}
