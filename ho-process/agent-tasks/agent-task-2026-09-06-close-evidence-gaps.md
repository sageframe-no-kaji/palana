---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Make operation-record failure visible and place safety-critical application orchestration under enforceable automated coverage.

**Context**

Run after Tasks 1–7 have merged. This is the final evidence pass over the repaired system, not a substitute for each task's focused tests.

**Files**

- Modify: `Sources/Palana/OperationLog.swift`
- Modify: `Sources/Palana/OperationModel.swift` only to surface log health
- Modify: `Scripts/coverage-floor.sh`
- Modify: `.github/workflows/ci.yml` if the coverage command changes
- Modify/Create: tests under `Tests/PalanaTests/`

**Required Changes**

1. Give `OperationLog` observable health. Directory creation, open, seek, write, flush, and close failures must be retained and surfaced without converting a successful transfer into a failed transfer.
2. Flush explicitly at operation completion and close the handle during teardown. Tests must inject write, seek, and open failures without touching the real application-support directory.
3. Extend the coverage gate to safety-critical application logic, including `OperationModel`, `RoundTripCenter`, `SettingsModel`, and other non-rendering orchestration introduced or changed by Tasks 1–7.
4. Keep pure SwiftUI rendering exclusions where instrumentation is impractical, but do not exclude an entire target containing state and safety contracts.
5. Run the complete build, test, lint, and coverage stack and record the resulting counts in the commit body.

**Acceptance**

- [ ] Log failure is visible and does not falsely change transfer outcome.
- [ ] Log handles flush and close deterministically.
- [ ] Safety-critical application state is included in an enforced coverage calculation.
- [ ] The coverage gate cannot pass while all application orchestration remains unmeasured.
- [ ] Full verification passes from a clean worktree.

**Verification**

```bash
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet
swift build --disable-sandbox
swift test --disable-sandbox
swift test --disable-sandbox --enable-code-coverage
scripts/coverage-floor.sh 90
git status --short
```

**Do Not**

- Do not lower the existing PalanaCore floor.
- Do not count generated, vendored, or purely declarative SwiftUI files merely to inflate coverage.
- Do not let log failure abort or roll back an otherwise successful transfer.

**Commit**

Single commit with subject: `operation evidence fails visibly`
