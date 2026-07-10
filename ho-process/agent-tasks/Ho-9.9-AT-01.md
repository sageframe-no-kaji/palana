---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.9
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.9-AT-01 — The engine: Collision, the detect, the report on the Plan

**Goal**

Grow the plan vocabulary so a plan names what it will overwrite: the `Collision` value, the pure `detect` over source entries and a destination listing, the `CollisionReport` with its sentence composer, `PlanFacts.collisions`, and the carry-through in `PlanEngine.plan()`. Pure `PalanaCore`—no app target, no gathering I/O (that is AT-02).

**Context**

ho-9.9 Decisions 1, 4, 5 govern (read `ho-process/hos/ho-9.9-collision-facts.md`). The shape mirrors `recursiveSizes`/`totalSizeComplete`—read how `PlanFacts.recursiveSizes` (Sources/PalanaCore/Plan/PlanRequest.swift, the PlanFacts struct) feeds `Plan.totalSizeComplete` (Sources/PalanaCore/Plan/Plan.swift) and follow that carry-through idiom. Read `FileEntry` (Sources/PalanaCore/Listing/FileEntry.swift) for `nameData`, `kind`, `size`, `modified`. Read `PlanEngine.plan()`/`classify()` (Sources/PalanaCore/Plan/PlanEngine.swift) for where the report is set.

**Files**

- Create: `Sources/PalanaCore/Plan/Collision.swift`
- Modify: `Sources/PalanaCore/Plan/PlanRequest.swift` (PlanFacts), `Sources/PalanaCore/Plan/Plan.swift` (the report field), `Sources/PalanaCore/Plan/PlanEngine.swift` (carry-through)
- Create: `Tests/PalanaCoreTests/CollisionTests.swift`

**Required Changes**

1. **`Collision`** — `Codable, Sendable, Equatable`: the colliding name (`nameData: Data` plus a lossy display accessor matching FileEntry's idiom), what stands at the destination (`standingKind: FileEntry.Kind`, `standingSize: Int64`, `standingModified: Date`), what arrives (`arrivingKind: FileEntry.Kind`). A computed `nature` enum: `.replace` (file over file), `.merge` (directory over directory), `.kindClash` (mixed).

2. **`Collision.detect(sources:destinationListing:) -> [Collision]`** — pure. Byte-exact `nameData` comparison (Decision 1), order stable by destination-listing appearance. Symlinks: compare by name like everything else; a symlink standing at the destination is `.replace` when a file arrives (rsync replaces the link, not the referent—do not follow).

3. **`CollisionReport`** — `Codable, Sendable, Equatable`: `items: [Collision]`, `gathered: Bool`. `sentence() -> String?` composes the panel line (Decision 4): nil when gathered and empty; when ungathered, exactly `destination unread — what this replaces is unknown`; otherwise the replaces/merges/kind-clash clauses with sizes rendered the way the panel already renders bytes, enumeration capped at four names per clause with `and N more`. Write the exact strings as tests first, then make them pass.

4. **`PlanFacts.collisions: [Collision]?`** — nil default, nil means ungathered.

5. **`Plan` carries `collisions: CollisionReport?`** — nil on plans whose request has no destination directory (rename, create, touch, delete, zfs mutations); on every destination-ful classification (Decision 5) the report is present: `gathered: facts.collisions != nil`, `items: facts.collisions ?? []`. Codable—extend the existing Plan Codable surface the way `totalSizeComplete` rides it.

**Battery**

- detect: empty destination, no overlap, single replace, dir-over-dir merge, both kind-clash directions, byte-exact names that differ only past UTF-8 (two nameData values with the same lossy display must not merge), stable order, multiple collisions.
- sentence: each nature alone, mixed natures, the cap with `and N more`, the ungathered string verbatim, nil when clean.
- plan carry-through: a copy plan with facts carrying collisions exposes the report; a rename/create/touch plan carries nil; a destination-ful plan with nil facts reads `gathered: false`; Codable round trip of a plan with a report.

**Do Not**

- Do not change any composed command—no compose function may differ. Add a test asserting an existing copy compose is byte-identical with and without collision facts if none exists.
- Do not touch `Sources/Palana/` (the gather and the panel line are AT-02).
- Do not add skip/overwrite behavior, flags, or options.

**Acceptance**

- [ ] Detect and sentence covered by exact-value tests; the report rides the Plan and round-trips Codable.
- [ ] Composed commands provably unchanged.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

Check the real test run line — `swift test | tail` masks exit codes. DocC on every public decl at writing time. New code goes in new files where it can—PlanEngine.swift and PlanRequest.swift are near their length budgets.

**Commit**

Do not commit. The session reviews and commits.
