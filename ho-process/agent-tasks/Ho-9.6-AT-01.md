---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.6
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.6-AT-01 — The engine: the payload and the drop decision

**Goal**

The core half of drag-and-drop: `DraggedSelection` (the typed drag payload) and `DropDecision` (the pure what-happens function). Small, exact, fully tested. No app target (that is AT-02).

**Context**

ho-9.6 Decisions 1, 3, 5 govern (read `ho-process/hos/ho-9.6-drag-and-drop.md`). Read `Sources/PalanaCore/Listing/FileEntry.swift` for the byte-name idiom and `Sources/PalanaCore/Plan/PlanRequest.swift` for `Locus` and `PlanOperation`. Trailing-slash normalization precedent: `FavoritesList`/`Favorite` (Sources/PalanaCore/Surface) — reuse the same rule for the same-place comparison.

**Files**

- Create: `Sources/PalanaCore/Surface/DraggedSelection.swift`
- Create: `Tests/PalanaCoreTests/DraggedSelectionTests.swift`

**Required Changes**

1. **`DraggedSelection`** — `Codable, Sendable, Equatable`: `host: String`, `directory: String`, `names: [Data]` (entry names as bytes, matching FileEntry's refusal to guess encodings). Codable must round-trip the byte names losslessly (Data encodes base64 under JSONEncoder — fine, assert it). Do NOT conform to Transferable here — that is app-target currency (Decision 1).

2. **`DropDecision`** — an enum: `.compose(PlanOperation)` (`.copy` or `.move`), `.refuseSamePlace`. A pure `decide(payload:targetHost:targetDirectory:optionHeld:)`:
   - same host and same directory after trailing-slash normalization → `.refuseSamePlace`
   - option held → `.compose(.move)`, else `.compose(.copy)` (Decision 2)
   - empty `names` → `.refuseSamePlace` is wrong for that — add a `.refuseEmpty` case; a drag of nothing composes nothing

**Battery**

- Codable round trip with a name that is not valid UTF-8 (raw bytes survive)
- decide: same place with and without trailing slash, differing host same path, same host differing path, option on and off, empty names
- Equatable sanity on the payload

**Do Not**

- Do not touch `Sources/Palana/`, Transferable, UTType, or any SwiftUI import.
- Do not add drag-out, favorites-drop, or row-target variants.

**Acceptance**

- [ ] Payload and decision covered exactly; full suite passes.
- [ ] `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

DocC on every public decl at writing time. Check the real test run line.

**Commit**

Do not commit. The session reviews and commits.
