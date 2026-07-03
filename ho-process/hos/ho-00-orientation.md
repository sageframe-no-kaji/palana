---
created: 2026-07-03
status: complete
type: ho-document
project: palana
ho: 00
kamae: 5
shape: orientation
builds-on:
  - kamae-1-palana-seed
  - kamae-2-palana-system-design
  - README.md (kamae-3)
  - kamae-4-palana-ho-overview
---

# ho-00 — Orientation

The orientation ho. The scaffold was built before this ho was authored, so this session verifies it rather than creating it—the build, the tests, the lint stack, the pre-commit hooks, each proven by running it. The session also writes the four concept primers the build leans on and commits the project's ho shape conventions. Nothing user-facing exists at the end of this ho, and nothing needs to.

One adjustment the autonomous shape makes: the primers' reader is not the practitioner. It is the fresh session that opens each later ho—an agent arriving with no memory of this one. The primers are written for that reader: the mechanics that would otherwise be rediscovered by trial, stated once, with the traps named.

**Out of scope:** any product code. The spike is ho-01's.

---

## 1. Pre-conditions

Verified 2026-07-03, by command:

- `swift build` — clean. Two targets (PalanaCore library, Palana executable), Swift 6 language mode, StrictConcurrency enabled on both.
- `swift test` — 1 suite, 1 test, passed. The smoke test asserts PalanaCore exposes a version string. This is the whole suite at scaffold stage—the floor starts mattering when ho-02 puts real code under it.
- `swift-format lint --recursive --strict Sources Tests` — zero findings.
- `swiftlint lint --strict` — 3 files, zero violations.
- `pre-commit run --all-files` — all ten hooks pass: whitespace, EOF, yaml, large-files, merge-conflict, private-key, swift-format, swiftlint, swift build.

The upstream Kamae chain is committed and public: seed, system design (frozen—addenda only), README with GPL-3.0, ho overview. `prompts/` is gitignored and carries the ntfy topic. The encoded environment is real.

One gap, named: there is no CI workflow. The coverage floor is CI's job—too slow for pre-commit, too important to skip—and the scaffold does not carry it yet. It lands with ho-02, when PalanaCore first holds code worth covering. Gating coverage on a scaffold smoke test would enforce nothing. See Handoff.

---

## 2. New concepts

Four primers, ordered by first appearance in the build. Classification is for the session that opens the relevant ho:

- **Pick-up-in-flight** — the primer is enough. Open the ho, learn by doing.
- **Pre-read** — read the canonical page before opening the ho that touches it.

### Swift structured concurrency for process orchestration — *pick-up-in-flight* (ho-01, then everywhere)

Foundation `Process` predates async/await and has no async API of its own. The bridge is built by hand: `terminationHandler` wrapped in a continuation for completion, pipe output lifted into `AsyncStream` or read via `FileHandle.bytes` for streaming. The trap that costs an afternoon: pipe buffers are finite (~64KB). A child that writes more than that blocks on write until someone reads—so a `waitUntilExit` before both pipes are drained deadlocks on any chatty command. Drain stdout and stderr concurrently, in child tasks, before awaiting exit. Two more facts for strict concurrency: `Process` is not `Sendable`, so each process instance stays confined to one actor or task—the Conduit is the natural actor. And Task cancellation does not touch a child process; map cancellation to `terminate()` explicitly via `withTaskCancellationHandler`, or an abandoned ssh outlives the intent that spawned it.

Resource: [The Swift Programming Language — Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/), [Foundation `Process`](https://developer.apple.com/documentation/foundation/process).

### ControlMaster mechanics — *pre-read before ho-02* (ho-02)

SSH connection multiplexing. The first connection to a host establishes a master and binds a Unix domain socket at `ControlPath`; every later command to that host rides the socket, skipping key exchange and auth—per-command overhead drops from seconds to milliseconds. The Conduit's whole lifecycle maps onto three flags and two control commands: `-o ControlMaster=auto -o ControlPath=<path> -o ControlPersist=<duration>` to open-or-reuse, `ssh -O check <host>` to ask whether a master lives, `ssh -O exit <host>` to close it on quit. Two traps. Unix socket paths cap near 104 bytes on macOS—use the `%C` token (a hash of host, port, user) in a short directory, never a descriptive path. And agent forwarding is a property of the master, decided at creation: a master opened without `-A` will not forward for any session multiplexed over it later. The Conduit decides forwarding when it opens the door, not when a transport asks. pālana sets its own `ControlPath` so its sessions stay distinct from whatever multiplexing the operator's config already does.

Resource: [ssh_config(5)](https://man.openbsd.org/ssh_config.5) — ControlMaster, ControlPath, ControlPersist.

### `zfs send/receive` semantics — *pre-read before ho-06* (fixture at ho-02, enactment at ho-06)

Block-level dataset replication. The fact that shapes everything: send operates on snapshots, never on live datasets. A whole-dataset move is therefore a sequence, and the plan renders every step: `zfs snapshot pool/ds@palana-<stamp>`, then `zfs send pool/ds@palana-<stamp> | ssh <host> zfs receive pool2/ds`, then verify, then destroy the source dataset and the snapshot. Receive creates the target dataset and fails if it already exists—`-F` forces a rollback of an existing target and the Plan Engine never composes it by default. `zfs send -v` reports progress to stderr, one line per second, after first printing the estimated stream size. Non-root operation needs delegated permissions on both ends via `zfs allow`: send, snapshot, hold on the source—receive, create, mount on the destination—and mount is the one that fails surprisingly, since receiving a dataset tries to mount it. Incremental send (`-i`) exists and v1 does not use it: whole-dataset moves only.

Resource: [zfs-send(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html), [zfs-receive(8)](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-recv.8.html).

### rsync progress parsing — *pick-up-in-flight* (ho-06)

`--info=progress2` emits whole-transfer progress—bytes, percent, rate, elapsed—rather than per-file noise. Three facts the parser is built on. First, the channel: progress2 writes to rsync's stdout, and `zfs send -v` writes to stderr—since every remote command arrives through the Conduit's ssh streams, the Transports must know which stream each transport's progress rides. Second, the line discipline: progress updates are separated by carriage returns, not newlines—one screen line, redrawn. The parser splits on `\r` as well as `\n` or it sees one enormous line at the end. Third, the honesty problem: while rsync's incremental recursion is still scanning, the total is an estimate that grows, so the percent can stall or move backwards. `--no-inc-recursive` pays for a full scan upfront and buys a stable total—which is exactly what deferred decision 5's criterion demands: a bar that finishes at 100 when the transfer finishes, not before, not after. progress2 needs rsync ≥3.1 on the sending side. The Mac's ancient rsync never runs—transfers are host-to-host on the fleet—but ho-03's capability probe records remote rsync versions so the plan can say so when a host falls short.

Resource: [rsync(1)](https://download.samba.org/pub/rsync/rsync.1) — `--info=progress2`, `--no-inc-recursive`.

---

## 3. Project ho shape

The conventions every later session opens against. Committed here, once.

**Shapes.** Building hos (ho-01 through ho-11) are ha-shaped: Think resolves the ho's decisions, Execute does the work, Reflect fills in before the ho closes. Replan checkpoints (after ho-01, ho-06, ho-09) are orientation-shaped. Hos inserted from UI/UX findings take ri when the fix is already specified by the finding, ha when it is not. ho-01's Think phase is thin by design—its one decision resolves by measurement, not deliberation.

**Documents.** Per-ho documents live at `ho-process/hos/ho-NN-<slug>.md`, frontmatter per the Kamae 5 conventions, status `draft` until Reflect is filled, then `complete`. A ho's document is authored before its work begins—the spec is the authorization.

**Agent tasks.** When a ho's work has real seams, it decomposes into agent tasks at `ho-process/agent-tasks/Ho-NN-AT-MM.md`, dandori format, executed as child sessions with fresh context. When it does not—one bounded conversation—the ho document frames the session directly and no task ceremony is added. Every task names its model. This build is a single-model run: `claude-fable-5` for authoring, implementation, and verification alike, named per task regardless, so the field is a record and not a default.

**The autonomous adjustments.** Think phases run against the Kamae chain instead of a conversation. A question the chain answers is not a question. A question it does not answer and that reshapes architecture halts the session and surfaces to the practitioner over the ntfy channel—the agent does not silently make the call. Smaller calls inside the chain's bounds are made, named in the ho document, and moved past. After each ho closes, the ho overview gets its small update—progress, checkpoint outcomes, insertions—so the practitioner's one read stays current.

**Verification rhythm.** After every implementation, before every commit: `swift-format lint --recursive --strict Sources Tests`, `swiftlint lint --strict`, `swift build`, `swift test`. Coverage by `swift test --enable-code-coverage` + `xcrun llvm-cov report`, on demand and in CI, floor ≥90% on PalanaCore. Claims of green are transcripts, not sentences.

**Commits.** Atomic, message prefixed `ho-NN:`, present-tense summary. No AI attribution tags anywhere—categorical. Closed hos stay closed: new knowledge produces new hos, never retroactive edits.

---

## 4. Handoff

The next session opens **ho-01 — The Spike**, authored via the Kamae 5 collaborator, ha-shaped. What it needs at start: the structured-concurrency primer above, the overview's ho-01 entry, and the table-verdict criterion (deferred decision 1: 5,000 rows, no perceptible lag, on the practitioner's hardware).

Two things deferred to ho-01's authoring:

- **The spike's listing source.** The overview says one real directory listing. The hard limit bans mutation, not reading—but the recommendation is the localhost sshd fixture with a generated 5,000-entry tree: real SSH on the wire, exact control of row count, and no need to stand near the one line this build never crosses. ho-01's Think phase makes the call.
- **How "no perceptible lag" is measured.** Feel is the criterion and the practitioner's hands are not in this session—frame timing instrumentation plus recorded scroll/navigation captures is the likely evidence shape. ho-01 commits to one.

One item assigned forward: **CI arrives with ho-02.** A workflow running the verification stack plus the coverage floor, gating on PalanaCore's first real code. Named here so the gap is a decision, not an oversight.

Between sessions: nothing. The scaffold is green and the chain is current.

---

_Authored: 2026-07-03._
_Execution: verification transcript recorded in section 1 the same day. No code—orientation._
