// The mount table read — two parsers, one selector. /proc/mounts on Linux
// is the kernel's own table; `mount` on BSD is the userland's stable format.
// The selector keys on HostCapability.kernel so BusyBox and GNU Linux both
// get the same kernel-owned truth.

import Foundation

/// Composes and parses the mount table read.
public enum MountTable {
    /// The command that reads the mount table, keyed on the kernel name.
    ///
    /// `"Linux"` returns `"cat /proc/mounts"` — the kernel's own table, BusyBox-safe.
    /// Every other kernel returns `"mount"` — the BSD-stable format.
    public static func command(forKernel kernel: String) -> String {
        kernel == "Linux" ? "cat /proc/mounts" : "mount"
    }

    /// Parses `/proc/mounts` output into mount facts.
    ///
    /// Six space-separated fields per line; first four consumed (source, target,
    /// fstype, options). Octal escapes in source and target — `\040` space,
    /// `\011` tab, `\012` newline, `\134` backslash — are decoded. `readOnly`
    /// when the comma-split options contain `ro` exactly. Lines with fewer than
    /// four fields are skipped.
    public static func parseLinux(_ stdout: String) -> [Mount] {
        stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count >= 4 else { return nil }
            let source = decodeOctal(String(fields[0]))
            let target = decodeOctal(String(fields[1]))
            let fstype = String(fields[2])
            let options = String(fields[3])
            let readOnly = options.split(separator: ",").map(String.init).contains("ro")
            return Mount(source: source, target: target, fstype: fstype, readOnly: readOnly)
        }
    }

    /// Parses `mount` output into mount facts.
    ///
    /// Format: `source on target (fstype, opt, …)`. The options group starts at
    /// the last `" ("` and runs to the trailing `")"`. The head splits at the
    /// first `" on "`. `fstype` is the first comma-separated token, trimmed.
    /// `readOnly` when tokens contain `read-only` (Darwin) or `ro` (BSD) exactly.
    /// Lines that do not fit are skipped.
    public static func parseBSD(_ stdout: String) -> [Mount] {
        stdout.split(separator: "\n").compactMap { line in
            let raw = String(line)
            guard
                raw.hasSuffix(")"),
                let optStart = raw.range(of: " (", options: .backwards)
            else { return nil }
            let optContent = String(raw[optStart.upperBound..<raw.index(before: raw.endIndex)])
            let head = String(raw[..<optStart.lowerBound])
            guard let onRange = head.range(of: " on ") else { return nil }
            let source = String(head[..<onRange.lowerBound])
            let target = String(head[onRange.upperBound...])
            let tokens = optContent.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let fstype = tokens.first ?? ""
            let readOnly = tokens.contains("read-only") || tokens.contains("ro")
            return Mount(source: source, target: target, fstype: fstype, readOnly: readOnly)
        }
    }

    /// Classifies a filesystem type.
    ///
    /// Network: nfs, nfs4, cifs, smbfs, afpfs, webdav, sshfs, fuse.sshfs.
    /// System: proc, sysfs, devfs, tmpfs, overlay, squashfs, autofs, cgroup, and their
    /// variants — the kernel's synthetic table.
    /// Storage: everything else, including anything unknown — the unfamiliar shows
    /// rather than hides.
    public static func classify(fstype: String) -> MountKind {
        switch fstype {
        case "nfs", "nfs4", "cifs", "smbfs", "afpfs", "webdav", "sshfs", "fuse.sshfs":
            return .network
        case "proc", "procfs", "sysfs", "devfs", "devpts", "devtmpfs", "tmpfs", "ramfs",
            "cgroup", "cgroup2", "pstore", "bpf", "securityfs", "debugfs", "tracefs",
            "configfs", "fusectl", "mqueue", "hugetlbfs", "overlay", "squashfs", "autofs",
            "binfmt_misc", "rpc_pipefs", "nsfs", "fdescfs", "swap", "efivarfs":
            return .system
        default:
            return .storage
        }
    }

    /// The set of normalized mount targets that begin with `/`.
    ///
    /// Trailing slashes are stripped; `/` itself stays `/`. Relative targets
    /// are excluded. Mirrors `ZFSTopology.mountpointSet`'s shape.
    public static func targetSet(in mounts: [Mount]) -> Set<String> {
        Set(
            mounts
                .filter { $0.target.hasPrefix("/") }
                .map { normalize($0.target) }
        )
    }

    /// The mount target containing `path` — longest prefix wins.
    ///
    /// The filesystem analog of `ZFSTopology.datasetContaining`: proves
    /// two paths share one filesystem so a same-host move can be a
    /// rename instead of a copy-verify-delete. Nil when no absolute
    /// target contains the path.
    public static func mountContaining(_ path: String, in mounts: [Mount]) -> String? {
        let normalized = normalize(path)
        return
            mounts
            .filter { $0.target.hasPrefix("/") }
            .map { normalize($0.target) }
            .filter { $0 == "/" || normalized == $0 || normalized.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
    }

    // MARK: - Private helpers

    // Decodes /proc/mounts octal escape sequences — \NNN where NNN is a
    // three-digit octal code. Unrecognized escapes pass through as-is.
    private static func decodeOctal(_ raw: String) -> String {
        var result = ""
        var idx = raw.startIndex
        while idx < raw.endIndex {
            if raw[idx] == "\\" {
                let after = raw.index(after: idx)
                if let ch = octalCharacter(in: raw, from: after) {
                    result.append(ch.char)
                    idx = ch.end
                    continue
                }
            }
            result.append(raw[idx])
            idx = raw.index(after: idx)
        }
        return result
    }

    // Attempts to read a three-digit octal escape starting at `from`.
    // Returns the decoded character and the index past the octal digits, or nil.
    private static func octalCharacter(
        in raw: String,
        from start: String.Index
    ) -> (char: Character, end: String.Index)? {
        var end = start
        var count = 0
        while count < 3, end < raw.endIndex, raw[end].isNumber {
            end = raw.index(after: end)
            count += 1
        }
        guard count == 3,
            let code = UInt32(raw[start..<end], radix: 8),
            let scalar = Unicode.Scalar(code)
        else { return nil }
        return (Character(scalar), end)
    }

    private static func normalize(_ path: String) -> String {
        guard path != "/" else { return "/" }
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
