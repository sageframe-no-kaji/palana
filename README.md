# pālana

*Tend your field.*

> pālana is a place to sit down and tend your infrastructure. A native Mac app — calm, keyboard-first, dual-pane — that plans every operation before enacting it, runs moves and copies server-side over SSH, and speaks ZFS natively. Select the files, press the key, read the plan, press Enter. The bytes travel host to host and your machine orchestrates without ever carrying them. A plugin workbench grows with the practice — the ZFS tool first, the rest as tending demands. It runs when you open it and stops when you close it. Nothing watches while you're away.

**Status:** **v1.0** — the first full release. The headless engine and the app surface are both complete: dual-pane SSH file management, plan → enact, cross-host transfers, the field view, the ZFS workbench (dataset tools, snapshots, mount), the interactive shell, the preview pane, drag-and-drop, dark mode, one-key zoom. A native, signed, notarized macOS app. Source open under GPL-3.0.

**▸ Get pālana.** A signed, notarized macOS app — [palana.sageframe.net](https://palana.sageframe.net) (macOS 14 or later). The source is here, GPL-3.0; **feedback and bugs** go to the [issue tracker](https://github.com/sageframe-no-kaji/palana/issues).

---

## What's Broken

There is no place to sit down and tend a homelab.

Every Mac file manager that speaks a network protocol — ForkLift, Transmit, Cyberduck — relays file operations through your machine. Drag a file from server A to server B and the bytes travel A → laptop → B. The interface presents a direct operation while executing an indirect one. For a 100GB archive moving between ZFS pools, that indirection is catastrophic — slow, fragile, and baffling when it fails, because you didn't know your machine was in the middle. The interface lied.

ZFS makes it worse. When every service has its own dataset, moving files between datasets is not a rename — it is a copy plus delete wearing a rename's clothes. File managers treat it as a rename and either fail silently or produce corrupt results. You discover this after the fact.

And the field has no map. Eleven machines, dozens of services, multiple pools — visible only as a stack of SSH tabs held together by memory. Grafana shows the disk filling, and then you open a terminal and do the work somewhere the graph can't see. Dashboards watch. Nobody works.

## What pālana Does

- **Plan → enact.** Every operation — copy, move, delete — compiles to a plan first: the entries with their sizes, the classification (within-dataset rename, cross-dataset copy-plus-delete, cross-host transfer), the transport with its auth path, the exact commands that will run. Dry-run is not a mode. It is the default. Enter enacts. Esc dismisses.
- **Server-side transfers.** Moves between hosts run host to host. The fast path forwards your SSH agent so host A authenticates to host B directly — your key never leaves your machine. When forwarding isn't available, pālana proxies through your machine instead. You don't choose. The plan names which path it will use.
- **ZFS, natively.** Dataset boundaries are first-class facts. A cross-dataset move is named as what it is before it runs. When both ends are whole datasets, the plan offers `zfs send | ssh | zfs receive` — block-level, an order of magnitude faster for large moves.
- **The field view.** One keystroke summons the topology — machines, pools, datasets, reachability — as an overlay. Pick a node, a pane points there, the overlay vanishes. Discovery happens on demand, never continuously.
- **The plan panel is a real terminal surface.** The plan's commands display there before enactment, and when Enter fires, the enactment echoes there live — the real commands, the real output, streaming. The claim that "these are the commands" is checkable by watching them run.
- **The Workbench.** A plugin architecture from day one. A plugin gets the SSH layer, the topology, and a surface slot. The ZFS tool — dataset management, snapshots, pool visualization — ships at v1 and proves the API.
- **The live shell.** `⌘\`` drops a real interactive terminal into the panel, per host — vim, htop, whatever — over your own `ssh`, without leaving pālana.
- **The preview pane.** Press `v` and the right pane follows the left's cursor: text scrollable and monospace, images and PDFs via Quick Look, an info card always. Local files, and remote text and images too.

## Your First Session

You open pālana. The panes are where you left them — left on jodo, right pointed nowhere useful. You tap the field view key and the topology appears: your machines, their pools, their datasets, remembered from last visit and marked as remembered. You pick a dataset on koan. The overlay vanishes and the right pane is there.

In the left pane you select 214 files — camera archives, 41.3 GB — and press the move key. Nothing moves. The plan panel opens: cross-host transfer, source and destination datasets named, transport rsync host-to-host, auth agent-forwarded direct, and under that the exact command that will run, one you could paste into a terminal yourself. You read it. Enter.

The command echoes into the panel and its output streams under it. A progress bar moves. The bytes travel jodo → koan and your laptop never carries one of them. Counts verify, the source entries delete as the plan said they would, both panes refresh. You saw everything before it happened, and everything that happened was something you saw.

You close pālana. It stops. The field has been tended.

## Keybindings

Five rule groups — learn the rules and the keys generate themselves.

**verbs** — a lowercase letter states an intent; the plan panel opens before anything runs

| key | verb |
|---|---|
| `y` | copy to other pane |
| `m` | move to other pane |
| `d` | delete |
| `r` | rename |
| `a` | create (trailing `/` = directory) |
| `t` | touch — update modified |

**names** — `r` and `a` open the name field; `⏎` does the whole job

**surfaces** — six summons, the set is closed

| key | surface |
|---|---|
| `f` | field view |
| `F` | host map (floats) |
| `*` | favorites panel |
| `` ` `` | terminal |
| `?` | this card · `?` again floats it |
| `⌘,` | settings |

**app** — `⌘` belongs to the app, never to files

| key | action |
|---|---|
| `⌘R` | refresh |
| `⌘← / ⌘→` | back / forward |
| `⌘+ / ⌘− / ⌘0` | zoom in / out / reset |
| `⌘K` | clear terminal |
| `⇧⌘G` | go to host : path |
| `⇧⌘L` | operations log |
| `8` | star highlighted entry |
| `⌘8` | star this folder |

**families** — sequence prefixes

| prefix | family |
|---|---|
| `c c / c d / c f / c n` | clipboard: path · directory · filename · name |
| `, n / , s / , m` | sort: by name · size · modified (again flips) |
| `g g / G` | top / bottom |

## What pālana Is Not

- **Not a dashboard or a monitor.** No alerts, no graphs, no watching. You cannot act from a graph anyway.
- **Not a daemon.** It runs when you open it and stops when you close it. There is no component that could outlive the window.
- **Not a sync tool.** No background replication, no continuous mutation. Every operation is one you enacted.
- **Not a Docker manager.** pālana sees services, not containers.
- **Not cross-platform.** Native Mac only. No Linux client, no web version. The cost is named and accepted.
- **Not an SMB/NFS/SFTP tool.** SSH is the only transport. This is a tool for tending your own machines, not for connecting to arbitrary ones.
- **No trust ceremony.** Trust is your `~/.ssh/config`. If you can SSH to it, pālana can see it — no key distribution, no parallel identity.

## Naming

**pālana** (पालन) — Sanskrit: to tend, nurture, sustain, steward. Not creation but ongoing care.

Not a management tool — management implies control. Not a monitoring tool — monitoring implies watching. A tending tool. You open it the way you walk through a garden: not because something is broken, but because tending is how things stay healthy.

## Where pālana Sits

pālana is the first tool of **Kṣetra-Ops**, a suite for tending homelab infrastructure, and it is governed by the suite's philosophy, **bīja**: no hidden causality, no automation without presence. Every principle above — the plan before the action, the on-demand discovery, the absence of a daemon — is that philosophy rendered as interaction design.

It is part of [Sageframe](https://atmarcus.net), a body of self-built tools and methodology by Andrew Marcus, and it is designed and built with the [Ho System](https://github.com/sageframe-no-kaji/ho-system). The `ho-process/` directory is the public build record — seed, system design, and the documents that follow.

## How It Works

**PalanaCore** is a headless Swift library that owns everything true — the topology, the directory reads, the plan engine, the transports — and carries a 90% test-coverage floor. **Palana**, the SwiftUI app, is a thin surface over it that renders state and forwards intent and decides nothing. All host contact passes through one component, **the Conduit**, which wraps the system `ssh` binary — your config, your keys, your agent, your ProxyJump behavior, exactly as they work in your terminal, with ControlMaster multiplexing keeping per-command overhead near zero. **The plan engine** is a pure function from gathered facts to a Plan, which makes it the most testable object in the system — and it had better be, because it is the part that must never lie.

## Architecture

Seven components, sliced by how the operator thinks about the work:

- **The Conduit** — SSH execution, and the only component that touches a host.
- **The Field** — the topology. Hosts from `~/.ssh/config`, facts discovered on demand, last-known state cached as memory.
- **The Listing** — remote directory reads. One command per directory.
- **The plan engine** — classification, transport selection, command composition. Facts in, Plan out.
- **The Transports** — enactment. rsync direct, proxy fallback, `zfs send/receive`, progress parsed from remote streams.
- **The Workbench** — the plugin API. The Conduit, the Field, and a surface slot, handed in.
- **The Surface** — the app. Panes, plan panel, field view, keyboard grammar.

The full design — every decision with its rationale — is public in the build record: [`ho-process/kamae-2-palana-system-design.md`](ho-process/kamae-2-palana-system-design.md).

## Tech Stack

- **Language:** Swift 6, strict concurrency
- **Package:** SwiftPM multi-product — PalanaCore library + Palana app
- **UI:** SwiftUI (macOS 14+)
- **Transport:** the system `ssh` and `rsync` binaries via Foundation `Process` — no embedded SSH library, no parallel transport stack
- **Testing:** swift-testing, ≥90% line coverage on PalanaCore
- **Lint and format:** swift-format + SwiftLint strict
- **Distribution:** signed and notarized `.dmg`, direct download

## Current State

| | |
|---|---|
| **Now** | v1.0 — the first full release. The headless engine (Conduit, Field, Listing, Plan Engine, Transports) at ~97% coverage, and the whole surface on it: dual panes, plan → enact, cross-host transfers, the field view, the ZFS workbench (datasets, snapshots, mount), the interactive shell, the preview pane, drag-and-drop, dark mode, one-key zoom. Signed, notarized, with a launch update check. |
| **Next** | Snapshot-history — browse a file's past like a directory, restore with a copy. The homelab's time machine. |
| **Later** | An operations queue; more Workbench tools as the practice demands. |

## What's Ahead

Items the architecture is prepared for but v1 does not include:

**An operations queue.** v1 enacts one plan at a time, synchronously. Plans are values — a queue is a list of them, and it is the first post-release enhancement.

**Forteller and Mujō plugins.** Config deployment and backup-state tooling, each arriving on the Workbench API when it exists and as the practice demands.

**A services plugin.** Extends the field view's vocabulary from machines and datasets to the services running on them.

**A silent in-app installer.** v1.0 checks for a newer release on launch and points you to it; a silent in-app updater (Sparkle) is a later option if the cadence wants it.

## Download

**pālana 1.0** — a signed and notarized macOS app, no App Store — is at [palana.sageframe.net](https://palana.sageframe.net). Drag it to Applications and open it; it runs on macOS 14 or later. Prefer to build it yourself? The source is here, GPL-3.0 — see [Development](#development).

## Requirements

- **macOS 14 or later**
- **Your existing SSH setup.** pālana runs your `ssh` and expects `rsync` on the hosts — both where they already are. Nothing to install, nothing to configure beyond the `~/.ssh/config` you already have.
- **For ZFS awareness:** `zfs` on the hosts, not on the Mac. `zfs send/receive` wants delegated permissions (`zfs allow`) on the datasets involved.

## Development

```sh
git clone https://github.com/sageframe-no-kaji/palana.git
cd palana
swift build
```

`swift test --enable-code-coverage` runs the suite. Format, lint, and build run pre-commit. The coverage floor is enforced in CI. Integration tests run against a local sshd container and a file-backed throwaway ZFS pool — never against live hosts.

pālana is also an experiment in method: the full Kamae chain — seed, system design, this README, and the build that follows — is authored and executed by the agent under the practitioner's discipline, with the practitioner's hands reserved for the UI sessions. The record of whether that held is in `ho-process/`, in public.

## License

pālana is open source under [GPL-3.0](LICENSE). Clone it, build it, run it, change it — the license protects the work and keeps it free.

---

*pālana is a [Sageframe](https://atmarcus.net) project by [Andrew Marcus](https://atmarcus.net), built with the [Ho System](https://github.com/sageframe-no-kaji/ho-system). Last meaningful update: 2026-07-09.*
