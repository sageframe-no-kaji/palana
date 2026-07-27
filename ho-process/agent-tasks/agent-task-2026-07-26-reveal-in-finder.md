---
created: 2026-07-26
type: agent-task
status: complete
project: palana
---

**Goal**

Add an "open in Finder" item to the pane rows' context menu, on local panes
only: clicked rows are revealed (selected) in a Finder window; a right-click
on empty pane space opens the pane's current directory in Finder. Menu-only —
no new keyboard verb.

**Context**

Practitioner request, 2026-07-26; standalone, no parent ho. pālana already
treats the Mac as first-class (drag out, open-in-its-app), and this is the
matching escape hatch toward Finder. Precedents to build on, not reinvent:
the context menu lives in `contextMenuItems(for:)` (`PaneView.swift:543`,
attached at `:496`); the app target already opens things via
`NSWorkspace` (`PaneModel.swift:648`); locality and host resolution are
visible in `dragPayload` (`model.state.host ?? PalanaCore.localHostName`) and
in the local file-open path near `PaneModel.swift:648` — reuse whatever test
that path uses to decide a file is local, do not invent a second one.

**Files**

- Modify: `Sources/Palana/PaneModel.swift` (target-resolution helper + the
  `NSWorkspace` call)
- Modify: `Sources/Palana/PaneView.swift` (the menu item)
- Modify or Create: a test file in `Tests/PalanaTests/` per that target's
  existing conventions (create `PaneRevealTests.swift` only if no natural
  home exists)

**Required Changes**

1. **Target-resolution helper on `PaneModel`** — a pure, testable function
   that maps a right-click to the paths to reveal. Selection manners match
   `operate()` and `dragPayload` exactly: a clicked row inside the selection
   resolves to the whole selection; a clicked row outside it resolves to that
   row alone; an empty `ids` set resolves to the pane's current directory.
   Path joining uses the same byte-accurate name handling the pane already
   uses (`childPath`/`nameData` conventions), not ad-hoc string concatenation.

2. **`revealInFinder(ids:)` on `PaneModel`** — guards on the existing
   locality test, resolves targets via (1), then: entry targets →
   `NSWorkspace.shared.activateFileViewerSelecting(_:)` with the file URLs;
   the directory-itself case → `NSWorkspace.shared.open(_:)` on the
   directory URL. The method stays thin; the logic lives in (1).

3. **Menu item in `contextMenuItems(for:)`** — labeled `open in Finder`
   (lowercase style matches the menu's existing items), placed directly
   under "open / enter", before the first `Divider`. On remote panes the
   item is absent entirely — same `EmptyView` pattern as
   `starContextItem(for:)` — not disabled-with-reason.

4. **Tests** for the helper in `Tests/PalanaTests/`: clicked-inside-selection
   → whole selection; clicked-outside-selection → single row; empty ids →
   directory case; joined paths are byte-accurate for a non-ASCII name.

**Acceptance**

- [ ] `open in Finder` appears in `contextMenuItems` gated on the pane's
      locality, positioned under "open / enter"
- [ ] The helper's unit tests pass, covering the four cases above
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift build` and `swift test` pass
- [ ] The diff touches only the Palana app target and `Tests/PalanaTests/` —
      no PalanaCore changes

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test

# The item exists and sits in the menu builder
grep -n "open in Finder" Sources/Palana/PaneView.swift

# Surface-only diff
git diff --stat
```

**Do Not**

- Do not add a keyboard shortcut. The key grammar is a designed surface
  (five rules, lowercase verbs open plans); this action is menu-only until a
  ho decides otherwise.
- Do not offer any remote-pane variant (no mounted-share cleverness, no
  disabled item with an explanation). Absent is the behavior.
- Do not touch PalanaCore. Opening Finder is Surface-side Mac integration,
  like opening a file in its app.

**Stop Condition**

If the locality test can't be reused cleanly at the menu layer, or if
byte-accurate entry names can't round-trip into `URL(fileURLWithPath:)`
without loss for non-UTF8 names, stop and surface findings — don't invent a
second locality test or a lossy conversion.

**Commit**

Single commit, repo message style (lowercase summary line, no attribution
trailers):

```
context menu: open in Finder on local panes

Reveal clicked rows in Finder (selection manners match operate());
empty-space click opens the pane's directory. Absent on remote panes.
```
