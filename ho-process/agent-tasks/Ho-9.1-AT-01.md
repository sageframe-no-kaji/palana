---
created: 2026-07-04
type: agent-task
project: palana
parent-ho: 9.1
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.1-AT-01 — The engine: targetName, rename, create

**Goal**

Grow the Plan Engine for in-place rename and creation: `PlanRequest.targetName`, `PlanOperation.rename`/`.create`, `Classification.creation`, portable guard composes with verification, full unit battery. Pure engine work—no app target, no wire.

**Context**

ho-9.1 Decisions 1–2 govern (read `ho-process/hos/ho-9.1-rename-and-create.md`). The engine is pure—`PlanRequest` + `PlanFacts` in, `Plan` out (`Sources/PalanaCore/Plan/`). `Classification.withinDatasetRename` exists since ho-05 but nothing composes it yet. BusyBox flag sets are vendor-dependent, so the composes avoid `mv -n` in favor of POSIX guards. Read `PlanEngine.swift` whole before writing—match how classification, transport selection, and compose dispatch already work, and how existing composes quote via `ShellQuote`.

**Files**

- Modify: `Sources/PalanaCore/Plan/PlanRequest.swift` (add `targetName: String?`, default nil)
- Modify: `Sources/PalanaCore/Plan/Plan.swift` (`PlanOperation.rename`, `.create`; `Classification.creation` with DocC in the committed-vocabulary voice)
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift` (classification, transport, composes, verification)
- Modify: `Tests/PalanaCoreTests/PlanCompositionTests.swift` or a new suite file `Tests/PalanaCoreTests/PlanRenameCreateTests.swift` (your call—new file if the existing suite's helpers don't fit)

**Required Changes**

1. **`PlanRequest.targetName: String?`** — nil default, DocC saying what it is (the bare new name for rename and create; nil for every other operation). Init gains the parameter with a default so all call sites stand.

2. **Operations and classification.** `.rename` classifies `.withinDatasetRename`, `.create` classifies `.creation` (new case). Both select transport `.local`. Engine refusals (typed, matching how the engine already throws on bad requests—read how it refuses today):
   - `.rename` requires exactly one entry and a non-empty `targetName` containing no `/`; a `targetName` equal to the entry's name is a refusal (nothing to do).
   - `.create` requires empty `entries`, a non-empty `targetName` whose only permitted `/` is a single trailing one (the directory marker). No destination for either—`destination` must be nil, like delete.

3. **Composes** (steps run on `request.source.host`, all names ShellQuoted, paths joined with the source directory):
   - rename: one step `test ! -e '<dir>/<new>' && mv -- '<dir>/<old>' '<dir>/<new>'`, role matching the closest existing role for a mutation (read the `PlanStep` role vocabulary and pick honestly). Verification: `test -e '<dir>/<new>' && test ! -e '<dir>/<old>'`.
   - create directory (trailing slash, slash stripped for the path): `mkdir -- '<dir>/<name>'`, verification `test -d`.
   - create file: `test ! -e '<dir>/<name>' && touch -- '<dir>/<name>'`, verification `test -f`.
   Follow exactly how existing composes attach verification (read how delete/local verify today—match the mechanism, do not invent a new one).

4. **Battery.** Rename compose exact-string tests (spaced names included), create dir/file, each refusal (multi-entry rename, empty name, embedded slash, same name, non-nil destination, entries on create), verification commands, and Codable round-trip of a rename Plan (PlanOperation raw values are part of the on-disk vocabulary). Assert command structure by anchor ranges where strings get long—test-authoring note from ho-06.5.

**Do Not**

- Do not touch `Sources/Palana/` — that is AT-02.
- Do not compose `mv -n` or any vendor-dependent flag (ho-9.1 Decision 2).
- Do not allow rename to reach a different directory or host — out of scope by name.

**Acceptance**

- [ ] The engine plans rename and create per the composes above, refuses the malformed shapes typed.
- [ ] All new tests pass; the full suite passes (fixture-gated suites self-skip if fixtures are down).
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
