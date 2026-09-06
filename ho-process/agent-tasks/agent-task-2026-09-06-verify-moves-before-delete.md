---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Release a move's destructive delete only after exact source and destination identity is established. Correct local cross-volume routing and refuse plans that already contain an impossible kind collision.

**Context**

Begin from a branch containing Task 1's process-lifecycle commit. Count equality is not identity, and POSIX pipeline status masks `find` failures in the current verifier.

**Files**

- Modify: `Sources/PalanaCore/Transports/Transports.swift`
- Modify: `Sources/PalanaCore/Plan/PlanEngine+SameFilesystem.swift`
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift`
- Modify: `Sources/PalanaCore/Plan/Collision.swift`
- Modify/Create: focused tests under `Tests/PalanaCoreTests/`

**Required Changes**

1. Replace `find ... | wc -l` verification with a deterministic manifest contract that fails when any source or destination path is absent or unreadable. The manifest must compare relative names, object types, regular-file sizes, symlink targets, and content digests for regular files.
2. Require successful manifest generation on both ends before comparison. Verification uncertainty must keep every gated delete closed.
3. Preserve transport-independent verification: rsync, tar, local copy, and ZFS file moves must share the same destructive gate where applicable.
4. Gather or derive local device identity and classify a local move as an instant rename only when source and destination are proven to share a filesystem. Unknown identity must take the verified copy/delete path.
5. Refuse plan composition or enactment when collision facts contain a kind clash. A plan described as “won't work” must not remain armed.
6. Add adversarial tests for equal counts with changed bytes, missing paths whose `find` would have been masked, type changes, changed symlink targets, pre-existing destination entries, cross-volume facts, and mixed selections containing a kind clash.

**Acceptance**

- [ ] Equal object counts with different content cannot release deletion.
- [ ] Missing or unreadable paths make verification unavailable and keep deletion closed.
- [ ] Manifest equality covers names, types, sizes, link targets, and regular-file content.
- [ ] Unknown local filesystem identity never claims an instant rename.
- [ ] Known kind clashes cannot be enacted.
- [ ] Format, lint, build, tests, and PalanaCore coverage pass.

**Verification**

```bash
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet
swift build --disable-sandbox
swift test --disable-sandbox
swift test --disable-sandbox --enable-code-coverage
scripts/coverage-floor.sh 90
rg -n "find .*wc -l" Sources/PalanaCore/Transports && exit 1 || true
```

**Do Not**

- Do not treat count, total byte count, mtime, or a successful transfer exit as content identity.
- Do not silently assume a hash command exists on every userland.
- Do not alter ZFS topology freshness; Task 3 owns that contract.

**Stop Condition**

If cryptographic manifests require a new cross-userland capability probe or external dependency, stop and present the smallest portable contract rather than substituting a weaker checksum silently.

**Commit**

Single commit with subject: `moves delete only after content identity`
