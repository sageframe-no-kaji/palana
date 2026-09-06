// The fact vocabulary. Everything the Field knows about a host is one of
// these — discovered on demand, timestamped, remembered as memory of the
// last visit. Facts never claim to be current; the timestamp says when.

import Foundation

/// A fact group with the moment it was discovered.
///
/// The field view renders "remembered as of when" — the timestamp is the
/// honesty, not metadata.
public struct Dated<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    /// The fact itself.
    public var value: Value
    /// When discovery recorded it.
    public var discoveredAt: Date

    /// Stamps a fact.
    public init(value: Value, discoveredAt: Date) {
        self.value = value
        self.discoveredAt = discoveredAt
    }
}

/// The typed outcome of the last discovery attempt.
///
/// Not a poll — reachability is recorded like any fact and goes stale
/// like any fact.
public enum Reachability: Codable, Sendable, Equatable {
    /// The last discovery reached the host.
    case reachable
    /// The last discovery failed at the door; the detail names how.
    case unreachable(detail: String)
}

/// Userland flavor, as the probe classifies it.
///
/// GNU means `stat --version` answered. BusyBox means the busybox
/// binary itself answered where GNU stat did not (ho-07.5 — the first
/// cut classified BusyBox as BSD, and zencat's stat-less userland
/// refused the BSD listing). BSD is the remainder — Macs, real BSDs.
public enum UserlandFlavor: String, Codable, Sendable {
    /// GNU coreutils userland.
    case gnu = "GNU"
    /// BSD userland — stat without long options.
    case bsd = "BSD"
    /// BusyBox userland — applets, trimmed flags, maybe no stat at all.
    case busybox = "BusyBox"
}

/// What one probe round trip learns about a host.
public struct HostCapability: Codable, Sendable, Equatable {
    /// Kernel name from `uname -s` — `Linux`, `Darwin`.
    public var kernel: String
    /// Userland flavor — selects the listing command path (ho-04).
    public var flavor: UserlandFlavor
    /// First line of `zfs version`, nil when zfs is absent.
    public var zfs: String?
    /// First line of `rsync --version`, nil when rsync is absent.
    public var rsync: String?
    /// Absolute path of the rsync the probe resolved, nil when it did not.
    ///
    /// Local-only today: ``CapabilityProbe/localCommand`` searches the
    /// Homebrew and MacPorts prefixes a Finder-launched app cannot see
    /// and names what it found, so a plan can name the binary it will
    /// run. Remote probes leave this nil on purpose — a remote plan
    /// runs under the host's own non-interactive PATH, which is exactly
    /// what `ssh host 'rsync …'` gets, so bare `rsync` is already the
    /// truth there. Optional with a default so cache files written
    /// before the field existed still decode.
    public var rsyncPath: String?

    /// Assembles a capability fact.
    public init(
        kernel: String,
        flavor: UserlandFlavor,
        zfs: String?,
        rsync: String?,
        rsyncPath: String? = nil
    ) {
        self.kernel = kernel
        self.flavor = flavor
        self.zfs = zfs
        self.rsync = rsync
        self.rsyncPath = rsyncPath
    }

    /// Dotted rsync version — `3.2.7` — parsed from the raw line.
    ///
    /// ho-06 needs ≥3.1 on the sending side. Requires a dot so
    /// openrsync's "protocol version 29" cannot masquerade as one.
    public var rsyncVersion: String? {
        rsync.flatMap(Self.dottedVersion(in:))
    }

    /// Dotted zfs version — `2.2.2` — parsed from the raw line.
    public var zfsVersion: String? {
        zfs.flatMap(Self.dottedVersion(in:))
    }

    private static func dottedVersion(in line: String) -> String? {
        let pattern = /(\d+\.\d+(?:\.\d+)*)/
        return line.firstMatch(of: pattern).map { String($0.1) }
    }
}

/// How a mount classifies — drives the surface's filter.
///
/// Unknown fstypes classify as storage: the unfamiliar shows rather than hides.
public enum MountKind: String, Codable, Sendable, Equatable {
    /// A data-bearing filesystem — ext4, apfs, zfs, xfs, and anything unknown.
    case storage
    /// A network-backed filesystem — nfs, cifs, sshfs, and their variants.
    case network
    /// A synthetic or kernel filesystem — proc, sysfs, devfs, tmpfs, overlay, and their kin.
    case system
}

/// One mounted filesystem as the mount table reports it.
public struct Mount: Codable, Sendable, Equatable, Hashable {
    /// Device or remote spec — `/dev/sda1`, `tank/data`, `server:/export`.
    public var source: String
    /// The mountpoint path.
    public var target: String
    /// The filesystem type — `ext4`, `apfs`, `zfs`, `nfs`, `proc`, and others.
    public var fstype: String
    /// Derived from the options field — a read-only ground changes what the operator can do.
    public var readOnly: Bool

    /// Assembles a mount fact.
    public init(source: String, target: String, fstype: String, readOnly: Bool) {
        self.source = source
        self.target = target
        self.fstype = fstype
        self.readOnly = readOnly
    }
}

/// One ZFS filesystem as the topology read reports it.
public struct ZFSDataset: Codable, Sendable, Equatable, Hashable {
    /// Dataset name — `tank/media/photos`.
    public var name: String
    /// The mountpoint property — a path, `legacy`, or `none`.
    public var mountpoint: String
    /// Whether the dataset is actually mounted.
    ///
    /// Unmounted datasets participate as facts but never match a path
    /// query — their mountpoint is an intention, not a location.
    public var mounted: Bool

    /// Assembles a dataset fact.
    public init(name: String, mountpoint: String, mounted: Bool) {
        self.name = name
        self.mountpoint = mountpoint
        self.mounted = mounted
    }

    /// The phrase naming what differs in `other`.
    ///
    /// The mountpoint move, the mounted flip — for a sentence that names
    /// a change. Empty when nothing but the name could differ.
    public func changes(to other: Self) -> String {
        var parts: [String] = []
        if mountpoint != other.mountpoint {
            parts.append("mountpoint \(mountpoint) → \(other.mountpoint)")
        }
        if mounted != other.mounted {
            parts.append(other.mounted ? "now mounted" : "now unmounted")
        }
        return parts.joined(separator: ", ")
    }
}

/// Why a plan-critical read failed on a reached host.
///
/// Recorded in place of the fact it could not refresh: a topology or
/// mount table that would not read is an absence with a reason, never
/// the previous visit's value wearing a new timestamp.
public struct FactReadFailure: Codable, Sendable, Equatable {
    /// The read command's exit status.
    public var exitStatus: Int32
    /// The last non-empty stderr line, or the whole of it when there is none.
    public var detail: String

    /// Records a failed read.
    public init(exitStatus: Int32, detail: String) {
        self.exitStatus = exitStatus
        self.detail = detail
    }
}

/// Everything remembered about one host, grouped by discovery kind.
///
/// Each group carries its own timestamp because each is discovered — and
/// goes stale — on its own schedule.
public struct HostFacts: Codable, Sendable, Equatable {
    /// Outcome of the last discovery attempt.
    public var reachability: Dated<Reachability>?
    /// What the probe learned, when it last ran.
    public var capability: Dated<HostCapability>?
    /// The dataset list, when zfs was last read.
    ///
    /// Nil when the host has no zfs, was never read, or the last read
    /// failed — a failed read clears this rather than keeping an older
    /// list a plan could route on; ``zfsTopologyUnavailable`` says why.
    public var zfsTopology: Dated<[ZFSDataset]>?
    /// Why the last topology read failed on a reached host, when it did.
    ///
    /// Cleared by the next read that succeeds. Present only alongside a
    /// nil ``zfsTopology`` — the two never both stand.
    public var zfsTopologyUnavailable: Dated<FactReadFailure>?
    /// The full mount table, when it was last read.
    ///
    /// Keyed on the kernel's own table — `/proc/mounts` on Linux, `mount`
    /// on BSD. Every filesystem, not just ZFS. Nil means unread, or a
    /// last read that failed; ``mountsUnavailable`` says why.
    public var mounts: Dated<[Mount]>?
    /// Why the last mount table read failed on a reached host, when it did.
    public var mountsUnavailable: Dated<FactReadFailure>?
    /// Whether the host grants passwordless sudo for the zfs verbs —
    /// blanket (`sudo -n true`) or scoped (`sudo -n -l zfs mount`).
    ///
    /// Probed on every discovery regardless of zfs presence: the fact is
    /// host-general, not zfs-specific. A host without sudo installed at all
    /// reads as `false`, never a thrown discovery.
    public var sudoNoPassword: Dated<Bool>?
    /// Whether this host can reach others with the operator's forwarded
    /// agent, keyed by destination alias — the system design's "probed
    /// once, remembered." Absent means unprobed, and unprobed selects
    /// the proxy path, the conservative truth.
    public var forwarding: [String: Dated<ForwardingFact>]?
    /// Which wire read of this process these facts came from.
    ///
    /// The Field counts its reads and stamps each host's facts with the
    /// read that produced them. Facts loaded from the cache carry nil —
    /// memory of another launch, shown but never plan-authorizing. Not
    /// persisted: a generation only means something to the process that
    /// counted it.
    public var generation: Int?

    /// A host not yet visited — all groups empty.
    public init(
        reachability: Dated<Reachability>? = nil,
        capability: Dated<HostCapability>? = nil,
        zfsTopology: Dated<[ZFSDataset]>? = nil,
        zfsTopologyUnavailable: Dated<FactReadFailure>? = nil,
        mounts: Dated<[Mount]>? = nil,
        mountsUnavailable: Dated<FactReadFailure>? = nil,
        sudoNoPassword: Dated<Bool>? = nil,
        forwarding: [String: Dated<ForwardingFact>]? = nil,
        generation: Int? = nil
    ) {
        self.reachability = reachability
        self.capability = capability
        self.zfsTopology = zfsTopology
        self.zfsTopologyUnavailable = zfsTopologyUnavailable
        self.mounts = mounts
        self.mountsUnavailable = mountsUnavailable
        self.sudoNoPassword = sudoNoPassword
        self.forwarding = forwarding
        self.generation = generation
    }

    /// The persisted keys — `generation` is deliberately absent, so a
    /// cache file never carries one launch's count into the next.
    private enum CodingKeys: String, CodingKey {
        case reachability
        case capability
        case zfsTopology
        case zfsTopologyUnavailable
        case mounts
        case mountsUnavailable
        case sudoNoPassword
        case forwarding
    }
}
