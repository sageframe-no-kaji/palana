# Full Review Repair Dispatch — 2026-09-06

## Ruling

The 28 findings should be executed as eight bounded tasks. Agents may run in parallel only within the waves below because later tasks either depend on new contracts or touch the same files.

Each agent should work in an isolated worktree and produce one atomic commit. Merge or cherry-pick completed commits into the integration branch in the stated order, then create the next wave's worktrees from that updated integration branch.

## Finding Coverage

| Task | Findings owned |
| --- | --- |
| 1. Process lifecycle | UI-only cancellation; orphaned pipeline halves; Workbench read deadlock and ignored exit |
| 2. Move verification | Count-only destructive gate; false local same-filesystem claim; executable kind clashes |
| 3. ZFS truth | Stale topology destruction; incomplete ZFS postconditions; snapshot-context race |
| 4. Round-trip integrity | Wrong upload directory; fail-open collision check; weak remote identity; lost queued saves; broad baseline refresh; watcher/temp leaks |
| 5. SSH configuration | `Match`/shared-block deletion; `local` collision; unsafe config transaction; inline comments; silent settings persistence |
| 6. SSH execution | Shell/option injection through aliases; indefinitely persistent crashed masters |
| 7. Path and read safety | Unbounded remote reads; dangling-symlink create; lossy filename actions; late Finder-drop destination |
| 8. Evidence and coverage | Silent operation-log failure; application layer excluded from coverage |

Every review finding is assigned once. Task 6 assumes Task 5 has established valid aliases, while Task 7 assumes Task 1 has established cancellable bounded commands and Task 4 has settled round-trip record ownership.

## Dispatch Waves

### Wave 1 — parallel

Run Tasks 1, 4, and 5 concurrently in separate worktrees. Their production files do not overlap materially.

Task 1 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-own-and-cancel-processes.md` and execute it exactly. Treat cancellation as an operating-system lifecycle contract, add adversarial process tests, make one atomic commit, and stop on any required public-contract change not authorized by the spec.

Task 4 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-harden-round-trip-integrity.md` and execute it exactly. Repair the round-trip subsystem as one identity-and-lifecycle unit, prove every named race with deterministic tests, make one atomic commit, and do not touch generic transport verification.

Task 5 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-repair-ssh-configuration.md` and execute it exactly. Preserve unrelated SSH configuration byte-for-byte, fail closed on every read or write uncertainty, make one atomic commit, and do not alter SSH process execution.

### Wave 2 — parallel after Wave 1 merges

Run Tasks 2 and 3 concurrently from the updated integration branch.

Task 2 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-verify-moves-before-delete.md` and execute it exactly. Replace the destructive count gate with content identity, correct local cross-volume classification, refuse known kind clashes, make one atomic commit, and stop if portable manifest evidence requires an unapproved capability contract.

Task 3 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-bind-zfs-truth.md` and execute it exactly. Make destructive ZFS plans depend on fresh version-bound facts and exact postconditions, repair the snapshot-context race, make one atomic commit, and do not weaken operator confirmation.

### Wave 3 — sequential

Task 6 must run after Tasks 1 and 5 because it changes SSH execution and relies on the repaired alias grammar. Task 7 must run after Tasks 1 and 4 because bounded reads need real cancellation and round-trip path ownership must already be settled; run it after Task 6 because both may touch plan composition.

Task 6 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-secure-ssh-execution.md` and execute it exactly. Remove every remaining alias-as-shell-syntax path, bound ControlMaster lifetime, preserve pasteable plan truth, and make one atomic commit.

Task 7 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-enforce-path-and-read-safety.md` and execute it exactly. Enforce byte-honest action boundaries, bounded remote reads, symlink-safe creation, and immutable drop destinations, with one atomic commit and adversarial tests.

### Wave 4 — final evidence pass

Run Task 8 only after Tasks 1–7 merge so its coverage work measures the repaired orchestration rather than the broken baseline.

Task 8 prompt:

> Read `ho-process/agent-tasks/agent-task-2026-09-06-close-evidence-gaps.md` and execute it exactly. Surface operation-log failure, extend enforceable coverage to safety-critical application logic, run the full verification stack, and make one atomic commit without changing product behavior outside those evidence paths.

## Integration Gate

After every merged task, run:

```bash
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet
swift build --disable-sandbox
swift test --disable-sandbox
```

After Task 8, also run:

```bash
swift test --disable-sandbox --enable-code-coverage
scripts/coverage-floor.sh 90
git status --short
```

Do not begin a later wave if an earlier task's tests fail, its commit includes unrelated files, or its agent reports an unresolved stop condition.
