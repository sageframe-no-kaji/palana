---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Make remote round-trip editing preserve immutable remote identity, fail closed on uncertain conflict checks, retain every distinct save, and retire all watcher and temporary-file resources.

**Files**

- Modify: `Sources/Palana/PaneModel.swift`
- Modify: `Sources/Palana/OperationModel+RoundTrip.swift`
- Modify: `Sources/Palana/RoundTripCenter.swift`
- Modify: `Sources/Palana/PalanaSession+RoundTrip.swift`
- Modify: `Sources/PalanaCore/Surface/RoundTrip.swift`
- Modify/Create: focused tests under `Tests/PalanaTests/` and `Tests/PalanaCoreTests/`

**Required Changes**

1. Capture the remote host, directory, full path, filename bytes, and open generation before fetching. Navigation or another open must not change the resulting record.
2. Extend the fetch baseline with a content digest. Conflict evaluation must return `clean`, `conflict`, or `unavailable`; missing remote files, changed digest, and changed metadata are conflicts, while any listing/read error is unavailable.
3. Permit automatic send-back only after a `clean` result. Conflict and unavailable states must require visible operator action and a successful recheck before overwrite.
4. Replace the one-slot pending offer with a keyed queue. Coalesce repeated events only for the same record and preserve ordering across distinct files.
5. Carry exact record identity through plan completion and refresh only that watcher's baseline. Ordinary copies and sibling records in the same directory must not affect it.
6. Add explicit record retirement that cancels both watchers, removes registry state, and deletes the per-open temporary directory. Deduplicate repeated opens or enforce a documented bounded eviction policy.
7. Add deterministic tests for navigation during fetch, remote deletion, same-size same-mtime content changes, collision-check failure, two files saved while busy, unrelated copy completion, event/refresh ordering, repeated opens, and retirement cleanup.

**Acceptance**

- [ ] A remote-open record always names the originally opened path.
- [ ] No unavailable or conflicting destination state can auto-send.
- [ ] Remote deletion and content-only changes are conflicts.
- [ ] Distinct pending saves cannot replace each other.
- [ ] Baseline refresh targets one exact record.
- [ ] Retired records leave no watcher, descriptor, registry entry, or temporary directory.
- [ ] Format, lint, build, tests, and PalanaCore coverage pass.

**Verification**

```bash
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet
swift build --disable-sandbox
swift test --disable-sandbox
swift test --disable-sandbox --enable-code-coverage
scripts/coverage-floor.sh 90
```

**Do Not**

- Do not change the generic move-verification gate; Task 2 owns it.
- Do not identify records by host and directory alone.
- Do not treat size and mtime as content identity.
- Do not make resource cleanup depend only on application termination.

**Stop Condition**

If the application has no observable notion of a remote-open record becoming closed, stop and present the smallest explicit retirement policy before inventing editor integration.

**Commit**

Single commit with subject: `round-trip saves preserve remote identity`
