// The ZFS topology read and the dataset-boundary question. `zfs list -H`
// is tab-separated and machine-stable; boundary resolution is a pure
// function over facts already gathered — longest mounted mountpoint
// prefix wins. Deferred to no one: the Plan Engine asks, the Field answers
// from memory.

import Foundation

/// Composes and parses the topology read, and resolves dataset boundaries.
public enum ZFSTopology {
    /// The topology command.
    ///
    /// `-H -p` for headerless tab-separated stability; `mounted` rides
    /// along because an unmounted mountpoint is an intention, not a
    /// location, and must never match a path query.
    public static let listCommand = "zfs list -H -p -o name,mountpoint,mounted -t filesystem"

    /// Parses `zfs list -H` output into dataset facts.
    ///
    /// Tab-separated, three fields per line. Lines that do not fit are
    /// skipped — stray noise is not topology.
    public static func parse(_ stdout: String) -> [ZFSDataset] {
        stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            return ZFSDataset(
                name: String(fields[0]),
                mountpoint: String(fields[1]),
                mounted: fields[2] == "yes"
            )
        }
    }

    /// Which dataset contains this path — longest-mountpoint-prefix match
    /// over mounted datasets with real mountpoints.
    ///
    /// `legacy`, `none`, and unmounted datasets participate as facts but
    /// never match. Prefixes bind at path-component boundaries:
    /// `/tank/data` contains `/tank/data/x`, never `/tank/database`.
    public static func datasetContaining(
        _ path: String,
        in datasets: [ZFSDataset]
    ) -> ZFSDataset? {
        let normalized = normalize(path)
        return
            datasets
            .filter { $0.mounted && $0.mountpoint.hasPrefix("/") }
            .filter { contains(mountpoint: $0.mountpoint, path: normalized) }
            .max { $0.mountpoint.count < $1.mountpoint.count }
    }

    private static func normalize(_ path: String) -> String {
        guard path != "/" else { return "/" }
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func contains(mountpoint: String, path: String) -> Bool {
        guard mountpoint != "/" else { return true }
        return path == mountpoint || path.hasPrefix(mountpoint + "/")
    }
}
