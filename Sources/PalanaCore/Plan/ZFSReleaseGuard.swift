import Foundation

/// The exact ZFS cleanup commands a received dataset authorizes.
///
/// Dataset existence proves only that one receive landed. This value binds
/// that proof to the snapshot cleanup and, for a move, the source dataset
/// destroy composed for the same operation identity.
public struct ZFSReleaseGuard: Codable, Sendable, Equatable {
    /// The source host that owns the sent dataset and snapshot.
    public var sourceHost: String
    /// The destination host that owns the received dataset.
    public var destinationHost: String
    /// The dataset sent from the source host.
    public var sourceDataset: String
    /// The dataset whose existence opens the gate.
    public var receivedDataset: String
    /// The snapshot and cleanup identity.
    public var token: String
    /// Whether the source dataset itself may be destroyed.
    public var deletesSource: Bool

    /// Assembles a release binding from the facts used to compose the plan.
    public init(
        sourceHost: String,
        destinationHost: String,
        sourceDataset: String,
        receivedDataset: String,
        token: String,
        deletesSource: Bool
    ) {
        self.sourceHost = sourceHost
        self.destinationHost = destinationHost
        self.sourceDataset = sourceDataset
        self.receivedDataset = receivedDataset
        self.token = token
        self.deletesSource = deletesSource
    }

    /// The only gated steps this binding authorizes, in execution order.
    ///
    /// A move's source step destroys the source only after proving no byte
    /// was written to it since the sent snapshot (``guardedSourceRelease``).
    public var releaseSteps: [PlanStep] {
        let receivedSnapshot = "\(receivedDataset)@\(token)"
        let sourceCommand =
            deletesSource
            ? Self.guardedSourceRelease(host: sourceHost, dataset: sourceDataset, token: token)
            : "zfs destroy -r \(ShellQuote.quote("\(sourceDataset)@\(token)"))"
        return [
            PlanStep(
                runsOn: .host(destinationHost),
                command: "zfs destroy -r \(ShellQuote.quote(receivedSnapshot))",
                role: .cleanup,
                gatedOnVerification: true),
            PlanStep(
                runsOn: .host(sourceHost),
                command: sourceCommand,
                role: deletesSource ? .delete : .cleanup,
                gatedOnVerification: true),
        ]
    }
}

// MARK: - The move's fence and proof (owner ruling 2026-11-18, final review F03)
//
// A whole-dataset move sends a snapshot taken at T1 and destroyed the live
// source at T2: whatever a service wrote between them existed nowhere
// else. The owner's ruling is fence and prove. Before the snapshot, every
// mounted dataset in the source tree is unmounted — a busy one refuses,
// and the datasets already unmounted are mounted again, before anything
// is sent. At release, the source is destroyed only when `written@<token>`
// is 0 for every dataset in the tree; anything else keeps the source, and
// a retained note names it and how to mount it again.

extension ZFSReleaseGuard {
    /// The step that unmounts the source tree before its snapshot.
    ///
    /// Children unmount before parents (`-S name`). A dataset that will not
    /// unmount stops the run before the snapshot, and the ones this step
    /// already unmounted are mounted again. Datasets that are not mounted
    /// (`canmount=noauto`, volumes) are left as they are — the release's
    /// written check covers them. Unmount and mount run as `sudo -n zfs
    /// unmount|mount`, the two privileged commands the mount seam composes
    /// and the narrow sudoers grant covers (ho-10.4, ho-17); with the
    /// dataset already unmounted, the delegated destroy needs no root.
    public static func fenceCommand(host: String, dataset: String) -> String {
        let quoted = ShellQuote.quote(dataset)
        let refusal = ShellQuote.quote(
            "palana-refused: \(host):\(dataset) — a dataset in it could not be unmounted, so nothing was sent")
        let note = ShellQuote.quote(
            "palana: \(dataset) is unmounted for the move · if the move stops before it finishes,"
                + " zfs mount brings it back")
        return [
            "palana_tree=$(zfs list -H -o name,mounted -r -S name \(quoted)) || exit 1",
            "palana_tab=$(printf '\\t')",
            "printf '%s\\n' \"$palana_tree\" | { palana_done=; while IFS=\"$palana_tab\" read -r palana_n palana_m; do"
                + " [ \"$palana_m\" = yes ] || continue;"
                + " if sudo -n zfs unmount \"$palana_n\"; then palana_done=\"$palana_n$palana_tab$palana_done\"; else"
                + " echo \(refusal) >&2;"
                + " IFS=\"$palana_tab\"; for palana_r in $palana_done; do sudo -n zfs mount \"$palana_r\"; done;"
                + " exit 1; fi; done; } || exit 1",
            "echo \(note) >&2",
        ].joined(separator: "; ")
    }

    /// The move's source release: destroy only a source nothing wrote to
    /// since the sent snapshot.
    ///
    /// `written@<token>` is read for every live dataset in the tree —
    /// filesystems and volumes, `-t filesystem,volume` — and each must be
    /// exactly 0. Snapshots and bookmarks are not the source's live state:
    /// a recursive `zfs get` lists them by default, and the operation's own
    /// `@<token>` snapshot reads `-` against itself, which refused every
    /// clean move (final review pass 2, F03; reproduced on the fixture
    /// pool). A live dataset with no snapshot of that name (created after
    /// it) still reads `-` and keeps the source, and an unreadable value
    /// keeps it. Exit 9 is this refusal, after the retained note.
    public static func guardedSourceRelease(host: String, dataset: String, token: String) -> String {
        let quoted = ShellQuote.quote(dataset)
        let kept = { (reason: String) in
            "{ printf '%s\\n' "
                + ShellQuote.quote(
                    "palana-retained: \(host):\(dataset) — \(reason), so the source is kept"
                        + " · it is unmounted · zfs mount brings it back")
                + " >&2; exit \(sourceKeptExitStatus); }"
        }
        return [
            "palana_written=$(zfs get -t filesystem,volume -H -p -r -o value \(ShellQuote.quote("written@\(token)")) \(quoted)) || "
                + kept("what was written since the snapshot could not be read"),
            "[ -n \"$palana_written\" ] || " + kept("what was written since the snapshot could not be read"),
            "for palana_w in $palana_written; do [ \"$palana_w\" = 0 ] || "
                + kept("it was written to after the snapshot that was sent") + "; done",
            "zfs destroy -r \(quoted)",
        ].joined(separator: "; ")
    }

    /// The release's exit status when the source was kept because it
    /// changed, or its change could not be read.
    public static let sourceKeptExitStatus: Int32 = 9
}
