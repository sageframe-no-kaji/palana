---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Make every command and SSH pipeline an owned resource that can be cancelled, awaited, and cleaned up. Workbench reads must drain both channels concurrently and report nonzero exit status.

**Problem**

Cancelling the Swift task currently changes UI state without terminating its operating-system processes. Pipeline startup failure can orphan the producer, and Workbench reads can deadlock by draining stdout before stderr.

**Files**

- Modify: `Sources/PalanaCore/Conduit/Conduit.swift`
- Modify: `Sources/PalanaCore/Conduit/SSHConduit.swift`
- Modify: `Sources/PalanaCore/Transports/SSHPipeline.swift`
- Modify: `Sources/PalanaCore/Transports/Transports.swift`
- Modify: `Sources/Palana/OperationModel.swift`
- Modify: tests under `Tests/PalanaCoreTests/` and `Tests/PalanaTests/`

**Required Changes**

1. Give `RunningCommand` an idempotent cancellation operation backed by its spawned process or process group. Cancellation must close relevant handles and permit callers to await final termination.
2. Add cancellation handlers throughout `Transports` so stream termination stops the active host command or both pipeline halves before reporting cancellation.
3. If the pipeline consumer cannot launch, immediately terminate and await the producer. Every exit path must close the pump and both stderr streams.
4. Make `OperationModel.cancelEnactment()` await actual teardown before entering `.cancelled`; never report that the work stopped while a destructive process remains live.
5. Drain Workbench stdout and stderr concurrently, await exit, retain bounded error context, and surface nonzero status.
6. Add integration tests using controllable local child processes. Prove cancellation prevents a delayed side effect, consumer-launch failure leaves no producer, repeated cancellation is safe, and high-volume stderr cannot deadlock a read.

**Acceptance**

- [ ] Cancelling an enactment terminates its active child process before `.cancelled` is published.
- [ ] Cancelling a proxied pipeline terminates and awaits both halves.
- [ ] Consumer-launch failure cannot leave a producer running.
- [ ] Workbench reads drain both channels concurrently and report nonzero exits.
- [ ] Cancellation is idempotent and covered by deterministic tests.
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

- Do not change move verification or plan classification; Task 2 owns them.
- Do not solve cancellation by detaching cleanup or merely suppressing UI events.
- Do not report `.cancelled` until every owned process has reached a terminal state.

**Stop Condition**

If safe cancellation requires changing the public `Conduit.run` contract beyond adding lifecycle control to `RunningCommand`, stop and present the required contract before implementing a broader redesign.

**Commit**

Single commit with subject: `commands stop before cancellation is reported`
