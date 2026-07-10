---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.9
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.9-AT-02 — The Surface: the gather and the line

**Goal**

Wire collision facts into the app: `OperationModel.gather` reads the destination directory through the existing listing path, runs `Collision.detect`, sets `PlanFacts.collisions` (nil with a spoken note when the read fails), and `PlanPanel` renders `CollisionReport.sentence()` as an alarm line. Depends on AT-01 being in the tree.

**Context**

ho-9.9 Decisions 2, 3 govern (read `ho-process/hos/ho-9.9-collision-facts.md`). Read `Sources/Palana/OperationModel.swift` `gather(_:source:destination:subjects:)` (~line 148)—the treeSizes gather (~lines 184–195) is the template: fetch, digest, note progress, never block the plan on a refusal. Read how the destination pane's listing is normally fetched (`PaneModel.commit` uses the engine's listing—find the exact listing call and reuse it verbatim; do not invent a new read). Read `Sources/Palana/PlanPanel.swift` `sizeLine` (~lines 173–174) for the alarm-line idiom and placement.

**Files**

- Modify: `Sources/Palana/OperationModel.swift` (gather), `Sources/Palana/PlanPanel.swift` (the line)
- Core logic stays in AT-01's files—if you find yourself writing comparison or sentence logic here, it belongs in core

**Required Changes**

1. **Gather** — when the request carries a destination directory: read that directory's listing on the destination host through the same Listing call the panes use (flavor from the host's capability facts, exactly as commit resolves it). On success, `facts.collisions = Collision.detect(sources: subjects, destinationListing: listing)` and, when non-empty, note it in the echo the way treeSizes notes progress. On any thrown read, `facts.collisions = nil` and note `destination unread — collisions unknown`. The gather must not fail the plan for an unreadable destination—the line carries the truth (Decision 3).

2. **The line** — `PlanPanel` renders `plan.collisions?.sentence()` under the size line: `Theme.alarm` whenever the report is ungathered or carries items. No line when the sentence is nil. Font and spacing match the size line exactly.

3. **No other behavior changes** — Enter arms exactly as before; no dialog, no confirmation, no gating on collisions.

**Battery**

App-target code carries no test target (the SwiftPM wall)—the tested truth lives in AT-01's core battery. Keep the app diff thin and mechanical. If any decision logic creeps in (which state renders, line color choice), move it to core and test it there.

**Acceptance**

- [ ] A copy onto colliding names shows the alarm line before Enter arms; a clean destination shows nothing; an unreadable one names the unknown.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

OperationModel.swift is over 650 lines—if your additions push a lint limit, extract the collision gather into a new file (`Sources/Palana/OperationModel+Collisions.swift`) rather than trimming elsewhere. SourceKit phantom "cannot find in scope" on app files is a known harness artifact—`swift build` is the type checker of record.

**Commit**

Do not commit. The session reviews and commits.
