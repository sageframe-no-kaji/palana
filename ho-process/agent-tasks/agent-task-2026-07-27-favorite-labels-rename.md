---
created: 2026-07-27
type: agent-task
status: complete
project: palana
---

**Goal**

A favorite can carry an operator-given label, editable by keyboard and
mouse: `r` on the focused row opens an inline name field, a second single
click on a focused row's name does the same (Finder's rename gesture), and
a row context menu offers `rename…`. The label displays in place of the raw
path everywhere favorites render, with the path still discoverable. Clearing
the label returns the row to path display. Renames are undoable with the
panel's existing ⌘Z.

**Problem**

Starred paths render as raw paths. A deep location — observed in the field:
`…s@gmail.com/My Drive/Job Search/2026` — truncates into an unreadable tail
in the panel. The path is the favorite's identity, but it's a poor display
name for exactly the locations worth starring.

**Context**

Favorites are app-side state in `favorites.json` — no host contact, no plan
gate; a label edit is the same class of act as starring itself.
`FavoritesModel` (`Sources/Palana/FavoritesModel.swift`) already has the
`snapshot()`/`undo()` machinery and `setScope(id:_:)` is the shape a label
setter follows. `r` is the app-wide rename letter (pane verb, ZFS-mode verb),
so the panel's vocabulary stays consistent. Panel affordances and footer
live in `FavoritesPanel.swift` / `FavoritesPanelNavigation.swift`.

**Files**

- Modify: the `Favorite` record (wherever it's declared — follow
  `FavoritesModel`'s imports): optional `label` field
- Modify: `Sources/Palana/FavoritesModel.swift` (`setLabel(id:label:)`)
- Modify: `Sources/Palana/FavoritesPanel.swift` and
  `FavoritesPanelNavigation.swift` (the `r` key, the inline field, display
  rule, footer hint)
- Modify: any other surface that renders favorites (the pane header's ▾
  host menu at minimum — `HostMenuButton.swift`) to prefer the label
- Modify/Create: tests in `Tests/PalanaTests/` per that target's conventions

**Required Changes**

1. **`label: String?` on `Favorite`** — Codable-compatible with existing
   `favorites.json` files: a file written before this change decodes with
   nil labels; a file written after decodes in a build before this change
   only if the decoder tolerates unknown keys (it does — note it in a test,
   not a comment).

2. **`setLabel(id:label:)` on `FavoritesModel`** — snapshot, mutate,
   persist, exactly the `setScope` rhythm. A nil, empty, or
   whitespace-only label stores nil (clears). No uniqueness rule — host +
   path is the identity; labels are display.

3. **The `r` key in the favorites panel** — opens an inline name field on
   the focused row, prefilled with the current label (empty when none);
   ⏎ commits, esc cancels, following the app's existing inline-field
   pattern. The panel footer — its own manual — gains `r rename`.

4. **The mouse routes to the same field.** (a) Finder's gesture: a single
   click on the name text of a row that is *already focused* begins the
   edit — armed only after the system double-click interval has passed, so
   a genuine double-click still jumps to the location, and a click that
   focuses a row never edits. (b) A context menu on panel rows — matching
   the pane rows' menu style — with `rename…`, `unstar`, and the
   promote/demote scope toggle: existing model operations only, the menu is
   glue. All three routes (key, click, menu) open the one inline field.

5. **Display rule** — label when present, path when not; the full
   `host:path` stays discoverable on a labeled row (tooltip or secondary
   text, per the panel's existing conventions). The rule applies everywhere
   favorites render: the panel and the ▾ host menu. If the panel type-finds
   or sorts by name, the label is the name it uses.

6. **Tests**: old-json decode (nil labels); set → persist → reload
   round-trip; clear-on-empty; undo restores the prior label; display rule
   prefers label. The click-to-rename arming logic (focused-row +
   double-click-interval guard) lives in a testable helper, not inline in
   the gesture handler.

**Acceptance**

- [ ] `r` in the favorites panel renames the focused favorite; esc cancels;
      ⌘Z undoes (app-target tests for model + persistence)
- [ ] A second single click on a focused row's name begins the edit; a
      double-click still jumps (arming-logic tests cover both)
- [ ] The row context menu offers rename…/unstar/scope toggle, all backed
      by existing model operations
- [ ] A pre-existing `favorites.json` without labels loads unchanged
      (compatibility test)
- [ ] Labeled favorites show the label in the panel and the ▾ menu; the
      path remains discoverable
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift build` and `swift test` pass

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test

# The setter and the key exist
grep -n "setLabel" Sources/Palana/FavoritesModel.swift
grep -rn "r rename" Sources/Palana | head
```

**Do Not**

- Do not gate label edits behind a plan — favorites are app state, not host
  mutations; the plan gate is for hosts.
- Do not enforce label uniqueness or validate label content beyond
  whitespace-trimming — display names, not identities.
- Do not touch promotion/scope semantics (host-bound vs global) beyond
  carrying the label through them unchanged.

**Commit**

Single commit, repo message style (lowercase summary, no attribution
trailers):

```
favorites: r renames a star — labels display over raw paths

Optional label on Favorite, set/clear via the panel's inline field,
undoable, shown wherever favorites render; path stays the identity.
```
