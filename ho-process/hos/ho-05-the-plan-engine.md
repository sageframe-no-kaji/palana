---
created: 2026-07-03
status: draft
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

### Decision 4 — Transport selection: zfs for whole datasets, agent-forwarded rsync, proxy as floor

When both ends of a cross-host move/copy are whole datasets (source selection is exactly a dataset root, destination is a dataset) and both capabilities carry zfs, transport is `zfs send | ssh | zfs receive`. Otherwise rsync: agent-forwarded direct when the fact says available, proxied through the operator's machine when unavailable or unprobed. The operator never chooses—the plan names the path taken and why-shaped facts stay visible in the value.

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

*To be filled in after execution. Prompts:*

- **Did the fact table stay total?** Any cell the types let through unclassified?
- **The composed commands against hand-run truth.** Any command that surprised when pasted?
- **The forwarding fact.** Does `nil`-means-proxy hold up, or does ho-06 need a richer shape?
- **Followups for ho-06.**

---

_Authored: 2026-07-03 (Think phase)._
_Execution and Reflect: pending—next session opens here._
