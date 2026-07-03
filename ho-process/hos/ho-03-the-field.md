---
created: 2026-07-03
status: complete
type: ho-document
project: palana
ho: 03
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-02-the-conduit
---

# ho-03 — The Field

Topology. Hosts parse from `~/.ssh/config`—if you can SSH to it, pālana can see it, and there is no trust ceremony of pālana's own. Per-host facts—reachability, ZFS pools and datasets, userland capability—are discovered on demand through the Conduit, never continuously, and remembered in the field cache as memory of the last visit.

**Out of scope:** any polling loop. Discovery is on demand only—the Field has no watching to enable. Services stay out of the vocabulary until the services plugin exists. No classification, no execution—the Field gathers and remembers.

**Resolves deferred decisions** (from the ho-overview):

- Capability probe design—what one round-trip learns about a host (deferred decision 3)

**Carries from ho-02:** the probe also records the remote rsync version (ho-06 needs ≥3.1 sending-side). Integration suites against one fixture are `.serialized`. Public declarations get DocC at writing time.

---

## Phase 1 — Think

### Decision 1 — Host enumeration parses aliases only; ssh resolves everything else

The config parser enumerates `Host` entries whose tokens carry no wildcard (`*`, `?`, `!`)—those are the operator's named hosts. It deliberately resolves nothing: no HostName lookup, no port, no user. The alias goes to the Conduit, the Conduit passes it to ssh, and ssh applies the operator's config exactly as the terminal would—ProxyJump, Match blocks, all of it. A parallel resolver would be a parallel identity, which the seed forbids. `Include` directives are followed recursively, paths relative to `~/.ssh`. The parser is pure—`(config text) → [alias]`—and unit-tested against config shapes including the practitioner's real patterns (multiple aliases per Host line, includes, wildcard exclusion).

### Decision 2 — The capability probe: one command, one round trip (deferred decision 3 resolved)

One compound command learns the host's shape:

```
uname -s && (stat --version >/dev/null 2>&1 && echo GNU || echo BSD) \
  && (command -v zfs >/dev/null && zfs version 2>/dev/null | head -1 || echo no-zfs) \
  && (command -v rsync >/dev/null && rsync --version 2>/dev/null | head -1 || echo no-rsync)
```

Four lines back: kernel, userland flavor, ZFS presence/version, rsync presence/version. The exact command is execution-time territory—it hardens against both fixture userlands (the container is Alpine/BusyBox-adjacent, the ZFS VM is Ubuntu) and the parse must survive both. The probe result is a fact like any other: recorded, timestamped, cached.

### Decision 3 — ZFS topology: `zfs list -H`, mountpoint-based boundary resolution

Topology reads as `zfs list -H -p -o name,mountpoint -t filesystem`—tab-separated, no headers, machine stable. The Plan Engine's dataset-boundary question—which dataset contains this path—resolves by longest-mountpoint-prefix match over the cached dataset list, a pure function on facts already gathered. Datasets with unmounted or legacy mountpoints participate as facts but never match a path query. Real `zfs` output is captured from the throwaway pool via `RecordingConduit` into transcripts; the parser's unit battery replays them.

### Decision 4 — The cache: one JSON file, timestamps per fact group, delete-safe

`field-cache.json` in `~/Library/Application Support/palana/` (injectable for tests). Shape: per host, the facts grouped by discovery kind—`reachability`, `capability`, `zfsTopology`—each group carrying its own `discoveredAt` timestamp, because the field view renders "remembered as of when." The cache is a convenience over re-derivable truth: corrupt or missing reads as empty, the Field rebuilds by discovering, and deleting the file is always safe. Atomic writes (write-temp-rename). No schema versioning yet—the file is deletable memory, not a system of record.

### Decision 5 — The Field is an actor over the Conduit, discovery explicit

`Field` is an actor holding the injected `any Conduit`, the parsed host list, and the cache. `hosts()` never touches the wire. `discover(host)` runs the probe and topology reads through the Conduit and updates the cache. `facts(host)` answers from cache only. `datasetContaining(path:on:)` serves the Plan Engine from cached topology. Reachability is not a poll—it is the typed outcome of the last discovery attempt, recorded like any fact.

### Discovery (deferred to execution) — the probe's exact text and both userlands' parses

The probe command's final form and its parser harden against the sshd container and the Ubuntu ZFS VM. Dataset fixtures (nested datasets, odd mountpoints) get created on the throwaway pool, recorded, and committed as transcripts.

---

## Phase 2 — Execute

One bounded conversation—no agent-task decomposition. Model: `claude-fable-5`.

Order of work:

1. Config parser, pure, with its unit battery (aliases, multi-alias lines, wildcards excluded, includes followed).
2. Fact model + cache: Codable shapes, timestamps per group, atomic write, corrupt-reads-as-empty. Unit-tested with injected paths.
3. The probe: command text, parser, hardened against both fixtures live, then recorded into transcripts.
4. ZFS topology parse + boundary resolution: datasets created on the throwaway pool, recorded via `RecordingConduit`, unit battery over the transcripts.
5. `Field` actor wiring it together; integration tests against both fixtures, `.serialized`.
6. Full verification rhythm; floor holds; CI green.

### Done means

- The Field answers `hosts()`, `discover(host)`, and `facts(host)` against fixtures, and dataset boundaries resolve correctly against the throwaway pool.
- The cache survives deletion—the Field rebuilds from the hosts themselves.
- The probe identifies userland flavor, ZFS, and rsync version on both fixture userlands in one round trip.

---

## Phase 3 — Reflect

**Did the probe hold on both userlands?** It held, after one execution-time redesign the Think phase had reserved room for. The positional four-line `&&` chain died on paper before it ever ran: an absent `zfs` yields an empty command substitution, the line count shifts, and a positional parse misreads every line after it. The hardened form prefixes every fact with a `palana:` marker—order-independent, noise-immune, empty-value-means-absent. Three userlands verified live: the container answers GNU/no-zfs/no-rsync, the pool VM answers GNU/zfs-2.4.1/rsync-3.4.1, Darwin answers BSD with openrsync—whose "protocol version 29" the version parse correctly refuses to read as a version (dotted-form required). One surprise worth recording: the Alpine-based container reports **GNU**, not BSD—the linuxserver image ships coreutils. BusyBox-classified-as-BSD remains the designed conservative fallback, but no fixture currently exercises it; CI's Darwin runner is the live BSD path.

**Boundary resolution against real mountpoints.** The pool surfaced one gap in the committed read: `zfs list -H -p -o name,mountpoint` cannot honor "unmounted datasets never match," because an unmounted dataset still reports its would-be mountpoint—an intention, not a location. The `mounted` column now rides along, and `palana/detached` (created, unmounted) correctly resolves its path to the parent. The out-of-tree mountpoint (`palana/svc` at `/opt/services`) proved longest-prefix against nesting, and component-boundary binding keeps `/tank/database` out of `/tank/data`.

**Cache shape review.** As designed: per host, three fact groups, each under its own `discoveredAt`—the field view reads "remembered as of when" straight off the shape. Corrupt-reads-as-empty and the unwritable-disk downgrade (memory-only, discovery unharmed) are both under test. One addition beyond the Think phase: reachable-but-garbled is not a fact—`ProbeParseError` throws rather than recording a lie, while door failures record as unreachable facts with the prior visit's memory retained.

**Followups for ho-04.** The rsync version fact is recorded (`rsyncVersion`, dotted-parse). The flavor fact selects the listing command path—note the container fixture is GNU, so ho-04's BSD listing battery leans on CI's Darwin sshd and recorded transcripts, not the container. Tooling findings for the execution record: SwiftLint's `pattern_matching_keywords` conflicts with swift-format's `UseLetInEveryBoundCaseVariable` (resolved in `.swiftlint.yml`, swift-format canonical), and `limactl show-ssh` is deprecated—the fixture script copies `~/.lima/<vm>/ssh.config` instead.

---

_Authored: 2026-07-03 (Think phase). Executed and closed: 2026-07-03._
_83 tests, 15 suites. PalanaCore 97.48% line coverage against the 90% floor._
