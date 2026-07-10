---
created: 2026-07-10
status: open
type: ho-document
project: palana
ho: 9.9
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-05-the-plan-engine
  - ho-06.5-recursive-size-facts
  - ho-9.1-rename-and-create
agent-tasks:
  - Ho-9.9-AT-01.md
  - Ho-9.9-AT-02.md
---

# ho-9.9 — Collision Facts

A copy over an existing name enacts without the plan saying so. ho-9.1's Reflect named it plainly: an unnamed overwrite is a lie of omission by the panel's own law. The panel's whole claim is that the operator reads what will happen before Enter arms—and today the plan for `y` onto a directory that already holds `notes.txt` reads exactly like the plan for `y` onto one that doesn't. rsync and cp overwrite by default. The plan must say so, by name.

The sealed direction from the slate: the plan names what it will overwrite before Enter arms—a gathered fact line, never an are-you-sure dialog. There is no second confirmation to add. The panel plus Enter is already the gate; this ho makes the gate honest.

**Out of scope:** changing what the composes do—no `--ignore-existing`, no interactive `-i` flags, no behavior change of any kind; the facts describe, the operator decides. Recursive collision detection inside merged directories—the fact is one level deep by design; the plan names the merge, not every leaf it may replace. Create keeps its refusal (creating over a file is truncation wearing creation's name) and rename keeps its `test ! -e` guard—both already speak. A skip/overwrite choice UI—a future ho if his hands ask for it.

---

## Phase 1 — Think

### Decision 1 — A collision is a typed fact, computed pure, carried on the Plan

`Collision` lives in `PalanaCore` beside the plan vocabulary: the destination name it strikes, what stands there (kind, size, modified), and what arrives (kind). Detection is a pure function—`Collision.detect(sources:destinationListing:)`—comparing `nameData` bytes exactly, the way the listing already refuses to guess about names. The engine stays pure: the app gathers, the core computes, the facts arrive. Same shape as `recursiveSizes`.

The Plan carries a `CollisionReport`—the collisions plus a `gathered` flag—set by `plan()` for every destination-ful classification. Nil on plans with no destination. The report is Codable like the rest of the plan vocabulary.

### Decision 2 — The gather is one listing round trip, full fidelity on every userland

The destination pane's cached rows would be free and stale. Facts are gathered fresh per plan—the treeSizes precedent—so the gather reads the destination directory through the existing listing path, one round trip, and intersects names. The listing already speaks GNU, BSD, and BusyBox at known fidelity, so collision facts inherit every userland for free. No new remote vocabulary.

### Decision 3 — Three states, and silence only means clean

Collisions found—the line renders in alarm: what it replaces, what it merges into. Gathered and clean—no line; silence is licensed because the third state is loud. Ungathered—the destination listing failed, and the line says so in alarm: what this replaces is unknown. The `totalSizeComplete` law again: a floor is never silent.

### Decision 4 — The line distinguishes replace, merge, and kind clash

A file arriving on a file replaces it. A directory arriving on a directory merges into it—rsync and cp -a both merge, and "replaces" would be a lie in the other direction. A file arriving where a directory stands (or the reverse) is a kind clash, named plainly—the tool will refuse it at enact, and the plan may as well say why before the operator finds out. The sentence composer lives in core—`CollisionReport.sentence()`—tested as strings, capped enumeration with an honest "and N more," so the panel stays a painter.

### Decision 5 — Every destination-ful operation gathers, whatever the transport

Copy, move, and the seam verbs all carry a destination directory, so all of them gather. The zfs-classified transfers keep their dataset-existence gate—these facts are file-level truth and don't replace it—but the listing intersection doesn't lie under any transport, so no exclusion is carved. Rename, create, touch, delete, and the zfs mutations carry no destination directory and no report.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.9-AT-01 — The engine: Collision, the detect, the report on the Plan

`Collision`, `Collision.detect`, `CollisionReport` with its sentence composer, `PlanFacts.collisions`, the carry-through in `plan()`, full unit battery. → `ho-process/agent-tasks/Ho-9.9-AT-01.md`

### Ho-9.9-AT-02 — The Surface: the gather and the line

The destination-listing fetch in `OperationModel.gather`, the detect call, the ungathered fallback that names itself, the collision line in `PlanPanel`. → `ho-process/agent-tasks/Ho-9.9-AT-02.md`

### Done means

- A copy or move onto colliding names shows an alarm line naming replaces, merges, and kind clashes before Enter arms
- A clean destination shows nothing; an unreadable one says the collisions are unknown—never silent
- Byte-exact name comparison; one-level-deep by design
- No compose changes anywhere—the diff of composed commands is empty
- Verification rhythm green, PalanaCore coverage floor holds

---

## Phase 3 — Reflect

_Filled at close._

---

_Authored: 2026-07-10 (Think phase). Queued from ho-9.1's Reflect—the third finding named this ho's reason._
