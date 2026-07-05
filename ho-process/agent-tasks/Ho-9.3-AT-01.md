---
created: 2026-07-05
type: agent-task
project: palana
parent-ho: 9.3
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.3-AT-01 — The core: the mount vocabulary, the third exchange, the map model

**Goal**

PalanaCore learns the mounts fact: a `Mount` vocabulary, a `MountTable` composer/parser pair covering Linux (`/proc/mounts`) and BSD (`mount`), `HostFacts.mounts` recorded by `Field.discover` as a third exchange, and a pure `HostMap` display model for the host map surface. Full unit battery plus live integration reads on both kernels.

**Context**

The Field answers two topology questions today: capability (one probe round trip, `CapabilityProbe`) and ZFS datasets (`ZFSTopology`, read when zfs is present). This task adds the third: the full mount table, every filesystem, so non-ZFS ground (kanyo's ext4) becomes visible. ho-9.3 Decision 2 keys the read on `HostCapability.kernel`, not the userland flavor—`/proc/mounts` is the kernel's own table and serves GNU and BusyBox identically, `mount` serves Darwin and the BSDs. Facts are discovered on demand, cached, and aged—no polling exists in this system. Read `Sources/PalanaCore/Field/` before writing: `Field.swift`, `HostFacts.swift`, `ZFSTopology.swift`, `CapabilityProbe.swift` establish every pattern this task follows, including DocC on all public declarations (swift-format strict enforces it).

**Files**

- Modify: `Sources/PalanaCore/Field/HostFacts.swift` (add `Mount`, `MountKind`, `HostFacts.mounts`)
- Create: `Sources/PalanaCore/Field/MountTable.swift`
- Modify: `Sources/PalanaCore/Field/Field.swift` (third exchange in `discover`)
- Create: `Sources/PalanaCore/Surface/HostMap.swift`
- Create: `Tests/PalanaCoreTests/MountTableTests.swift`
- Create: `Tests/PalanaCoreTests/HostMapTests.swift`
- Modify: `Tests/PalanaCoreTests/FieldTests.swift` (discover scripts grow the mounts exchange)
- Modify: `Tests/PalanaCoreTests/FieldCacheTests.swift` (round-trip with mounts present)
- Modify: `Tests/PalanaCoreTests/FieldIntegrationTests.swift` (live mounts assertions)

**Required Changes**

1. **`Mount` and `MountKind` in `HostFacts.swift`**, beside `ZFSDataset`.

   ```swift
   public struct Mount: Codable, Sendable, Equatable, Hashable {
       public var source: String    // device or remote spec — /dev/sda1, tank/data, server:/export
       public var target: String    // the mountpoint path
       public var fstype: String    // ext4, apfs, zfs, nfs, proc…
       public var readOnly: Bool    // derived from options — a read-only ground changes what the operator can do
   }
   ```

   `MountKind` is a three-case enum: `storage`, `network`, `system`. `HostFacts` gains `public var mounts: Dated<[Mount]>?` with the initializer growing a defaulted-nil parameter, matching the existing groups.

2. **`MountTable` in `Sources/PalanaCore/Field/MountTable.swift`** — an enum namespace on the `ZFSTopology` model:

   - `command(forKernel:) -> String` — `"cat /proc/mounts"` when the kernel is `"Linux"`, `"mount"` otherwise.
   - `parseLinux(_:) -> [Mount]` — `/proc/mounts` lines: six space-separated fields, first four consumed (source, target, fstype, options). Decode octal escapes `\040` (space), `\011` (tab), `\012` (newline), `\134` (backslash) in source and target. `readOnly` when the comma-split options contain `ro` exactly. Lines with fewer than four fields are skipped.
   - `parseBSD(_:) -> [Mount]` — `source on target (fstype, opt, …)` lines: the options group starts at the *last* `" ("` and runs to the trailing `")"`, the head splits at the *first* `" on "` (sources are devices and specs—`map auto_home` carries a space but never `" on "`; targets may carry anything). `fstype` is the first comma-separated token, trimmed. `readOnly` when the tokens contain `read-only` (Darwin) or `ro` (BSD) exactly. Lines that do not fit are skipped.
   - `classify(fstype:) -> MountKind` — network: `nfs`, `nfs4`, `cifs`, `smbfs`, `afpfs`, `webdav`, `sshfs`, `fuse.sshfs`. System: `proc`, `procfs`, `sysfs`, `devfs`, `devpts`, `devtmpfs`, `tmpfs`, `ramfs`, `cgroup`, `cgroup2`, `pstore`, `bpf`, `securityfs`, `debugfs`, `tracefs`, `configfs`, `fusectl`, `mqueue`, `hugetlbfs`, `overlay`, `squashfs`, `autofs`, `binfmt_misc`, `rpc_pipefs`, `nsfs`, `fdescfs`, `swap`. Everything else—including anything unknown—is `storage`: the unfamiliar shows rather than hides.
   - `targetSet(in:) -> Set<String>` — the targets of all mounts whose target begins with `/`, normalized without a trailing slash (`/` stays `/`), on the `ZFSTopology.mountpointSet` model.

3. **The third exchange in `Field.discover`.** After the capability parse (and the ZFS read when zfs is present), inside the same `do` block: run `MountTable.command(forKernel: capability.kernel)` through the conduit, and when `exitStatus == 0`, record `facts.mounts = Dated(value:discoveredAt:)` with the kernel-matched parser's result. A nonzero exit records nothing and the prior fact stands—the ZFS read's exact shape.

4. **`HostMap` in `Sources/PalanaCore/Surface/HostMap.swift`** — the map's pure display model, on the `FieldOutline` precedent (build from hosts + facts, the Surface renders and owns nothing):

   ```swift
   public struct HostMap: Equatable, Sendable {
       public struct MountRow: Equatable, Sendable { target, fstype, source, readOnly, kind, isDatasetMountpoint }
       public struct HostSection: Equatable, Sendable {
           alias, isLocal, visited, reachability: Reachability?, rememberedAt: Date?,
           flavor: UserlandFlavor?, hasZFS, hasRsync,
           mounts: [MountRow],          // storage + network only, sorted by target
           systemMountCount: Int,       // what the sort hid — the count line, never silent
           mountsRememberedAt: Date?    // the mounts fact's own age
       }
       public let sections: [HostSection]
       public init(hosts: [String], facts: [String: HostFacts], localHost: String)
   }
   ```

   Hosts arrive ordered (local first—the caller's job, as with `FieldOutline`). The local section carries no facts. `isDatasetMountpoint` is true when the row's normalized target sits in `ZFSTopology.mountpointSet` of that host's remembered datasets. Exact stored property names may follow the codebase's idiom—the shape above is the contract, not a transcription.

5. **`MountTableTests`** — inline corpora, one test per truth:

   - A kanyo-shaped `/proc/mounts`: ext4 root, `/proc`, `/sys`, `cgroup2`, several `overlay` lines, a `tmpfs`, an `nfs4` line—asserting counts per `MountKind`, field extraction, and that overlay classifies as system.
   - A zencat-shaped BusyBox `/proc/mounts`: squashfs root read-only (`ro` in options), tmpfs, proc—asserting `readOnly` and classification.
   - An escape line: `/dev/sdb1 /mnt/with\040space ext4 rw 0 0` decodes to `/mnt/with space`.
   - A Darwin `mount` corpus: `/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)`, `devfs on /dev (devfs, local, nobrowse)`, `map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)`—asserting the space-carrying source parses whole and root reads `readOnly`.
   - A FreeBSD-shaped line: `zroot/ROOT/default on / (zfs, local, noatime, nfsv4acls)`.
   - Malformed lines (short fields, no ` on `, no parens) skip without throwing.
   - `targetSet` normalization: trailing slashes drop, `/` survives, relative targets excluded.

6. **`HostMapTests`** — sections order and carry facts correctly, storage/network sort by target, system mounts count instead of render, dataset correlation marks exactly the remembered mountpoints, never-visited hosts produce an empty-but-present section, the local section is bare.

7. **Existing suites grow.** `FieldTests`: discover scripts gain the third exchange (scripted conduits answer `cat /proc/mounts` or `mount` per the corpus kernel)—assert the fact records, ages, and survives a failed mounts read (nonzero exit → prior fact stands). `FieldCacheTests`: a `HostFacts` with mounts round-trips, and a cache written without mounts still loads. `FieldIntegrationTests`: live discover against the container fixture asserts a non-empty mounts fact whose targets include `/`; a `LocalConduit`-driven parse of this machine's `mount` output asserts `/` present with a non-empty fstype. Reads only, as ever.

**Do Not**

- Do not touch `CapabilityProbe.command`—a probe change forces both recorded corpora to re-record live (ho-07.5's cost). The mounts read is its own exchange.
- Do not filter mounts at parse or record time. The fact is complete—classification is the surface's filter, applied in `HostMap`.
- Do not add capacity fields (size, used, available). That is a `df`-shaped fact, out of this ho's scope.
- Do not introduce any polling, timer, or background refresh. Discovery runs when asked and only then.
- Do not modify the Plan Engine, Transports, or any listing path.

**Stop Condition**

If the container fixture's live `/proc/mounts` read comes back empty or in a shape the parser refuses wholesale, stop and surface the raw output before loosening the parser—the format is kernel-documented, and a wholesale refusal means the model of it is wrong somewhere that matters.

**Acceptance**

- [ ] `swift build` clean
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift test` green — new suites and grown suites both, with the sshd fixture up so the integration reads run live (`scripts/sshd-fixture.sh start`)
- [ ] `HostFacts.mounts` survives a cache round trip, and a pre-9.3 cache file still loads
- [ ] No test mutates any host, any config, or anything outside temp dirs and fixtures

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
scripts/sshd-fixture.sh start
swift test 2>&1 | tail -20   # then check the run line itself, not just the tail
```

**Commit**

Single commit. Message format:

```
ho-9.3: the mounts fact — the Field's third question

Mount/MountKind vocabulary, MountTable (kernel-keyed: /proc/mounts on
Linux, mount elsewhere), HostFacts.mounts through Field.discover as the
third exchange, HostMap display model. Corpus battery both kernels,
live reads container + local.
```

No AI attribution tags, no Co-Authored-By—categorical.
