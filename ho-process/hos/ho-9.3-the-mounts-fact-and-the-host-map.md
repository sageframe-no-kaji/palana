---
created: 2026-07-05
status: draft
type: ho-document
project: palana
ho: 9.3
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-03-the-field
  - ho-07.5-the-busybox-userland
  - ho-09-the-surface-field-view
  - ho-9.2-settings
agent-tasks:
  - Ho-9.3-AT-01.md
  - Ho-9.3-AT-02.md
---

# ho-9.3 — The Mounts Fact and the Host Map

The Field learns its third topology question, and the answer gets a surface. Today the Field knows what a host can do (the capability probe) and where its ZFS datasets sit (the topology read). What it cannot answer is the ground itself—kanyo runs the production containers on plain ext4, and to pālana that filesystem does not exist. The mounts fact fixes this: every filesystem, not just ZFS, discovered on demand and remembered like every other fact. The host map renders it—the practitioner's ask, verbatim: "an info pane, like ??, pulled up from the top bar menu"—hosts, filesystems present, aged honestly.

**Out of scope:** capacity (how full a filesystem is—a `df`-shaped fact, its own question, queued not built). The local machine's mounts in the map (the local row appears and says "this machine"—the Field's memory is remote memory, and growing local discovery into the Field is a bigger move than this ho needs). Pointing a pane from a map row (the field view owns the pointing verbs—if his hands want it here too, that is a feedback round). A probe-all sweep. Any polling, anywhere.

**Resolves deferred decisions** (from the overview's Checkpoint 3 entry): the map surface—field view grown versus a pinned sibling—decided here, Decision 4.

---

## Phase 1 — Think

### Decision 1 — The mount vocabulary: source, target, fstype, read-only

`Mount` joins the fact vocabulary beside `ZFSDataset`: the device or remote spec (`source`), the mountpoint (`target`), the filesystem type (`fstype`), and one derived bit (`readOnly`)—a read-only ground changes what an operator can do there, so it earns a place the options noise does not. findmnt's shape without findmnt's dependency. The fact records every mount the host reports—truth does not editorialize—and a pure classifier (`MountKind`: storage, network, system) gives the surfaces their filter. Unknown fstypes classify as storage: the unfamiliar shows rather than hides.

### Decision 2 — The read keys on the kernel, not the flavor

The committed direction said findmnt-shaped on GNU, with the BSD/BusyBox variants to decide or a degradation to name. The engineering answer dissolves the question: the mount table is the kernel's truth, not the userland's. On Linux—GNU and BusyBox alike—`cat /proc/mounts` reads the kernel's own table in a format the kernel documents: six space-separated fields, spaces in paths escaped as octal `\040`. One parser serves kanyo and zencat at identical fidelity, and BusyBox's vendor-trimmed flag roulette (ho-07.5's lesson) never enters the game because `cat` is the whole dependency. Everywhere else—Darwin, the real BSDs—`mount` answers in the stable `source on target (fstype, options)` shape, parsed by splitting at the first " on " and the last " (". `HostCapability.kernel` already carries the selector. No degradation to name: both paths carry the full four fields. Lines that fit neither shape are skipped—stray noise is not topology, the ZFS parse's own law.

### Decision 3 — Mounts ride discover, the third exchange

`HostFacts` grows `mounts: Dated<[Mount]>?`, and `Field.discover` grows the third exchange: probe, then the ZFS read when zfs is present, then the mounts read keyed on the probed kernel. Recorded only on exit 0, like the ZFS read—a failed read leaves the prior fact standing. Cached in field-cache.json, aged by its own timestamp, refreshed by the same `r` that refreshes everything. Old caches decode with the field absent, no migration. No new wire paths, no polling—discovery still runs when asked and only then.

### Decision 4 — The host map is a pinned sibling panel, KeysPanel lineage

His ask named the interaction: an info pane, like `??`, pulled up from the top bar. The feel is his call and the machinery is mine—so the map is a floating, borderless, hand-built NSPanel on the KeysPanel lineage, never a SwiftUI Window scene (the law, learned three rounds running). `HostMapPanelController.shared`, its own window identifier, Esc closing by window identity in the key monitor, freely resizable with the frame remembered. It floats while the panes work—that is the point of pinned. Summoned by the titlebar glyph beside the gear and by `F` (bare keys keep their case—G's precedent). The content: every visible host—the ho-9.2 curtain applies—wearing the field card's fact line (reachability and age, flavor, zfs, rsync), then its filesystems: storage and network mounts sorted by target, ◆ where a target is exactly a remembered dataset mountpoint, one quiet count line for the system mounts not shown—no silent truncation. A per-host probe button rides each section, because a map of "never visited" with no way to ask is the discoverability miss his hands have caught twice. The panel refreshes on summon and after its own probes. It stays up when the help card or field view opens—reference, not modal.

### Decision 5 — Core owns the map's display model

`HostMap` is a pure core value on the FieldOutline precedent: hosts plus a fact snapshot in, ordered host sections out—fact line data, classified and sorted mount rows, dataset correlation, system count. The panel renders sections and owns nothing. Everything that can be wrong lives where the tests are.

### Decision 6 — The boundary marks: ◆ keeps the dataset, ◇ joins for the plain mount

The pane rows already wear ◆ where a row is exactly a remembered dataset mountpoint. The mounts fact extends the same question to every filesystem: a row that is exactly a mount target—and not a dataset—wears ◇. Filled means zfs send territory, hollow means a filesystem boundary the transports care about. `PaneModel.commit` gathers both sets from memory in the same no-wire hop it already makes, and the resolution is a pure core function beside `ZFSTopology.mountpointSet`.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session—the ho-09 delegation verdict stands. AT-02 depends on AT-01.

### Ho-9.3-AT-01 — The core: the mount vocabulary, the third exchange, the map model

`Mount`/`MountKind`, `MountTable` (commands, both parsers, classification, target set), `HostFacts.mounts`, `Field.discover`'s third exchange, `HostMap`, full battery plus live integration reads. → `ho-process/agent-tasks/Ho-9.3-AT-01.md`

### Ho-9.3-AT-02 — The Surface: the pinned panel, the summons, the hollow diamond

`HostMapPanelController` and the panel content, `F` and the titlebar glyph, the key monitor's identity branch, the per-host probe wiring, the ◆/◇ marks through `PaneModel`, the vocabulary lines. → `ho-process/agent-tasks/Ho-9.3-AT-02.md`

### Done means

- One probe records a host's mount table beside its datasets—Linux proven live against the container fixture, BSD proven live against this machine, BusyBox proven by corpus
- kanyo-shaped ground—ext4, no zfs—renders in the map, which is the reason this ho exists
- `F` and the titlebar glyph summon a panel that stays up while the panes work, and Esc puts it away
- Pane rows at filesystem boundaries wear ◆ for datasets and ◇ for plain mounts
- Verification rhythm green, coverage floor holds, `gh run list` consulted after push, no test mutates anything anywhere

---

## Phase 3 — Reflect

*To be filled in after execution. Prompts:*

- **Did the design hold?** Did the kernel-keyed read survive contact with zencat's vendor BusyBox and kanyo's Docker overlay noise?
- **Decision review.** Was the pinned panel the right reading of "like ??"—or do his hands want the field view grown instead?
- **What did the real mount tables look like?** System-mount counts, unexpected fstypes, anything the classifier misfiled.
- **What broke that the tests didn't catch?**
- **Followups.** Capacity fact, local mounts in the map, pointing from map rows—did any of these get asked for?

---

_Authored: 2026-07-05 (Think phase)._
_Execution and Reflect: pending._
