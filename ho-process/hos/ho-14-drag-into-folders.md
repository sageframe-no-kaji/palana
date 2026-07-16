---
created: 2026-07-15
status: ready
type: ho-document
project: palana
ho: 14
kamae: 5
shape: ha
phase: 6 — the v1 polish
builds-on:
  - ho-9.6-drag-and-drop
---

# ho-14 — Drag files into folders

Today a drop is **pane-level**: `.onDrop` on the whole pane surface
(`PaneView.swift`) resolves the destination to the pane's current directory. This
ho adds the obvious missing gesture: **drop onto a folder row → the files land
inside that folder**, not in the pane's cwd. It extends ho-9.6's `DropDecision`
machinery; it does not replace the pane-level drop.

**Out of scope:** dropping onto ZFS dataset rows (files pane only). Drag-out to
Finder (already shipped). Any change to the drag *source* side.

---

## Phase 1 — Think

### Decision 1 — Folder rows become drop targets
Each row whose `FileEntry` is a directory gets a row-level drop target
(`.dropDestination`/`.onDrop` on the row content) that resolves the destination to
**that folder's full path** (`pane.directory` + entry name), then runs the same
`onDropSelection` path ho-9.6 already uses — copy, or option-move — composing a
plan the operator reads before Enter. Non-directory rows and empty space are NOT
row targets; they fall through to the existing pane-level drop (pane cwd).

### Decision 2 — The hover affordance (design system §7)
While a valid drag hovers a folder row, the row shows the **accent selection wash**
(`accent @ 0.08–0.10`, radius per the list's row fill) — the same "this is where it
lands" language as the cursor row, so the target is unmistakable. No new color, no
box. The wash clears the instant the drag leaves or drops.

### Decision 3 — Self- and no-op drops refuse quietly
Dropping a selection onto a folder that is itself in the selection, or onto the
folder the files already live in, refuses the same way ho-9.6 already refuses
self-drops (no plan, no wash-stick). Reuse `DropDecision`'s existing refusal.

### Decision 4 — Precedence: row target beats pane target
When the pointer is over a folder row, the row's drop wins; the pane-level drop
only fires for drops that land off any folder row. The two `.onDrop`s must not
double-fire — the row consuming the drop prevents the pane handler from also
running (SwiftUI delivers to the innermost target; verify no double-plan).

---

## Phase 2 — Execute (ho-14-AT-01)

- Row-level drop target on directory rows in `PaneView.swift`, resolving the
  destination path to the folder and calling the ho-9.6 drop path with it.
- The accent hover wash on the hovered folder row; cleared on leave/drop.
- Self/no-op refusal reused from `DropDecision`.
- Confirm row-vs-pane precedence: no double-fire, no double-plan.

### Done means
- Dragging a selection onto a folder row plans the copy/option-move **into that
  folder**; dropping off any folder still targets the pane cwd (unchanged).
- The hovered folder row wears the accent wash; it clears cleanly.
- Self-drops and same-dir drops refuse quietly (no stuck wash, no plan).
- Tests: destination resolves to the folder path for a directory row vs the pane
  cwd for a fall-through; the self/no-op refusal.
- Verification rhythm green; PalanaCore coverage floor held (cover the
  destination-resolution logic in core/`DropDecision`; the row view is app-target).

---

## Phase 3 — Reflect
_Waits on execution and his hands (does the row target feel natural; is the wash
timing right; does precedence ever misfire on fast drags)._
