// SudoGuidance — the exact, narrow sudoers grant pālana asks for (ho-17).
//
// Mounting is root's on Linux: the delegated `zfs allow` covers create,
// destroy, snapshot, rollback, and the properties, but NOT mount/unmount. The
// mount seam (ho-10.4) composes exactly two privileged commands —
// `sudo -n zfs mount <dataset>` and `sudo -n zfs unmount <dataset>` — and
// nothing else. This enum is the single source of truth for the sudoers line
// that grants those two and ONLY those two, so the string an operator copies
// into their sudoers file can never silently drift toward a blanket `zfs` grant
// (which would be a root-escalation footgun). The line is pinned by tests.

import Foundation

/// The narrow sudoers grant that unlocks pālana's mount/unmount verbs.
public enum SudoGuidance {
    /// The conventional absolute path to the `zfs` binary on Linux.
    ///
    /// sudoers command specs require an absolute path (no `PATH` lookup); this
    /// is right on most installs, and the operator checks `which zfs` when it
    /// isn't (`/sbin/zfs` on some distros).
    public static let zfsPath = "/usr/sbin/zfs"

    /// The placeholder used when pālana doesn't know the host's login — a clear
    /// "fill this in", never a wrong guess baked into a root grant.
    public static let userPlaceholder = "<user>"

    /// The exact sudoers line granting passwordless sudo for `zfs mount` and
    /// `zfs unmount` — and nothing else.
    ///
    /// - Parameters:
    ///   - user: The login pālana connects as on the host, or
    ///     ``userPlaceholder`` when it isn't known.
    ///   - zfsPath: The absolute path to `zfs`; defaults to ``zfsPath``.
    /// - Returns: One sudoers line, scoped to mount and unmount only.
    public static func sudoersLine(user: String, zfsPath: String = zfsPath) -> String {
        "\(user) ALL=(root) NOPASSWD: \(zfsPath) mount *, \(zfsPath) unmount *"
    }
}
