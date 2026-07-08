// SystemReadsTool — the first WorkbenchTool. Four read verbs: disk usage
// and ZFS topology. The host is a parameter the tool accepts for protocol
// conformance; v1 commands are host-agnostic. No parsing — what the
// remote command writes is what the caller receives.

import Foundation

/// The built-in system reads tool.
///
/// Exposes four read verbs: `df -h` (requires only reachability) and the
/// three ZFS reads (`zfs list`, `zpool status`, `zpool list`, each
/// requiring a probed `zfsTopology` fact). Raw output, no interpretation.
public struct SystemReadsTool: WorkbenchTool {
    /// `"reads"` — the stable tool identifier.
    public let id = "reads"
    /// `"system reads"` — the display label.
    public let label = "system reads"

    /// The four system read verbs.
    public let verbs: [WorkbenchVerb] = [
        WorkbenchVerb(
            id: "df",
            label: "df",
            keyHint: "d",
            requirement: .reachable,
            kind: .read
        ),
        WorkbenchVerb(
            id: "zfs-list",
            label: "zfs list",
            keyHint: "z",
            requirement: .zfs,
            kind: .read
        ),
        WorkbenchVerb(
            id: "zpool-status",
            label: "zpool status",
            keyHint: "s",
            requirement: .zfs,
            kind: .read
        ),
        WorkbenchVerb(
            id: "zpool-list",
            label: "zpool list",
            keyHint: "p",
            requirement: .zfs,
            kind: .read
        ),
    ]

    /// Creates the system reads tool.
    public init() {}

    /// The literal command for a verb, for any host.
    ///
    /// The host parameter is accepted for protocol conformance — v1
    /// commands are host-agnostic. Future verbs may compose differently
    /// per host (e.g., targeting a specific pool by name).
    public func command(for verb: WorkbenchVerb, on host: String) -> String {
        switch verb.id {
        case "df": return "df -h"
        case "zfs-list": return "zfs list"
        case "zpool-status": return "zpool status"
        case "zpool-list": return "zpool list"
        default: return verb.id
        }
    }
}
