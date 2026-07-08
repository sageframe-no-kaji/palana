---
created: 2026-07-08
type: agent-task
project: palana
parent-ho: 9.4
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.4-AT-01 — The engine: Favorite, FavoriteScope, FavoritesStore

**Goal**

Add the favorites value types and their persistence store to `PalanaCore`: `Favorite`, `FavoriteScope`, and `FavoritesStore` with silent-fail load and atomic save, plus a full unit battery. Pure core work—no app target, no wire, no UI.

**Context**

ho-9.4 Decisions 1–2 govern (read `ho-process/hos/ho-9.4-favorites.md`). This mirrors the session-persistence idiom already in the codebase—do not invent a new shape. Read these first and match them exactly:

- `Sources/PalanaCore/Surface/SessionSnapshot.swift` — the Codable snapshot + its store (`defaultURL()`, `load(from:)`, `save(_:to:)`); this is the pattern to follow for App Support pathing and atomic save.
- `Sources/PalanaCore/Field/FieldCache.swift` — the silent-fail load convention (missing/corrupt reads as nil, never throws on load).

`PalanaCore` carries the local-host constant (memory names it `PalanaCore.localHostName` / `Engine.localHost`—grep for it and use the existing constant; a favorite's host is an ssh alias or that constant). DocC on every public declaration, one-line summary then blank, in the committed-vocabulary voice the surrounding core uses.

**Files**

- Create: `Sources/PalanaCore/Surface/Favorite.swift` (`Favorite`, `FavoriteScope`) — or place beside SessionSnapshot if that reads more consistently; your call after reading the directory.
- Create: `Sources/PalanaCore/Surface/FavoritesStore.swift` (`defaultURL`, `load`, `save`) — mirror where `SessionStore` lives relative to `SessionSnapshot`.
- Create: `Tests/PalanaCoreTests/FavoritesTests.swift`

**Required Changes**

1. **`Favorite`** — `public struct Favorite: Codable, Identifiable, Sendable, Equatable` with `public let host: String`, `public let path: String`, `public var scope: FavoriteScope`, `public var label: String?`, and `public var id: String { "\(host):\(path)" }`. The initializer normalizes `path` on the way in: strip a single trailing `/` except when the path is exactly `/` (root keeps its slash). `label` defaults to nil.

2. **`FavoriteScope`** — `public enum FavoriteScope: String, Codable, Sendable { case host, global }`. The raw values `host`/`global` are on-disk vocabulary; a round-trip test pins them.

3. **`FavoritesStore`** — an enum or struct of statics mirroring `SessionStore`:
   - `defaultURL() -> URL` — `~/Library/Application Support/palana/favorites.json`, computed the same way SessionStore computes its path.
   - `load(from url: URL) -> [Favorite]?` — silent-fail: `guard let data = try? Data(contentsOf: url) else { return nil }`, then `try? JSONDecoder().decode`. Never throws.
   - `save(_ favorites: [Favorite], to url: URL) throws` — create the parent directory with intermediates, encode with `.prettyPrinted` + `.sortedKeys`, write `.atomic`. Match SessionStore's save exactly.

**Battery**

- Path normalization: `"/tank/media/"` stores as `"/tank/media"`; `"/"` stays `"/"`; a path with no trailing slash is unchanged; `id` reflects the normalized path.
- `Codable` round-trip of a `[Favorite]` covering both scopes and a nil and a non-nil label; assert the decoded value equals the encoded (Equatable).
- `FavoriteScope` raw values are exactly `"host"` and `"global"` (decode from a literal JSON string, not just round-trip).
- `save` then `load` through a temp-directory URL returns an equal array; `load` from a non-existent URL returns nil; `load` from a URL holding garbage bytes returns nil (silent-fail, no throw).
- `save` creates the intermediate directory when absent.

Use a unique temp directory per test (the codebase's fixtures note: shared paths let one test's teardown bite another). Assert long JSON by decoded value, not raw-string equality.

**Do Not**

- Do not touch `Sources/Palana/` — that is AT-02.
- Do not add an observable model, any SwiftUI, or any wire/Conduit code — this task is value types plus a file store.
- Do not invent a persistence shape—if SessionStore does it a certain way, do it that way.

**Acceptance**

- [ ] `Favorite`, `FavoriteScope`, `FavoritesStore` exist in `PalanaCore` with DocC on every public decl.
- [ ] Path normalization, Codable round-trip, raw-value pinning, and silent-fail load/save all covered and passing.
- [ ] Full suite passes (fixture-gated suites self-skip if fixtures are down).
- [ ] `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

Check the test run line itself — `swift test | tail` masks exit codes in chains.

**Commit**

Do not commit. The session reviews and commits.
