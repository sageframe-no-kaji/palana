---
created: 2026-07-08
type: agent-task
project: palana
parent-ho: 9.4
task: 02
model: claude-sonnet-4-6
status: ready
depends-on: Ho-9.4-AT-01
---

# Ho-9.4-AT-02 — The Surface: the star, the model, the host-menu section

**Goal**

Wire favorites into the app: an `@Observable` `FavoritesModel` over the AT-01 store, a star toggle in the address bar, a favorites section in the host menu, point-at-favorite, and scope promotion. The engine (AT-01) is done and merged before this starts.

**Context**

ho-9.4 Decisions 3–5 govern (read `ho-process/hos/ho-9.4-favorites.md`). AT-01 delivered `Favorite`, `FavoriteScope`, and `FavoritesStore` in `PalanaCore`. This is thin surface over them. Read these before writing and match their idioms:

- `Sources/Palana/SettingsModel.swift` — the `@Observable` + `didSet`-persists pattern (favorites persist the same way, silent-fail write).
- `Sources/Palana/PaneView.swift` (the `header`, `addressReadout`, ~lines 54–123) — where the star goes: between the address readout and the host menu.
- `Sources/Palana/HostMenuButton.swift` — the NSMenu built dynamically with callbacks (`onChoose`, `onType`, `onEditConfig`, `onReload`); the favorites section is new items in that menu.
- `Sources/Palana/PalanaSession.swift` — `hosts: [String]`, `focusedPane`, and pointing: `point(host:path:)` on the pane, `PalanaSession.point(_:host:path:)`, `focusedPane.state.host`/`.path`, `setLandOn`. The `revealOperationsLog()` method (~line 383) is the model for a session-level "point somewhere" verb.
- Memory / role boundary: **the practitioner owns UI/UX feel.** Build the honest v1 (star host-bound by default, menu section, promote/demote); the scope-feel gets settled in his hands session, not guessed at more elaborately here.

**Files**

- Create: `Sources/Palana/FavoritesModel.swift` (`@Observable final class FavoritesModel`)
- Modify: `Sources/Palana/PaneView.swift` (the star in the header)
- Modify: `Sources/Palana/HostMenuButton.swift` (favorites section + its callbacks) and its call site in `PaneView.swift`
- Modify: `Sources/Palana/PalanaSession.swift` (own the `FavoritesModel`, expose toggle/point/promote, load at start)
- Tests where they fit: `FavoritesModel` logic is app-target and drivable without SwiftUI—add a `Tests/PalanaTests/` suite if the target has one, or exercise the model's add/remove/promote/query logic directly. (Core coverage is AT-01's; this task's floor is that the model's non-UI logic is tested where the app target's tests live.)

**Required Changes**

1. **`FavoritesModel`** — `@Observable`, holds `[Favorite]`, loads from `FavoritesStore.load(defaultURL())` at init, persists on every mutation via a private `persist()` that `try?`s `FavoritesStore.save` (silent-fail, like OperationLog/SettingsModel). API:
   - `isFavorited(host:path:) -> Bool` — matches the normalized `host:path` in either scope.
   - `toggle(host:path:)` — remove if present (any scope), else add host-bound.
   - `add(host:path:scope:)`, `remove(id:)`, `setScope(id:_:)` (promote/demote).
   - `global: [Favorite]` and `hostBound(for host: String) -> [Favorite]` slices, insertion-ordered.
   Normalize the incoming path through `Favorite`'s initializer so queries and toggles agree with what's stored.

2. **The star** — in `PaneView`'s `header`, between `addressReadout` and the host menu (`hostMenu` / Spacer per the current layout). `Image(systemName: session.favorites.isFavorited(host:path:) ? "star.fill" : "star")`, accent when filled, `inkFaint` when hollow, a local hover `@State` lifting it to accent on hover (match the toolbar hover idiom—`ToolbarGlyphButton` light-moss). Click calls `session.toggleFavorite(forFocusedPaneOr: model)`—toggle the pane this header belongs to, using that pane's `state.host`/`.path`. Guard the star off when the pane has no host yet (empty/pre-read state).

3. **The host-menu section** — `HostMenuButton.pop` grows a favorites block after the hosts, before or around edit-config/reload (your placement, match the menu's existing visual grouping with separators). Global favorites always; host-bound favorites for the menu's pane host. Each item's action points that pane: `point(host:path:)`. Add a "Promote to Global" / "Move to this host" affordance—either a submenu per favorite or a modifier-click; the simplest honest form, since the feel is his to refine. Thread the needed data/callbacks in as new `HostMenuButton` inputs (`favorites`, `onChooseFavorite`, `onPromoteFavorite`)—do not reach into the session from inside the NSView.

4. **Session wiring** — `PalanaSession` owns `let favorites = FavoritesModel()`, loaded at `start()`. Expose `toggleFavorite(...)`, `chooseFavorite(_:for:)` (points the given side's pane), `promoteFavorite(id:)`. A chosen favorite points through the existing `point` path; a global favorite on another host re-points there (the existing `point(host:path:)` already does this—no special case).

**Do Not**

- Do not add a new grammar key or a summonable card (ho-9.4 Decision 5—reserved for the hands session).
- Do not build a label/rename editor (out of scope; the field exists but stays nil).
- Do not modify `PalanaCore` — AT-01 owns the engine; if you find you need a core change, stop and surface it.
- Do not reach into `PalanaSession` from inside `HostMenuButton`'s NSView—pass data and callbacks, matching how the menu already takes `onChoose`/`onReload`.

**Acceptance**

- [ ] The star reflects the focused pane's location and toggles a host-bound favorite; a second click removes it whatever its scope.
- [ ] The host menu lists global favorites always and host-bound favorites for that pane's host; choosing one points the pane; a global favorite re-points across hosts.
- [ ] Promote/demote flips scope and persists; `favorites.json` survives relaunch.
- [ ] `FavoritesModel`'s add/remove/toggle/promote/query logic is tested where the app target's tests live.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

SourceKit may throw phantom "cannot find in scope" on app-target files—`swift build` is the type checker of record. Check the test run line itself; `swift test | tail` masks exit codes in chains.

**Commit**

Do not commit. The session reviews and commits.
