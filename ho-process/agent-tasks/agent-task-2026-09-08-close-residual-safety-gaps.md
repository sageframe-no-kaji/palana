---
created: 2026-09-08
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Close the residual safety gaps found after the 2026-09-06 repair program: bind round-trip replacement and move deletion to the exact bytes that were verified, terminate commands whose merged output consumer is cancelled, and make the SSH-config transaction test fail diagnostically rather than crash. Preserve data rather than narrowing a check-then-act race and calling it closed.

**Problem**

The repair program fixed the original static failure cases and added substantial adversarial coverage, but a 2026-09-08 follow-up audit found three remaining runtime gaps.

First, round-trip send-back reads the remote digest and then composes an ordinary copy plan. The plan carries no expected remote version, so another writer can change the destination after the check and before the upload; the upload then overwrites work that was never approved for replacement.

Second, a move manifests the source, then the destination, then releases its delete step. Those manifests are snapshots, not a state binding: a source edit after its manifest can be deleted without reaching the destination, while a destination change after its manifest can invalidate the evidence on which source deletion depends.

Third, `RunningCommand.output()` cancels only its Swift stream pump when the consumer is cancelled. A local reproduction cancelled a consumer of a 30-second command and confirmed that the child process remained alive. `runWorkbenchRead` launches an unowned task over this path, so a stalled read can outlive the consumer or session.

The earlier CI signal-6 abort is already repaired on current `main` by `4d6d15e`; GitHub Actions run `34271724860` is green. This task must preserve that repair and finish with the same full workflow green.

**Context**

The governing safety invariant is version binding: verification authorizes action only against the exact filesystem version that produced the evidence. A later version must never be silently overwritten or deleted merely because an earlier version passed a check.

Cross-host filesystems do not provide one universal compare-and-swap API. When a target cannot support a defensible version-bound commit, Palana must fail closed, retain recoverable bytes, and explain why; it must not substitute a second preflight check whose only effect is to make the race shorter.

The move and round-trip paths may use different mechanisms, but they must implement the same invariant and expose typed evidence or refusal. The task does not reopen address parsing, topology binding, SSH alias grammar, or the other completed findings.

**Files**

- Modify: `Sources/Palana/OperationModel+RoundTrip.swift`
- Modify: `Sources/Palana/PalanaSession+RoundTrip.swift`
- Modify: `Sources/PalanaCore/Surface/RoundTrip.swift`
- Modify: `Sources/PalanaCore/Plan/Plan.swift`
- Modify: `Sources/PalanaCore/Plan/PlanRequest.swift`
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift`
- Modify: `Sources/PalanaCore/Transports/Transports.swift`
- Modify: `Sources/PalanaCore/Transports/TransferManifest.swift`
- Modify: `Sources/PalanaCore/Transports/EnactmentEvent.swift`
- Modify: `Sources/PalanaCore/Conduit/Conduit.swift`
- Modify: `Sources/Palana/OperationModel+ToolReads.swift`
- Modify: `Sources/Palana/PalanaSession+ZFS.swift`
- Modify: `Tests/PalanaCoreTests/RoundTripConflictTests.swift`
- Modify/Create: focused round-trip commit tests under `Tests/PalanaTests/`
- Modify: `Tests/PalanaCoreTests/TransportsManifestTests.swift`
- Modify: `Tests/PalanaCoreTests/TransportsLocalGateTests.swift`
- Modify/Create: focused move-race tests under `Tests/PalanaCoreTests/`
- Modify: `Tests/PalanaCoreTests/ProcessOwnershipTests.swift`
- Modify: `Tests/PalanaTests/OperationCancellationTests.swift`
- Modify: `Tests/PalanaTests/SettingsModelConfigTests.swift`
- Read-only: `ho-process/reviews/2026-09-06-full-code-review.md`
- Read-only: `ho-process/agent-tasks/agent-task-2026-09-06-harden-round-trip-integrity.md`
- Read-only: `ho-process/agent-tasks/agent-task-2026-09-06-verify-moves-before-delete.md`
- Read-only: `ho-process/agent-tasks/agent-task-2026-09-06-own-and-cancel-processes.md`

If the implementation needs a dedicated value type or protocol, create one narrowly named file beside the owning subsystem rather than enlarging an unrelated file past the repository lint budget. Record every additional file in the commit body.

**Required Changes**

1. **Add failing adversarial tests before changing production code.**

   Reproduce each residual failure through an injected seam rather than sleeps or live infrastructure.

   - Round trip: the destination begins at the fetched digest, changes after the clean check, and changes before replacement. The later bytes must not be lost or silently replaced.
   - Move: mutate the source after its first verification observation but before deletion. The changed source must remain recoverable and the destructive release must refuse.
   - Move: mutate the destination after its verification observation but before source deletion. The source must remain recoverable and the destructive release must refuse.
   - Process output: cancel a consumer of `RunningCommand.output()` while a real local child is sleeping. Cancellation must terminate the complete process group and await its exit before the consuming task finishes.

   Each test must fail against the current implementation for the stated reason. Put deterministic hooks at protocol boundaries; do not add production sleeps.

2. **Bind round-trip replacement to the verified remote version.**

   Replace the check-then-ordinary-copy path with a version-bound commit contract.

   - Carry the exact remote host, byte-honest path identity, expected presence, and expected content digest from conflict evaluation into enactment. A plain `PlanRequest(operation: .copy, ...)` with no expected version is not sufficient.
   - Upload new content to a unique temporary entry on the destination filesystem. The requested destination path must not be modified while bytes are still transferring.
   - At commit, prove that the destination still represents the expected baseline. If it is missing, changed, unreadable, replaced, or cannot be compared, refuse the commit and retain the operator's local edit.
   - Promotion must not silently destroy an intervening destination version. Use a platform-supported conditional operation when available; otherwise preserve the displaced version in a uniquely named recovery entry before promotion. If neither guarantee can be provided, disable automatic send-back for that host/path and return a typed refusal.
   - Apply the same guard after an operator-confirmed conflict because the destination may change while the panel waits for Enter. Confirmation authorizes the observed conflict, not any later version.
   - Clean up operation-owned temporary entries after success or refusal. If cleanup fails, surface the retained path; never swallow it.
   - Keep the existing three-state `clean` / `conflict` / `unavailable` decision and exact-record watcher behavior. This change binds enactment to that decision rather than replacing it.

3. **Bind move deletion to stable source and destination evidence.**

   A move may delete only bytes that are represented at the destination and have not changed since they were verified.

   - Introduce an explicit move-release state carrying the source identity and source/destination manifests that authorize deletion. Do not use a Boolean `gatesReleased` as the complete authorization.
   - Before destructive release, place each source top-level entry under an operation-owned, same-filesystem quarantine or use another mechanism that prevents a newly created entry at the original pathname from being included in deletion. The operation token must make every quarantine identity unique.
   - Re-manifest the exact quarantined source and destination after the source is frozen. Release deletion only when every quarantined source entry is represented identically at the destination.
   - If the source changes, the destination changes, a manifest fails, or the original pathname becomes occupied, preserve the quarantined source and report its recovery location. Never delete or overwrite the newer entry to restore appearances.
   - A crash or cancellation after quarantine must leave enough durable, visible evidence to recover the source. Use the existing operation record where it can carry this truth; do not create an untracked hidden tomb.
   - Preserve the existing subset rule for merge moves: destination-only entries do not invalidate a move, while every source entry must be present with the same kind, size, digest, and symlink target.
   - True same-filesystem renames remain atomic renames and do not need the copy/manifest/quarantine route. Kind clashes remain refused before enactment.

4. **Make merged-output cancellation own the child process.**

   Repair `RunningCommand.output()` and its Workbench caller.

   - When output consumption is cancelled or abandoned before normal completion, terminate the owned process group rather than only cancelling the two stream pumps.
   - The async caller must await process exit before reporting cancellation or releasing its task.
   - Make the Workbench-read task explicitly owned and replaceable by the session or operation model. Starting a replacement read or shutting down must cancel and await the prior read.
   - Preserve concurrent stdout/stderr draining, bounded stderr retention, nonzero-exit reporting, and the existing transport cancellation behavior.
   - Add a regression using a real local child and a delayed side-effect marker, matching the process-ownership fixtures already in the repository.

5. **Make the config-transaction test fail without crashing.**

   In `SettingsModelConfigTests.versionedBackups`, require the expected backup count before indexing the array.

   - Replace the non-blocking count expectation with `#require` or an equivalent guard.
   - Preserve the byte and permission assertions when the prerequisite holds.
   - Do not weaken or skip the test in restricted environments; the test should report the file-coordination failure cleanly without producing an index-out-of-range abort.

6. **Preserve and extend evidence.**

   - Every refusal must identify the host, path, operation, and reason without printing file contents or credentials.
   - Operation events and records must distinguish upload, verification, quarantine, promotion, restoration, retained recovery data, and final deletion.
   - Codable plan changes must decode plans written before this task. Old plans lacking a version guard must never gain destructive authority by default; refuse or route them through a non-destructive compatibility path.
   - Do not lower either coverage floor or expand the rendering exclusion pattern.

**Acceptance**

- [ ] A round-trip destination changed after the clean check is never silently overwritten.
- [ ] Automatic and operator-confirmed send-back both revalidate the exact expected remote version at commit.
- [ ] A host without the required commit guarantee fails closed or preserves the displaced version in a named recovery entry.
- [ ] A source changed after copy or initial verification is never deleted as though its newer bytes were transferred.
- [ ] A destination changed after initial verification never authorizes source deletion from stale evidence.
- [ ] Move interruption after quarantine leaves a named, recoverable source and a durable operation record.
- [ ] Merge moves retain destination-only entries while still proving every source entry.
- [ ] Cancelling or abandoning `RunningCommand.output()` terminates and reaps the process group.
- [ ] Workbench reads are owned, replaceable, and cancelled during shutdown.
- [ ] `SettingsModelConfigTests.versionedBackups` cannot index an array whose required count failed.
- [ ] Existing plan files decode safely, while unguarded legacy plans cannot perform a newly guarded destructive release.
- [ ] No test under `Tests/PalanaTests` constructs a live `SSHConduit`.
- [ ] Format, lint, build, the complete test suite, and both coverage floors pass at one commit.
- [ ] GitHub Actions is green after the completed commits are integrated and pushed.

**Verification**

```bash
# The task begins from a clean, current main.
git status --short --branch
git log -1 --oneline

# Focused regression suites. Add the exact new suite names to this filter.
swift test --disable-sandbox --filter \
  'RoundTripConflictTests|RoundTripCenterTests|MoveRelease|TransportsManifestTests|TransportsLocalGateTests|ProcessOwnershipTests|OperationCancellationTests|SettingsModelConfigTransactionTests'

# Complete local gate.
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet --no-cache
swift build --disable-sandbox
swift test --disable-sandbox
swift test --disable-sandbox --enable-code-coverage --no-parallel
scripts/coverage-floor.sh 90 35

# Structural guards.
grep -RIn 'SSHConduit(' Tests/PalanaTests \
  && echo 'application tests opened a live SSH conduit' && exit 1 || true
grep -RIn 'continuation.onTermination = { _ in pump.cancel() }' Sources \
  && echo 'output cancellation still stops only the pump' && exit 1 || true

# Inspect the final plan and transport contracts: no round-trip auto-send
# may compile to an unguarded ordinary copy, and no gated delete may be
# authorized by a bare Boolean detached from the manifests it represents.
grep -RIn 'RoundTrip\|gatesReleased\|MoveRelease\|quarantine' \
  Sources/Palana Sources/PalanaCore/Plan Sources/PalanaCore/Transports

# Every commit is clean and the final stack contains only task-authorized changes.
git diff --check
git status --short
git log --oneline --decorate -8
```

Post-push verification:

```bash
gh run list --limit 3 --json headSha,status,conclusion,url
gh run watch --exit-status
```

The executing agent reports the exact final HEAD and test counts. The orchestrating agent performs the push and post-push CI check if the executing worktree is intentionally isolated from `main`.

**Do Not**

- Do not claim a race is closed because a second digest or manifest check makes the window smaller.
- Do not overwrite an intervening remote version without preserving it under a visible recovery identity.
- Do not delete from the original source pathname after it has been released for reuse by another writer.
- Do not hide quarantined or displaced data without recording its exact recovery path.
- Do not weaken automatic send-back conflict policy, move verification contents, merge subset semantics, or kind-clash refusal.
- Do not add shell interpolation of host aliases or unquoted paths; retain the existing argument and quoting boundaries.
- Do not contact configured personal hosts from tests. Use injected conduits, local fixtures, or the CI sshd fixture only.
- Do not modify the completed address grammar or recovery behavior.
- Do not lower coverage floors, skip failing tests, or change CI to ignore a nonzero test exit.
- Do not edit state memory or mark the full review closed; the orchestrator owns final integration records after independent verification.

**Stop Condition**

Stop and surface a protocol proposal before implementation if the supported host/filesystem matrix cannot provide either a version-bound commit or a recoverable displaced version for round-trip send-back. Do not silently choose a best-effort overwrite.

Stop and surface before destructive implementation if a move source cannot be frozen or quarantined without creating an unrecorded crash-recovery state. The acceptable fallback is a copy that keeps the source, not a delete authorized by stale evidence.

Stop if current `main` has advanced in any file listed under **Files** after the task worktree was created. Rebase or recreate the worktree through the orchestrator before continuing so tests and commit claims refer to one base.

**Commit**

Produce four reviewable commits in this order:

1. `round trips commit against a bound remote version`
2. `moves release only frozen source bytes`
3. `output consumers terminate their commands`
4. `config tests require backups before indexing`

Each commit body must name the failure reproduced, the invariant introduced, the focused tests added, and their passing count. Run the complete verification stack after the fourth commit and report the final HEAD; do not squash unless the orchestrator explicitly requests it.
