---
created: 2026-07-03
status: complete
type: seed
stage: kamae-1
project: palana
builds-on:
  - pre-seed-1-palana-original-seed.md
  - pre-seed-2-palana-design-language.md
next: kamae-2-palana-system-design.md
---

# Project Seed: pālana

_Kṣetra-Ops — Operational Workbench_
_Seed created: July 3, 2026. Supersedes the March 22, 2026 seed, demoted to `pre-seed-1-palana-original-seed.md`. Design language from `pre-seed-2-palana-design-language.md`._

---

## 1. The Problem

There is no place to sit down and tend a homelab.

There are dashboards to watch it — Grafana, Portainer, Cockpit, Proxmox's own web UI. There are terminals to operate on it — one SSH session per machine, each a separate context, the operator's memory holding the whole picture together. There are file managers that pretend to work across networks. There is no single surface where an operator can see the field, understand its state, and work on it.

Not monitoring. Not automation. A place to work. That is the problem.

The specific pain points, unchanged since March because nothing has fixed them:

**No file manager does server-side operations.** Every existing tool — ForkLift, Finder, Transmit, Cyberduck, every SFTP client — routes file operations through the operator's machine. Drag a file from server A to server B and the bytes travel A → laptop → B. The interface presents a direct operation while executing an indirect one. For a 100GB camera dataset moving between ZFS pools, that indirection is catastrophic — slow, fragile, and baffling when it fails, because the operator didn't know their machine was in the middle. The interface lied.

**ZFS cross-dataset moves are invisible landmines.** In a homelab where every service has its own dataset (`rpool/sage/machine/service`), moving files between datasets is not a rename — it is a cross-dataset copy plus delete. Every file manager treats it as a rename and either fails silently or produces corrupt results. The operator discovers this after the fact. The quote from the working session that started this project: _"Moving between datasets — that's what fucking kills me!"_

**The field has no map.** Eleven machines, dozens of services, multiple ZFS pools, replication schedules, a config vault — and no single view of what exists where. Sanoid runs on three machines and checking it means three SSH sessions. The coverage matrix — which datasets are backed up by which systems — is a manually-maintained table that goes stale the day it's written.

**Dashboards watch. Nobody works.** Grafana shows the disk filling. Then you open a terminal, SSH in, and do the work somewhere the dashboard can't see. The watching surface and the working surface are completely disconnected. The dashboards are security cameras. The garden needs a gardener with tools.

## 2. The Landscape

**ForkLift / Transmit / Cyberduck.** Mac file managers with network protocols. All operations route through the client. Host-to-host transfer is impossible. No ZFS awareness, no plan-before-execute, and the interaction is a little ratchet — the seams show. Designed for uploading files to a web server, not for tending a distributed homelab.

**yazi / ranger / Midnight Commander.** Terminal file managers. yazi in particular gets the feel right — keyboard-first, fluid, fast. But they are single-machine tools. You can run yazi on koan and manage koan's files. You cannot see jodo at the same time, and you cannot move a file between them. The keyboard grammar is right — the scope is wrong.

**Finder.** No dual pane. That absence is brutal, and it is twenty years old.

**Portainer / Cockpit / Proxmox UI.** Organ-specific diagnostic tools. Each sees its own domain — containers, OS, VMs — and none sees the ZFS topology as a first-class object or the homelab as a single organism.

**Grafana and the monitoring stacks.** For watching, not working. You cannot act from a graph.

**What's actually missing:** a tool that operates server-side and never relays bytes through the client, understands ZFS datasets as first-class objects, shows the full field as a single navigable space, plans operations before executing them, and feels like a well-made Mac app rather than a terminal cosplay or a web dashboard. Nobody has built it. The ZFS-aware part, nobody has even tried.

## 3. The Vision

pālana is the place where you sit down and tend your infrastructure. You open it and see two panes — left pane pointed at one host, right pane at another. You summon the field view, pick a dataset on jodo, and the pane goes there. You select 40GB of camera archives and press the key for move. pālana does not move anything. It shows you a plan: these files, this size, source dataset and destination dataset named, cross-dataset copy-plus-delete declared as what it is, transport chosen — rsync host-to-host, or `zfs send` if both ends are datasets. The plan's data sits in a quiet monospace block, because that is where the truth lives. You read it. You press Enter. The bytes travel jodo → koan directly, and your laptop orchestrates without ever touching them.

You close pālana. It stops. Nothing watches while you're away, nothing mutates behind your back. The field has been tended, and you know what you did because you did it deliberately — the tool showed you what it would do before it did it.

**The organizing principle.** The ZFS topology — `pool/machine/service` — is the data model. It already encodes the organism: which host, which function, where the data lives. pālana renders this topology as a navigable, workable space. Everything else hangs off it.

**The feel.** Calm, spare, two or three colors — the register of Typora, not the register of a cockpit. Keyboard-first with the fluidity of yazi. Monospace appears exactly once: in the plan panel, where operation truth is displayed. A consumer app in its manners, an operator's tool in its engine. The calm is the point — the calm is what tending feels like when the tool isn't fighting you.

**Dry-run is not a mode. It is the default.** Every operation produces a plan first. Execution is the deliberate second step. This is bīja rendered as interaction design: no hidden causality, no action without presence.

## 4. Audience

**Primary: me.** Eleven machines, dozens of services, multiple ZFS pools, replication across hosts. The alternative is a dozen terminal tabs and my memory.

**Secondary: ZFS homelab operators on Macs** — people with 5 to 20 machines who have hit the cross-dataset move problem, who know their file manager lies about network operations, and who want one surface for the work. The ZFS requirement narrows this audience. The people inside it are passionate and unserved.

**Tertiary: Mac-based homelab operators generally** who want something better than SSH tabs and Portainer for working on their infrastructure as a whole. The server-side and plan-first principles apply to any filesystem — ZFS awareness is the sharpest edge, not the entry requirement.

The March seed reached for Linux workstations too. This seed doesn't. Native Mac is a commitment (§7), and the cost — no Linux client — is accepted, named, and revisitable only if the secondary audience demands it louder than the primary audience demands quality.

## 5. Identity

**pālana** (पालन) — Sanskrit: to tend, nurture, sustain, steward. Not creation but ongoing care. If bīja plants seeds, pālana tends the garden.

Not a management tool — management implies control. Not a monitoring tool — monitoring implies watching. A tending tool. You open it the way you walk through a garden: not because something is broken, but because tending is how things stay healthy.

Part of Kṣetra-Ops. Governed by bīja: no hidden causality, no automation without presence.

## 6. Project Nature and Intent

**Open source**, published under `sageframe-no-kaji`.

**Production application.** Not a prototype, not a learning exercise. A real desktop application that solves a daily problem for a real operator — and the first Kṣetra-Ops tool to ship. The March seed called pālana the second proof, behind Forteller. Forteller remains two commits — a seed and a README. pālana goes first, and its architecture leaves a socket Forteller plugs into later.

**Designed for plugins.** The core is the file manager and the field view. Tools arrive as the practice demands them — ZFS management first (it proves the plugin API at first release), then Mujō (backup and resilience state), Forteller (config deployment, when it exists), services, git/vault state.

**A demonstration of the broader work.** The build itself is an experiment: the full Kamae chain — this seed included — authored and executed autonomously by the agent, under the practitioner's discipline, with the practitioner interrupted only to put his hands on the UI. Whether that works is one of the things this project exists to find out. The build record is public — `ho-process/` is tracked, the way Sharibako's is.

## 7. Architecture Direction

_Opinions, not commitments. Kamae 2 commits._

**Swift, end to end.** SwiftPM multi-product package on the Sharibako layout: `PalanaCore` — a headless library owning topology, SSH orchestration, ZFS introspection, the plan engine, and the transports — and `Palana`, a SwiftUI app that is a thin surface over it. The 90% coverage floor lives in the core, where the truth lives. Swift 6, strict concurrency. Structured concurrency (actors, task groups) carries the many-simultaneous-SSH-sessions load the March seed thought needed tokio.

**Orchestrate the system binaries. Do not reimplement them.** pālana runs the same `ssh`, `rsync`, and `zfs` commands the operator runs by hand — it does not embed an SSH library. This is a philosophical choice wearing an engineering costume: the operator's `~/.ssh/config`, keys, agent, ProxyJump, and ControlMaster behavior apply exactly as they do in the terminal, and every operation pālana plans is a command the operator could read, understand, and run themselves. No parallel transport stack. No hidden causality in the plumbing. ControlMaster multiplexing keeps per-command SSH overhead near zero after first connection.

**Trust is `~/.ssh/config`.** If you can SSH to it, pālana can see it. No trust ceremony of its own, no key distribution, no parallel identity. The March seed borrowed Forteller's trust model — this seed borrows the operator's, which already exists and already works.

**Server-side transport, two mechanisms, tried in order.** Primary: SSH agent forwarding — pālana tells host A to rsync to host B, A authenticates to B with the forwarded agent, the key never leaves the operator's machine. Fallback: proxy through the operator's machine via the SSH connection layer — slower, zero inter-host trust required. pālana tries the fast path and degrades gracefully. The operator doesn't choose. The plan names which path it will use.

**ZFS-native transport.** When source and destination are both ZFS datasets on ZFS-capable hosts, the plan offers `zfs send | ssh | zfs receive` — block-level, an order of magnitude faster for large moves. The 100GB dataset that motivated this project moves in minutes instead of hours. No GUI file manager does this. Still.

**The plan engine is the core abstraction.** Every operation — copy, move, delete — compiles to a plan: the files, the sizes, the classification (within-dataset rename, cross-dataset copy-plus-delete, cross-host transfer), the transport, the exact commands. The plan renders in the panel, monospace, before anything runs. Enter enacts. Esc dismisses. The plan engine is pure logic over gathered facts, which makes it the most testable object in the system — and it had better be, because it is the part that must never lie.

**Dual-pane, keyboard-first.** Two panes, each pointed at a host and path. Keyboard grammar descends from yazi and Mac conventions — not the F-key row, which the March seed asserted and nobody's hands confirmed. Smooth is a requirement: a keystroke that stutters is a defect.

**The field view is a summonable overlay.** One keystroke brings the topology — machines, datasets, services — as an overlay. Pick a node, a pane points there, the overlay vanishes. Discovery happens on demand over SSH, minimal at startup — reachability only. bīja says no hidden observation.

**Plugin architecture from day one.** Plugins get the SSH connection layer, the topology, and a surface in the workbench. The ZFS tool (dataset CRUD, snapshots, pool visualization) ships first and proves the API. Forteller, Mujō, services, and git/vault state follow as the practice demands.

**No daemon. No background process.** pālana runs when you open it and stops when you close it.

## 8. Constraints

**Skills.** Not a developer — a systems architect who builds with AI under the Ho System. Swift is younger territory than Python but no longer new: Sharibako shipped on the exact Core + App layout with the signing pipeline this project reuses. SwiftUI keyboard handling and table performance at scale are the unproven parts, and they get proven or disproven in the first spike.

**The autonomous build.** The agent authors and executes the chain. Hard limit, no exceptions: no mutating operations against live homelab hosts during development. The engine is developed and verified against localhost SSH and container fixtures, and ZFS behavior against dedicated test datasets that hold nothing anyone loves. The practitioner's machines become targets only when the practitioner is driving.

**Time.** Weeks, not days. The core file manager is the first deliverable. Plugins arrive incrementally.

**Pure SSH.** No SMB, no NFS, no SFTP abstractions, no cloud protocols. Philosophical constraint, not technical. This is a tool for tending your own machines, not for connecting to arbitrary ones.

## 9. Scope Boundaries

**pālana IS:**

- A native macOS desktop application for tending infrastructure
- A dual-pane, keyboard-first file manager whose operations run server-side
- ZFS-aware: cross-dataset moves named as what they are, `zfs send/receive` offered when possible
- Plan-first: dry-run is the default, enact is the deliberate second step
- A field view of the full topology, summoned on demand
- A plugin workbench, with the ZFS tool proving the API at first release
- Calm: Typora's register, yazi's fluidity, monospace only where data truth lives
- Governed by bīja: no hidden causality, no automation without presence

**pālana is NOT:**

- A dashboard, a monitoring tool, or anything with alerts and graphs
- A daemon — it runs when opened, stops when closed
- A sync tool — no background replication, no continuous mutation
- A Docker manager — pālana sees services, not containers
- A cross-platform application — native Mac, no Linux client, no web version
- An SMB/NFS/SFTP tool — SSH is the only transport
- Dependent on Forteller — that integration arrives as a plugin when Forteller exists

**First release:**

- Dual-pane file manager, server-side host-to-host operations
- Agent forwarding with proxy fallback, chosen automatically, named in the plan
- ZFS dataset awareness — within-dataset vs cross-dataset visible, `zfs send/receive` offered
- Plan → enact workflow with the monospace plan panel
- Field view overlay: machines and their top-level structure
- Keyboard-first, yazi-descended grammar
- Plugin API defined, ZFS tool built on it
- Signed, notarized, distributed direct — the Sharibako pattern

**Later, as the practice demands:** Mujō, Forteller, services, git/vault state, operations queue with background execution, search, batch tools.

## 10. Success Criteria

1. **Server-side move between hosts.** File on host A, moved to host B, bytes travel A → B. The operator's machine never relays.

2. **ZFS cross-dataset moves are visible.** Before executing, the plan says: cross-dataset copy-plus-delete, not a rename. Source dataset, destination dataset, size. The operator sees what they're doing.

3. **Plan before enact.** No operation executes without first showing what will happen. The plan's commands are real — an operator could copy them into a terminal and get the same result.

4. **The field is legible.** One keystroke shows eleven machines, their datasets, their state. The whole topology navigable without opening a terminal.

5. **The plugin API works.** The ZFS tool is built on the same interface any future plugin would use, without modifying core. The second plugin follows the pattern the first one proved.

6. **It feels calm.** Typora's quiet, yazi's speed. No stutter, no clutter, no lie in the interface. A person who has never seen a terminal could watch the operator work and find it unremarkable — until they learn what the Enter key just did between two machines in another room.

7. **The autonomous chain held.** The seed, system design, README, overview, and hos were authored and executed by the agent, and the practitioner — reviewing the record afterward — would seal the decisions made in his name.

8. **I stop opening terminal tabs.** The actual test: do I reach for pālana instead of SSH when I need to tend the field? If yes, the tool has earned its place.

## 11. Where I'm Starting From

**Strong territory:** the Ho System, which carries the learning. The problem space — I am the user, and the operations pālana plans (rsync, scp, `zfs send/receive`) are ones I run by hand today. Shipped desktop applications: m4Bookmaker in Python/PyQt, Sharibako in Swift on the exact package layout this project uses. The signing and notarization pipeline exists and has shipped a real app.

**Familiar but not deep:** SwiftUI at file-manager complexity — tables with thousands of rows, focus management, keyboard grammar. Plugin architecture design.

**New territory:** orchestrating concurrent SSH sessions from Swift structured concurrency. ZFS introspection over SSH as a data model. Parsing progress from `rsync` and `zfs send` streams over SSH in real time. A GUI whose core interaction is a plan compiled from remote state.

## 12. What I Want to Learn

Whether a single application can be the operational surface for an entire homelab — whether the workbench metaphor holds when the machines are real and the operations have consequences. Whether tending infrastructure through a GUI governed by bīja feels different from tending it through terminals. Whether it feels better.

And this time, one more: whether the methodology itself can be handed to the agent whole — the chain authored, the discipline kept, the discernment matched — with the practitioner present only where presence is irreplaceable. The tool is the first deliverable. The answer is the second.

## 13. Open Questions

**SwiftUI feasibility spike.** SSH to a host, list a directory of a few thousand entries, render it in a keyboard-navigable pane with no perceptible lag. This is the go/no-go for the UI layer — the engine has no such doubt. Build it before anything else. If SwiftUI's tables can't carry it, AppKit's `NSTableView` under a SwiftUI shell is the fallback, and the spike decides.

**ZFS test fixtures.** macOS has no ZFS. The engine's ZFS logic needs real `zfs` behavior to verify against. Provisional: recorded command transcripts for unit tests, a Linux VM or container with a throwaway pool for integration. The fixture strategy is a Kamae 2 decision — it shapes the testing architecture.

**Progress reporting.** rsync and `zfs send` report progress in different formats, over SSH, host-to-host — where the orchestrator isn't in the byte path. How does the operator see a live progress bar for bytes that never pass through their machine? Parsing remote stderr streams is the likely answer. Unproven.

**`zfs send/receive` permissions.** Delegated permissions via `zfs allow` exist but aren't universally configured. Provisional: require delegation on relevant datasets, document in setup.

**Agent forwarding security.** A compromised host could use the forwarded agent. Acceptable for a trusted homelab — documented honestly, with the proxy fallback as the conservative option.

**Operations queue.** Synchronous execution first, or a queue from day one? Provisional: the plan engine designs for a queue, the first release executes synchronously, the queue is the first post-release enhancement.

**The overlay's contents.** Machines and datasets, certainly. Services — at first release or later? Provisional: reachability and datasets at first release, services when the services plugin exists. The overlay should not promise more than the field can answer.

---

## The Soul and the Body

**Soul:** A place to sit down and tend your infrastructure — where the work of care becomes a practice with tools, presence, and memory.

**Body:** A native macOS application in Swift — a calm, keyboard-first, dual-pane file manager that plans every operation before enacting it, runs moves and copies server-side over SSH, speaks ZFS natively, and holds a plugin workbench that grows with the practice.
