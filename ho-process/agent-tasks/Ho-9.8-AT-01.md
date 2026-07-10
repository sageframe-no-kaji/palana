---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.8
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.8-AT-01 — The engine: the timestamps, the listing surgery, the sort keys

**Goal**

Grow the listing's gathered truth: `FileEntry.created`/`FileEntry.changed`, the GNU and BSD listing composes and parsers extended at each flavor's sealed fidelity, the recorded corpora re-recorded (recorder first), and `PaneState.SortKey` grown with nils-last comparators. Pure `PalanaCore`. The columns themselves are AT-02.

**Context**

ho-9.8 Decisions 2, 3, 6 govern (read `ho-process/hos/ho-9.8-columns.md`). This is listing surgery — the highest-ceremony part of the codebase. Read in full before touching anything:

- `Sources/PalanaCore/Listing/` — the per-flavor composes (GNU `find -printf`, BSD batched `stat`, BusyBox date ladder), the parsers, and `FileEntry`. Note the BSD batch pairing law (stat blocks paired with NUL names BY COUNT — ho-08's fork-storm fix) and the ./-prefix desync guard; your changes must preserve both.
- The listing corpus tests and their RECORDER — find where recorded transcripts live (Tests/PalanaCoreTests fixtures) and the script/helper that captures them. ho-9.3's lesson, binding here: when a command changes, the recorder learns the new exchange BEFORE the corpus re-records, and corpora are re-recorded LIVE, never fabricated by hand.
- `Sources/PalanaCore/Surface/PaneState.swift` — `SortKey` (~lines 12–18) and the sort application.

**Sealed fidelity (Decision 2 — do not exceed it):**

- **BSD**: gather both. Extend the batched `stat` format with birth time (`%SB` with epoch formatting the parser already uses for the existing date — match the existing timestamp idiom exactly) and ctime (`%Sc`/`%c`). This Mac is the live BSD host for verification.
- **GNU**: gather `changed` via `%C@` in the existing `find -printf` format; `created` stays nil. `%C@` is fractional-epoch like `%T@` — same parse.
- **BusyBox**: untouched. Both fields nil. The busybox corpus does not change — assert it byte-identical.

**Files**

- Modify: `Sources/PalanaCore/Listing/FileEntry.swift`, the flavor compose/parse files in `Sources/PalanaCore/Listing/`
- Modify: `Sources/PalanaCore/Surface/PaneState.swift` (SortKey)
- Modify: the corpus recorder + re-recorded corpus fixtures
- Extend: existing listing test suites + `Tests/PalanaCoreTests/` sort tests

**Required Changes**

1. **`FileEntry`** — `created: Date?`, `changed: Date?`, nil defaults so every existing construction stands. Codable: new optional fields must decode absent from old data (decodeIfPresent) — session/cache files on disk predate them.

2. **GNU listing** — one more `-printf` directive; parser maps it; `created` nil.

3. **BSD listing** — extend the stat format block; parser maps both; count-pairing and desync guards preserved and still tested.

4. **Recorder then corpora** — teach the recorder the new command shapes first; re-record the GNU corpus against the sshd container fixture (`scripts/sshd-fixture.sh start`, port 2223 — it should already be up; start it if not) and the BSD corpus against this Mac live. If any recorded assertion carried old command strings, update to the new exact strings. BusyBox corpus asserted unchanged.

5. **`SortKey`** — cases for created, changed, permissions, owner, group, starred is NOT core (favorites live app-side at sort time — check how applySort consumes SortKey; if the comparator takes only FileEntry, starred needs an app-side comparator in AT-02 instead; put the five entry-resident keys in core and note the starred call). Nils sort last in BOTH directions, stable. Permissions/owner/group compare as strings.

**Battery**

- parse: GNU line with `%C@` fractional epoch; BSD block with birth+ctime; BusyBox unchanged rows read nil/nil
- a pre-9.8 recorded cache/session JSON (hand-write a minimal old-shape fixture) decodes with nil timestamps
- sort: each new key both directions, nils-last both directions, stability among equal keys
- corpus replays green for all three flavors
- BSD pairing/desync tests still pass with the wider format

**Do Not**

- Do not gather GNU birth time by any mechanism — the fidelity is sealed.
- Do not touch BusyBox composes or corpus content.
- Do not touch `Sources/Palana/` — columns, customization, and the star are AT-02.
- Do not hand-edit corpus fixtures into plausibility — re-record live or leave unchanged.

**Acceptance**

- [ ] Both flavors gather at sealed fidelity; corpora re-recorded live and replaying; recorder updated first; old-shape JSON decodes.
- [ ] Sort keys grown with nils-last proven.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
scripts/sshd-fixture.sh start   # if not already up
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

Integration suites against the sshd fixture are `.serialized` — keep any new ones so. Check the real test run line. DocC on every public decl at writing time.

**Commit**

Do not commit. The session reviews and commits.
