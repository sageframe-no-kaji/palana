---
created: 2026-07-03
status: complete
type: ho-overview
project: palana
stage: kamae-4
kamae-chain: seed → system-design → readme → **ho-overview**
builds-on: kamae-1-palana-seed, kamae-2-palana-system-design, README.md (kamae-3)
next: per-ho dandori specs authored via ho-kamae-5
---

# pālana — Ho Overview

Twelve hos across five phases (v1.0 target). Phase 1 stands the project up and answers its one genuine go/no-go. Phase 2 builds the entire engine headless — everything below the Surface, tested against fixtures, with no UI in existence. Phase 3 builds the app on the finished engine, one surface at a time. Phase 4 proves the plugin API with the ZFS tool. Phase 5 signs, notarizes, and releases v1.0.

This is the autonomous build the seed committed to. The agent authors and executes every ho — the per-ho dandori specs, the code, the tests, the commits. The practitioner is interrupted for exactly three sessions: ho-07, ho-08, and ho-09, hands on the running app, feel feedback, pinged via the project's ntfy channel (topic recorded in `prompts/ntfy-topic.txt`, gitignored) when the app is ready for hands. Everything else runs without interruption, with two standing rules. An architecture-reshaping surprise halts the session and surfaces to the practitioner — the agent does not silently make the call. And the hard limit has no exceptions: no mutating operations against live homelab hosts, ever. Development runs against fixtures only — a localhost sshd container and a file-backed throwaway ZFS pool in a Linux VM. The practitioner's machines become targets only when the practitioner is driving.

UI/UX findings from the three sessions become new hos in the current build slot. Closed hos stay closed — forward-only.

---

## What this is, and what it is not

This document is the build's directional plan. Each ho is sized to fit a single focused session, combined hos are flagged as candidates to split, and the numbering scheme (ho-N.1, ho-N.5) exists because the plan is supposed to evolve as the build proceeds. The system design's provisional ho sequence is welcomed as starting material — this overview keeps its order and organizes it into phases with checkpoints and release tags. The deferred-decisions table is dissolved into per-ho decision callouts, so the decisions a given ho is responsible for resolving are right there in the ho. All eight land inside the sequence.

This is not a contract. It is the map. Per-ho dandori specs are the territory.

---

## Phase structure

| Phase | Hos | What it produces |
|---|---|---|
| 1. Foundation | ho-00, ho-01 | Verified scaffold, primed concepts, the go/no-go answered with evidence |
| 2. The Engine | ho-02 – ho-06 | PalanaCore complete and headless — Conduit, Field, Listing, Plan Engine, Transports |
| 3. The Surface | ho-07, ho-08, ho-09 | The app — panes, plan → enact, field view. Three UI/UX sessions |
| 4. The Workbench | ho-10 | Plugin API proven by the ZFS tool, core unmodified |
| 5. The Ship | ho-11 | Signed, notarized .dmg on GitHub Releases, docs current, v1.0 tagged |

---

## Phase 1 — Foundation

The project stands up and answers its one genuine go/no-go. The scaffold — SwiftPM package on the Sharibako layout, verification stack, pre-commit — is built before ho-00 is authored, so ho-00 verifies it rather than creating it, and primes the concepts every downstream session leans on. ho-01 then puts a few thousand real rows into a SwiftUI pane and watches the keyboard. At the end of the phase the scaffold is green, the vocabulary is shared, and the UI layer's feasibility question is answered with evidence instead of hope.

*Release on phase complete: v0.1*

### ho-00 — Orientation

The orientation ho. The scaffold exists before this ho is authored — ho-00 verifies it, running the build, the tests, the lint stack, and the pre-commit hooks to prove the encoded environment is real. The session writes the concept primers the build depends on and commits the project's ho shape conventions, so every later session opens against a paved environment and a shared vocabulary. Nothing user-facing exists at the end of it, and nothing needs to.

**Depends on:** Nothing (this is the start)

**What's in scope:**
- Concept primers: Swift structured concurrency for process orchestration, ControlMaster mechanics, `zfs send/receive` semantics, rsync progress parsing
- Project ho shape commitments — what a pālana ho document contains, how agent tasks decompose
- Scaffold verification: `swift build`, `swift test`, lint, pre-commit all run clean

**What "done" means:**
- The four primers exist and a fresh session can read them instead of rediscovering the ground
- The scaffold passes its own verification stack end to end, and the ho shape is committed

**What's out of scope:** Any product code. The spike is ho-01's.

### ho-01 — The Spike

The go/no-go. A minimal Conduit, one real listing, and a SwiftUI pane rendering a few thousand rows with keyboard navigation and no lag — the one part of the architecture the seed named as unproven. Spike code is throwaway. The findings graduate into the per-ho record and the ho-07 design, the code does not — Phase 2 starts clean.

**Depends on:** ho-00

**What's in scope:**
- Minimal SSH execution — enough Conduit to fetch one real directory listing
- A SwiftUI table rendering the listing at a few thousand rows
- Keyboard navigation over that table, measured by feel and by frame

**What "done" means:**
- The 5,000-row test has a clear verdict on the practitioner's hardware, recorded with the evidence
- The spike code is deleted. The findings are not.

**What's out of scope:** Production code of any kind. Error taxonomy, session pooling, parsing rigor — all Phase 2.

**Decisions required:**
- **SwiftUI table vs `NSTableView` under a SwiftUI shell** (deferred decision 1): a 5,000-row listing scrolls and keyboard-navigates with no perceptible lag on the practitioner's hardware. If SwiftUI's table carries it, SwiftUI wins. If not, `NSTableView` under a SwiftUI shell is the committed fallback.

**Replan checkpoint — after ho-01.** First contact with the stack. See "Replan checkpoints" below.

---

## Phase 2 — The Engine

Everything below the Surface, built headless and tested to the 90% floor against fixtures. The Conduit opens the one door to the hosts, the Field maps them, the Listing reads their directories, the Plan Engine composes truthful plans, and the Transports enact them server-side. At the end of the phase PalanaCore can discover a field, read a directory, compose a plan an operator could run by hand, and enact it host to host — with no UI in existence.

*Release on phase complete: v0.2*

### ho-02 — The Conduit

The single door to the hosts. Session pool and ControlMaster lifecycle — open on first use, reuse thereafter, close on quit — wrapping the system `ssh` binary via Foundation `Process`. The error taxonomy lives here: every failure a host can produce surfaces typed at the Conduit before anything above it interprets raw process noise. The RecordedConduit test infrastructure is built here too, because it is the seam the whole testing strategy hangs on.

**Depends on:** ho-01 (findings, not code)

**What's in scope:**
- `run(host, command) → (stdout stream, stderr stream, exit status)` behind a protocol, with the ControlMaster session lifecycle per host
- The error taxonomy
- RecordedConduit playback for unit tests, localhost sshd container for integration tests

**What "done" means:**
- Commands run against the sshd fixture with sessions reused, and every failure class the fixture can produce surfaces as a typed error
- RecordedConduit plays back captured transcripts and the pattern is documented for every downstream ho

**What's out of scope:** Anything above the door — parsing, topology, plans.

**Decisions required:**
- **ZFS fixture mechanics — Lima vs OrbStack, pool setup script** (deferred decision 2): a make target produces a throwaway file-backed pool from nothing in under two minutes. Decided here because ho-03 and ho-06 both need the fixture standing.

### ho-03 — The Field

Topology. Hosts parse from `~/.ssh/config` — if you can SSH to it, pālana can see it, and there is no trust ceremony of pālana's own. Per-host facts — reachability, ZFS pools and datasets, userland capability — are discovered on demand through the Conduit, never continuously, and remembered in the field cache as memory of the last visit.

**Depends on:** ho-02

**What's in scope:**
- ssh config parsing → `hosts()`
- On-demand discovery — reachability, ZFS topology, the capability probe — and dataset-boundary queries for the Plan Engine
- `field-cache.json` — last-known facts with timestamps, rendered as remembered until re-probed

**What "done" means:**
- The Field answers `hosts()`, `discover(host)`, and `facts(host)` against fixtures, and dataset boundaries resolve correctly against the throwaway pool
- The cache survives deletion — the Field rebuilds from the hosts themselves

**What's out of scope:** Any polling loop. Discovery is on demand only — the Field has no watching to enable. Services stay out of the vocabulary until the services plugin exists.

**Decisions required:**
- **Capability probe design — what one round-trip learns about a host** (deferred decision 3): the probe identifies userland flavor (GNU or BSD) and ZFS presence on every fleet host in one command, and the Field records it as a fact like any other.

### ho-04 — The Listing

Remote directory reading. One SSH command per directory read, emitting a parseable listing — GNU `stat` and `find -printf` as the primary path, a BSD fallback selected by ho-03's capability probe. The FileEntry model and the pane state model are the contract the Surface will render against, so they are committed here, three hos before any pane exists.

**Depends on:** ho-02, ho-03 (the probe selects the command path)

**What's in scope:**
- The listing command and its parser
- The FileEntry model — name, size, mtime, kind, permissions, owner, symlink target — and the pane state model
- Fixture coverage for both userlands, symlinks, and hostile filenames

**What "done" means:**
- `list(host, path) → [FileEntry]` is correct on GNU and BSD userlands against fixtures, and weird filenames survive byte for byte
- One round-trip per directory — a pane refresh is one command

**What's out of scope:** Writing, classifying, composing. The Listing reads.

**Decisions required:**
- **Listing command exact format** (deferred decision 4): one round-trip per directory, correct on GNU and BSD userlands, symlinks and weird filenames survive.

### ho-05 — The Plan Engine

The core abstraction. A pure function — (source state, destination state, requested operation) → Plan — carrying classification, transport selection, and command composition. It performs no I/O of its own, which makes it the most testable object in the system, and it had better be, because it is the part that must never lie. The full unit-test battery lands here: every classification, every transport choice, every composed command verified against recorded truth.

**Depends on:** ho-03 (dataset boundaries), ho-04 (entries)

**What's in scope:**
- Classification: within-dataset rename, cross-dataset copy-plus-delete, cross-host transfer
- Transport selection: rsync agent-forwarded direct, rsync proxied, `zfs send/receive` when both ends are whole datasets
- Command composition — commands an operator could paste into a terminal and get the same result
- The full unit-test battery over RecordedConduit facts

**What "done" means:**
- Every classification produces the committed Plan shape and composed commands match hand-verified equivalents exactly
- No I/O anywhere in the engine — facts in, Plan out

**What's out of scope:** Enactment. The Plan Engine composes and never runs.

### ho-06 — The Transports

Enactment. Executes an approved Plan exactly as composed — rsync host-to-host with agent forwarding as the fast path, proxy through the operator's machine as the fallback, `zfs send | ssh | zfs receive` for whole datasets — with no improvisation between approval and execution. Progress events parse from remote stderr into a stream the Surface will later render as a bar. ZFS behavior verifies against the throwaway pool from ho-02's fixture, never against a live host.

**Depends on:** ho-02, ho-05

**What's in scope:**
- rsync direct with agent forwarding, proxy fallback
- `zfs send/receive` for whole-dataset moves
- Progress parsing — `rsync --info=progress2`, `zfs send -v`
- Count verification on completion, ZFS fixture integration tests

**What "done" means:**
- `enact(plan)` runs the Plan's exact commands against fixtures and emits progress events, with the proxy fallback engaging when agent forwarding is unavailable
- A whole-dataset move completes over `zfs send/receive` against the throwaway pool with counts verified

**What's out of scope:** Any queue. One enactment at a time — the operations queue is post-release, and the Transports expose no seam for it beyond Plans being values.

**Decisions required:**
- **Progress parsing specifics — rsync progress2 field stability, `zfs send -v` cadence** (deferred decision 5): a progress bar that moves smoothly and finishes at 100 exactly when the transfer finishes.

**Possible split:** three transports plus progress parsing may be two sessions — ho-06.1 (rsync direct + proxy, progress parsing) and ho-06.2 (`zfs send/receive` + fixture integration). Split before opening the session if the dandori spec cannot hold all of it.

**Phase boundary — replan checkpoint.** The engine is complete and the Surface commits next. See "Replan checkpoints" below.

---

## Phase 3 — The Surface

The app, built on a finished engine. Dual panes and the keyboard grammar first, then the plan panel and the enact flow, then the field view overlay. Each ho ends in a UI/UX session — the practitioner's hands on the running app are the validation layer the fixtures cannot be, summoned via the project's ntfy channel. Findings become new hos in the current build slot, forward-only. At the end of the phase pālana is a usable dual-pane file manager with plan → enact and the field view.

*Release on phase complete: v0.3*

### ho-07 — The Surface: Panes

The first visible surface. Dual panes on the pane state model from ho-04, the keyboard grammar, and navigation — the register is the good notebook, calm, almost no chrome, one interactive accent. The table technology is whatever ho-01's verdict committed. The ho ends in the first UI/UX session: the practitioner's hands on the panes, the grammar pruned by feel.

**Depends on:** ho-01 (the table verdict), ho-04 (pane state and entries)

**What's in scope:**
- Dual panes, each pointed at a host and path
- Keyboard grammar and navigation — pane focus, entry movement, selection, descend and ascend
- The first UI/UX session, practitioner pinged via ntfy

**What "done" means:**
- Both panes render real listings from the engine and navigate without stutter
- The practitioner has driven the panes by hand — feel feedback recorded, scope-reshaping findings queued as new hos

**What's out of scope:** The plan panel and enactment (ho-08). The field view (ho-09).

**Decisions required:**
- **Keyboard grammar specifics — which keys do what** (deferred decision 6, resolved with the practitioner's hands on it): yazi's verb set — including the clipboard verbs, copy path and kin — is the starting vocabulary, pruned by feel. The practitioner stops thinking about the keys within one session.

### ho-08 — The Surface: Plan and Enact

The workflow the project exists for, made visible. The plan panel is a real terminal surface, not monospace styling — the Plan's commands display there before enactment, and when Enter fires, the enactment echoes there live, real commands, real output, streaming. Progress renders from the Transports' event stream. The ho ends in the second UI/UX session, the practitioner reading plans and watching them run.

**Depends on:** ho-05, ho-06, ho-07

**What's in scope:**
- The plan panel rendering the committed Plan shape — classification, transport, auth path, exact commands
- The enact flow — Enter enacts, Esc dismisses — with live enactment echo and progress display from the event stream
- The second UI/UX session, practitioner pinged via ntfy

**What "done" means:**
- A cross-host move traces end to end through the panel exactly as the system design's core interaction describes, with the echo streaming smoothly and no dropped lines
- The practitioner has read a plan, pressed Enter, and watched the truth run

**What's out of scope:** An interactive terminal — type into it, per host — is a Workbench tool for later. The v1 commitment is the echo, not the shell.

**Decisions required:**
- **Terminal surface implementation — SwiftTerm embed vs a purpose-built streaming text view** (deferred decision 7): the plan panel displays commands, echoes live enactment output without dropped lines, and stays smooth. If a full terminal emulator is more than the echo needs, the smaller thing wins.

### ho-09 — The Surface: Field View

The summonable overlay. One keystroke brings the topology — machines, datasets, reachability — rendered from the Field's cache instantly and marked as remembered until re-probed. Pick a node, a pane points there, the overlay vanishes. The ho ends in the third UI/UX session, and the phase's checkpoint consolidates the findings from all three.

**Depends on:** ho-03 (the Field and its cache), ho-07 (panes to point)

**What's in scope:**
- The overlay — summon, navigate, point a pane, dismiss
- Remembered state rendered instantly from `field-cache.json`, re-probe on demand
- The third UI/UX session, practitioner pinged via ntfy

**What "done" means:**
- Summon, point a pane, dismiss works against the real cache, with remembered facts visibly marked as remembered
- The practitioner's feel feedback is recorded and consolidated with ho-07's and ho-08's

**What's out of scope:** Services in the overlay — the field view does not promise more than the Field can answer. That vocabulary arrives with the services plugin, post-v1.

**Decisions required:**
- **Field view contents and summon key** (deferred decision 8, resolved with the practitioner): summon, point a pane, dismiss — under two seconds end to end.

**Phase boundary — replan checkpoint.** UI/UX findings from all three sessions consolidate here. See "Replan checkpoints" below.

---

## Phase 4 — The Workbench

The plugin API and its proof. The Workbench hands a plugin exactly three things — the Conduit, the Field, and a surface slot — and the ZFS tool, built as a compiled-in Swift target conforming to the Workbench protocol, demonstrates that the boundary holds. At the end of the phase the ZFS tool runs on the same interface any future plugin would use, and core was not modified to admit it.

*Release on phase complete: v0.4*

### ho-10 — The Workbench

The API is the commitment, and its first consumer proves it by use, not by speculation. The Workbench protocol defines registration, the two core capabilities handed in, and the one surface slot handed out. The ZFS tool — dataset CRUD, snapshots, pool visualization — builds on that interface as a compiled-in target. A plugin that needs something the API doesn't offer is a reason to grow the API deliberately, not a reason to open the core.

**Depends on:** ho-02, ho-03 (the capabilities handed in), ho-07 (the surface slot)

**What's in scope:**
- The Workbench protocol — registration, Conduit and Field handed in, one surface slot out
- The ZFS tool: dataset CRUD, snapshots, pool visualization, verified against the throwaway pool
- The proof condition itself — no core modification to admit the plugin

**What "done" means:**
- The ZFS tool works end to end through the Workbench API alone, with mutating operations against the fixture pool only
- A diff of PalanaCore across this ho shows the API growing deliberately or not at all — never a plugin reaching inside

**What's out of scope:** Dynamically loaded bundles — prepared for by the protocol, not built. Forteller, Mujō, and services stay sockets.

**Possible split:** ho-10.1 (the Workbench protocol and its harness) and ho-10.2 (the ZFS tool built on it). The API and its first consumer are different work, and the split line is exactly the boundary the ho exists to prove.

---

## Phase 5 — The Ship

Release. The Sharibako signing and notarization pipeline is reused, not rebuilt — the existing Developer ID cert, `notarytool` and `stapler`, a `.dmg` through GitHub Releases on `sageframe-no-kaji/palana`. The `.app` bundles nothing but itself, which makes this a simpler notarization than Sharibako's. Docs get their final pass against shipped behavior. At the end of the phase a signed, notarized `.dmg` sits on GitHub Releases, the documentation is current, and v1.0 is tagged.

*Release on phase complete: v1.0*

### ho-11 — The Ship

Signing, notarization, docs, release. The pipeline exists and has shipped a real app — this ho adapts it, verifies the notarized build on a clean machine, brings the README and the build record current against what actually shipped, and tags v1.0. No App Store, no sandbox, no auto-update — the Sparkle slot stays named and empty.

**Depends on:** ho-07, ho-08, ho-09, ho-10 (the app is complete before signing matters)

**What's in scope:**
- Developer ID signing and notarization via the Sharibako pipeline, scripts under `scripts/`, credentials never in the repository
- `.dmg` build, Gatekeeper verification on a clean machine
- Docs final pass against shipped behavior, GitHub release, v1.0 tagged

**What "done" means:**
- A signed, notarized, stapled `.dmg` installs and runs on a machine that has never seen the project
- The docs describe the app as released, not as planned, and v1.0 is tagged and public

**What's out of scope:** Sparkle auto-update (prepared for, not built). Marketing beyond the release itself.

---

## What's NOT in this sequence

Deferred, not forgotten. Tracked for post-v1:

- **Operations queue.** Plans are values — a queue is a list of them. Arrives without redesigning the Plan Engine.
- **Forteller plugin.** The Workbench API is the socket, when Forteller exists.
- **Mujō plugin.** Backup and resilience state, same interface.
- **Services plugin.** Extends the field view's vocabulary when it lands.
- **Sparkle auto-update.** Slot named in the deployment model, not built.
- **Search.** Panes navigate, they do not query.
- **Batch tools.** Batch rename and kin — none in v1.
- **Interactive terminal.** Type into it, per host — a Workbench tool for later. v1 commits to the echo.

---

## Replan checkpoints

Three explicit pause points. At each one the build stops, evaluates against real evidence, and decides whether to continue as planned, insert, or replan. In the autonomous shape, "stops" means the agent surfaces the checkpoint's questions and its recommendation to the practitioner before opening the next phase.

### Checkpoint 1 — after ho-01 (first contact with the stack)

The reality check. The spike is the project's first contact with SwiftUI at file-manager density and with SSH orchestration from Swift concurrency. The table verdict is in, and whatever else the spike surfaced — process handling friction, concurrency surprises, listing latency — gets weighed before Phase 2 commits five hos to the engine. If the spike reshapes the plan, the reshaping happens here, not mid-engine.

### Checkpoint 2 — after ho-06 (the engine is complete)

Phase boundary. PalanaCore is done and headless, and the next phase commits to the Surface — the first work whose validation needs the practitioner's hands. Evaluate: did the engine hold to the 90% floor, did the fixtures cover what they claimed, is the Plan shape the panel will render actually final. Anything soft in the engine gets hardened now, before three UI hos build on top of it.

### Checkpoint 3 — after ho-09 (UI/UX findings consolidated)

Phase boundary. The findings from all three UI/UX sessions consolidate here. Feel feedback that demands rework becomes new hos in the current build slot — forward-only, never edits to the closed Surface hos. The Workbench and the release only open once the practitioner's hands say the surface holds.

---

## Numbering and insertion

The numbering scheme exists because plans evolve. Framework rules:

- **Splits:** ho-N becomes ho-N.1, ho-N.2 when its scope turns out larger than one focused session can hold. The original ho-N stops being authored — its split successors carry the work.
- **Insertions:** new work between ho-N and ho-N+1 gets a decimal — ho-N.5. Insertions usually appear at replan checkpoints or when the UI/UX sessions surface work the plan did not anticipate.
- **Abandonment:** a published number that the plan no longer needs stays dead. The address space is immutable once committed to the overview.
- **Forward-only:** closed hos stay closed. New knowledge produces new hos that reference and supersede, never retroactive edits.

---

## Anticipated splits and insertions

**Combined-scope hos likely to split:**

- **ho-06 (The Transports)** is the likely split candidate — three transports plus progress parsing may be two sessions. Natural cut: ho-06.1 (rsync direct + proxy, progress parsing) and ho-06.2 (`zfs send/receive` + fixture integration).
- **ho-10 (The Workbench)** may split API from tool — ho-10.1 (the protocol) and ho-10.2 (the ZFS tool). The split line is the boundary the ho proves.

**Insertions likely:**

- Feel-driven hos after any of the three UI/UX sessions, consolidated at Checkpoint 3 — grammar tuning after ho-07, panel behavior after ho-08, overlay contents after ho-09. Each lands as a new ho in the current build slot.
- A small parsing or performance ho if the fixtures surface listing or progress behavior the engine hos did not anticipate.

---

## Other deferred decisions

The system design's eight deferred decisions all tie to specific hos and render inline above — nothing in the table escapes the sequence. One item lives outside it: **visual identity for the app icon.** No design work is committed in the sequence. The `.dmg` in ho-11 needs an icon — a basic mark suffices for v1.0, and a designed identity is post-v1 work if it earns the scope.

---

## Dependency summary

```
Phase 1 — Foundation
├── ho-00 (Orientation)
└── ho-01 (The Spike — go/no-go, table verdict)
        ▲
        │  ◆ Checkpoint 1 — first contact with the stack ───── v0.1

Phase 2 — The Engine (headless, fixtures only)
├── ho-02 (The Conduit)
├── ho-03 (The Field)
├── ho-04 (The Listing)
├── ho-05 (The Plan Engine)
└── ho-06 (The Transports)
        ▲
        │  ◆ Checkpoint 2 — engine complete ────────────────── v0.2

Phase 3 — The Surface (three UI/UX sessions)
├── ho-07 (Panes)            · session 1
├── ho-08 (Plan and Enact)   · session 2
└── ho-09 (Field View)       · session 3
        ▲
        │  ◆ Checkpoint 3 — UI/UX findings consolidated ────── v0.3

Phase 4 — The Workbench
└── ho-10 (Plugin API + ZFS tool) ──────────────────────────── v0.4

Phase 5 — The Ship
└── ho-11 (Signing, notarization, docs, release) ───────────── v1.0
```

The cross-phase dependencies live in each ho's **Depends on** field above. The load-bearing ones: ho-04 waits on ho-03's probe, ho-05 draws on ho-03 and ho-04 and touches no wire, ho-07 builds on ho-01's verdict and ho-04's pane state, and ho-10 consumes exactly what the Workbench hands in — ho-02, ho-03, and ho-07's surface slot.

---

## What to do with this document

The overview is the map. Each ho is the destination for a Kamae 5 session, which produces the per-ho dandori spec — the surgical, command-verifiable instruction the executing agent runs against. Open one ho at a time. Do not write all the dandori specs in advance.

Update this overview as the build proceeds. A ho that splits gets its successors named here, a checkpoint that fires gets its outcome recorded, a UI/UX session that produces findings gets its resulting hos added in the current build slot. Small frequent updates beat large rare ones. In the autonomous shape this document is also the practitioner's window into a build he is mostly not watching — checkpoint outcomes, halt-and-surface records, and UI/UX findings all land here, so a two-week absence ends with one read: where the build is, what was decided, what comes next.

**Build record.**

- ho-00 closed 2026-07-03 — scaffold verified green end to end, four primers written, ho shape conventions committed (`ho-process/hos/ho-00-orientation.md`). CI assigned to ho-02.
- ho-01 closed 2026-07-03 — **the go/no-go answers go.** SwiftUI `Table` holds 5,080 real rows at the display's own 120Hz cadence under sustained keyboard navigation, zero hitches over 100ms, first render 164ms. Deferred decision 1 resolved: SwiftUI, no `NSTableView` fallback. One primer correction graduates to ho-02: drain `Process` pipes with `readabilityHandler` streams, never `FileHandle.bytes` (observed deadlock, recorded in the ho). Spike code deleted; evidence in `ho-process/hos/ho-01-metrics-swiftui.json`.
- **Checkpoint 1 fired 2026-07-03: continue as planned.** No insertions, no replan. Phase 1 complete — tagged v0.1.
- ho-02 closed 2026-07-03 — the Conduit stands: `run(host, command)` behind the protocol, ControlMaster lifecycle (cold 66.6ms → multiplexed 9.9ms against the container fixture), the error taxonomy typing every fixture-producible failure, RecordedConduit/RecordingConduit as the test seam. Deferred decision 2 resolved: Lima — `make zfs-fixture` re-creates the throwaway pool in 1m05s cached (3m24s first run, image download). CI green with the 90% floor enforced; PalanaCore at 99.4% locally, 98.2% on the runner.
- ho-03 closed 2026-07-03 — the Field stands: hosts from `~/.ssh/config` (aliases only, ssh resolves the rest), the one-round-trip capability probe hardened against three userlands live (deferred decision 3 resolved — marker-lined, order-independent, empty-means-absent), ZFS topology with `mounted` riding along so unmounted mountpoints never match a path query, boundary resolution by longest mounted prefix at component granularity, `field-cache.json` as deletable memory with per-group timestamps. Fixture truth recorded into committed transcripts; the corpus replays everywhere. 83 tests, PalanaCore 97.48%.
- ho-04 closed 2026-07-03 — the Listing stands: `FileEntry` with name bytes as truth and String as face, `PaneState` committed as the Surface's contract, and both userland paths one round trip each (deferred decision 4 resolved — GNU `find -printf` NUL-everywhere, BSD stat-line-then-NUL-name self-aligned records with keyed symlink targets, because BSD stat cannot emit NUL). The eleven-name hostile battery — embedded and trailing newlines, UTF-8, marker-shaped names — passes byte for byte live on both userlands and replays from committed corpus. Read failures typed at the Listing. 119 tests, PalanaCore 97.60%.
- **ho-06 split fired 2026-07-03**, before opening, on the anticipated cut: **ho-06.1** (enactment machinery — the event stream, rsync direct, the tar-stream proxy pipeline, progress parsing, verification and gate enforcement, against the sshd fixture) and **ho-06.2** (`zfs send/receive` against the throwaway pool, whole-dataset verification). The original ho-06 stops being authored; its successors carry the work.
- ho-06.1 closed 2026-07-03 — enactment stands: the event stream is the panel's echo, host steps run the Plan's exact commands through the Conduit, proxied pipelines enact in-process with pālana counting the bytes, and gates release only on matched counts (deferred decision 5's rsync half resolved — progress2 bytes and percent stable, the live bar finishes at 1.0 exactly, real stream recorded into corpus). The fixture plays two hosts via a self-reach alias and real rsync. Live traces run the whole stack: probe → Listing → Plan Engine → Transports. CI's openrsync skips the rsync-direct live test by the probe's own version fact; everything else runs everywhere. 165 tests, PalanaCore 97.44%.
- ho-06.2 closed 2026-07-03 — the engine is COMPLETE. zfs send/receive enacts against the throwaway pool, delegated, no sudo in any composed command: forwarded move lands, verifies by dataset existence (the stream is its own byte verification — VerificationReport grew a second shape, the gate contract unmoved), destroys its source, sweeps snapshots, checksums identical; proxied copy pumps through the operator's machine on the proven pipeline. Deferred decision 5 fully resolved (send -v parsed against the header estimate, capped at one). Engine corrections: receive -u (Linux mounting is root's regardless of delegation), and the delegation finding that property names must be delegated alongside verbs. 173 tests, PalanaCore 97.69%.

**Checkpoint 2 fired 2026-07-03 — the engine is complete. Surfaced to the practitioner; Phase 3 waits for his word.** The checkpoint's questions, answered from the record: *Did the engine hold to the 90% floor?* 97.69%, never below 97 at any close. *Did the fixtures cover what they claimed?* Three userlands probed live, hostile filenames byte-exact both paths, transfers enacted end to end with gates proven, zfs against a real pool — the one soft spot is that no fixture exercises BusyBox-classified-BSD or a genuinely slow link. *Is the Plan shape the panel will render final?* The Plan is a Codable value carrying classification, transport, auth path, exact commands, gates, and the received dataset — ho-08's panel renders it without reaching back. **Two things for the practitioner's eyes before Phase 3:** (1) ho-05's correction — "rsync proxied" was never a command that exists; the proxy floor is a tar stream through the operator's machine, named in the plan. (2) Plan.totalSize counts directory entries at inode size — honest for files, shallow for trees; if the panel should promise recursive truth, that is a small facts ho before ho-08. **Recommendation: continue as planned into Phase 3 (v0.2 tagged), with the practitioner's UI/UX session at ho-07's close as scheduled.**
- **Checkpoint 2 response received 2026-07-03 — Phase 3 is open.** The practitioner's word: continue — author ho-07 and execute, ending with his hands on the app. The recursive-size bracket arrived unfilled: whether `Plan.totalSize` should promise recursive truth for directories stays an open decision. It rides to ho-07's UI/UX session and must land before ho-08 opens — if the answer is recursive truth, a small facts ho slots in as ho-06.5 in the current build slot.
- **The bracket landed 2026-07-03, at ho-07's UI/UX session: "we NEED to know the WHOLE contents, not just the next level down. 100% recursive."** **ho-06.5 — Recursive Size Facts** is inserted before ho-08: one `du`-shaped round trip per plan so `Plan.totalSize` carries the true recursive total for directory entries, sizes labeled honestly until then. Authored via Kamae 5 when it opens.
- **Checkpoint 2's named soft spot materialized 2026-07-03, minutes after ho-07 closed: zencat runs BusyBox.** The probe classified it into a flavor whose listing command BusyBox's `find` refuses — the pane connected fine and surfaced usage spew as a typed read failure. **ho-07.5 — The BusyBox Userland** is inserted: a third flavor in the capability probe, a BusyBox listing path (BusyBox `stat -c` speaks GNU-ish format), fixture coverage on an Alpine container. Authored via Kamae 5 when it opens. Post-close ho-07 addendum, same session: the operator's own machine became a pointable host — `LocalConduit` promoted from test infrastructure to PalanaCore, "local" leads the host list and is the go-to bar's default (the prior default was the config's first alias — a github key alias that refuses shells, which read as "won't connect").
- **Design basis, restated by the practitioner mid-session 2026-07-03, verbatim — the sentence the Surface hos build against:** "this i LIKE working in a terminal based browser but with all the pleasure and benefit of a native GUI. that is what the design basis it. yazi is powerful and fast as hell and lets you do so much but is ugly and rough and doing things is hard and requires muscle memory. I want all that power and speed and simplicity AND the muscle memory, but also an intuitive, calm, well designed experience." This sharpens pre-seed-2's reference ladder into one line: yazi's power under a calm native surface, muscle memory kept, roughness removed.
- **Queued the same night: a host-onboarding surface.** "Add a host" as a guided flow — writes the `Host` block into `~/.ssh/config` (the file stays the only registry, the flow is a surface over it, never a parallel store), walks key setup and first reach. Mutates the operator's ssh surface, so it earns a full Think phase — placed at Checkpoint 3's consolidation, not before.
- **ho-06.5 closed 2026-07-03 — plans carry recursive truth.** `Listing.treeSizes` gathers apparent bytes under every selected directory in one round trip (find walks, awk sums remotely, both userland paths), and every number rides with a completeness flag — a refused subtree can never hide inside a clean-looking total. `Plan.totalSize` is now the whole contents; `Plan.totalSizeComplete` says when it is only a floor. Proven live on both flavors with a mode-000 subtree. 228 tests, TreeSize 100%. **Next: ho-07.5 (BusyBox) or ho-08 (Plan and Enact) — ho-08 has everything it needs.**
- **ho-07 closed 2026-07-03 — the Surface stands and the practitioner has driven it.** Dual panes on SwiftUI `Table` over the engine, the yazi-under-Mac vocabulary through the core's recognizer, ⇧⌘G and click-to-type pointing, session restore, the notebook first cut. The first UI/UX session ran live in three feedback rounds while the build session was still open: scroll-follow (the Table does not track programmatic selection), reads that commit only on success (a bad pointing never navigates), the `?` vocabulary card, focus-follows-click, the dimmer unfocused pane, right-click clipboard verbs, and Enter opening files through a size-guarded temp fetch (`Listing.readFile` — composition stayed below the boundary). Deferred decision 6 resolved by the practitioner's word: "i like the vim keys" — yazi's vocabulary kept whole. Queued for Checkpoint 3: symlink descend, selection color and palette (design polish), Space-to-open, dataset/mount indicators (ho-09 territory). 208 tests, CI green. **Next: ho-06.5 (recursive size facts), then ho-08.**
- ho-05 closed 2026-07-03 — the Plan Engine stands, pure: PlanRequest + PlanFacts in, Plan out, no I/O anywhere. Plans are Codable values with gated steps. Classification conservative on unknown datasets, transport gated (zfs send/receive for whole datasets both ends, rsync agent-forwarded fast path), composition UTF-8-honest with typed refusal. **One committed line corrected: "rsync proxied" is not a command that exists — rsync refuses two remote endpoints. The proxy floor is a tar stream piped through the operator's machine, streaming, no temp storage, both halves visible in the plan. Every architectural commitment held; one tool name did not. For Checkpoint 2's eyes.** The forwarding fact is three-valued (available/unavailable/unprobed — unprobed proxies); ho-06 discovers it. Hand-verified command battery passed first run. 149 tests, PalanaCore 97.34%. Next: **ho-06 — The Transports** (split candidate: 06.1 rsync + progress, 06.2 zfs + fixture integration).
- **ho-08 closed 2026-07-04 — the workflow the project exists for is visible, and the practitioner has run it.** The plan panel composes in the open and renders the Plan whole exactly once; Enter enacts through the Transports with the echo live; the purpose-built `EchoBuffer` resolved deferred decision 7 against SwiftTerm — the smaller thing won and held. The engine grew what the session's questions exposed: the forwarding probe (promised by the system design, never built — verdict on stdout so ssh's 255 stays the door's, probed once, remembered), `rsyncDirect` and `tarStreamDirect` for this machine at either end, rsync gated on facts with tar as the floor everywhere, `--partial` on every compose, same-host copies riding rsync where the host carries it. The second UI/UX session ran six live rounds: arrows navigate and Enter alone opens, `r` removes, Esc hides where ⌃C cancels (the panel is a view, the work is the work), the pane verbs settled in the titlebar's own suggestion, the keys window became the chromeless card, Finder's selection manners layered over yazi's marks — and the session's best bug report ("is that weird?") found the BSD listing forking stat per entry, 3.5 seconds against 0.04 batched, fixed with byte-exactness intact. The practitioner set the role boundary mid-session: he is UI/UX and behavior, the engineering calls are the engineer's. Queued for their own hos or Checkpoint 3: create/rename (the engine needs a target name), favorites (host-bound + global), drag-and-drop composing the same plans, settings with verb-time overrides, transcript scroll-pinning, the host-onboarding surface. 280 tests, 52 suites, PalanaCore 97.9. **Next: ho-07.5 (BusyBox — zencat waits), then ho-09 (field view, third hands session), then Checkpoint 3 consolidates all three sessions' queues.**
- **ho-07.5 closed 2026-07-04 — zencat's userland has a name and a listing.** The probe grew a third tell (`busybox true` after GNU stat declines — a GNU host with busybox stays GNU), and the BusyBox listing is `ls -lan` under a one-round-trip date-precision ladder, because BusyBox flag sets turned out vendor-build-dependent: zencat's 1.25 has `-e`, Alpine's 1.37 has `--full-time` with a real timezone instead. Degradations named — numeric ids, approximate clocks, symlink arrows split at first ` -> `, unparseable lines refuse the whole listing. `treeSizes` answers no facts for BusyBox (no walkable find) and plans show ho-06.5's inode floor, flagged. Verified against real BusyBox via a bare Alpine container; both probe corpora re-recorded live. 292 tests, 53 suites, core 97.93. **Next: ho-09 (field view — dataset/mount indicators, explicit re-probe for zencat's stale flavor, third hands session), then Checkpoint 3.**
- **ho-09 closed 2026-07-04 — the map is summoned, consulted, dismissed, and the practitioner has consulted it.** `f` brings the topology card over dimmed panes — an in-window overlay, no second window — rendered from the cache in one hop: reachability aged by its own `discoveredAt`, flavor, zfs/rsync presence, dataset counts, remembered datasets under `l`, Enter pointing the focused pane, `r` re-probing one host in place. `FieldOutline` is a pure core value per ho-07's law; the pane wears a quiet ◆ where a row is exactly a remembered dataset mountpoint. The third UI/UX session proved the verbs in anger: `r` healed zencat's stale BSD to BusyBox in one keystroke, and the practitioner added chumon to the field by editing `~/.ssh/config` from the ▾ menu — edit, reload, probe, no code helping ("i love that that is the control"). Implementation ran delegated on claude-sonnet-4-6 across three dandori tasks; the session's review caught unrendered probe refusals, the missing scroll-follow, and a cancellation seam. At close the session found CI red since ho-08's first push — the rsync floor compose carried `-s`, which openrsync refuses, and under it the real incompatibility: modern rsync protects remote args by default, so no one compose serves an unknown local rsync. Errata: `rsyncDirect` asks for both binaries known (unknown falls to tar), modern keeps `-s`, the floor inner-quotes remote paths — both paths proven live, this Mac's 3.4.1 and the runner's openrsync. Sealed by the practitioner for Checkpoint 3: `# palana: hide` in ssh config as the host filter with a settings surface over it, settings in popped panels mirrored to Apple Settings, the host map grown from a mounts fact (all filesystems, not just ZFS), the titlebar `?` built as round 1 with a gear to follow. 323 tests, 58 suites, core 97.67. **Next: Checkpoint 3 — Phase 3 complete, v0.3 at the boundary, all three sessions' queues consolidate.**
- **CHECKPOINT 3 FIRED 2026-07-04 — Phase 3 complete, v0.3 tagged, the three sessions' queues consolidated into a proposed slate.** Post-close rounds landed first: the titlebar `?`, then the mouse joining the field (click moves the cursor, double-click points, the disclosure triangle turns a host down and back up, `l` toggles — his ll). The proposed insertion slate, forward-only, for the practitioner's ordering call: **ho-9.1 Rename and Create** (PlanRequest grows a target name — mv within a filesystem, the panel names when a rename is really copy-plus-delete; sealed by his word at the checkpoint), **ho-9.2 Settings** (pālana's popped panels mirrored to Apple Settings; the `# palana: hide` editor over ssh config comments; rsync flag defaults; verb-time overrides), **ho-9.3 The Mounts Fact and the Host Map** (the Field's third topology question — all filesystems, not just ZFS; the map surface decided in its Think phase), **ho-9.4 Favorites** (host-bound + global, favorites.json), **ho-9.5 Host Onboarding** (writes the Host block, walks key setup — full Think phase, it mutates the operator's ssh surface), **ho-9.6 Drag-and-Drop** (composing the same plans), **ho-9.7 Design Polish** (palette pruning, the NSMenu refit on his attributedTitle snippet, glyph pruning). Verification debts fold into whichever ho touches them: help-card cmd-swallow, echo coalescing at tar -v line rates, -A forwarding against a real two-host world, the mutating-directory listing refusal, transcript scroll-pinning. **Recommendation: 9.1 → 9.2 → 9.3 before ho-10 (small, sealed, operator-facing); 9.4 through 9.7 between the Workbench and the ship ho. The practitioner's ordering call decides.**
- **Checkpoint 3 slate amendment, same day — the columns ho.** Round-3 feedback while the checkpoint waited: the pane's columns want operator control — drag the edges to resize, choose which show (created, last changed, and the rest). Proposed as **ho-9.8 Columns**: table-side width and visibility control, and the listing grows the timestamps it doesn't gather yet (creation time is a new field on `FileEntry`, per-userland). The triangle also earned its size (round 3, in the tree). Rename and settings were read as missing from the app — they are 9.1 and 9.2, proposed, not built; the checkpoint's ordering call stands open.
