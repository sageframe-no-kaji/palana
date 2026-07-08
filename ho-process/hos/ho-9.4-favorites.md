---
created: 2026-07-08
status: complete
type: ho-document
project: palana
ho: 9.4
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-07-the-surface-panes
  - ho-09-the-surface-field-view
  - ho-9.2-settings
agent-tasks:
  - Ho-9.4-AT-01.md
  - Ho-9.4-AT-02.md
---

# ho-9.4 — Favorites

A file surface earns its second visit by remembering the first. The operator reaches the same handful of directories across a handful of hosts—koan's media pool, this Mac's projects, zencat's config—and types the address every time. Favorites remembers the location so the address bar doesn't have to. A location is a host and a path; a favorite is that pair, named, kept in `favorites.json` beside the session and the settings, jumped to with one act. Fourth on the Checkpoint 3 slate, first of the between-Workbench-and-ship run by the ratified order.

Two scopes, sealed in the slate: **host-bound** favorites belong to one host and surface in that host's context; **global** favorites are the cross-machine bookmark bar, jumpable from anywhere and switching the pane's host on the way. The distinction is presentation, not a different kind of thing—both are a host and a path. The engineering is one store; where each scope shows and how it feels is the hands session's to settle.

**Out of scope:** reordering favorites by drag—the list is insertion-ordered in v1, a sort ho or his hands can grow it. A rename/label editor—the model carries an optional label field for the future, but v1 shows `host:path` and builds no editing UI. Host-agnostic path templates ("`~/dev` on whatever host")—a favorite is a concrete location, never a template; a path means nothing without a host. Favorites sync across machines. Drag-a-directory-onto-favorites (that rides ho-9.6 drag-and-drop). A dedicated favorites summon key or overlay card—v1 surfaces through the star and the host menu; a keyboard path waits for the hands session's word (Decision 5).

**Resolves deferred decisions:** none from the overview—this ho was born at Checkpoint 3, its two scopes named in the slate the practitioner ratified.

---

## Phase 1 — Think

### Decision 1 — A favorite is a host, a path, a scope, and an optional label

The value type lives in `PalanaCore`, pure and testable, the way `SessionSnapshot` does—the app target carries only the live observable model and the wiring:

```swift
public struct Favorite: Codable, Identifiable, Sendable, Equatable {
    public let host: String        // ssh alias, or PalanaCore's local-host constant
    public let path: String        // the pane's canonical path at favoriting time
    public var scope: FavoriteScope // .host | .global
    public var label: String?      // nil means show host:path
    public var id: String { "\(host):\(path)" }
}

public enum FavoriteScope: String, Codable, Sendable { case host, global }
```

A location is favorited at most once—`id` is `host:path`, and scope is a property you flip, not a second entry. `label` is nil in v1 and carries no editor; it exists so renaming favorites later is a field default, not a Codable migration. `path` is stored as the pane's own path, normalized by stripping a trailing slash except at root, so `koan:/tank/media` and `koan:/tank/media/` are one favorite. Equality is exact string after that trim.

### Decision 2 — Persistence mirrors SessionStore exactly

`favorites.json` sits beside `session.json` and `settings.json` in `~/Library/Application Support/palana/`. The store is the established idiom, no invention:

- `FavoritesStore.defaultURL()` — the App Support path, `palana/favorites.json`
- `FavoritesStore.load(from:) -> [Favorite]?` — silent-fail: missing or corrupt reads as nil, never a throw, the way `FieldCache` and `SessionStore` already do
- `FavoritesStore.save(_:to:) throws` — atomic write, `.prettyPrinted` + `.sortedKeys`, creating the directory if absent

The app target's `FavoritesModel` (`@Observable`) loads at start and persists on every mutation, silent-fail on write like `OperationLog`. One list, both scopes; the model owns add, remove, promote, and the queries the surface asks (`isFavorited(host:path:)`, the host-bound and global slices).

### Decision 3 — The star toggles the current location, host-bound by default

The address bar grows a star between the readout and the host menu. It reflects whether the focused pane's `host:path` is favorited in either scope. A click on an unfavorited location adds it **host-bound**—the common act is "remember this directory on this host." A click on a favorited location removes it, whatever its scope. Global is a promotion, not the star's default (Decision 4). The star is a single clean binary; whether the hands session wants a scope choice at creation is its call to make, not the engine's to presume.

### Decision 4 — Favorites surface through the host menu; host-bound filtered to the focused host, global always

The ▾ menu already carries the hosts, type-an-address, edit-config, reload. It grows a favorites section: **global** favorites always listed (the bookmark bar—jump from any host), **host-bound** favorites for the focused pane's current host. Choosing one points the focused pane through the existing `point(host:path:)`—a global favorite on another host re-points there, which is the whole reason global exists. A "promote to global" / "demote to host" item flips a favorite's scope in place. A host-bound favorite whose host is hidden by the 9.2 curtain simply never appears under a host that isn't shown; a global favorite always can be reached. The menu is the concrete v1 surface; whether favorites also want a summonable card on the `f`/`F`/backtick lineage is the hands session's feel call.

### Decision 5 — No new grammar key in v1

The star (mouse) adds and removes; the host menu jumps. That covers the loop without spending a grammar letter blind. yazi's bookmark keys (`'`, `m`) collide with pālana's move-verb `m` and the marks it doesn't have, so there's no muscle-memory key to honor cheaply. If the hands session wants a keyboard path—summon a favorites card, jump by number—the field/map overlay lineage is where it belongs, and it opens as a round then. v1 ships star plus menu and reserves the grammar.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.4-AT-01 — The engine: Favorite, FavoriteScope, FavoritesStore

The value types and the persistence store in `PalanaCore`, silent-fail load and atomic save, full unit battery including Codable round-trip and path normalization. → `ho-process/agent-tasks/Ho-9.4-AT-01.md`

### Ho-9.4-AT-02 — The Surface: the star, the model, the host-menu section

`FavoritesModel`, the address-bar star toggle, the host-menu favorites section, point-at-favorite, scope promotion, persistence wiring. → `ho-process/agent-tasks/Ho-9.4-AT-02.md`

### Done means

- The star reflects the focused pane's location and toggles a host-bound favorite; a second click removes it whatever its scope
- The host menu lists global favorites always and host-bound favorites for the focused host; choosing one points the pane, a global one re-pointing across hosts
- Promote/demote flips a favorite's scope in place and persists
- `favorites.json` round-trips through the store; a corrupt file reads as empty, never a crash
- Verification rhythm green, PalanaCore coverage floor holds

---

## Phase 3 — Reflect

**The truth-in-core discipline paid, and the review caught where it slipped.** The engine tasks landed the value types and the store where they belonged, but the surface task hit the SwiftPM wall—an executable target can't be imported by a test target—and papered over it with a reference implementation, tests that exercised a copy of the logic instead of the model itself. The review caught it: the fix was to relocate the list logic into a pure `FavoritesList` in the core, tested for real, with `FavoritesModel` a thin shell over it. The same shape held for the column: `FavoritesOutline` (grouping) and its `flatRows` (keyboard order) are pure and tested; the panel and the fold state are surface. Every piece of favorites truth ended up in `PalanaCore` where the floor bites, exactly as the system design promises.

**The v1 surface was the star and the host menu; the hands session grew the column the ho anticipated.** The Think phase deferred "a dedicated favorites summon key or overlay card" to the practitioner's hands, and that is what arrived—a floating column on the host-map lineage, opened with `*` and a titlebar star, organized by machine with expanders, keyboard-navigable like a single pane of the main program (arrows and hjkl, dig and climb, Enter jumps, shift-arrows promote and demote), with a one-level-plus undo stack. The two scopes the slate named held all the way through: host-bound under each machine, global on top, promote and demote in place.

**A platform trap worth keeping: `charactersIgnoringModifiers` applies Shift.** `cmd-shift-8` beeped because the token builder produced `cmd-shift-*` (shift-8 is `*`), not the literal the handler checked. The same builder drops Shift entirely for arrow keys, so the panel reads the raw `NSEvent` to tell shift-up from up. Any future shifted-number or shift-arrow binding inherits both facts.

**The jump-target question converged through the practitioner's hands into the cleanest form.** It moved from "which pane does Enter target?" (the focused one) through a live text strip naming the destination, to a three-arrow selector—left, both, right—defaulting to the pane he was on, one mechanism for mouse and keyboard both. His word on it: "a hot fucking solution." Shift-Enter, added a round earlier for the opposite pane, was superseded and removed—the arrow said it better.

**Deferred, named:** a "starred" column in the column picker—marking favorited directories in the pane table—waits for ho-9.8, which builds the picker it rides on.

---

_Authored: 2026-07-08 (Think phase, Opus). Executed same day—two agent tasks on claude-sonnet-4-6, reviewed by the session; three hands rounds grew the column, the keyboard navigation, and the arrow selector. Closed 2026-07-08. Favorites truth is core-resident and tested; the surface is thin. CI green._
