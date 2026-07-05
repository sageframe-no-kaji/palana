// MountTable's unit battery — inline corpora, one test per truth. Both
// kernels, both parsers, the octal decoder, the classifier, and the target
// set normalizer. No wire contact of any kind.

import Foundation
import Testing

@testable import PalanaCore

@Suite("MountTable")
struct MountTableTests {
    // MARK: - command(forKernel:)

    @Test("Linux kernel returns cat /proc/mounts")
    func commandLinux() {
        #expect(MountTable.command(forKernel: "Linux") == "cat /proc/mounts")
    }

    @Test("Darwin and other kernels return mount")
    func commandBSD() {
        #expect(MountTable.command(forKernel: "Darwin") == "mount")
        #expect(MountTable.command(forKernel: "FreeBSD") == "mount")
        #expect(MountTable.command(forKernel: "OpenBSD") == "mount")
    }

    // MARK: - parseLinux

    @Test("kanyo-shaped /proc/mounts: counts per kind, field extraction, overlay is system")
    func parseLinuxKanyo() {
        // 8 lines: sysfs(sys), proc(sys), ext4(storage), cgroup2(sys),
        //          overlay×2(sys), tmpfs(sys), nfs4(network)
        let stdout = """
            sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
            proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
            /dev/sda1 / ext4 rw,relatime 0 0
            cgroup2 /sys/fs/cgroup cgroup2 rw 0 0
            overlay /var/lib/docker/overlay2/a overlay rw 0 0
            overlay /var/lib/docker/overlay2/b overlay rw 0 0
            tmpfs /tmp tmpfs rw 0 0
            server:/export /mnt/share nfs4 rw 0 0
            """
        let mounts = MountTable.parseLinux(stdout)
        #expect(mounts.count == 8)

        let systemMounts = mounts.filter { MountTable.classify(fstype: $0.fstype) == .system }
        let storageMounts = mounts.filter { MountTable.classify(fstype: $0.fstype) == .storage }
        let networkMounts = mounts.filter { MountTable.classify(fstype: $0.fstype) == .network }
        // sysfs + proc + cgroup2 + overlay + overlay + tmpfs = 6 system
        #expect(systemMounts.count == 6)
        #expect(storageMounts.count == 1, "only ext4 root")
        #expect(networkMounts.count == 1, "nfs4 share")

        // overlay classifies as system
        let overlayMounts = mounts.filter { $0.fstype == "overlay" }
        #expect(overlayMounts.count == 2)
        #expect(MountTable.classify(fstype: "overlay") == .system)

        // ext4 root fields
        let root = mounts.first { $0.target == "/" }
        #expect(root?.source == "/dev/sda1")
        #expect(root?.fstype == "ext4")
        #expect(root?.readOnly == false)

        // nfs4 line
        #expect(networkMounts[0].source == "server:/export")
        #expect(networkMounts[0].target == "/mnt/share")
        #expect(networkMounts[0].fstype == "nfs4")
        #expect(networkMounts[0].readOnly == false)
    }

    @Test("zencat-shaped BusyBox /proc/mounts: squashfs read-only, tmpfs rw, proc system")
    func parseLinuxZencat() {
        let stdout = """
            /dev/sda / squashfs ro 0 0
            tmpfs /tmp tmpfs rw 0 0
            proc /proc proc rw 0 0
            """
        let mounts = MountTable.parseLinux(stdout)
        #expect(mounts.count == 3)

        let squashfsMount = mounts.first { $0.fstype == "squashfs" }
        #expect(squashfsMount?.readOnly == true, "ro option sets readOnly")
        #expect(MountTable.classify(fstype: "squashfs") == .system)
        #expect(MountTable.classify(fstype: "tmpfs") == .system)
        #expect(MountTable.classify(fstype: "proc") == .system)

        let tmpfsMount = mounts.first { $0.fstype == "tmpfs" }
        #expect(tmpfsMount?.readOnly == false, "rw option: not read-only")
    }

    @Test("octal escape \\040 in target decodes to space")
    func parseLinuxOctalSpace() {
        let line = "/dev/sdb1 /mnt/with\\040space ext4 rw 0 0"
        let mounts = MountTable.parseLinux(line)
        #expect(mounts.count == 1)
        #expect(mounts[0].target == "/mnt/with space")
        #expect(mounts[0].source == "/dev/sdb1")
        #expect(mounts[0].fstype == "ext4")
    }

    @Test("malformed Linux lines skip without throwing")
    func parseLinuxMalformed() {
        let stdout = """
            short
            two fields
            three fields here
            /dev/sda1 / ext4 rw 0 0
            """
        let mounts = MountTable.parseLinux(stdout)
        #expect(mounts.count == 1, "only the four-field line survives")
    }

    // MARK: - parseBSD

    @Test("Darwin corpus: space-carrying source parses whole; root is read-only")
    func parseBSDDarwin() {
        let stdout = """
            /dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
            devfs on /dev (devfs, local, nobrowse)
            map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)
            """
        let mounts = MountTable.parseBSD(stdout)
        #expect(mounts.count == 3)

        let root = mounts.first { $0.target == "/" }
        #expect(root?.source == "/dev/disk3s1s1")
        #expect(root?.fstype == "apfs")
        #expect(root?.readOnly == true, "read-only token flags the root")

        let dev = mounts.first { $0.target == "/dev" }
        #expect(dev?.source == "devfs")
        #expect(dev?.fstype == "devfs")
        #expect(dev?.readOnly == false)

        // source "map auto_home" carries a space but no " on "
        let home = mounts.first { $0.target == "/System/Volumes/Data/home" }
        #expect(home?.source == "map auto_home", "space-carrying source parses whole")
        #expect(home?.fstype == "autofs")
        #expect(MountTable.classify(fstype: "autofs") == .system)
    }

    @Test("FreeBSD zfs line parses correctly")
    func parseBSDFreeBSD() {
        let line = "zroot/ROOT/default on / (zfs, local, noatime, nfsv4acls)"
        let mounts = MountTable.parseBSD(line)
        #expect(mounts.count == 1)
        #expect(mounts[0].source == "zroot/ROOT/default")
        #expect(mounts[0].target == "/")
        #expect(mounts[0].fstype == "zfs")
        #expect(mounts[0].readOnly == false)
        #expect(MountTable.classify(fstype: "zfs") == .storage)
    }

    @Test("ro token flags BSD read-only")
    func parseBSDReadOnlyToken() {
        let line = "zroot/data on /data (zfs, local, ro)"
        let mounts = MountTable.parseBSD(line)
        #expect(mounts.count == 1)
        #expect(mounts[0].readOnly == true, "ro token in BSD options signals read-only")
    }

    @Test("malformed BSD lines skip without throwing")
    func parseBSDMalformed() {
        // no parens, no trailing ), no " on "
        let stdout = """
            no parens here at all
            /dev/disk1 on /mnt no parens here
            /dev/disk1s1 on / (apfs, local)
            """
        let mounts = MountTable.parseBSD(stdout)
        #expect(mounts.count == 1, "only the well-formed line survives")
    }

    // MARK: - classify

    @Test("network fstypes classify as network")
    func classifyNetwork() {
        for fstype in ["nfs", "nfs4", "cifs", "smbfs", "afpfs", "webdav", "sshfs", "fuse.sshfs"] {
            #expect(
                MountTable.classify(fstype: fstype) == .network,
                "expected network for \(fstype)"
            )
        }
    }

    @Test("system fstypes classify as system")
    func classifySystem() {
        let systemTypes = [
            "proc", "procfs", "sysfs", "devfs", "devpts", "devtmpfs", "tmpfs", "ramfs",
            "cgroup", "cgroup2", "pstore", "bpf", "securityfs", "debugfs", "tracefs",
            "configfs", "fusectl", "mqueue", "hugetlbfs", "overlay", "squashfs", "autofs",
            "binfmt_misc", "rpc_pipefs", "nsfs", "fdescfs", "swap",
        ]
        for fstype in systemTypes {
            #expect(
                MountTable.classify(fstype: fstype) == .system,
                "expected system for \(fstype)"
            )
        }
    }

    @Test("unknown fstypes classify as storage — the unfamiliar shows rather than hides")
    func classifyUnknownIsStorage() {
        #expect(MountTable.classify(fstype: "ext4") == .storage)
        #expect(MountTable.classify(fstype: "apfs") == .storage)
        #expect(MountTable.classify(fstype: "zfs") == .storage)
        #expect(MountTable.classify(fstype: "xfs") == .storage)
        #expect(MountTable.classify(fstype: "btrfs") == .storage)
        #expect(MountTable.classify(fstype: "exfat") == .storage)
        #expect(MountTable.classify(fstype: "anything-unknown") == .storage)
    }

    // MARK: - targetSet

    @Test("targetSet includes normalized absolute targets, excludes relative ones")
    func targetSetNormalization() {
        let mounts: [Mount] = [
            Mount(source: "a", target: "/", fstype: "ext4", readOnly: false),
            Mount(source: "b", target: "/home/", fstype: "ext4", readOnly: false),
            Mount(source: "c", target: "/tank", fstype: "zfs", readOnly: false),
            Mount(source: "d", target: "relative", fstype: "proc", readOnly: false),
        ]
        let set = MountTable.targetSet(in: mounts)
        #expect(set.contains("/"), "/ stays /")
        #expect(set.contains("/home"), "trailing slash stripped")
        #expect(!set.contains("/home/"), "trailing slash gone")
        #expect(set.contains("/tank"))
        #expect(!set.contains("relative"), "relative target excluded")
        #expect(set.count == 3)
    }

    @Test("targetSet on empty list is empty")
    func targetSetEmpty() {
        #expect(MountTable.targetSet(in: []).isEmpty)
    }
}
