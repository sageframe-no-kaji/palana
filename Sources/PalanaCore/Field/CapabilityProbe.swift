// The capability probe — one command, one round trip. Five marker lines
// come back: kernel, userland flavor, zfs, rsync, rsync's capability list. Markers make the parse
// order-independent and immune to stray output; empty values read as
// absent. Deferred decision 3, resolved in ho-03.

import Foundation

/// The probe's stdout did not carry the markers.
///
/// A reached host that answers garbage is a surprise worth surfacing,
/// not a fact worth recording — deliberately outside `ConduitError`.
public struct ProbeParseError: Error, Equatable, Sendable {
    /// What the probe actually produced.
    public let stdout: String
}

/// Composes and parses the one-round-trip capability probe.
public enum CapabilityProbe {
    /// The probe command, POSIX-sh portable across GNU, BSD, and BusyBox.
    ///
    /// `stat --version` answering is the GNU tell; `busybox true`
    /// exiting clean is the BusyBox tell where GNU stat did not answer
    /// (a GNU host with busybox installed stays GNU — first tell wins).
    /// Absent binaries yield empty marker values — the shell's
    /// not-found noise lands on the redirected stderr, never in the
    /// markers.
    public static let command = [
        #"echo "palana:kernel:$(uname -s)""#,
        #"if stat --version >/dev/null 2>&1; then echo "palana:flavor:GNU"; "#
            + #"elif busybox true >/dev/null 2>&1; then echo "palana:flavor:BusyBox"; "#
            + #"else echo "palana:flavor:BSD"; fi"#,
        #"echo "palana:zfs:$(zfs version 2>/dev/null | head -n 1)""#,
        #"echo "palana:rsync:$(rsync --version 2>/dev/null | head -n 1)""#,
        // The capability list, folded onto one line: real rsync names
        // "xattrs" and "ACLs" there, or "no xattrs" / "no ACLs";
        // openrsync prints no list at all.
        #"echo "palana:rsynccaps:$(rsync --version 2>/dev/null | head -n 16 | tr '\n' ' ')""#,
    ].joined(separator: "; ")

    /// The probe for this machine — ``command`` under a widened PATH,
    /// plus the resolved rsync path.
    ///
    /// A Finder-launched app inherits `/usr/bin:/bin:/usr/sbin:/sbin`
    /// and never sources a shell profile, so the operator's Homebrew or
    /// MacPorts rsync is invisible to ``command`` and Apple's openrsync
    /// answers instead. Prepending the usual prefixes lets the probe
    /// see what the operator's terminal sees. Because the PATH is
    /// widened for the whole line, the `palana:rsync:` version and the
    /// `palana:rsyncpath:` path report the same binary — they cannot
    /// disagree. Remote hosts keep ``command``: their non-interactive
    /// PATH is the truth a remote plan runs under.
    public static let localCommand =
        "PATH=/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$PATH; "
        + command
        + #"; echo "palana:rsyncpath:$(command -v rsync 2>/dev/null)""#

    /// Parses probe output into a capability fact.
    ///
    /// Kernel and flavor markers are required — their absence throws
    /// ``ProbeParseError``. zfs and rsync are optional facts: empty
    /// marker values mean the binary is not there. `rsyncpath` rides
    /// only in ``localCommand`` output; remote output lacks the marker
    /// and the path stays nil without a branch.
    public static func parse(_ stdout: String) throws -> HostCapability {
        var markers: [String: String] = [:]
        for line in stdout.split(separator: "\n") {
            guard line.hasPrefix("palana:") else { continue }
            let body = line.dropFirst("palana:".count)
            guard let colon = body.firstIndex(of: ":") else { continue }
            let key = String(body[..<colon])
            let value = String(body[body.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            markers[key] = value
        }
        guard
            let kernel = markers["kernel"], !kernel.isEmpty,
            let flavor = markers["flavor"].flatMap(UserlandFlavor.init(rawValue:))
        else {
            throw ProbeParseError(stdout: stdout)
        }
        let rsync = nonEmpty(markers["rsync"])
        return HostCapability(
            kernel: kernel,
            flavor: flavor,
            zfs: nonEmpty(markers["zfs"]),
            rsync: rsync,
            rsyncPath: nonEmpty(markers["rsyncpath"]),
            rsyncXattrs: rsyncListed("xattrs", rsync: rsync, caps: markers["rsynccaps"]),
            rsyncACLs: rsyncListed("ACLs", rsync: rsync, caps: markers["rsynccaps"])
        )
    }

    // swiftlint:disable discouraged_optional_boolean
    // Three states, as on HostCapability: nil is unprobed.
    /// Whether rsync's folded capability list names `item` — and not
    /// as `no <item>`.
    ///
    /// nil when rsync is absent or the probe carried no list (output
    /// recorded before the marker existed); false when the list is
    /// empty, which is openrsync's answer. The item must stand as a
    /// whole list entry, so `ACL-at` is not `ACLs`.
    static func rsyncListed(_ item: String, rsync: String?, caps: String?) -> Bool? {
        guard rsync != nil, let caps else { return nil }
        let entries = caps.split { $0 == "," || $0 == "\n" }
            .map { $0.split(whereSeparator: \.isWhitespace) }
        for words in entries {
            // The fold can glue a heading onto the last entry
            // ("file-flags Optimizations:"), so match a word, not the
            // whole entry; only "no" directly before it negates.
            if let index = words.firstIndex(where: { $0 == item }) {
                return index == 0 || words[index - 1] != "no"
            }
        }
        return false
    }
    // swiftlint:enable discouraged_optional_boolean

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
