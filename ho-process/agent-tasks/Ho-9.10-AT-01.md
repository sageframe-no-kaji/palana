---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.10
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.10-AT-01 — The engine: RoundTripRecord, the watcher, the baseline compare

**Goal**

The core machinery for remote round-trip editing: `RoundTripRecord` (what was fetched, where it lives), `RoundTripWatcher` (a directory-watching change detector with debounce), and `RoundTrip.changedSinceFetch` (the baseline compare). Pure `PalanaCore` plus a unit battery that beats on real temp files. No app target (that is AT-02).

**Context**

ho-9.10 Decisions 1, 2, 4 govern (read `ho-process/hos/ho-9.10-remote-round-trip-editing.md`). Read `Sources/PalanaCore/Surface/SessionStore.swift` for the core-side local-filesystem idiom and `Sources/PalanaCore/Listing/FileEntry.swift` for the entry shape. Read `Sources/Palana/PaneModel.swift` `openFile` (~line 497) to understand the per-open directory the watcher will be pointed at — but do not modify it.

**Files**

- Create: `Sources/PalanaCore/Surface/RoundTrip.swift`
- Create: `Tests/PalanaCoreTests/RoundTripTests.swift`

**Required Changes**

1. **`RoundTripRecord`** — `Sendable, Equatable`: `host: String`, `remoteDirectory: String`, `fetched: FileEntry`, `localURL: URL`. A computed display name from the entry.

2. **`RoundTripWatcher`** — a final class, one per record. Watches the record's local directory (the per-open UUID directory) via `DispatchSource.makeFileSystemObjectSource` on the directory's file descriptor with `.write` events (Decision 1 — editors save by atomic replace, which kills a file-fd watch; the directory event survives it). On each event, stat the record's file (size + mtime via FileManager) and compare against the last-seen pair — only a real difference counts as a change. Debounce: coalesce events, fire the callback once no new event has arrived for a beat (500ms is fine — make it an injectable interval so tests can shrink it). Callback is `@Sendable`, delivered off the source's queue. `start()` / `cancel()` lifecycle, idempotent cancel, no leaked file descriptors (close in the source's cancel handler). Baseline refresh: a method that re-snapshots size+mtime as the new last-seen (Decision 3's post-send refresh — AT-02 calls it).

3. **`RoundTrip.changedSinceFetch(baseline:current:) -> Bool`** — pure: true when size or modified differ between two `FileEntry` values (Decision 4). Compare by those two fields only — permissions drift is not an edit.

**Battery**

Real temp files under `FileManager.default.temporaryDirectory` (the tests own their dirs, create and remove them):

- an in-place write to the watched file fires the callback once
- an atomic-replace save (write a sibling temp file, `replaceItemAt`/rename over the original) fires the callback — this is the case that justifies the directory watch; it must be tested exactly this way
- a burst of writes inside the debounce window fires once
- an event with no stat difference (touch the directory by creating and removing an unrelated file, file itself untouched) does not fire
- baseline refresh: after refreshing, an identical stat fires nothing; a subsequent real edit fires
- cancel stops delivery; double-cancel is safe
- changedSinceFetch: size change, mtime change, both, neither, permissions-only difference is false

Async tests: use confirmation or a short polling await with a hard timeout — never an unbounded wait. Keep the debounce interval tiny in tests via the injectable interval.

**Do Not**

- Do not touch `Sources/Palana/` — registration and the panel summon are AT-02.
- Do not add persistence — records live for a run (out of scope: watches across launches).
- Do not use FSEvents or third-party watchers — DispatchSource is the committed mechanism.

**Acceptance**

- [ ] The watcher detects in-place and atomic-replace saves, debounces bursts, ignores non-changes, refreshes its baseline, and cancels cleanly.
- [ ] changedSinceFetch covered exactly.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

Check the real test run line — `swift test | tail` masks exit codes. DocC on every public decl at writing time. Strict concurrency is on — the watcher's mutable state needs a lock or a serial queue, and the callback must be `@Sendable`; design for it rather than bolting `@unchecked Sendable` on (if you genuinely need `@unchecked`, justify it in a comment).

**Commit**

Do not commit. The session reviews and commits.
