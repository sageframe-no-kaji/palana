---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.10
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.10-AT-02 — The Surface: register, summon, send

**Goal**

Wire the round trip into the app: a remote open registers a `RoundTripRecord` and starts its watcher, a debounced save composes the upload plan and summons the panel (waiting politely if a plan owns it), the gather notes a remote that changed since the fetch, the transcript names the watch. Depends on AT-01 and on ho-9.9 (collision facts) being in the tree.

**Context**

ho-9.10 Decisions 2–5 govern (read `ho-process/hos/ho-9.10-remote-round-trip-editing.md`). Read:

- `Sources/Palana/PaneModel.swift` `openFile` (~line 497) — the remote branch that fetches into a per-open UUID directory; this is the registration site. The fetched `FileEntry` is in hand there.
- `Sources/Palana/OperationModel.swift` — `begin` (~line 105) and `gather` (~line 148) for how a plan request is composed and gathered, `Phase` (~line 16) for what "the panel is owned" means, and how notes echo into the transcript. The upload cannot ride `begin` (it takes panes) — it needs its own entry point composing the `PlanRequest` directly.
- How AT-02 of ho-9.9 fetches the destination listing in `gather` — the changed-since-fetch note rides that same listing.

**Files**

- Create: `Sources/Palana/RoundTripCenter.swift` — the app-side owner of live records + watchers
- Modify: `Sources/Palana/PaneModel.swift` (registration at the remote-open site — a callback out, following how PaneModel already signals the session; keep PaneModel free of OperationModel reach)
- Modify: `Sources/Palana/OperationModel.swift` or a new `Sources/Palana/OperationModel+RoundTrip.swift` (the upload entry point; prefer the new file — OperationModel is over 650 lines)
- Modify: `Sources/Palana/PalanaSession.swift` only for wiring (it is over its length budget — extract to a new file if more than a few lines land here)

**Required Changes**

1. **`RoundTripCenter`** (`@MainActor`, observable if the UI ever asks): holds `[RoundTripRecord]` with their `RoundTripWatcher`s. `register(record:)` starts a watcher whose callback hops to the main actor and asks the center to offer the upload. Cancel-all on deinit. A pending queue: if the operation model's phase is anything but idle/finished/failed/cancelled, hold the offer and re-offer when the phase frees (observe the phase or poll on a short timer — pick the cleaner given the code; nothing may evict a live plan, Decision 3).

2. **Registration** — in `openFile`'s remote branch, after the fetched copy lands, build the record (host, remote directory, fetched entry, local URL) and hand it out through a callback the session wires to the center. Transcript line at registration (Decision 5): `watching <name> — a save offers to send it back`, through the same echo path gather notes use.

3. **The upload entry point** — composes `PlanRequest(operation: .copy, source: Locus(host: localHost, directory: <per-open dir>), entries: [<local FileEntry>], destination: Locus(host: record.host, directory: record.remoteDirectory))` and runs the standing gather so the panel arrives in `.ready` with the collision line naming the replace. The local `FileEntry` for the temp file comes from the existing local listing path over the per-open directory (one call, byte-honest — do not hand-build an entry from FileManager attributes). Enter enacts through the standing machinery untouched. Esc declines — the watch stays live (the center just goes quiet until the next save). After a `.finished` upload, refresh the watcher's baseline (AT-01's method) so the send itself doesn't re-offer.

4. **Changed-since-fetch note** — during the upload's gather, when the destination listing (fetched by ho-9.9's collision gather) contains the record's file and `RoundTrip.changedSinceFetch(baseline: record.fetched, current: found)` is true, echo a note: `remote changed since fetch — <size> · <date> now stands there`. The comparison call is core; the note is one line here. Thread the record through the upload entry point so gather can see the baseline (an optional round-trip context on the gather call — keep it a parameter, not model state, if you can).

**Battery**

App-target code carries no test target. AT-01 carries the watcher truth. Anything decision-shaped you find yourself writing here (offer-or-hold logic beyond a phase check, note composition) — move it to core and test it. `RoundTrip` in core may grow a pure helper for the note sentence if that keeps this diff mechanical.

**Do Not**

- Do not auto-send. Nothing mutates the remote without Enter.
- Do not evict or reset a live plan when a save lands.
- Do not persist records across launches.

**Acceptance**

- [ ] Remote open → transcript names the watch. Save (in-place or atomic) → panel arrives ready with the upload plan and its collision line. Enter sends; Esc declines and a later save re-offers. Busy panel → the offer waits.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

SourceKit phantom "cannot find in scope" on app files is a known harness artifact — `swift build` is the type checker of record. Check the real test run line.

**Commit**

Do not commit. The session reviews and commits.
