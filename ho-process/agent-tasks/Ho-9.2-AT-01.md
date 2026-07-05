---
created: 2026-07-05
type: agent-task
project: palana
parent-ho: 9.2
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.2-AT-01 — The core: hide parsing, the hide transform, the flags fact

**Goal**

Grow PalanaCore for the settings ho: `SSHConfigParser.hiddenHosts(in:)` reads `# palana: hide` markers, a pure text transform inserts/removes them, and `PlanFacts.rsyncOperatorFlags` rides into every rsync compose. Full battery. No app target, no filesystem writes in the library, no wire.

**Context**

ho-9.2 Decisions 1–3 govern (read `ho-process/hos/ho-9.2-settings.md`). Read `Sources/PalanaCore/Field/SSHConfigParser.swift` whole first—the parser's block structure, `Include` following, and the wildcard-exclusion rule are the ground the hide awareness joins. The transform is text-in-text-out—the app side owns files. Read `PlanEngine.swift`'s rsync composes (`composeRsync`, `composeRsyncDirect`, and the same-host rsync path in `composeLocal`) before touching flags.

**Files**

- Modify: `Sources/PalanaCore/Field/SSHConfigParser.swift` (hide parsing + the transform)
- Modify: `Sources/PalanaCore/Plan/PlanRequest.swift` (`PlanFacts.rsyncOperatorFlags: String?`)
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift` (flags into the rsync composes)
- Modify: `Tests/PalanaCoreTests/SSHConfigParserTests.swift` (hide battery)
- Modify: `Tests/PalanaCoreTests/PlanCompositionTests.swift` and/or `PlanLocalEndpointTests.swift` (flags assertions)

**Required Changes**

1. **`hiddenHosts(in:including:)`** — same signature family as `hosts(in:including:)`, follows `Include` identically, returns the set of aliases whose `Host` block contains a line matching `^\s*#\s*palana:\s*hide\s*$` (case-insensitive on the word `palana`? No—exact lowercase `palana: hide`, documented). Every alias of a marked block is hidden. Wildcard patterns stay excluded as in `hosts`.

2. **The transform** — two pure static functions on `SSHConfigParser` (or a small `HideMarker` enum beside it, your call, DocC'd):
   - `hiding(alias:in:) -> String?` — returns new config text with the marker line inserted as the first line inside the alias's `Host` block (indented to match the block's option indentation, or four spaces when the block is empty). Returns nil when the alias isn't found or is already hidden (nothing to do — the caller treats nil as no-write).
   - `showing(alias:in:) -> String?` — removes exactly the marker line(s) from the alias's block, nil when not found or not hidden.
   - Both touch nothing else — byte-for-byte identity outside the one line, preserving line endings and comments. They operate on the TOP-LEVEL file text only: when the alias was declared inside an Include'd file, return nil — the app surfaces "managed in an included file" rather than writing somewhere surprising. Document this boundary.

3. **`PlanFacts.rsyncOperatorFlags: String?`** — nil/whitespace-empty means absent. Every rsync compose (forwarded, direct, same-host local rsync) appends the trimmed flags after the base flag set and before the paths: `rsync -a -s --partial --info=progress2 <operatorFlags> <sources> <dest>`. Tar, zfs, mv, and the guards are untouched — this is an rsync default only.

4. **Battery.** Hide parsing: marked block, unmarked, multi-alias block (all aliases hidden), marker in an Include'd file (hidden set still reports it — parsing follows includes), indentation and CRLF tolerance. Transform: insert then parse reports hidden, remove restores byte-identical original (lock with an exact equality on a fixture string), already-hidden → nil, unknown alias → nil, alias-in-include → nil. Flags: one compose per rsync path asserting placement, absent-when-nil, whitespace-trimmed.

**Do Not**

- Do not write any file from PalanaCore — the transform is text to text.
- Do not change what `hosts(in:)` returns — visibility subtraction is the Surface's (ho-9.2 Decision 1: the Field's truth doesn't shrink).
- Do not validate flag strings — the panel shows the exact command and a bad flag fails typed (Decision 3).

**Acceptance**

- [ ] `hiddenHosts` and the two transforms behave per the battery above, all tests green.
- [ ] Every rsync compose carries the operator flags when present, proven by assertions.
- [ ] `swift-format lint --recursive --strict Sources Tests`, `swiftlint lint --strict`, `swift build`, `swift test` all green (read the run line).

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

**Commit**

Do not commit. The session reviews and commits.
