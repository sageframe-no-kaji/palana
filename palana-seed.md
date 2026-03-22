# Project Seed: pālana

_Kṣetra-Ops Suite — Operational Workbench_
_Seed created: March 22, 2026_

---

## 1. The Problem

There is no place to sit down and tend a homelab.

There are dashboards to watch it — Grafana, Portainer, Cockpit, Proxmox's own web UI. There are terminals to operate on it — SSH sessions, one per machine, each a separate context. There are file managers that pretend to work across networks — ForkLift, Transmit, Finder, every SFTP client. And there is Forteller, now, for config deployment.

But there is no single surface where an operator can see the field, understand its state, and work on it. The closest thing is a collection of terminal tabs, each SSHed into a different machine, and the operator's memory holding the whole picture together.

This is the problem pālana solves. Not monitoring. Not automation. A place to work.

The specific pain points:

**No file manager does server-side operations.** Every existing tool — ForkLift, Finder, Transmit, Cyberduck, every SFTP client — routes file operations through the operator's machine. Drag a file from server A to server B and the bytes travel: A → your laptop → B. The interface presents a direct operation while executing an indirect one. For small files this is invisible. For a 100GB camera dataset being moved between ZFS pools, it's catastrophic — slow, fragile, and the failure mode is baffling because the operator didn't know their machine was in the middle.

**ZFS cross-dataset moves are invisible landmines.** In a ZFS homelab where every service has its own dataset (`rpool/sage/machine/service`), moving files between datasets is not a rename — it's a cross-dataset copy plus delete. Every file manager treats it as a rename and either fails silently or produces corrupt results. The operator discovers this after the fact. The actual quote from the working session that motivated this project: _"Moving between datasets — that's what fucking kills me!"_

**The field has no map.** An operator with eleven machines, dozens of services, multiple ZFS pools, backup replication schedules, and a config vault has no single view of what exists where. The topology lives in their head, supplemented by markdown files they update manually. Sanoid is running on three machines but the operator has to SSH into each one to check. Syncoid replication is pushing to koan but the operator has to read timer logs to know if it's current. The coverage matrix — which datasets are backed up by which systems — is a manually-maintained table that goes stale the day it's written.

**Dashboards watch. Nobody works.** Grafana shows metrics. Portainer shows containers. Cockpit shows system state. None of them let you _do_ anything that matters at the infrastructure level. You can restart a container in Portainer but you can't move a ZFS dataset. You can see disk usage in Cockpit but you can't manage the dataset topology. The dashboards are security cameras. The garden needs a gardener with tools.

---

## 2. The Landscape

### ForkLift / Transmit / Cyberduck

Dual-pane (ForkLift) or single-pane file managers for Mac. SFTP, SCP, various protocols. Good UI. Real products used by real people.

**Where they fall short:** All operations route through the client. Host-to-host transfers are impossible — you can connect to two servers but you can't move a file between them without it passing through your laptop. No ZFS awareness. No concept of planned operations or dry-run. No memory of what was done. They were designed for uploading files to a web server, not for tending a distributed homelab.

### Midnight Commander / ranger / lf

Terminal-based dual-pane file managers. Fast, keyboard-driven, powerful for local operations.

**Where they fall short:** Single-machine tools. They work beautifully on the machine you're SSHed into. They don't see the field. You can run MC on koan and manage koan's files, but you can't see jodo at the same time. The dual-pane model is right — left pane source, right pane destination — but the scope is wrong.

### Portainer / Cockpit / Proxmox UI

Web-based management interfaces for specific domains. Portainer for Docker. Cockpit for Linux system administration. Proxmox for virtualization.

**Where they fall short:** Each one sees its own domain. Portainer sees containers but not systemd services. Cockpit sees the OS but not Docker. Proxmox sees VMs and LXCs but not what's running inside them. None of them see the ZFS dataset topology as a first-class object. None of them understand the homelab as a single organism. They're organ-specific diagnostic tools, not a workbench for the whole body.

### Grafana / Prometheus / monitoring stacks

Metrics, dashboards, alerting. The industry standard for observability.

**Where they fall short:** Dashboards are for watching, not working. You cannot act from Grafana. You see a graph that shows a disk filling up. You then open a terminal, SSH into the machine, and do the work. The dashboard and the work surface are completely disconnected. pālana's thesis is that visibility should be a byproduct of working, not a separate activity.

### Webmin / NFS-based tools / Synology DSM

Various attempts at unified management interfaces.

**Where they fall short:** Webmin is a web UI for one machine at a time. NFS-based tools are filesystem-specific. Synology DSM is vendor-locked. None of them understand a heterogeneous homelab as a single field.

### What's actually missing

A tool that:

- Operates server-side, never routing bytes through the client
- Understands ZFS datasets as first-class objects (not just filesystems)
- Shows the full field — all machines, all services, all datasets — as a single navigable space
- Lets the operator work, not just watch
- Plans operations before executing them (dry-run first, always)
- Integrates Forteller for config deployment from the same surface
- Is governed by bīja: no hidden causality, no automation without presence
- Is a workbench, not a dashboard

---

## 3. The Vision

pālana is the place where you sit down and tend your infrastructure. The shed where the tools are kept and the work gets done.

You open pālana. You see the field — your machines, your datasets, your services, their state. You navigate to a host. You see its files, its running services, its ZFS datasets, its replication status. You select a file and move it to another host — the operation happens server-side, between the hosts directly, and you saw the plan before it executed. You open the Forteller tool and see which configs have drifted. You deploy a fix. You open the Mujō tool and see which datasets aren't replicated. You check why.

You close pālana. The field has been tended. You know what you did because you did it deliberately, and the tool showed you what it would do before it did it.

### The organizing principle

The ZFS topology — `pool/machine/service` — is the data model. It already encodes the organism: which host, which function, where the data lives. pālana renders this topology as a navigable, workable space. Everything else hangs off it.

### Core: File operations

Dual-pane, keyboard-first. Left pane: source host or dataset. Right pane: destination. Operations happen between hosts directly via SSH — the operator's machine orchestrates but never relays bytes. Every operation is planned: you see what will happen (files to copy, files to overwrite, files to delete) and then you enact it. Dry-run is not a mode — it is the default. Execution is the deliberate second step.

ZFS-first: pālana understands that a move between datasets is fundamentally different from a move within a dataset, and makes this visible. A within-dataset move is instant (rename). A cross-dataset move is a copy-plus-delete across pool boundaries. pālana shows you which one you're doing before you do it.

Not ZFS-only. The server-side, planned, visible principles apply to any filesystem on any host.

### Tools in the shed

pālana is a workbench with a plugin architecture. Each tool is a view into a different aspect of the same field. All tools obey bīja — no tool acts without the operator's knowledge and presence.

**Forteller** — Config deployment. Invokes Forteller CLI as an external process. Shows vault state: what seeds exist, where they're planted, drift detection, deploy/beam/summon from within the workbench. Every `fortell` command is available as a pālana operation.

**Mujō** — Backup and resilience. Sanoid snapshot schedules and status. Syncoid replication state. Hōzō device reachability. Borg identity backup coverage. The coverage matrix rendered live. You see a gap, you act on it from the same surface.

**ZFS** — Dataset management. The topology as a first-class object. Create, destroy, rename datasets. Visualize pool hierarchy and usage. Manage snapshots. The infrastructure legible at the storage layer.

**Services** — Everything running in the field. Not just Docker containers — systemd units, timers, Caddy, Sanoid, everything. The things dashboards miss because they only see containers.

**Git/Vault** — The state of the config repo. What's committed, what's dirty, what's been pushed. The vault is the mind of the system — this tool makes the mind's state visible.

**Future tools** arrive as the practice demands them. The architecture assumes plugins. The core is the file manager and the field view. Everything else is a tool in the shed.

---

## 4. Audience

**Primary: Me.** Eleven machines. Dozens of services. Multiple ZFS pools. Backup replication across hosts. A config vault managed by Forteller. I need this tool because the alternative is a dozen terminal tabs and my memory.

**Secondary: ZFS homelab operators** with 5–20 machines who have hit the cross-dataset move problem, who are frustrated by file managers that lie about network operations, and who want a single surface for tending their infrastructure. This is a smaller audience than Forteller's — the ZFS requirement narrows it — but the people who need it are passionate and vocal.

**Tertiary: Homelab operators generally** who want something better than SSH tabs and Portainer for understanding and working on their infrastructure as a whole.

---

## 5. Identity

**pālana** (पालन) — Sanskrit for "to tend, nurture, sustain, steward." Not creation but ongoing care — the mindful act of maintaining what already exists. If bīja plants seeds, pālana tends the garden.

The name captures the core identity: this is not a management tool (implies control), not a monitoring tool (implies watching), not an administration tool (implies bureaucracy). It is a tending tool. You open it to care for your infrastructure the way you'd walk through a garden — not because something is broken but because the practice of tending is how things stay healthy.

Part of the Kṣetra-Ops suite. Governed by bīja. The workbench that holds the tools.

---

## 6. Project Nature and Intent

**Open source.** Published on GitHub under `sageframe-no-kaji`.

**Production application.** This is not a prototype or a learning exercise. It is a real desktop application that solves a real daily problem.

**Designed for plugins.** The architecture assumes that tools will be added over time. The core (file operations + field view) ships first. Forteller integration ships next. Everything else arrives when the practice demands it.

**The second proof of Kṣetra-Ops.** Forteller proves the philosophy at the CLI layer. pālana proves it at the GUI layer — and proves that bīja-governed tools can be composed into a coherent operational surface.

**A demonstration of the broader work.** Like Forteller, pālana is a tangible expression of Kṣetra-Ops, bīja, the Ho System, and the practice. It's also the most ambitious piece of software in the suite and will be the most visible.

---

## 7. Architecture Direction

_Opinions, not commitments._

**Language and framework:** Tauri + Rust backend + Svelte frontend. This is the ambitious choice and the right one.

pālana's core requirements — multiple simultaneous SSH connections, streaming file operations, async ZFS commands, responsive UI during heavy I/O — are exactly what Rust is built for. Rust's async runtime (tokio) handles dozens of concurrent SSH sessions without blocking. The GIL problem that would plague a Python implementation doesn't exist. The SSH story is strong: `russh` (pure Rust) or `openssh` crate (wraps the system SSH binary, meaning Forteller's trust model and agent forwarding work identically).

Tauri uses the OS's native webview (WebKit on Mac, WebKitGTK on Linux, WebView2/Edge on Windows) — not a bundled Chromium like Electron. The result: 5–10MB instead of 200MB, startup in milliseconds, memory usage closer to native. Cross-platform from day one: Mac primary, Linux secondary, Windows if anyone asks.

Svelte for the frontend — compiles to minimal vanilla JS, no virtual DOM overhead, reactive by default. The dual-pane file manager, F-key shortcuts, keyboard navigation, plan/enact workflow — all implementable in Svelte with Tailwind for styling. Tools like Warp (the terminal) prove that Rust + web UI can feel indistinguishable from native.

**Why not the alternatives:**

_PyQt/Python:_ Proven territory (m4Bookmaker shipped with it), but Python's GIL makes true concurrency painful. pālana needs dozens of async SSH connections while the UI stays fluid. Possible with QThreads but swimming upstream.

_Swift/SwiftUI:_ Best possible Mac experience, but Mac-only. No path to Linux. pālana's operator runs Linux on every server — testing from a Linux workstation should be natural.

_Go/Wails:_ Simpler than Rust, excellent concurrency (goroutines), but Wails is less mature than Tauri with a smaller ecosystem. The pragmatic fallback if Rust proves too steep.

_Electron:_ No.

**The learning cost is real.** Rust is new territory. Svelte is new territory. Tauri is new territory. The Ho System is designed for exactly this: structured learning through building a real thing. Rust's compiler is the best teacher in programming — it refuses to let you write bad concurrent code, which is exactly what pālana needs. The early prototype test is simple: SSH to a host, list a directory, render it in a Tauri window. If that works, everything else follows. If it doesn't, Go/Wails is the fallback with minimal lost time.

Forteller remains Python. pālana invokes it as a subprocess — `fortell deploy`, `fortell status`, etc. The language difference is invisible. The CLI is the API.

**Pure SSH. Pure ZFS.** This is not a tool for connecting to arbitrary machines. It is a tool for tending your own. SSH is the only transport. ZFS is the storage model. No SMB, no SFTP abstractions, no cloud protocols, no NFS. If the machine has SSH and you've trusted it with Forteller, pālana can see it and work on it. That is the boundary.

**SSH transport and inter-host trust.** pālana orchestrates operations between hosts. When the operator moves a file from host A to host B, the bytes must not pass through the operator's machine. Two mechanisms, tried in order:

_Primary: SSH agent forwarding._ pālana connects to host A with agent forwarding enabled. The Forteller key is in the operator's SSH agent. When pālana tells host A to rsync to host B, host A authenticates to B using the forwarded agent. The key never leaves the operator's machine. This is the fast path — standard multi-hop SSH, no key distribution between hosts.

_Fallback: Proxy through the operator's machine._ pālana opens SSH connections to both A and B and tunnels the data through itself via ProxyJump. Basho becomes the control plane. Slightly slower but requires zero inter-host trust — each host only needs to trust the operator's Forteller key, which it already does.

Agent forwarding first. Proxy fallback automatic. The operator doesn't choose — pālana tries the fast path and degrades gracefully.

**ZFS-native transport.** For moves between ZFS datasets, pālana can offer `zfs send | ssh | zfs receive` instead of file-level rsync. This operates at the block level and is dramatically faster — an order of magnitude for large datasets. The 100GB camera dataset move that motivated the project would take hours via rsync and minutes via zfs send.

pālana detects when both source and destination are ZFS datasets on ZFS-capable hosts and offers the ZFS transport as the preferred option. This is genuinely novel for a GUI file manager. Nobody does this.

**Forteller integration (built in, not a plugin).** Forteller is part of pālana's core, not an optional plugin. Every `fortell` command is available in the UI: deploy, beam, summon, status, ask, trust, hosts, tree. pālana invokes the Forteller CLI as a subprocess — same commands, same behavior, GUI surface. The vault view (Forteller's tree of seeded files, drift status, pragma inspection) is a persistent panel.

**Plugin architecture (designed from day one).** The UI and internal API assume plugins from the start. Every plugin gets: access to the SSH connection pool, the current host context, the field topology, and a panel/tab in the workbench. Plugins do not modify the core. The plugin interface is defined before the first plugin is built, because the Forteller integration — even though it ships in core — should follow the same interface pattern. If Forteller integration works through the plugin API, the API is proven.

Planned plugins: Mujō (backup/resilience), ZFS management (dataset CRUD, snapshots), Services (full-field service visibility), Git/vault state. Each arrives when the practice demands it.

**The field view.** A navigable representation of the full topology. Machines as top-level nodes. Under each: datasets, services, files. The Forteller vault provides config file topology. For live state (running services, ZFS datasets, replication status), pālana queries hosts over SSH at startup and on demand. Not continuously — when the operator asks, because bīja says no hidden observation.

**Dual-pane file manager.** Left/right panes, each connected to a host. Keyboard-first with F-key muscle memory (F5 Copy, F6 Move, F7 New folder, F8 Delete, F3 Preview). Drag-and-drop generates a _plan_, not an action. The plan shows what will happen — files to copy, overwrite, delete, and whether the operation is within-dataset (instant) or cross-dataset (copy+delete). An explicit "Enact" step executes.

**Operations queue.** Long operations run in the background with progress, speed, ETA. The operator continues working while a large transfer runs.

**No daemon. No background process.** pālana runs when you open it. It does not watch, correct, or mutate state while you're away. When you close it, it stops.

---

## 8. Constraints

**Skills:** Not a developer. Build production software using the Ho System. Shipped m4Bookmaker (Python/PyQt), Kanyō (Python), Hōzō (Python). Rust, Svelte, and Tauri are all new territory. The Ho System and AI collaboration are the methodology for navigating this. The early prototype — SSH to a host, list a directory, render in a Tauri window — is the feasibility test before committing.

**Time:** Larger project than Forteller. Weeks to months. Core file manager is the first deliverable. Plugins arrive incrementally.

**Dependency: Forteller first.** Forteller should be built and working before pālana development begins. pālana depends on Forteller for config operations, and the Forteller build surfaces SSH patterns and trust model decisions that pālana reuses.

**Inter-host trust topology.** Agent forwarding is the primary mechanism. The operator decides which paths exist. pālana tries the connection and reports if it fails.

**Pure SSH.** No SMB, NFS, SFTP, or cloud protocols. Philosophical constraint, not technical.

**Rust learning curve.** The biggest constraint. Rust's ownership model and borrow checker are genuinely difficult for newcomers. The mitigation is that pālana's Rust code is primarily async SSH orchestration and ZFS command invocation — not algorithmic complexity. The frontend (Svelte) handles the UI complexity separately. If Rust proves too steep, Go + Wails is the fallback with the same architecture at lower performance.

---

## 9. Scope Boundaries

**pālana IS:**

- A desktop application for tending infrastructure
- A dual-pane, keyboard-first file manager with server-side operations
- A field view showing the full topology (machines, datasets, services)
- Pure SSH, pure ZFS — your machines, your trust, no abstractions
- ZFS-aware (cross-dataset moves are visible and planned, zfs send/receive when possible)
- Dry-run by default (plan first, enact second)
- Forteller built in (deploy, beam, summon, status, ask — all from the workbench)
- Plugin architecture from day one for everything beyond file operations and Forteller
- Governed by bīja: no hidden causality, no automation without presence

**pālana is NOT:**

- A dashboard (not for watching — for working)
- A monitoring tool (no alerts, no metrics, no graphs)
- A daemon (runs when opened, stops when closed)
- A sync tool (no background replication, no continuous mutation)
- A Docker manager (Docker is connective tissue — pālana sees services, not containers)
- A general-purpose file manager for arbitrary machines (SSH + Forteller trust only)
- A web application (desktop native)
- An SMB/NFS/SFTP tool (SSH is the only transport)

**First release:**

- Dual-pane file manager with server-side host-to-host operations
- SSH agent forwarding for inter-host transport, proxy fallback
- ZFS dataset awareness (cross-dataset vs within-dataset visible, zfs send/receive offered)
- Dry-run / plan / enact workflow
- Field view: machines and their top-level structure
- Keyboard-first with F-key conventions
- Forteller built in (full command vocabulary from the GUI)
- Plugin API defined and proven by the Forteller integration pattern

**Plugins (later, as the practice demands):**

- Mujō (backup and resilience state)
- ZFS management (dataset CRUD, snapshot management)
- Services (full-field service visibility including non-containerized)
- Git/vault state
- Operations queue with background execution
- Search (path, metadata, fulltext via ripgrep)
- Batch tools (multi-select rename, sanitation, dedup)

---

## 10. Success Criteria

1. **Server-side file move between hosts.** Select a file on host A, move to host B, bytes travel A → B directly. The operator's machine never relays.

2. **ZFS cross-dataset move is visible.** Before executing, pālana tells the operator: "This is a cross-dataset copy-plus-delete, not a rename. Source dataset: X. Destination dataset: Y. Estimated size: Z." The operator sees what they're doing.

3. **Plan before enact.** No destructive operation executes without first showing what will happen. Dry-run is the default, not a mode.

4. **The field is legible.** Opening pālana shows me my eleven machines, their datasets, their services, and their state. I can navigate the entire topology without opening a terminal.

5. **Forteller works inside pālana.** Every fortell command — deploy, beam, summon, status, ask — is available within the workbench. Same behavior, GUI surface.

6. **Feels right.** The file manager is responsive. Keyboard navigation is fast. The UI doesn't lie about what operations mean. It feels like a tool built by someone who uses it, not a demo.

7. **Plugin architecture works.** Adding the Forteller plugin doesn't require modifying the core. The interface between core and plugin is clean enough that the second plugin (Mujō or ZFS) can be built by following the same pattern.

8. **I stop opening terminal tabs.** The actual test: do I reach for pālana instead of SSH when I need to tend the field? If yes, the tool has earned its place.

---

## 11. Where I'm Starting From

**Strong territory:**

- Ho System methodology — will carry the learning
- Know the problem space intimately — I am the user
- Forteller will be built first, providing SSH patterns and trust model
- The file operations (rsync, scp, zfs send/receive) are ones I run daily by hand
- Shipped desktop applications (m4Bookmaker) — understand the UX patterns even if the stack changes

**Familiar but not deep:**

- Web frontend development (HTML/CSS/JS fundamentals exist, frameworks are new)
- Plugin architecture design

**New territory:**

- Rust (language, ownership model, async with tokio)
- Tauri (framework, IPC between Rust backend and web frontend)
- Svelte (reactive frontend framework)
- Designing a desktop application that orchestrates operations between multiple remote hosts simultaneously
- ZFS introspection from a remote client over SSH

---

## 12. What I Want to Learn

Whether a single application can be the operational surface for an entire homelab — whether the workbench metaphor holds when the field is real, the machines are real, and the operations have consequences. Whether tending infrastructure through a GUI governed by bīja feels different from tending it through terminals. Whether it feels _better_.

---

## 13. Open Questions

**Rust feasibility prototype.** Can we SSH to a host, list a directory, and render it in a Tauri window with acceptable performance? This is the go/no-go test for the stack. If it fails, Go + Wails is the fallback. Build this before anything else.

**Field view data model.** How does pālana learn the topology? The Forteller vault provides config file locations. For live state (running services, ZFS datasets, replication status), pālana queries hosts over SSH on demand. How much discovery happens at startup vs. per-host? Provisional: minimal at startup (reachability only), full discovery on demand.

**Plugin interface design.** What does a plugin need from the core? Access to the SSH connection pool? The current host context? The file pane state? Define this before the Forteller integration is built — even though Forteller ships in core, it should use the plugin API so the API is proven.

**Hōzō as a plugin.** Hōzō already manages wake-on-demand backup orchestration. As a pālana plugin it would show backup target status (reachable? awake? last backup time?), trigger wake and backup from the workbench, and integrate with the Mujō plugin's resilience view. Hōzō is Python — the plugin wraps its CLI the same way pālana wraps Forteller. This is a natural early plugin after Mujō.

**zfs send/receive permissions.** Typically requires elevated privileges. Delegated ZFS permissions (`zfs allow`) exist but aren't universally configured. Provisional: require delegated send/receive on relevant datasets, document in trust setup.

**Docker visibility line.** Docker is connective tissue. Compose files are visible as Forteller seeds. Running container state appears in the Services plugin. pālana never manages containers directly.

**Agent forwarding security.** Carries risk — a compromised host could use the forwarded agent. Acceptable for a trusted homelab. Documentation should discuss this honestly and offer the proxy fallback as the conservative option.

**Operations queue timing.** Synchronous execution in first release, or proper queue from day one? Provisional: synchronous first, queue as the first enhancement after launch.

**macOS vs cross-platform.** Tauri is cross-platform by nature. Provisional: macOS primary, Linux secondary, Windows if asked.

---

## The Soul and the Body

**Soul:** A place to sit down and tend your infrastructure — where the work of care becomes a practice with tools, presence, and memory.

**Body:** A Tauri desktop application with a Rust backend and Svelte frontend — dual-pane file manager, server-side operations, ZFS awareness, a field view of the full topology, Forteller built in, and a plugin architecture that grows with the practice.

---

## Context Documents

- `Kṣetra-Ops Philosophy Brief` — governing philosophy, expanded pālana vision with tool descriptions
- `palana-server-side-app.md` — original spec and design
- `real-world-context.md` — the actual pain points, especially the ZFS cross-dataset problem and the coverage matrix
- `repo-config-plan.md` — the topology pālana would render
- `1.90.01-sageframe-mujo-method-philosophy.md` — the Mujō Method, which governs the backup/resilience plugin
- `Ksetra-Ops-README.md` — suite philosophy and axioms (Docker as connective tissue, ZFS as physical truth, services as functions)
- `seed-forteller-v2.md` — Forteller seed, particularly the CLI-as-API design, trust model, and command vocabulary
- `*_audit.txt` — the actual machine topology and service inventory that pālana would render
- `sageframe-config tree` — the repo structure that IS the Forteller vault, and one of pālana's field views
