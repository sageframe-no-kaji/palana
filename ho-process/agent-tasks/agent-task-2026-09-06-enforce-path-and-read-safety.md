---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Make file actions operate on exact filename identity, enforce remote-read ceilings during streaming, refuse dangling-symlink creation, and bind Finder drops to the destination that received them.

**Context**

Begin from branches containing Tasks 1 and 4. Task 1 provides real cancellation; Task 4 settles round-trip record identity and cleanup.

**Files**

- Modify: `Sources/PalanaCore/Listing/FileEntry.swift`
- Modify: `Sources/PalanaCore/Listing/Listing.swift`
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift`
- Modify: `Sources/Palana/PaneModel.swift`
- Modify: `Sources/Palana/PreviewController.swift`
- Modify: `Sources/Palana/PalanaSession+Preview.swift`
- Modify: `Sources/Palana/DragDrop.swift`
- Modify/Create: focused tests under `Tests/PalanaCoreTests/` and `Tests/PalanaTests/`

**Required Changes**

1. Establish one byte-honest action boundary. Where Foundation or shell APIs cannot address `nameData` exactly, refuse the action explicitly before composing a path; `FileEntry.name` remains display-only.
2. Apply that boundary to navigation, file opening, preview, favorites, starring, Finder reveal, and round-trip initiation. Byte-invalid names must never resolve to replacement-character paths.
3. Add bounded streaming reads that terminate the underlying command at limit plus one byte and report oversize distinctly. Remote open and binary preview must not depend on stale listing size for memory safety.
4. Write fetched content incrementally to its temporary destination where whole-file `Data` is unnecessary.
5. Change create and rename collision guards to detect dangling symbolic links with `lstat` semantics. Verify the resulting directory entry itself rather than its target.
6. Capture Finder-drop destination host and directory synchronously before any source listing await.
7. Add tests for two byte-distinct names with the same lossy display, a growing remote stream, a stale small-size fact followed by oversized content, cancellation at the cap, dangling symlinks, and pane navigation during Finder-drop resolution.

**Acceptance**

- [ ] No action composes a path from lossy `FileEntry.name` without an explicit representability guard.
- [ ] Remote reads cannot retain or write more than their configured ceiling.
- [ ] Oversize reads terminate their child command.
- [ ] Create and rename refuse dangling-link destinations.
- [ ] Finder drops retain their original destination locus.
- [ ] Format, lint, build, tests, and PalanaCore coverage pass.

**Verification**

```bash
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet
swift build --disable-sandbox
swift test --disable-sandbox
swift test --disable-sandbox --enable-code-coverage
scripts/coverage-floor.sh 90
rg -n "childPath\(of:.*entry\.name|appendingPathComponent\(entry\.name" Sources/Palana
```

**Do Not**

- Do not silently normalize, replace, or round-trip invalid filename bytes through `String`.
- Do not retain the stale metadata check as the actual byte ceiling.
- Do not alter round-trip queue or conflict policy; Task 4 owns them.

**Stop Condition**

If exact byte-addressing requires replacing the public path model across the application, stop and present the minimum refusal-first implementation and the larger architectural option separately.

**Commit**

Single commit with subject: `file actions preserve exact path identity`
