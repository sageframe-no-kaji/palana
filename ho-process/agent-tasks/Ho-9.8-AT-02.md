---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.8
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.8-AT-02 — The Surface: the columns, the customization, the star

**Goal**

The pane's table grows the six new columns behind a Finder-style header right-click: `tableColumnCustomization` for show/hide/resize, persisted to `columns.json`, the ★ column wired to favorites' truth, sort wiring for the new keys. Depends on AT-01.

**Context**

ho-9.8 Decisions 1, 4, 5, 6 govern (read `ho-process/hos/ho-9.8-columns.md`). Read:

- `Sources/Palana/PaneView.swift` (~lines 267–320) — the Table and its three columns, `sortOrder` → `PaneModel.applySort`. Note ho-9.6 may have converted the Table to the `rows:` form by the time you read it — read the tree as it stands.
- `Sources/PalanaCore/Surface/SessionStore.swift` + how `SessionSnapshot` persists — `columns.json` mirrors the store idiom (atomic write, silent-fail load), but the customization value is app-target state, so the store lives app-side (e.g. `Sources/Palana/ColumnStore.swift`).
- `Sources/Palana/FavoritesModel.swift` / `Sources/PalanaCore/Surface/FavoritesList.swift` — `isFavorited(host:path:)` and the toggle path `8` uses (find where starFocusedDirectory/starHighlightedEntry live, likely PalanaSession/FavoritesPanelNavigation) — the ★ click rides the same toggle, not a new one.

**Files**

- Modify: `Sources/Palana/PaneView.swift`
- Create: `Sources/Palana/ColumnStore.swift` (persistence) — keep PaneView's diff to columns and bindings
- Modify: wiring files only as needed (PalanaSession is over budget — extract, don't inflate)

**Required Changes**

1. **Columns** (Decision 1) — after name/size/modified: created, changed, permissions, owner, group, ★. Dates format like the modified column; nil renders as `—` in `Theme.inkFaint`. permissions/owner/group render the FileEntry strings mono-faithful. Every column gets `.customizationID`; name stays non-hideable (the platform supports marking it required — use it).

2. **Customization** (Decision 4) — `Table(..., columnCustomization: $customization)` bound per pane but stored ONCE (one customization serves both panes and the operator everywhere — share the binding). Persist via `ColumnStore` to `~/Library/Application Support/palana/columns.json`: encode on change (debounced or on scene phase change — pick the idiom session persistence already uses), silent-fail load at start. **Escape hatch, only if the platform value refuses Codable in practice:** persist an own-model `visibleColumns: [String]` + skip widths, and note the boundary in the report — do not invent a third mechanism.

3. **The star** (Decision 5) — ★ shows filled `star.fill` in `Theme.accent` on favorited directories, nothing on files and unfavorited rows (hover affordance is NOT required — Table row hover is a known dead end; the click target is the cell). Click toggles through the existing favorites toggle path with the pane's host and the row's full path. Column header is a star glyph, narrow fixed width.

4. **Sort** (Decision 6) — extend the `sortOrder` handling so every new column sorts through `PaneModel.applySort` with AT-01's SortKey comparators. Starred sort: if AT-01 left it app-side, the comparator asks favorites for each directory row — compute the starred set ONCE per sort, not per comparison.

**Battery**

App-target code carries no test target. Persistence encode/decode of whatever `ColumnStore` writes: if it's an own Codable shape, put that shape in core and test it; if it's the platform value, test load-of-corrupt-file silently fails by the store's construction (mirror how SessionStore handles it — if SessionStore's silent-fail is untested app-side precedent, keep the store thin and matching).

**Do Not**

- Do not build a custom picker UI — the header right-click is the picker.
- Do not add per-host column sets, reordering machinery, or type-to-jump.
- Do not let the ★ column create a second favorites registry — one toggle path.

**Acceptance**

- [ ] Header right-click shows/hides; widths and visibility survive relaunch (or the named escape hatch shipped and reported); ★ shows and toggles favorites; all columns sort, nils last.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

SourceKit phantom errors on app files: `swift build` is the type checker of record. Check the real test run line.

**Commit**

Do not commit. The session reviews and commits.
