---
created: 2026-07-06
type: agent-task
project: palana
parent-ho: 9.3
task: 03
model: claude-sonnet-4-6
status: ready
---

# Ho-9.3-AT-03 — Round 6: the log is one keystroke, the header is one target

**Goal**

Two hands-feedback items from the practitioner's round-6 notes, both in the app target only:

1. `⌘⇧L` points the focused pane at the operations log's directory (`~/Library/Application Support/palana/`) and lands the cursor on `operations.log`.
2. A click *anywhere* in a pane's address header focuses that pane — not only a click on the address text.

**Context**

Round 5 landed the operations log (`OperationLog.swift`, written to `~/Library/Application Support/palana/operations.log`). The practitioner wants to read it without hunting: one chord jumps the focused pane there with the cursor already seated on the file.

The pane already has the landing machinery rename/create uses: `PaneModel.setLandOn(_ name:)` stores a name, and the next `commit` seats the cursor on the row whose name matches (`PaneModel.swift` `commit`, lines ~315). `point(host:path:)` triggers the read that commits. `Engine.localHost` is this Mac; `OperationLog.defaultURL()` is the file's path. Set the landing *before* pointing — the read's commit consumes it — exactly as `onFinished` does in `PalanaSession` (`setLandOn` then refresh).

The app verbs that are not core `PaneIntent`s (`f`, `F`, backtick) are handled in `PalanaSession.handleMainSpecialKey` — string tokens, gated on `pendingPrefix.isEmpty`, reached only after the text-field stand-down guard (`handle`, line ~208). `⌘⇧L` is the same shape: app-target-only (the log path lives in the app target), so it does **not** join `Grammar.bindings` and does **not** add a `PaneIntent` case. `Grammar.token` already produces `"cmd-shift-l"` for the chord (cmd + shift + l → `"cmd-shift-l"`); verify by reading `Grammar.token`.

For the header: `PaneView.body` carries a body-level `.simultaneousGesture(TapGesture().onEnded { onFocus() })`, but it does not fire on the header's padding/spacer regions — only the address `Text` (which has its own `.onTapGesture { beginAddressEditing() }`) reacts. The fix makes the whole header rectangle a focus target while leaving the text's begin-editing tap intact.

Read before writing: `PalanaSession.swift` (`handle`, `handleMainSpecialKey`, the `f`/`F`/backtick precedent, `focusedPane`), `PaneModel.swift` (`setLandOn`, `point`, `commit`'s landOn consumption), `OperationLog.swift` (`defaultURL`), `Grammar.swift` (`token`, confirm the chord), `PaneView.swift` (`body`, `header`, `addressReadout`, `onFocus`).

**Files**

- Modify: `Sources/Palana/PalanaSession.swift` (the `cmd-shift-l` branch in `handleMainSpecialKey`, a `revealOperationsLog()` method)
- Modify: `Sources/Palana/PaneView.swift` (header becomes a focus target)

**Required Changes**

1. **`⌘⇧L` reveals the log.** In `PalanaSession.handleMainSpecialKey`, add a branch beside the `f`/`F`/backtick cases:

   ```swift
   if token == "cmd-shift-l" {
       revealOperationsLog()
       return true
   }
   ```

   And the method (place it near `beginNaming`/the pane verbs, with a DocC summary):

   ```swift
   /// ⌘⇧L: points the focused pane at the operations log's directory and
   /// seats the cursor on operations.log — the run record, one keystroke away.
   ///
   /// The log lives on this Mac. If no run has written it yet the file is
   /// absent, the landing simply misses, and the pane shows the directory —
   /// nothing is fabricated to make the cursor land.
   func revealOperationsLog() {
       let logURL = OperationLog.defaultURL()
       focusedPane.setLandOn(logURL.lastPathComponent)
       focusedPane.point(host: Engine.localHost, path: logURL.deletingLastPathComponent().path)
   }
   ```

   The text-field stand-down guard (`handle`, line ~208) already sits ahead of `handleMainSpecialKey`, so the chord will not fire while a path or naming field is being typed — correct.

2. **The header is one focus target.** In `PaneView.swift`, on the `header` computed property, after `.background(Theme.groundDeep)`, add:

   ```swift
   .contentShape(Rectangle())
   .simultaneousGesture(TapGesture().onEnded { onFocus() })
   ```

   `contentShape(Rectangle())` makes the whole header rectangle (padding and spacer included) hittable; `simultaneousGesture` fires `onFocus()` alongside — never instead of — the address text's `beginAddressEditing()` tap and the host menu button's own click. Leave `addressReadout`'s `.onTapGesture { beginAddressEditing() }` and the body-level gesture exactly as they are.

**Do Not**

- Do not add `⌘⇧L` to `Grammar.bindings` or a `PaneIntent` case — the log path is app-target knowledge; `f`/`F`/backtick are the precedent for app-only session verbs.
- Do not modify PalanaCore. This round is entirely in the app target.
- Do not create the log file or its directory to force a landing — if the file is absent the miss is correct.
- Do not replace the header text's begin-editing tap with focus, or swallow the host menu button — use `simultaneousGesture`, additive.
- Do not touch the plan panel, the field card, the host map, or any other round-5 surface.

**Stop Condition**

If `Grammar.token` does not in fact yield `"cmd-shift-l"` for the chord (read it and confirm before trusting this spec), or if the header focus gesture swallows the host menu button or the address text tap, stop and surface rather than reaching for a different event path.

**Acceptance**

- [ ] `swift build` clean
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift test` green — the full existing suite (425 tests / 71 suites), nothing skipped that ran before; **check the run line itself, not just the tail**
- [ ] Hands (practitioner drives): `⌘⇧L` jumps the focused pane to the palana app-support dir with the cursor on `operations.log`; a click anywhere in either header focuses that pane

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test 2>&1 | tail -20   # then read the run line, not just the tail
```

**Commit**

Single commit. Message format:

```
ho-9.3: round 6 — the log is a keystroke, the header a whole target

⌘⇧L points the focused pane at the operations log's directory and
seats the cursor on operations.log (app-target session verb, the
f/F/backtick precedent — no core intent). The address header focuses
its pane on a click anywhere in the strip, not only on the text.
```

No AI attribution tags, no Co-Authored-By — categorical.
