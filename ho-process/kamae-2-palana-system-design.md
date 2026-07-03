---
created: 2026-07-03
status: complete
type: system-design
project: palana
stage: kamae-2
kamae-chain: seed → **system-design** → readme → ho-overview
builds-on: kamae-1-palana-seed
next: kamae-3-palana-readme
---

# pālana — System Design (Kamae 2)

**Tend your field.**

> pālana is a place to sit down and tend your infrastructure. A native Mac app — calm, keyboard-first, dual-pane — that plans every operation before enacting it, runs moves and copies server-side over SSH, and speaks ZFS natively. Select the files, press the key, read the plan, press Enter. The bytes travel host to host and your machine orchestrates without ever carrying them. A plugin workbench grows with the practice — the ZFS tool first, the rest as tending demands. It runs when you open it and stops when you close it. Nothing watches while you're away.

---

## 1. Architecture Overview

Two products in one SwiftPM package, on the Sharibako layout. **PalanaCore** is a headless library — all truth, all logic, the 90% coverage floor lives here. **Palana** is the SwiftUI app — a thin surface with no business logic. If the app disappeared tomorrow, everything pālana knows and everything pālana can do would still be sitting in the core, fully tested.

Seven components, sliced by experience and purpose, not by technical layer. These are not a view layer, a data layer, and a service layer. They are the door to the hosts, the map of the field, the reading of a directory, the plan, the enactment, the workbench, and the surface — the components match how the operator thinks about the work, because the operator is the one who has to reason about it when something needs attention.

```
┌────────────────────────────────────────────────────────────────────┐
│                          Palana — the app                          │
│  ┌────────────────────────────┐    ┌────────────────────────────┐  │
│  │        The Surface         │    │          Plugins           │  │
│  │  dual panes · plan panel   │    │  ZFS tool (ships at v1)    │  │
│  │  field view · keyboard     │    │  Forteller · Mujō · later  │  │
│  └─────────────┬──────────────┘    └─────────────┬──────────────┘  │
└────────────────┼─────────────────────────────────┼─────────────────┘
                 │                                 │
                 │      ═══ The Workbench API ═════╡
                 ▼                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                             PalanaCore                             │
│                                                                    │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐   │
│  │   The Field   │  │  The Listing  │  │    The Plan Engine    │   │
│  │   topology    │  │   directory   │  │  (source, dest, op)   │   │
│  │   and facts   │  │     reads     │  │        → Plan         │   │
│  └───────┬───────┘  └───────┬───────┘  └───────────┬───────────┘   │
│          │                  │                      │ Plan          │
│          │                  │          ┌───────────▼───────────┐   │
│          │                  │          │    The Transports     │   │
│          │                  │          │  rsync · proxy · zfs  │   │
│          │                  │          │     send/receive      │   │
│          │                  │          └───────────┬───────────┘   │
│          ▼                  ▼                      ▼               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                         The Conduit                          │  │
│  │     the single door to hosts — system ssh via Process,       │  │
│  │            one ControlMaster session per host                │  │
│  └───────────────────────────────┬──────────────────────────────┘  │
└──────────────────────────────────┼─────────────────────────────────┘
                                   │ ssh
                 ┌─────────────────┼─────────────────┐
                 ▼                 ▼                 ▼
               jodo              koan             chumon   ...
```

Two lines in the diagram carry most of the architecture. The Workbench API line is the only thing the app and its plugins can see — everything above it is surface, everything below it is truth. The Conduit is the only door to the hosts — every fact discovered, every listing read, every byte moved passes through one component that does nothing but run the operator's own `ssh`. Both lines exist for the same reason: a boundary you can point at is a boundary you can test.

Per component — what it does, what it owns, what it talks to:

- **The Conduit** — SSH execution. Owns the ControlMaster session lifecycle per host and the streams that come back. Talks to the hosts, and is the only component that does.
- **The Field** — topology. Owns the map — hosts from `~/.ssh/config`, per-host facts discovered on demand, last-known state cached as memory. Talks to the Conduit to discover and to everyone else to answer.
- **The Listing** — remote directory reading. Owns the FileEntry model and the parsing that produces it. Talks to the Conduit — one command per directory read.
- **The Plan Engine** — the core abstraction. Owns classification, transport selection, and command composition — a pure function from gathered facts to a Plan an operator could read and run by hand. Talks to the Field for dataset boundaries and to nothing over the wire.
- **The Transports** — enactment. Owns the execution of an approved Plan and the progress events parsed from the remote streams. Talks to the Conduit.
- **The Workbench** — the plugin API. Owns the boundary between core and plugins. Hands a plugin the Conduit, the Field, and a surface slot — core stays closed.
- **The Surface** — the Palana app. Owns the panes, the plan panel, the field view, and the keyboard grammar. Talks to PalanaCore, renders state, forwards intent, decides nothing.

---

## 2. Component Breakdown

Four boundary statements hold the system's shape. Only the Conduit touches `ssh`. Only the Plan Engine classifies operations. The Surface renders state and forwards intent — it never composes shell commands. Plugins see the Workbench API, never PalanaCore internals. Everything below elaborates these four lines.

### The Conduit

**Responsibility.** SSH execution and nothing else. Owns the ControlMaster session lifecycle per host — open on first use, reuse thereafter, close on quit. Runs commands on hosts, captures stdout and stderr as streams, reports exit status. It wraps the system `ssh` binary via Foundation `Process` — it does not embed an SSH library, so the operator's `~/.ssh/config`, keys, agent, and ProxyJump behavior apply exactly as they do in the terminal.

**Interface.** `run(host, command) → (stdout stream, stderr stream, exit status)`, plus session lifecycle — open, reuse, close. That is the whole surface. The error taxonomy lives here too (built in ho-02) — every failure a host can produce surfaces at the Conduit first, typed, before anything above it has to interpret raw process noise.

**Boundaries.** Only the Conduit touches `ssh`. No other component spawns a process toward a host, ever. The Conduit knows nothing about files, datasets, or plans — it moves commands and streams.

**Replaceability.** The Conduit sits behind a protocol. Tests inject a RecordedConduit that plays back captured transcripts. If the system-binary decision ever needed revisiting, this protocol is the seam — nothing above it would know.

### The Field

**Responsibility.** Topology. Hosts are parsed from `~/.ssh/config` — if you can SSH to it, pālana can see it, and there is no trust ceremony of pālana's own. Per-host facts — reachability, ZFS pools and datasets, OS flavor and coreutils capability — are discovered on demand through the Conduit, never continuously. bīja governs here: no hidden observation.

**Interface.** `hosts()` from the SSH config, `discover(host)` for on-demand facts, `facts(host)` for what is currently known, dataset-boundary queries for the Plan Engine.

**Boundaries.** The Field gathers and remembers facts. It classifies nothing and executes nothing. The last-known topology is cached locally as JSON so the field view opens instantly, showing remembered state marked as remembered — the cache is memory of what the operator did. It is not surveillance.

**Replaceability.** The cache is a convenience layer over re-derivable truth. Delete it and the Field rebuilds from the hosts themselves.

### The Listing

**Responsibility.** Remote directory reading. One SSH command per directory read, emitting a parseable listing. GNU coreutils `stat` and `find -printf` are the primary path — the fleet is Linux — with a capability probe per host and a BSD/`ls` fallback for the rest.

**Interface.** `list(host, path) → [FileEntry]`. A FileEntry carries name, size, mtime, kind, permissions, owner, and symlink target.

**Boundaries.** The Listing reads. It never writes, never classifies, never composes operations. One round-trip per directory is the budget — a pane refresh is one command.

**Replaceability.** The listing command format is a contained decision (deferred to ho-04). The FileEntry type is the contract — the command behind it can change without anything above noticing.

### The Plan Engine

**Responsibility.** The core abstraction. A pure function: (source state, destination state, requested operation) → Plan. A Plan carries the entries with their sizes, the classification — within-dataset rename, cross-dataset copy-plus-delete, or cross-host transfer — the chosen transport with its named auth path (agent-forwarded direct or proxied), and the exact shell commands that will run. Commands an operator could paste into a terminal and get the same result.

**Interface.** `plan(source, destination, operation) → Plan`. Facts in, Plan out.

**Boundaries.** Only the Plan Engine classifies operations. It is pure logic over facts the Field and the Listing already gathered — it performs no I/O of its own. That purity makes it the most testable object in the system, and it had better be, because it is the part that must never lie.

**Replaceability.** Not replaceable. This is the identity of the product. Everything else exists to feed it facts or enact its output.

### The Transports

**Responsibility.** Enactment. Executes a Plan: `rsync` host-to-host with agent forwarding as the fast path, proxy through the operator's machine as the fallback, `zfs send | ssh | zfs receive` when both ends are whole datasets. Emits progress events parsed from remote stderr — `rsync --info=progress2`, `zfs send -v`.

**Interface.** `enact(plan) → progress events, completion`. Progress is a stream the Surface renders as a bar.

**Boundaries.** The Transports run exactly the commands the Plan composed — no improvisation between approval and execution. All host contact goes through the Conduit. Verification of counts on completion belongs here.

**Replaceability.** Each transport is a strategy behind the same enactment interface. New transports join without touching the Plan Engine's classification logic.

### The Workbench

**Responsibility.** The plugin API. A plugin gets three things: the Conduit, the Field, and a surface slot in the app. Plugins do not modify core. The ZFS tool — dataset CRUD, snapshots, pool visualization — ships at first release and proves the API. Forteller, Mujō, services, and git/vault state arrive later on the same interface.

**Interface.** Plugin registration, the two core capabilities handed in, one surface slot handed out.

**Boundaries.** Plugins see the Workbench API and never PalanaCore internals. A plugin that needs something the API doesn't offer is a reason to grow the API deliberately, not a reason to open the core.

**Loading.** Plugins are compiled-in Swift targets conforming to the Workbench protocol — the ZFS tool is a target in this package, built into the app. Dynamically loaded bundles would buy third-party plugins at the price of a harder signing story and a public ABI, and v1 has no third-party plugins to buy. The protocol doesn't care where a conforming type comes from — dynamic loading is prepared for, not built.

**Replaceability.** The API is the commitment. Its first consumer ships with v1 precisely so the interface is proven by use, not by speculation.

### The Surface

**Responsibility.** The Palana app. Dual panes, the plan panel, the field view as a summonable overlay, the keyboard grammar. SwiftUI, with AppKit interop only where the spike proves SwiftUI can't carry it. The register is the design language's, which is Sutra's: the good notebook — calm, almost no chrome, one interactive accent, everything background until called. Typora's quiet, yazi's fluidity, two or three colors, no terminal density. A consumer app in its manners over an operator's tool in its engine.

**Interface.** Human-facing. Toward the core: it reads state and forwards intent.

**Boundaries.** The Surface renders state and forwards intent — it never composes shell commands, never classifies an operation, never touches a host. A keystroke that stutters is a defect. Monospace appears exactly once: the plan panel, which is a real terminal surface, not monospace styling. The plan's commands display there before enactment, and when Enter fires, the enactment echoes there live — the real commands, the real output, streaming. The interface's claim that "these are the commands" is checkable by watching them run. An interactive terminal — type into it, per host — is a Workbench tool for later. The v1 commitment is the echo, not the shell.

**Replaceability.** Thin by construction. The 90% coverage floor lives below it because everything that matters lives below it.

---

## 3. Core Interaction

A cross-host move, traced end to end.

1. The operator's left pane sits on jodo at `/tank/sage/jodo/kanyo/archive`. The right pane sits on koan at `/rpool/sage/koan/cold`. 214 files are selected, 41.3GB. The move key goes down.

2. **The Surface** forwards intent to the Plan Engine — source pane state, destination pane state, operation. It composes nothing.

3. **The Plan Engine** asks the Field for dataset boundaries at both paths. Source and destination are different datasets on different hosts. Classification: cross-host transfer. This is not a rename. It is a transfer followed by a delete, and the plan will say so.

4. Both hosts are ZFS-capable, but the selection is a subtree of a dataset, not a whole dataset — `zfs send` is off the table. Transport: rsync host-to-host, agent-forwarded. The Field knows jodo can reach koan — probed once, remembered.

5. **The Plan** renders in the plan panel, monospace: the entries, 41.3GB total, the classification named, the transport named with its auth path, the exact rsync command that will run. In shape:

   ```
   move · cross-host transfer
   214 entries · 41.3 GB
   jodo:/tank/sage/jodo/kanyo/archive → koan:/rpool/sage/koan/cold
   transport: rsync host-to-host · auth: agent-forwarded direct

   ssh jodo 'rsync ... /tank/sage/jodo/kanyo/archive/ koan:/rpool/sage/koan/cold/'
   then: delete source entries — runs after count verification
   ```

   The panel's final face is ho-08's. The content is committed here: classification, transport, auth path, and the real commands, every time. The operator reads it. Enter.

6. **The Transport** opens the Conduit session to jodo and runs rsync toward koan with `--info=progress2`. The command echoes into the plan panel's terminal surface as it runs — the same command the plan showed, now with its real output streaming under it. Progress parses from remote stderr into a progress bar. The bytes travel jodo → koan. The operator's machine orchestrates and never carries a byte.

7. Completion verifies counts. The deletion half of the move renders as its own already-approved plan step and runs.

8. **The panes refresh** — one listing command each.

The operator saw everything before it happened, and everything that happened was something they saw.

The same components compose every other operation. A move within one dataset classifies as a within-dataset rename and the plan shows one `mv`. A move between datasets on the same host classifies as a cross-dataset copy-plus-delete — the landmine named before it is stepped on, which is the sentence this project exists to make true. A whole dataset moving between ZFS-capable hosts gets `zfs send | ssh | zfs receive` offered in the plan. Different facts in, different Plan out, same trace through the same seven components.

---

## 4. Data Model

No database. A database would make the cache look like a system of record, and it is not one — the hosts are. Local state is two JSON files in `~/Library/Application Support/palana/`, human-readable and safe to delete:

- **`field-cache.json`** — last-known topology with timestamps. What the Field remembers from the operator's last visit, rendered as remembered until re-probed.
- **`session.json`** — pane hosts and paths, window state. The workbench as it was left.

Opening pālana is therefore instant and honest at once: `session.json` puts the panes back where they were left, `field-cache.json` renders the remembered topology marked as remembered, and nothing touches a host until the operator does something that needs one.

Plans are in-memory values, never persisted in v1. The operations queue, when it arrives post-release, will persist them — a queue is a list of Plans, and the architecture is prepared for exactly that.

All remote truth lives on the hosts and is re-derivable. The cache is a convenience, deletable at any time without loss. This is not a second system of record. It is a memory of the last visit.

The organizing data model is the ZFS topology itself — `pool/machine/service` — rendered by the Field. It already encodes the organism: which host, which function, where the data lives. pālana does not invent a schema over the field. It reads the one the field already has:

```
jodo
└── tank
    └── sage/jodo
        ├── kanyo          ← service dataset
        └── ...
koan
└── rpool
    └── sage/koan
        ├── cold           ← service dataset
        └── ...
```

Pool, machine, service — the model as the seed states it. The field cache records this tree per host, with a timestamp per fact, so the field view can render the remembered shape instantly and mark it as remembered until the operator asks the Field to look again. What the Field discovered, when it discovered it, and nothing it wasn't asked to see.

---

## 5. Technology Stack

| Element | Choice | Rationale |
|---|---|---|
| Language | Swift 6, strict concurrency | Sealed in the seed. Structured concurrency carries the many-simultaneous-SSH-sessions load the March seed thought needed tokio. The environment is paved — language module written, Sharibako shipped on it. |
| Package shape | SwiftPM multi-product — PalanaCore library + Palana executable | The Sharibako layout. The coverage floor lives in the core, the app stays thin. |
| UI | SwiftUI primary, AppKit interop where the spike demands | SwiftUI table performance at a few thousand rows is the one unproven part. Deferred to ho-01 — the spike decides, `NSTableView` under a SwiftUI shell is the fallback. |
| Subprocess orchestration | Foundation `Process` wrapping the system `ssh` binary | No embedded SSH library. The operator's ssh config, agent, and ProxyJump apply identically, every planned command is operator-readable, and there is no parallel transport stack to audit. |
| Session reuse | ControlMaster multiplexing | Per-command SSH overhead near zero after first connection. One master per host, owned by the Conduit. |
| Testing | swift-testing for new tests, XCTest only where UI testing demands it | Per the language module. |
| Lint and format | swift-format + SwiftLint strict | Per the language module. Warnings escalate to errors in CI. |
| Logging | os.Logger | Mac-only app — the unified log is the native answer. |
| Coverage | ≥90% line coverage on PalanaCore, measured via `swift test --enable-code-coverage` | The truth lives in the core, so the floor does too. |

**Non-obvious evaluations:**

- **System `ssh` over an embedded SSH library.** This is a philosophical choice wearing an engineering costume. An embedded library (libssh2, swift-nio-ssh) would give pālana its own transport stack — and its own key handling, its own config parsing, its own ProxyJump semantics, all subtly divergent from what the operator's terminal does. Wrapping the system binary means the operator's `~/.ssh/config`, keys, agent, and ProxyJump apply identically, every planned command is something the operator could read and run themselves, and there is no parallel transport stack to audit. The cost — parsing process output instead of calling an API — is exactly the discipline the Plan Engine wants anyway, because the plan's commands have to be real.
- **Transport order is decided by the Plan Engine, not the operator.** Agent forwarding is the fast path — jodo authenticates to koan with the forwarded agent, the key never leaves the operator's machine. Proxying through the operator's machine is the fallback — slower, zero inter-host trust required. The operator doesn't choose. The plan names which path it will use, and the naming is the point: the choice is visible, not hidden.
- **`zfs send/receive` only when both ends are whole datasets.** Block-level, an order of magnitude faster for large moves — and meaningless for a subtree, which is a file-level operation. The Plan Engine's classification draws this line, the plan states it, and rsync carries everything the send stream can't.

**Testing architecture.** The Conduit is a protocol, and that single seam carries the whole strategy:

- **Unit tests** inject a RecordedConduit that plays back captured transcripts — including real `zfs` command output recorded once from a throwaway pool. The Plan Engine, the Field's parsers, and the Listing's parsers all test against recorded truth at full speed with no network.
- **Integration tests** run against a local sshd fixture — a Docker or OrbStack container — and are skipped when the fixture is absent. They verify the Conduit and the transports against a real SSH stack.
- **ZFS integration** is verified against a file-backed throwaway pool in a Linux VM — Lima or OrbStack — and never against live homelab datasets. This is the hard limit the seed named and it has no exceptions: no mutating operations against live hosts during development. The practitioner's machines become targets only when the practitioner is driving.

The 90% floor is enforced in CI, where the coverage run belongs — it is too slow for a pre-commit hook and too important to skip. Pre-commit carries format, lint, and build, per the language module.

---

## 6. Deployment Model

Native macOS app. Minimum macOS 14 (Sonoma) — `NavigationSplitView` and the keyboard APIs are mature there, and Sharibako set the precedent.

Open source, published on `github.com/sageframe-no-kaji/palana`, with `ho-process/` tracked — the build record is public, the way Sharibako's is.

Distribution is the Sharibako pattern:

- **Developer ID signing** with the existing Apple Developer Program cert.
- **Notarization** via `notarytool` + `stapler` — the pipeline exists and has shipped a real app.
- **`.dmg` direct download**, released through GitHub Releases on `sageframe-no-kaji/palana`.
- **No App Store.** No sandboxing constraints on `Process`, SSH agent access, or the filesystem.
- **No auto-update in v1.** The Sparkle slot is named and prepared for, not built.

The `.app` bundles nothing but itself. pālana orchestrates the operator's own `ssh` and `rsync`, and `zfs` lives on the hosts — there is no sidecar binary to sign, which makes this a simpler notarization than Sharibako's.

The signing scripts live per-project under `scripts/`, per the language module, and the credentials never enter the repository. Releasing v1.0 is ho-11's whole job — the pipeline is reused, not rebuilt.

---

## 7. Scope Boundaries

The seed's boundaries, restated as what the architecture enforces. These are not intentions to skip features. They are shapes the code cannot take without redesign.

### MVP Architectural Commitments

- **Synchronous execution only.** One enactment at a time. The Transports expose no queue — the queue is post-release.
- **No daemon, no background process.** pālana runs when opened and stops when closed. There is no component that could outlive the window.
- **No watching.** Discovery is on demand only. The Field has no polling loop to enable.
- **The field view shows machines, datasets, and reachability.** Services arrive with the services plugin, not before. The field view does not promise more than the Field can answer.
- **No Forteller integration in v1.** The socket is named: Forteller will be a Workbench plugin wrapping the `fortell` CLI when Forteller exists. Core carries no Forteller awareness.
- **No search.** Panes navigate, they do not query.
- **No batch rename.**
- **Mac only.** No Linux client, no web version. The cost is named in the seed and accepted.

### Architecturally Prepared For (Not Built)

- **Operations queue.** Plans are values — a queue is a list of them. Persistence and background execution arrive without redesigning the Plan Engine.
- **Forteller plugin.** The Workbench API is the socket.
- **Mujō plugin.** Backup and resilience state, same interface.
- **Services plugin.** Extends the field view's vocabulary when it lands.
- **Sparkle auto-update.** Slot named in the deployment model.
- **Localization.** Nothing in the architecture resists it. Nothing in v1 does it.

---

## Provisional Ho Sequence

Directional — Kamae 4 commits. The sequence carries the autonomous-build shape from the seed: the agent authors and executes the chain, and the practitioner is interrupted for exactly three sessions — ho-07, ho-08, and ho-09, hands on the running app, feel feedback. The engine hos before them need no hands. The spike comes first because it is the one genuine go/no-go in the project.

| Ho | Title | Purpose |
|---|---|---|
| ho-00 | Orientation | Concept primers — Swift concurrency for process orchestration, ControlMaster, `zfs send/receive` semantics, rsync progress parsing. Project ho shape, scaffold verification. |
| ho-01 | The Spike | Go/no-go. Conduit minimal + one real listing + a SwiftUI pane rendering a few thousand rows with keyboard navigation, no lag. Resolves SwiftUI tables vs `NSTableView` fallback. Spike code is throwaway — the findings graduate, the code does not. |
| ho-02 | The Conduit | Session pool, ControlMaster lifecycle, error taxonomy, RecordedConduit test infrastructure. |
| ho-03 | The Field | ssh config parsing, discovery — reachability, ZFS topology, capability probe — and the field cache. |
| ho-04 | The Listing | Listing command, parser, FileEntry model, pane state model. |
| ho-05 | The Plan Engine | Classification, transport selection, command composition, the full unit-test battery. |
| ho-06 | The Transports | rsync direct + proxy fallback, `zfs send/receive`, progress parsing, ZFS fixture integration. |
| ho-07 | The Surface: Panes | Dual panes, keyboard grammar, navigation. First UI/UX session. |
| ho-08 | The Surface: Plan and Enact | Plan panel, enact flow, progress display. Second UI/UX session. |
| ho-09 | The Surface: Field View | The summonable overlay. Third UI/UX session. |
| ho-10 | The Workbench | Plugin API + the ZFS tool as proof. |
| ho-11 | The Ship | Signing, notarization, docs, v1.0. |

---

## Deferred Decisions

Each open question is assigned to a specific ho with evaluation criteria. None of these is a to-be-determined — each one names where it gets decided and what a good answer looks like.

| # | Question | Deferred to | Evaluation criteria |
|---|---|---|---|
| 1 | SwiftUI table vs `NSTableView` under a SwiftUI shell | ho-01 | A 5,000-row listing scrolls and keyboard-navigates with no perceptible lag on the practitioner's hardware. |
| 2 | ZFS fixture mechanics — Lima vs OrbStack, pool setup script | ho-02 | `make zfs-fixture` (or equivalent) produces a throwaway pool from nothing in under two minutes. |
| 3 | Capability probe design — what one round-trip learns about a host | ho-03 | The probe identifies userland flavor (GNU or BSD) and ZFS presence on every fleet host in one command, and the Field records it as a fact like any other. |
| 4 | Listing command exact format | ho-04 | One round-trip per directory, correct on GNU and BSD userlands, symlinks and weird filenames survive. |
| 5 | Progress parsing specifics — rsync progress2 field stability, `zfs send -v` cadence | ho-06 | A progress bar that moves smoothly and finishes at 100 exactly when the transfer finishes. |
| 6 | Keyboard grammar specifics — which keys do what | ho-07, with the practitioner's hands on it | yazi's verb set — including the clipboard verbs, copy path and kin — is the starting vocabulary, pruned by feel. The practitioner stops thinking about the keys within one session. |
| 7 | Terminal surface implementation — SwiftTerm embed vs a purpose-built streaming text view | ho-08 | The plan panel displays commands, echoes live enactment output without dropped lines, and stays smooth. If a full terminal emulator is more than the echo needs, the smaller thing wins. |
| 8 | Field view contents and summon key | ho-09, with the practitioner | Summon, point a pane, dismiss — under two seconds end to end. |

---

_Next document: Kamae 3 (README), drafted against this document._
