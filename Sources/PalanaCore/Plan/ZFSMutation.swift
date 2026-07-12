// The ZFS mutation vocabulary — the typed verbs a ZFSMutationTool (AT-02)
// packs into a PlanRequest for the engine to compose. One enum, closed,
// Codable so a Plan round-trips on disk. Sendable and Equatable for test
// clarity and actor safety.

import Foundation

/// A ZFS mutation the operator has asked the Plan Engine to compose.
///
/// Each case carries exactly the parameters the `zfs` command needs —
/// no more, no less. Dataset and snapshot names are bare strings; the
/// composer quotes them with ``ShellQuote`` and joins `@` where the
/// tool requires it. The operator reads every composed command before
/// Enter; the enum is the truth that made it.
public enum ZFSMutation: Sendable, Equatable, Codable {
    /// Create a new dataset.
    ///
    /// When `mountpoint` is non-nil the composer appends
    /// `-o mountpoint=<path>` to `zfs create`.
    case createDataset(name: String, mountpoint: String?)
    /// Destroy a dataset and, when `recursive` is true, all its children.
    case destroyDataset(name: String, recursive: Bool)
    /// Rename a dataset in place.
    case renameDataset(from: String, to: String)
    /// Take a snapshot of a dataset.
    ///
    /// When `recursive` is true the composer appends `-r` so the
    /// snapshot covers the dataset's entire subtree.
    case snapshot(dataset: String, name: String, recursive: Bool)
    /// Destroy a snapshot.
    case destroySnapshot(dataset: String, name: String)
    /// Roll a dataset back to a snapshot, discarding newer state.
    ///
    /// When `destroysNewer` is true the composer appends `-r`, which
    /// DESTROYS every snapshot newer than the target on the way back —
    /// zfs refuses the rollback otherwise. Never defaulted on: the
    /// operator opts in through a plainly-worded toggle and reads the
    /// `-r` in the plan (the hands round asked 'Do we want this?!' —
    /// yes, but only out loud).
    case rollback(dataset: String, name: String, destroysNewer: Bool)
    /// Set the mountpoint property on a dataset.
    case setMountpoint(dataset: String, path: String)
    /// Clear the mountpoint property so the dataset inherits from its
    /// parent (`zfs inherit mountpoint`).
    case clearMountpoint(dataset: String)
}
