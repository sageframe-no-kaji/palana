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
/// GNU means `stat --version` answered. BusyBox declines long options and
/// classifies BSD — the conservative side, since BSD is the fallback
/// command path downstream.
public enum UserlandFlavor: String, Codable, Sendable {
    /// GNU coreutils userland.
    case gnu = "GNU"
    /// BSD or BusyBox userland — the portable command path.
    case bsd = "BSD"
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

    /// Assembles a capability fact.
    public init(kernel: String, flavor: UserlandFlavor, zfs: String?, rsync: String?) {
        self.kernel = kernel
        self.flavor = flavor
        self.zfs = zfs
        self.rsync = rsync
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
    public var zfsTopology: Dated<[ZFSDataset]>?
    /// Whether this host can reach others with the operator's forwarded
    /// agent, keyed by destination alias — the system design's "probed
    /// once, remembered." Absent means unprobed, and unprobed selects
    /// the proxy path, the conservative truth.
    public var forwarding: [String: Dated<ForwardingFact>]?

    /// A host not yet visited — all groups empty.
    public init(
        reachability: Dated<Reachability>? = nil,
        capability: Dated<HostCapability>? = nil,
        zfsTopology: Dated<[ZFSDataset]>? = nil,
        forwarding: [String: Dated<ForwardingFact>]? = nil
    ) {
        self.reachability = reachability
        self.capability = capability
        self.zfsTopology = zfsTopology
        self.forwarding = forwarding
    }
}
