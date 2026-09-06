---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Bind every destructive ZFS plan to fresh topology and exact postconditions. Prevent asynchronous snapshot context from crossing between gathers.

**Problem**

Cached topology survives across launches and failed subprobes preserve older values, so current paths can be mapped to obsolete datasets. ZFS verification currently proves only that a query ran, not that the requested state exists.

**Files**

- Modify: `Sources/PalanaCore/Field/Field.swift`
- Modify: `Sources/PalanaCore/Field/HostFacts.swift`
- Modify: `Sources/PalanaCore/Plan/Plan.swift`
- Modify: `Sources/PalanaCore/Plan/PlanEngine+ZFSComposition.swift`
- Modify: `Sources/Palana/OperationModel+Gather.swift`
- Modify: `Sources/Palana/OperationModel+ZFS.swift`
- Modify: `Sources/Palana/OperationModel.swift` only if required for pre-enactment validation
- Modify/Create: focused tests under `Tests/PalanaCoreTests/` and `Tests/PalanaTests/`

**Required Changes**

1. A plan that uses topology, mounts, capability, or sudo facts must gather them fresh for that plan. A failed topology or mount read must become explicit unavailable state rather than retaining older plan-authorizing values.
2. Record a fact generation or fingerprint on plans whose routing or destructive target depends on topology. Immediately before enactment, refresh and compare the relevant dataset names, mountpoints, mounted states, and selection relationship; refuse on any mismatch or unavailable refresh.
3. Keep discovery cache useful for display, but prohibit stale cached facts from authorizing `zfs send`, `zfs receive`, rollback, or destroy.
4. Change mountpoint verification to assert the exact expected value. Change mount and unmount verification to assert `mounted=yes` or `mounted=no` respectively.
5. Store and cancel the snapshot-context task. Commit its result only when a captured generation, host, dataset, and verb still match the current gather.
6. Add tests reproducing a moved mountpoint, a failed refresh retaining old cache, a plan/enactment topology change, wrong mountpoint output with exit 0, wrong mounted state with exit 0, and out-of-order snapshot-context completion.

**Acceptance**

- [ ] Cached topology alone cannot authorize a destructive ZFS plan.
- [ ] Failed critical subprobes cannot leave old facts eligible for planning.
- [ ] Enactment refuses when fresh topology differs from the plan-bound facts.
- [ ] ZFS verify steps assert exact requested state.
- [ ] Late snapshot-context results cannot alter another gather.
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

- Do not remove timestamps or the display cache; stale facts may still be shown when labeled.
- Do not weaken typed confirmation for destructive ZFS verbs.
- Do not make a failed refresh fall back to the last known destructive target.

**Stop Condition**

If plan-bound fact validation requires changing `Plan` serialization incompatibly, stop and present a backward-compatible migration before proceeding.

**Commit**

Single commit with subject: `zfs plans bind to fresh topology truth`
