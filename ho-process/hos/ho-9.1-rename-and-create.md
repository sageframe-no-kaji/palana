---
created: 2026-07-04
status: complete
type: ho-document
project: palana
ho: 9.1
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-05-the-plan-engine
  - ho-08-the-surface-plan-and-enact
  - ho-09-the-surface-field-view
agent-tasks:
  - Ho-9.1-AT-01.md
  - Ho-9.1-AT-02.md
---

# ho-9.1 — Rename and Create

The two verbs every file surface owes its operator, arriving late because the engine was honest about not having them: `PlanRequest` carries a destination directory and no target name, so ho-08 held rename out of scope and queued it. This ho grows the name. Rename works with `mv`, as the practitioner said—and it rides the same law as every mutation: the panel shows the exact command, Enter runs it, nothing else does. Create is the same shape with nothing to start from. First on the Checkpoint 3 slate by his word.

**Out of scope:** cross-directory and cross-host rename—a rename that moves is a move wearing a rename's clothes, and the move verbs already exist. Overwrite-on-rename—the compose refuses an existing destination, always. Names with path separators—the target is a bare name in the pane's own directory (create's one exception: a trailing slash means directory, yazi's grammar). Undo. Batch rename.

**Resolves deferred decisions:** none from the overview—this ho was born at Checkpoint 3.

---

## Phase 1 — Think

### Decision 1 — The engine grows a name, two operations, one classification

`PlanRequest` gains `targetName: String?`, defaulted nil so every existing call site stands. `PlanOperation` gains `.rename` and `.create`. `Classification` gains `.creation`—rename already has its name in the committed vocabulary (`withinDatasetRename`, ho-05), and the engine finally composes it. Both transport as `.local`: one host, no transfer, no gathering beyond what the pane already knows.

### Decision 2 — The composes are portable guards, not vendor flags

`mv -n` would be the obvious refusal, but BusyBox flag sets are vendor-build-dependent—ho-07.5's lesson, not relearned. The composes are POSIX and identical on all three userlands:

- rename: `test ! -e '<dir>/<new>' && mv -- '<dir>/<old>' '<dir>/<new>'`—an existing destination exits 1 and nothing moves
- create directory: `mkdir -- '<dir>/<name>'`—mkdir refuses an existing name natively, loudly
- create file: `test ! -e '<dir>/<name>' && touch -- '<dir>/<name>'`

Verification rides the same truth: rename verifies `test -e new && test ! -e old`, create verifies existence of the right kind (`test -d` / `test -f`). ShellQuote everywhere a name touches a command.

### Decision 3 — `R` renames, `a` creates, yazi's trailing slash decides

yazi spends `r` on rename, but pālana's `r` is remove (ho-08, his hands). The capital sibling takes it: `R` renames the cursor entry—bare keys keep their case in the grammar, `G` is the precedent. `a` creates, empty field, and yazi's grammar is kept whole: a trailing `/` makes a directory, no slash makes a file. Finder's Enter-renames stays rejected—Enter opens, settled in the second hands session.

### Decision 4 — The panel gains its first text input, on the pathEditing precedent

A new phase, `naming`, ahead of `gathering`: `R` or `a` opens the panel with a one-line name field—prefilled and fully selected for rename, empty for create. While the field is live the key monitor stands down entirely, exactly as `pathEditing` does—typed letters belong to the field, Esc cancels through the field's own exit, Enter commits the name and the flow rejoins the panel's law: gather (trivial here), the Plan whole, Enter arms, Enter enacts. An empty or unchanged name on commit dismisses quietly—nothing to plan.

### Decision 5 — After the rename, the cursor stays on the thing

`finished` already refreshes both panes. Rename additionally lands the cursor on the new name through the pane's existing `landOn` mechanism—the operator renamed a thing, the thing stays under their finger.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.1-AT-01 — The engine: targetName, rename, create

`PlanRequest.targetName`, the two operations, `.creation`, guard composes, verification, full battery. → `ho-process/agent-tasks/Ho-9.1-AT-01.md`

### Ho-9.1-AT-02 — The Surface: R, a, and the naming field

Grammar rows, the `naming` phase, the panel's field, monitor stand-down, landOn. → `ho-process/agent-tasks/Ho-9.1-AT-02.md`

### Done means

- `R` on an entry renames it in place through the panel—guard shown, refused when the name exists, cursor lands on the result
- `a` creates a file, `a` with a trailing slash creates a directory, in the focused pane's directory
- The composes are identical on GNU, BSD, and BusyBox—proven by the battery, and live against the fixture
- Verification rhythm green, coverage floor holds

---

## Phase 3 — Reflect

**The naming field didn't fight the monitor.** The pathEditing precedent held—one flag beside it, letters reach the field, Esc cancels through the field's own exit. The panel's first text input cost less than feared.

**The guard did not read legibly, and his hands said so.** A refused create surfaced as a bare exit 1—fixed in the errata: the guard carries its own sentence, `refused: <path> exists` on stderr, and the panel shows it typed.

**His hands found what no battery could: the open path ate an edit.** Not this ho's code—ho-07's open verb fetched every file, local included, into one shared temp path, and a re-open destroyed the edited copy. The worst kind of failure: silent, data-losing, wearing correct behavior's clothes. Errata in the tree: local files open in place, remote opens get a fresh directory per open. Remote round-trip editing queued as ho-9.10.

**The third finding named the next ho's reason.** A copy over an existing name enacts without the plan saying so—an unnamed overwrite is a lie of omission by the panel's own law. ho-9.9 Collision Facts queued: the plan states what it will overwrite, a gathered fact line, never a dialog. And create keeps its refusal—creating over a file is truncation wearing creation's name.

---

_Authored: 2026-07-04 (Think phase). Executed same day—two agent tasks on claude-sonnet-4-6, reviewed by the session._
_Errata and Reflect: 2026-07-05, from the practitioner's hands. 345 tests, 61 suites, CI green._
