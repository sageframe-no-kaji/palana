---
created: 2026-07-04
type: agent-task
project: palana
parent-ho: 9.1
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.1-AT-02 — The Surface: R, a, and the naming field

**Goal**

Wire rename and create into the Surface: `R` renames the cursor entry, `a` creates (trailing slash = directory), both through a new `naming` phase in the plan panel with a one-line text field, the key monitor standing down while it is live. Depends on Ho-9.1-AT-01 being in the tree.

**Context**

ho-9.1 Decisions 3–5 govern (read `ho-process/hos/ho-9.1-rename-and-create.md`). Read before writing: `Sources/Palana/Grammar.swift` (binding table — bare keys keep case, `G` is the precedent for a capital verb), `Sources/Palana/OperationModel.swift` whole (the phase machine, `beginOperation`, how gather builds the `PlanRequest`, `panelShowing`), `Sources/Palana/PlanPanel.swift` (where the field renders), `Sources/Palana/PalanaSession.swift` (`handle(_:)` — how `pathEditing` stands the monitor down, how `handlePanelKey` routes), `Sources/Palana/PaneModel.swift` (`landOn`, `operationSubjects`, cursor entry).

**Files**

- Modify: `Sources/Palana/Grammar.swift` (two rows: `["R"]`, `["a"]` — read how `PaneIntent` cases arrive from core first; if `PaneIntent` needs new cases, that lives in `Sources/PalanaCore/Surface/PaneIntent.swift` and its transitions must stay total)
- Modify: `Sources/PalanaCore/Surface/PaneIntent.swift` (new intents `operationRename`, `operationCreate` — follow how the existing operation intents are declared and routed)
- Modify: `Sources/Palana/OperationModel.swift` (the `naming` phase and the flow into gather)
- Modify: `Sources/Palana/PlanPanel.swift` (the name field)
- Modify: `Sources/Palana/PalanaSession.swift` (monitor stand-down while naming, intent routing)
- Modify: `Sources/Palana/PaneModel.swift` (only if landOn needs a hook it doesn't have)
- Modify: `Sources/Palana/HelpOverlay.swift` (vocabulary rows for `R` and `a`)

**Required Changes**

1. **Grammar and intents.** `["R"]` → rename (cursor entry — exactly one subject, the cursor, not the selection), `["a"]` → create. Route them wherever the existing operation verbs (`y`/`m`/`r`) are routed from the session to the operation model.

2. **The `naming` phase.** New phase before `gathering`. `beginOperation`-equivalent entry point takes the operation kind and, for rename, the cursor entry. The panel shows: a short label ("rename" with the old name, or "create — trailing / makes a directory"), the text field (prefilled + fully selected for rename via `selectAll`; empty for create), and nothing else — the plan renders only after the name commits.

3. **Monitor stand-down.** While `naming` is live, `handle(_:)` releases every key to the field exactly as `pathEditing` does (read that guard and mirror it — a flag on `OperationModel` the session checks). Esc cancels through the field's exit (`onExitCommand`), dismissing the panel to idle. Enter commits through `onSubmit`. An empty or unchanged (rename) name on commit dismisses quietly — ho-9.1 Decision 4.

4. **Commit → plan.** On name commit, build the `PlanRequest` with `operation: .rename` (single cursor entry) or `.create` (empty entries), `targetName` set (trailing slash preserved for create — the engine reads it), source = the focused pane's locus, destination nil. Flow into the existing gather → plan-whole → Enter-arms machinery unchanged. The guard compose renders in the panel like every command — no special casing.

5. **Cursor lands on the result.** On `finished` for a rename, set the focused pane's `landOn` to the new name before the refresh so the cursor follows the renamed entry (read how `ascend()` uses `landOn` — same mechanism). For create, land on the created name likewise.

6. **The `?` card** gains `R rename` and `a create (name/ = directory)` rows in the fitting group.

**Do Not**

- Do not add a rename affordance outside the panel law (no inline edit-in-table — mutations go through plan-and-Enter, kamae-2).
- Do not let `R` act on a multi-selection — the cursor entry is the subject, always.
- Do not build filename validation beyond what the engine refuses — the engine is the truth, the Surface relays its refusal.

**Acceptance**

- [ ] `R` on the cursor entry opens the panel naming, prefilled and selected; Enter shows the guard-compose plan; Enter enacts; the cursor lands on the new name after refresh.
- [ ] `a` then `name` creates a file; `a` then `name/` creates a directory — proven live against the sshd fixture and on local.
- [ ] Esc in naming dismisses to idle; typed letters never leak to the grammar while naming.
- [ ] A rename to an existing name runs, refuses at the guard (exit 1), and the panel shows the failure typed — nothing moved.
- [ ] `swift-format lint --recursive --strict Sources Tests`, `swiftlint lint --strict`, `swift build`, `swift test` all green (check the run line).

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
# Live walk (fixture up):
scripts/sshd-fixture.sh start
PALANA_SSH_CONFIG=.fixtures/ssh_config swift run Palana
# R on an entry → rename · a → file · a name/ → dir · rename onto existing name → refused
```

The live walk is manual; quit the app when done — the session re-walks it.

**Commit**

Do not commit. The session reviews and commits.
