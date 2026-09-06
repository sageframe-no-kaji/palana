---
created: 2026-09-06
type: agent-task
status: ready
parent: ho-process/reviews/2026-09-06-full-code-review.md
project: palana
---

**Goal**

Make SSH configuration parsing and mutation preserve unrelated policy, reject ambiguous local identity, and fail closed under read, write, encoding, or concurrent-edit uncertainty.

**Files**

- Modify: `Sources/PalanaCore/Field/SSHConfigParser.swift`
- Modify: `Sources/PalanaCore/Field/SSHConfigParser+User.swift`
- Modify: `Sources/PalanaCore/Field/HostBlock.swift`
- Modify: `Sources/Palana/SettingsModel.swift`
- Modify: `Sources/Palana/PalanaSession.swift`
- Modify/Create: focused tests under `Tests/PalanaCoreTests/` and `Tests/PalanaTests/`

**Required Changes**

1. Implement OpenSSH-aware tokenization for unquoted inline comments. Apply the same token rules to host enumeration, includes, user lookup, hiding, showing, and removal.
2. Treat both `Host` and `Match` as block boundaries. Removing one alias from a shared `Host foo bar` line must retain the remaining aliases and shared options; remove the block only when no aliases remain.
3. Reserve `local` for the local endpoint. Exclude or reject `Host local` consistently in parsing, onboarding validation, reloading, favorites, and restored sessions, with an explicit diagnostic rather than silent rerouting.
4. Replace `try? ... ?? ""` configuration reads with typed failures. Preserve original bytes and refuse all mutations when reading or decoding fails.
5. Make the read-transform-write transaction coordinated and compare the original content before replacement so external edits cannot be overwritten. Preserve a versioned backup of the exact prior bytes.
6. Report settings persistence failure and distinguish unsaved in-memory values from values confirmed on disk.
7. Add tests for `Match` boundaries, shared aliases, quoted and unquoted comments, invalid UTF-8, failed reads, external changes between read and write, reserved `local`, backup fidelity, and settings write failure.

**Acceptance**

- [ ] Removing one alias cannot remove another alias or a following `Match` block.
- [ ] Inline comments never become aliases or include paths.
- [ ] A real SSH alias named `local` cannot enter the endpoint registry.
- [ ] Read or decode failure leaves the SSH configuration byte-identical.
- [ ] Concurrent external edits cannot be overwritten silently.
- [ ] Backups preserve exact prior bytes and are not a single overwritten slot.
- [ ] Settings persistence failures are visible.
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

- Do not rewrite or normalize unrelated SSH configuration.
- Do not flatten included files into the top-level file.
- Do not change SSH process execution or ControlMaster behavior; Task 6 owns them.
- Do not represent read failure as an empty configuration.

**Stop Condition**

If Foundation file coordination cannot provide an atomic compare-and-replace against an external editor, stop and present the locking boundary before choosing a weaker transaction silently.

**Commit**

Single commit with subject: `ssh config edits preserve unrelated policy`
