---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.6
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.6-AT-02 — The Surface: drag sources, drop surface, the wash

**Goal**

Wire drag-and-drop into the app: rows drag a `DraggedSelection`, each pane is a drop surface for the selection type and for Finder file URLs, a valid hover wears an accent wash, and the drop routes through `DropDecision` into the standing plan path. Nothing enacts on a drop — the panel plus Enter stays the gate. Depends on AT-01.

**Context**

ho-9.6 Decisions 1–4 govern (read `ho-process/hos/ho-9.6-drag-and-drop.md`). Read:

- `Sources/Palana/PaneView.swift` (~lines 267–320) — the Table (data-collection initializer, three columns, context menu). Row drags likely need the `Table(of:selection:sortOrder:columns:rows:)` form with `TableRow(...).draggable(...)`, macOS 14 SDK. Verify against the SDK; if TableRow drag refuses multi-selection cleanly, drag the row under the pointer and expand to the selection when that row is selected (Done-means allows exactly that).
- `Sources/Palana/OperationModel.swift` `begin` (~line 105) — how a verb composes source/destination loci and subjects from panes. The drop composes the same shapes; a Finder drop's source locus is local (`PalanaCore.localHostName`) with the URLs' parent directory.
- `Sources/Palana/PaneModel.swift` — rows, selection, `state.host`/path. ho-9.9/9.10 have touched OperationModel by now — read the tree as it stands, not a cached idea of it.
- Theme tokens in `Sources/Palana/Theme.swift` — the wash is `Theme.accent` at low opacity plus a 2px accent border, matching the focus-bar voice.

**Files**

- Modify: `Sources/Palana/PaneView.swift` (drag/drop modifiers, the wash)
- Create: `Sources/Palana/DragDrop.swift` — Transferable conformance (custom `UTType`, e.g. `com.sageframe.palana.selection`, declared in code via `UTType(exportedAs:)`), URL-drop resolution helpers, and the glue that turns a decision into a `begin`-shaped call. Keep PaneView's diff thin.
- Modify: `Sources/Palana/PalanaSession.swift` or `Sources/Palana/OperationModel.swift` only for the entry point if the standing `begin(...)` can't serve; prefer reusing `begin` with the panes when the drop's source pane is live on screen (a pane-to-pane drag always is — resolve which PaneModel matches the payload's host+directory and hand `begin` the real panes).

**Required Changes**

1. **Drag out of a row** — dragging a row carries `DraggedSelection` (host, directory, the dragged row's name — or the whole selection when the row is selected). Byte names from the entries' `nameData`.

2. **Drop on a pane** — the pane container (not rows) accepts `DraggedSelection` first, `URL` second (`dropDestination` handles both registrations). On drop: `DropDecision.decide(payload:targetHost:targetDirectory:optionHeld: NSEvent.modifierFlags.contains(.option))`.
   - `.compose`: route into the standing plan path with the payload's entries resolved from the source pane's rows (pane-to-pane) — the panel arrives gathering→ready exactly as `y`/`m` produce.
   - `.refuseSamePlace` / `.refuseEmpty`: one transcript line (`drop refused — same location` / nothing for empty), no plan.

3. **Finder URLs** (Decision 4) — resolve dropped file URLs to their parent directory; if parents differ, keep the first parent's cohort and note what was left in the transcript. Entries come from the existing local listing call over that parent, filtered to the dropped names — never hand-built from FileManager attributes. Compose a copy plan (option = move) from local to the pane.

4. **The wash** — while a compatible drag hovers a pane that would accept it, the pane wears `Theme.accent.opacity(≈0.08)` ground plus a 2px accent inner border; gone on exit/drop. Use `dropDestination`'s `isTargeted` binding. No wash on the source pane for a drag that would refuse.

5. **The drop never enacts.** Assert by construction: the only mutation path out of this diff is the standing gather→ready→Enter machinery.

**Battery**

App-target code carries no test target — decision truth is AT-01's. If URL-parent resolution or cohort filtering grows logic, put it beside `DropDecision` in core and test it there (`DragDrop.swift` should read as wiring).

**Do Not**

- Do not implement drag-out to Finder (no file promises), row-targeted drops, or drops onto the favorites panel.
- Do not enact anything on drop, and do not add a confirmation dialog — the panel is the confirmation.
- Do not fight the Table for per-row hover effects — the wash is pane-level.

**Acceptance**

- [ ] Pane-to-pane drag composes copy (option: move) and the panel arrives ready; Finder drop composes local-source copy; self-drop refuses with one line; the wash tracks valid hovers.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

If converting the Table to the `rows:` form, keep the sort/selection/context-menu behavior byte-identical — the diff reviewer will check each. SourceKit phantom errors on app files: `swift build` is the type checker of record.

**Commit**

Do not commit. The session reviews and commits.
