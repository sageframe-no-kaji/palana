---
created: 2026-11-15
type: agent-task
status: ready
parent: ho-process-private/reviews/2026-11-15-pre-1.0-review.md
project: palana
---

**Goal**

Close the remaining findings of the pre-1.0 review before v1.0 ships. Moves keep extended attributes where both ends can, or say they won't. A failed or cancelled move still reports which sources remain. Send-back no longer empties a remote path on filesystems without hard links. Retained-source notes survive long reports. A failed send-back no longer leaves its staging folder behind unannounced. Settings says custom rsync flags apply to copies only.

**Context**

- Precondition: branch `v1-release` carries the committed pre-1.0 fixes for findings 1, 2, 3, 5, 6, 9, 10 and 12. Verify `git log v1-release`, and that `git status` is clean on that branch, before you start. If not, stop and say so.
- Work on a new branch `review-remainder` cut from `v1-release`, in a sibling worktree: `git branch review-remainder v1-release && git worktree add ../palana-review-remainder review-remainder`.
- Read the review, `ho-process-private/reviews/2026-11-15-pre-1.0-review.md`, findings 4, 7, 8, 11 and 13. Each has WHERE, SCENARIO and FIX. The fixes there are the starting point, not a mandate. Choose the smallest correct fix, and record the choice in the commit body.
- Moves no longer take operator rsync flags (`rsyncFlags(... removingSource: true)` drops them, in `Sources/PalanaCore/Plan/PlanEngine+Rsync.swift`). A same-host progressive move now starts with a place-guard step (`PlanEngine.placeGuardStep`, in `PlanEngine+Safety.swift`). `Transports.validateProgressiveMovePlan` enforces the step shape. Any change to a move's steps must keep that contract and its tests in agreement.
- Capability probing lives in `CapabilityProbe` (`HostCapability.rsync`, `rsyncVersion`, `rsyncPath`). `rsync --version` lists "xattrs" and "ACLs" among its capabilities when they are compiled in. openrsync supports neither.

**Files**

- Modify: `Sources/PalanaCore/Plan/PlanEngine+Rsync.swift`, `Sources/PalanaCore/Plan/PlanEngine.swift` (finding 4)
- Modify: `Sources/PalanaCore/Conduit/CapabilityProbe.swift` and `HostCapability` wherever it is declared (finding 4: the xattr/ACL capability, defaulting to absent so old caches decode)
- Modify: `Sources/PalanaCore/Plan/Plan.swift` or the plan warning composition (finding 4: the warning line)
- Modify: `Sources/PalanaCore/Transports/Transports.swift`, `Sources/PalanaCore/Transports/Transports+ProgressiveMove.swift` (finding 7)
- Modify: `Sources/PalanaCore/Plan/RemoteVersionGuard.swift` (finding 8)
- Modify: `Sources/PalanaCore/Transports/EnactmentEvent.swift`, `Transports.swift` (finding 11)
- Modify: `Sources/PalanaCore/Plan/PlanEngine+Binding.swift` (finding 13)
- Modify: `Sources/Palana/SettingsCard.swift` (the helper text at the "more flags" field, near line 382)
- Create: `Tests/PalanaCoreTests/ReviewRemainderTests.swift` (or extend the matching existing suites, one test per finding at minimum)
- Modify: `README.md`, `CHANGELOG.md` (v1.0 entry: moves and metadata, failed-move accounting)

**Required Changes**

1. **Finding 4, metadata on moves.** On a progressive move:
   - Add `-X` when the running rsync and the receiving rsync both report xattr support. Add `-A` when both report ACL support.
   - When either end lacks them, including openrsync, the plan carries one warning line that names what will not be kept: extended attributes, Finder tags, ACLs.
   - Copies are unchanged.
   - Probe support from `rsync --version` into `HostCapability`, optional and defaulting to nil.
   - Test both paths with recorded capabilities.
2. **Finding 7, accounting after failure.** When a progressive move's transfer step fails or is cancelled after it started, Transports still runs the leftover-source report step (never the empty-directory sweep), so `palana-retained:` notes name what remains. The run's result stays failed or cancelled. Test with a transfer step that exits 23 partway, using the existing transcript fakes.
3. **Finding 8, send-back without hard links.**
   - Restore the set-aside version with `mv -n -- kept entry`, not `ln`.
   - When the promoting `ln` fails, tell "exists" apart from "unsupported" (`[ -e entry ]`). On unsupported, fall back to a no-clobber rename promotion, or refuse before setting the original aside. Pick one and say which in the commit.
   - Keep the staged copy, and name it in a `palana-retained:` note, whenever the commit does not land.
   - Test the composed script under `/bin/sh` in a scratch directory, with `ln` failing. Use a function override or a PATH shim; you can't count on an exFAT volume.
4. **Finding 11, long reports.** Parse `palana-retained:` notes from the full stderr stream, line by line as chunks arrive, with lossy UTF-8 decoding, rather than from the 4 KiB tail. Test with 60 long-path notes and a multi-byte character across a chunk boundary.
5. **Finding 13, staging after a failed send-back.** When the transfer step of a version-bound send-back fails, remove the staging directory, or emit a retained note naming it. Test that the failure leaves either no `palana-send-*` directory or a note naming it.
6. **Settings text.** Change the helper under "more flags" to say the flags apply to copies only, and that moves use pālana's own flags. Keep the existing "always on" facts.
7. **Docs.** README and CHANGELOG v1.0 entry gain one line each for metadata on moves and for what a failed move reports. Remove anything in the README's known limits that this task resolved.

**Acceptance**

- [ ] Each of findings 4, 7, 8, 11 and 13 has at least one test that fails against `v1-release` and passes after the change. Name the test in the commit body.
- [ ] `validateProgressiveMovePlan` and its tests agree with any change to a move's step shape.
- [ ] The Settings helper text says copies only.
- [ ] The verification stack is green, with the sshd fixture running.

**Verification**

```sh
cd ../palana-review-remainder
scripts/sshd-fixture.sh start
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test --enable-code-coverage
scripts/coverage-floor.sh 90 35
grep -n "copies only" Sources/Palana/SettingsCard.swift
```

**Do Not**

- Do not change drag and drop. That is `agent-task-2026-11-15-drag-out-and-freeze.md`, running in parallel on its own branch.
- Do not loosen any refusal added on 2026-11-15 (place guard, flag rules, enactment token check).
- Do not run mutating commands against any live host. Use fixtures and scratch directories only.
- Do not push, merge into `main`, or tag.

**Stop Condition**

Halt, write findings under a new heading at the end of the review file, and ping the ntfy topic in `prompts/ntfy-topic.txt`, if any of these happens:

- A finding's fix would change what an existing plan shows the operator, beyond one added warning line.
- `-X` across a Mac-to-Linux move fails on a recorded or fixture rsync in a way that would fail real moves.
- The finding 8 fallback cannot be made no-clobber with POSIX tools.

**Commit**

One commit per finding, plus one for Settings and one for docs, on `review-remainder`. Subjects are plain and descriptive, for example "keep extended attributes on moves where both rsyncs can", "report retained sources after a failed move". No AI attribution of any kind. Stage explicit paths, never `git add -A`.

**Practitioner rulings (2026-11-15, planning)**

- D1, finding 8: the commit refuses before setting anything aside when the destination filesystem has no hard links, and says why with a distinct exit code. Like the other refusals before the set-aside, it clears staging; the edit stays in the Mac's round-trip copy. The "no-clobber with POSIX tools" stop condition does not apply to the rename mode: the practitioner accepted its check-then-rename gap as an explicit, per-send opt-in. **Scope extended by the practitioner:** the app then offers "Replace without the safe check", which re-runs the send-back in a rename commit mode (`mv -n`, then a content check). The guard carries the mode, defaulting to link so old plans decode; enactment accepts rename only when the guard names it. Own commit, after finding 8.
- D2, finding 4: `-A` only when both rsyncs report ACLs and both hosts run the same kernel. Across kernels the notice names ACLs as not kept.
- D3, finding 8: the staged copy is kept and named only on failures after the set-aside. Earlier refusals still clear staging.
- D4, finding 13: a retained note naming the staging directory; no unshown command. Visible cleanup step deferred, recorded in the review file.
