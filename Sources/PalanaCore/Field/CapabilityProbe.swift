// The capability probe — one command, one round trip. Four marker lines
// come back: kernel, userland flavor, zfs, rsync. Markers make the parse
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
    ].joined(separator: "; ")

    /// Parses probe output into a capability fact.
    ///
    /// Kernel and flavor markers are required — their absence throws
    /// ``ProbeParseError``. zfs and rsync are optional facts: empty
    /// marker values mean the binary is not there.
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
        return HostCapability(
            kernel: kernel,
            flavor: flavor,
            zfs: nonEmpty(markers["zfs"]),
            rsync: nonEmpty(markers["rsync"])
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
