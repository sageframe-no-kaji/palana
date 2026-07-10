---
created: 2026-07-10
status: executed — hands verdicts pending
type: ho-document
project: palana
ho: 9.6
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-07-the-surface-panes
  - ho-08-the-surface-plan-and-enact
agent-tasks:
  - Ho-9.6-AT-01.md
  - Ho-9.6-AT-02.md
---

# ho-9.6 — Drag-and-Drop

The grammar sends with `y` and `m`. The mouse should send too—the design language promised Mac muscle memory beside the vim keys, and dragging a file from one pane to the other is the oldest Mac muscle there is. The sealed direction from the slate: drag-and-drop composes the same plans. A drop is a verb, not an act—the panel arrives with the plan whole, the operator reads it, Enter enacts. Nothing moves on the drop itself. The gate law doesn't bend for the mouse.

**Out of scope:** dragging out to Finder or other apps—remote files would need materializing through file promises, a real machine of its own; deferred, named. Row-targeted drops (into a subfolder under the pointer)—SwiftUI's Table already lost the per-row hover fight in ho-10; the drop targets the pane's directory, whole. Drag-reordering, drag-to-favorites (ho-9.4 named it for this ho, but the favorites column earns it later—dropping onto a floating panel is its own wiring). Spring-loaded descend during hover.

---

## Phase 1 — Think

### Decision 1 — The payload is a typed selection, not paths pretending to be files

`DraggedSelection` in `PalanaCore`: source host, source directory, entry names as bytes. Codable—it crosses the drag pasteboard as data. A pane-to-pane drag never pretends the remote entries are local files; it carries the address of a selection, and the drop composes a plan from it exactly as `y` would. The app target conforms it to Transferable (the SwiftUI drag currency) with a custom content type—declared plain per the ho-07 finding on same-package retroactive conformances.

### Decision 2 — A drop composes copy; option composes move

Finder's muscle: plain drag copies across volumes, option forces copy within one. pālana simplifies to one legible rule—a plain drop composes a copy plan, an option-drop composes a move plan—and the panel names the verb either way before anything runs. The panel is where the choice gets read; a wrong modifier costs an Esc, never a file. Verb-time re-choice in the panel (his queued y/m alternates idea) waits for the hands session's word.

### Decision 3 — The drop targets the pane, and self-drops refuse quietly

The whole destination pane is the drop surface, wearing an accent-wash affordance while a drag hovers. The drop composes into that pane's current directory. A drop onto the pane it came from—same host, same directory—composes nothing and says why in one transcript line. The engine's own guards keep every other refusal they already own.

### Decision 4 — Finder drags in; pālana drags out later

File URLs dropped from Finder onto a pane compose a copy plan from this machine—the entries resolved through the local listing of their parent directory, byte-honest, never hand-built from FileManager attributes. One parent per drop in v1: a Finder multi-selection drags from one directory anyway; a mixed-parent drop takes its first parent's cohort and names what it left. Dragging out stays out of scope until file promises earn a ho.

### Decision 5 — The decision logic is core; the wiring is thin

Given a payload, a target, and the modifier, what happens—copy, move, refuse-same-place—is a pure function in `PalanaCore`, tested. The app target owns only Transferable, the drag sources, the drop destination, and the wash.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.6-AT-01 — The engine: the payload and the drop decision

`DraggedSelection`, `DropDecision.decide(payload:target:optionHeld:)`, unit battery. → `ho-process/agent-tasks/Ho-9.6-AT-01.md`

### Ho-9.6-AT-02 — The Surface: drag sources, drop surface, the wash

Transferable conformance, row drag from the Table, pane-level drop destination for both the selection type and Finder URLs, the hover wash, composition through the standing begin/gather path. → `ho-process/agent-tasks/Ho-9.6-AT-02.md`

### Done means

- A row drag carries the selection (multi-selection included when the drag starts on a selected row); the opposite pane accepts it and the panel arrives with a copy plan; option at drop makes it a move plan; Enter enacts, Esc declines
- A Finder drop composes a local-source copy plan the same way
- Self-drops refuse with one spoken line; nothing enacts on any drop without Enter
- The destination pane wears the wash only while a valid drag hovers
- Verification rhythm green, PalanaCore coverage floor holds

---

## Phase 3 — Reflect

**The Table gave up its data-collection form for the drag, and the conversion held.** Per-row `.draggable` demanded the `rows:` builder; columns, sort, selection, and the context menu came through byte-identical by the diff. The payload expands to the whole selection when the dragged row is in it—Finder's manners—with the selection's names gathered once per render, because the agent's per-row filter was O(n²) against the cadence law and the review caught it.

**A drop that can't resolve its names refuses.** The review's second catch: when the dragged names no longer stand in the source pane (rows changed between drag and drop), the routing fell through to `begin` with the pane's stale cursor and selection—a plan for entries nobody dragged, saved only by the gate. It refuses with one spoken line now.

**The gate law needed no defending.** Every drop path funnels into the standing gather—the panel arrives ready, Enter enacts, and there was no temptation anywhere in the diff to shortcut it. The engine half (payload + pure decision) went in without a single deviation.

**Hands verdicts pending:** the wash's weight, the option-for-move muscle, whether the panel arriving on a drop feels like the right ceremony or wants a quieter form, and the Finder-drop cohort rule against a real mixed drag.

---

_Authored: 2026-07-10 (Think phase). Executed same day—two agent tasks on claude-sonnet-4-6, reviewed by the session. Sixth on the Checkpoint 3 slate—the mouse learns the verbs the keys already know._
