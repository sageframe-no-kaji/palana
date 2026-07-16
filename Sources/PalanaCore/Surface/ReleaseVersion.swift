// ReleaseVersion — the pure version comparison behind the update check (ho-12).
//
// pālana checks GitHub for the latest release tag on launch and announces when a
// newer one exists (no auto-install — the operator clicks through to the
// release). The compare is the one part worth pinning without a network: parse a
// tag like `v1.2` or a bundle version like `1.2.0`, and decide which is newer.
// Missing trailing components read as zero (so `v1.0` == `1.0.0`); a pre-release
// suffix (`v1.0-beta`) sorts below the same release.

import Foundation

/// A parsed release version, comparable across `v`-prefixed tags and bundle
/// version strings.
public struct ReleaseVersion: Comparable, Equatable, Sendable {
    /// The dotted numeric components — `1.2.0` parses to `[1, 2, 0]`.
    public let components: [Int]
    /// True when the version carried a pre-release suffix (`-beta`, `-rc1`).
    public let isPrerelease: Bool

    /// Parses `raw`, tolerating a leading `v`/`V` and a `-suffix` pre-release.
    ///
    /// Returns `nil` when the numeric core is absent or non-numeric — the caller
    /// treats an unparseable version as "no update", never a false positive.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text = String(text.dropFirst()) }
        let core = text.split(separator: "-").first.map(String.init) ?? text
        let parsed = core.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
        components = parsed.compactMap { $0 }
        isPrerelease = text.contains("-")
    }

    /// Orders by numeric components (missing trailing ones read as zero), then
    /// by pre-release status (a pre-release sorts below the same final release).
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        // Equal numeric core: a pre-release is older than the final release.
        if lhs.isPrerelease != rhs.isPrerelease { return lhs.isPrerelease }
        return false
    }

    /// Whether `latest` names a newer release than `current`.
    ///
    /// `false` when either string doesn't parse — an announce only ever fires on
    /// a version we're sure is newer.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let latest = Self(latest), let current = Self(current) else {
            return false
        }
        return latest > current
    }
}
