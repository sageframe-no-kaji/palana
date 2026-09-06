---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Ensure SSH aliases remain data rather than shell or option syntax in every execution route, and ensure crashed ControlMaster sessions expire or are swept safely.

**Context**

Begin from branches containing Tasks 1 and 5. Task 5 establishes the accepted alias grammar; this task enforces safe execution even for restored or legacy data.

**Files**

- Modify: `Sources/PalanaCore/Conduit/SSHConduit.swift`
- Modify: `Sources/PalanaCore/Transports/SSHPipeline.swift` if its structured launch still needs validation
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift`
- Modify/Create: focused tests under `Tests/PalanaCoreTests/`

**Required Changes**

1. Validate SSH destinations before process launch, including rejection of leading `-` and tokens outside Task 5's safe alias grammar.
2. Quote every host alias that appears inside a shell command, including direct tar and forwarded ZFS routes. Structured pipeline execution must pass aliases as arguments rather than reconstructing shell syntax.
3. Preserve the plan's pasteable command as a truthful equivalent of the structured execution path.
4. Replace indefinite `ControlPersist=yes` with a finite value and perform startup cleanup for stale sockets owned by the current user. Verify the control directory's owner and mode before use.
5. Add tests for metacharacters, leading-option aliases, direct tar, forwarded and proxied ZFS display commands, structured pipeline arguments, stale sockets, wrong-owner or wrong-mode directories, and normal shutdown cleanup.

**Acceptance**

- [ ] No accepted alias can create local or remote shell syntax.
- [ ] Leading-hyphen aliases cannot become SSH options.
- [ ] Displayed pipeline commands remain pasteable and semantically equivalent.
- [ ] Crashed masters have a finite lifetime or are removed at startup.
- [ ] Unsafe control-directory ownership or permissions fail closed.
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

- Do not broaden the accepted alias grammar beyond Task 5's result.
- Do not remove multiplexing merely to avoid lifecycle work.
- Do not leave the displayed command less safe than the structured execution.

**Commit**

Single commit with subject: `ssh aliases never become command syntax`
