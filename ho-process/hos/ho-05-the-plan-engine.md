---
created: 2026-07-03
status: complete
type: ho-document
project: palana
ho: 05
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-03-the-field
  - ho-04-the-listing
---

# ho-05 — The Plan Engine

The core abstraction. A pure function—(source state, destination state, requested operation) → Plan—carrying classification, transport selection, and command composition. It performs no I/O of its own, which makes it the most testable object in the system, and it had better be, because it is the part that must never lie. The full unit-test battery lands here: every classification, every transport choice, every composed command verified against hand-checked equivalents.

**Out of scope:** enactment. The Plan Engine composes and never runs—ho-06 runs. No wire, no Field held, no Conduit held. Facts arrive as values.

**Carries from ho-03/ho-04:** `datasetContaining` answers the boundary question. `FileEntry` selections are the manifest and `nameData` is the truth. `ShellQuote` embeds paths. The rsync version fact exists for ho-06's ≥3.1 check.

---

## Phase 1 — Think

### Decision 1 — The Plan is a value: header facts plus ordered steps

`Plan` carries what the panel renders and what the Transports run, nothing else: the operation, the classification, the entries with total size, both endpoints (host, path, dataset name where known), the transport with its named auth path, and `steps: [PlanStep]`. A step is `(host, command, role)`—role one of `transfer`, `copy`, `rename`, `delete`, with delete steps explicitly gated on count verification (the gate is declared in the Plan; enforcing it is ho-06's job). Plans are `Sendable`, `Equatable`, `Codable` values—the post-release queue is a list of them, and the battery compares them whole.

### Decision 2 — Facts arrive as a value, not a dependency

`plan(request:facts:)` takes a `PlanFacts` value: source dataset and destination dataset (as ho-03's boundary query answers them), each end's capability facts, and `agentForwardingAvailable: Bool?`—`nil` means unprobed. The engine holds no Field, same posture as the Listing's flavor parameter: the coupling lives at the call site, purity stays absolute, and the battery feeds facts by hand. Inter-host reachability probing does not exist yet—ho-06 discovers that fact and owns it; until then `nil` selects the proxy path, the conservative truth.

### Decision 3 — Classification is a total function over the fact table

- Same host, same dataset → **within-dataset rename**. One `mv` toward the destination directory.
- Same host, different datasets (either end's dataset unknown counts as different only if both are known and differ—unknown-vs-known classifies conservatively as cross-dataset) → **cross-dataset copy-plus-delete**: `cp -a` then gated delete. Never a bare `mv` wearing a rename's clothes—naming this landmine is the sentence the project exists to make true.
- Different hosts → **cross-host transfer**: rsync host-to-host, delete gated behind verification for moves.
- `copy` composes the same shapes minus delete. `delete` needs no destination and composes gated `rm`.

### Decision 4 — Transport selection: zfs for whole datasets, agent-forwarded rsync, tar stream as the proxy floor

When both ends of a cross-host move/copy are whole datasets (source selection is exactly a dataset root, destination directory is exactly a dataset's mountpoint) and both capabilities carry zfs, transport is `zfs send | ssh | zfs receive`—over the forwarded path when available, piped through the operator's machine when not. Otherwise: rsync agent-forwarded direct when the forwarding fact says available. When unavailable or unprobed, the proxy path is a **tar stream**, not rsync—rsync refuses two remote endpoints (`The source and destination cannot both be remote.`, verified), so "rsync proxied" as the overview's one-liner had it is not a command that exists. `ssh src 'tar -cf - …' | ssh dest 'tar -xpf - …'` streams through the operator's machine with no temp storage, both commands visible in the plan—every architectural commitment intact, one tool corrected. The operator never chooses—the plan names the path taken.

### Decision 5 — Composition refuses to lie: UTF-8 or refuse

Commands are Strings an operator could paste. Entry names compose through `ShellQuote` from the String face—and when `nameData` does not round-trip UTF-8, the engine throws `PlanError.unrepresentableName` instead of composing a command that names a different file. Byte-truth is preserved at the Listing; composition is UTF-8-honest in v1; a byte-exact composition path is a future ho if the fleet ever surfaces such a name. Sources compose as explicit per-entry arguments—paste-able, ARG_MAX is not a v1 concern at homelab selection sizes.

### Discovery (deferred to execution) — the exact command shapes

rsync flag set (`-a`, `--info=progress2` arrives with ho-06's parsing needs—the plan composes what enactment will run, so the flags commit here against ho-06's Think notes), trailing-slash semantics per classification, `zfs send -R` vs plain, and the hand-verified equivalents for the battery. Recorded pool truth from ho-03's transcripts seeds the dataset shapes.

---

## Phase 2 — Execute

One bounded conversation—no agent-task decomposition. Model: `claude-fable-5`. **Open this in a fresh session—the engine wants clean context.**

Order of work:

1. Plan, PlanStep, PlanRequest, PlanFacts, PlanError shapes—the values, with their battery.
2. Classification: the full fact table, unit-tested cell by cell including the conservative unknown-dataset rows.
3. Transport selection: the zfs whole-dataset gate, the forwarding fact's three states.
4. Command composition per classification × operation, every composed command string compared to a hand-verified equivalent. Hostile-name refusal battery.
5. End-to-end: plan values over ho-03's recorded pool topology and ho-04's recorded listings—facts from committed transcripts, Plans out, compared whole.
6. Full verification rhythm; floor holds; CI green.

### Done means

- Every classification produces the committed Plan shape and composed commands match hand-verified equivalents exactly.
- No I/O anywhere in the engine—facts in, Plan out.
- Non-UTF-8 names refuse composition, typed.

---

## Phase 3 — Reflect

**Did the fact table stay total?** Total by construction—Swift's exhaustive switches close every cell, and the battery walks them: proven-same-dataset renames, both orders of unknown-dataset conservatism, the three forwarding states, the zfs gate's four failure modes (no whole-dataset selection, no destination dataset, destination deeper than the mountpoint, either end missing zfs). The one cell the types allow but the routing forbids—a cross-host classification reaching the local composer—returns empty steps and is documented as unreachable rather than papered over with a fatalError.

**The composed commands against hand-run truth.** The whole battery of hand-verified strings passed on first run, which says the composition logic is as boring as it should be. The interesting command is the one that changed shape before it was ever composed: the proxy path. rsync refuses two remote endpoints—`The source and destination cannot both be remote.` is rsync's own sentence—so the overview's "rsync proxied" was corrected in this ho's Think phase to a tar stream: `ssh src 'tar -cf - -C dir -- entries' | ssh dest 'tar -xpf - -C dir'`, streaming through the operator's machine with no temp storage, both halves visible in the plan. Every architectural commitment held; one tool name did not. Flagged for Checkpoint 2. A second refinement earned its place: `ShellQuote` went smart—safe strings stay bare, so the common plan reads `mv /tank/media/a.txt /tank/other/` instead of a wall of quotes, and hostile names still get full armor. The plan panel's register is the reason.

**The forwarding fact.** `Bool?` did not survive contact with the linter, and the linter was right: `discouraged_optional_boolean` forced the question and the answer is `ForwardingFact`—available, unavailable, unprobed—which is exactly the richer shape the prompt anticipated. Unprobed selects the proxy path. ho-06 discovers the fact; the seam is ready.

**Followups for ho-06.** The Transports enact what this ho composed: the rsync flag set (`-a -s --info=progress2`) is committed and progress2 is the parse target. The tar proxy pipeline should be enacted in-process—two Conduit-spawned processes piped together—with pālana counting bytes for progress, since tar offers no progress2. The zfs step sequence (snapshot → send/receive → gated cleanups/destroys) declares gates the Transports must enforce: nothing gated runs before count verification. Also carried: `Plan.totalSize` counts directory entries at inode size—recursive sizing is a facts question for a later ho if the panel wants honest totals for directory selections.

---

_Authored: 2026-07-03 (Think phase). Executed and closed: 2026-07-03._
_149 tests, 29 suites. PalanaCore 97.34% line coverage against the 90% floor._
