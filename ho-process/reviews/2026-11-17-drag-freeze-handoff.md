---
created: 2026-11-17
status: open; merge accepted with known issue
type: review
project: palana
---

# Drag freeze: operational handoff after accepted merge

## Decision

The practitioner explicitly authorized merging `v1-release` into `main`,
leaving the intermittent freeze as an open issue, and continuing other work.
They then requested extensive Markdown documentation so the investigation is
not lost. This supersedes the agent's earlier proposal to keep the merge
blocked and to continue native-table experiments immediately. It does not
authorize a new build, signing run, tag or release publication. Do not restart
screen replay or rewrite the file table without a new task.

The public technical record is `../../docs/known-issues/drag-freeze.md` in the
parent Palana checkout; GitHub issue #4 links to it. It contains the current
behavior matrix, signatures, chronological experiment table, exact latest
incident, replay results, limitations and requirements for a future fix.
Use that record for conclusions; use this private companion for local paths.

The merge and public documentation were pushed to `origin/main` as `78c0fd7`.
Issue #4 remains open and links to the public record. The application source
matches `ff203c7`; the follow-up commit changes documentation only. Main is the
active checkout. No tag exists for this work and no release was published.

## Current artifact locations after worktree consolidation

On 2026-11-17 the practitioner also authorized removing `palana-dist`,
`palana-drag-native` and `palana-release-20261117`. All three commits were
confirmed ancestors of main; none had tracked changes or nonignored untracked
files. The old dist checkout was locked by Supacode and contained only build
cache beyond its tracked source. Its lock was removed for authorized cleanup.

The signed app and installer are now in the parent checkout:

- `dist/Palana.app`
- `dist/palana-1.0.0.dmg`

The copied app's signature verified and the DMG SHA-256 remains
`c9b39f067ed5bb826936f27acb6c772fbb40967ae8bcb23121e3b928f7763412`.
No rebuild, re-signing, tag or release publication occurred.

Archive root in the parent checkout:
`.fixtures/archives/worktree-cleanup-20261117/`.

- `drag-native/.fixtures/` replaces the old implementation fixture path.
- `drag-native/dist/` retains the saved hands-passed and other candidate apps.
- `release/dist/` retains another exact copy of the signed release artifacts.
- `previous-main-dist/` retains what was in the main checkout's dist beforehand.
- `manifest.json` records hashes and source commits; 333 copied entries totaling
  596,817,416 bytes were verified, including the new main dist copy.

The archive is ignored by Git and its root is mode 0700. It includes private
fixture SSH material and must not be committed or published. Scripts/configs
inside retain historical paths: adapt those paths before running them; this
is an evidence archive, not a newly configured runnable test environment.
The build caches were not preserved. Historical paths in the rest of this
record should be resolved through the mapping above.

Remaining registered worktrees are only the parent `palana` checkout on main
and `../palana-v1-docs` on v1-docs. The documentation worktree was not part of
the requested cleanup. Branch drag-freeze-fix remains; its code is in main.
An unrelated local main commit caf4661 was present and left untouched/unpushed.

## Build and branch identities

All paths below are relative to the parent `palana/` checkout unless absolute.

| Item | Identity / location |
| --- | --- |
| Application source accepted for merge | `ff203c7` on `v1-release`; application source matches `ee3c137` |
| Drag scope commit | `ee3c137`, branch `drag-freeze-fix`, worktree `../palana-drag-native` |
| Merge into release branch | `daf537f` |
| Installer signing correction | `ff203c7`; only `scripts/build_macos.sh` changed |
| Current signed app | `../palana-release-20261117/dist/Palana.app` |
| Current signed DMG | `../palana-release-20261117/dist/palana-1.0.0.dmg` |
| Saved hands-passed candidate | `../palana-drag-native/dist/Palana-Pane-Drag-Restored.app` |
| Abandoned runtime-patched source branch | `drag-out`, tip `2be783e`; checkout removed after verified archive on 2026-11-17 |
| Unrelated documentation branch | `v1-docs`, tip `0d81fa7`; not part of this merge |

Signed ARM64 executable UUID: `C8A2B805-1469-381D-922D-E4BD42A894FC`.
Saved candidate ARM64 UUID: `95B98F84-3F3B-3106-97C6-A0C862DD79F6`.
Saved candidate executable SHA-256:
`d5b5a398353e2f0dee1dca653ff3aff6aa0e1bea83aae71bb60e088f4c0e6d09`.
Signed DMG SHA-256:
`c9b39f067ed5bb826936f27acb6c772fbb40967ae8bcb23121e3b928f7763412`.

Do not run `scripts/build_macos.sh` in the implementation worktree without
first preserving `dist/`; the script deletes that directory. The signed
release worktree is detached at `ff203c7`. No final rebuild is necessary to
merge the existing source. Packaging checks passed but cannot prove UI safety.

## Latest failure: exact evidence

The practitioner reported the first drag from storage-host froze the signed app.
At capture time `pgrep` showed PID 17048 running the signed app path above.
Unified logs and a three-second sample were collected before termination.
The sample UUID was later compared against the current signed executable and
the saved candidate; it identifies the signed candidate, not an old build.

Times on 2026-11-17 EST: launch 13:51:34.149; drag-server activation
13:51:48.731; cancellation with `CALayerInvalidGeometry` .773; HIServices fault
.809; sample 13:54:09.125. Destination clarification was asked but not answered.
Do not silently turn this into another confirmed Chrome case. The earlier
`linkage2.msi` remote-to-Chrome case on 2026-11-16 is distinct.

The latest incident happened with remote external delivery already disabled.
That restriction is not complete freeze containment. Remote-to-pane drags
remain enabled at the practitioner's explicit request. A separate blanket
remote gate and conditional row modifier previously caused scope/click
regressions; neither should be casually restored.

## Evidence preserved in this private repository

The directory [drag-freeze-evidence-2026-11-17](drag-freeze-evidence-2026-11-17/)
contains copies of eleven evidence/source files, plus `manifest.json` with
original absolute paths and SHA-256 values:

- `palana-latest-freeze.log`: signed-candidate event times and exception.
- `palana-signed-freeze-sample.txt`: process sample and loaded binary UUID.
- `saved-batch1.log`, `saved-batch2.log`: 5 + 15 saved-candidate attempts;
  twenty writers and accepted drops, no failure signature.
- `release-batch1.log`, `release-batch2.log`: 5 + 15 signed-candidate attempts;
  nineteen writers and accepted drops, no failure signature. The missing
  initiation is not a successful drag.
- `destination-probe.log`, `DragDestinationProbeTests.swift`: offscreen
  hierarchy inspection; only the intended Catcher receivers were registered.
  Temporary probe test was removed from the production test target afterward.
- `run-batch.py`: exact batch runner used in the local experiment; its relative
  paths assume the original fixture location, not this archive directory.
- `NativeTableProbe.swift`, `status.json`: compiled standalone AppKit experiment
  and its limits. It was not physically tested or integrated into production.

These files contain private workstation/fixture details. Do not publish the
directory, attach its raw contents to GitHub, or export it through ho-process.
No account credentials are intended to be stored here.

## Remaining local evidence and tools

Root: `../palana-drag-native/.fixtures/drag-freeze-20261116/`.

| Subpath | Contents / caveat |
| --- | --- |
| `3ping.jsonl` | Extracted 398-event recorded trackpad drag, original time interval 135.6–137.9; 1.29 seconds of events |
| `replay.swift` | Restamps event timestamps and clears stale window IDs; supports x/y translation |
| `storage-host-recurrence/replay` | Compiled replay executable used in latest comparison |
| `signing-comparison/` | Latest profiles, logs, batch runner, offscreen probe and signing variants |
| `signing-comparison/Saved-Signed.app` | Saved binary with Developer ID/hardened runtime signing; not replayed |
| `signing-comparison/Release-Adhoc.app` | Release binary with ad-hoc signing; not replayed |
| `remote-internal-only/source.patch` | Snapshot of the candidate accepted in manual testing |
| `finder-command-move/` | Failed local Finder-move attempt; issue #6, excluded from current source |
| `finder-command-move-deferred/` | Changes archived before rollback |
| `finder-command-move-check/` | Superseded move diagnostic; not a pending screen task |
| `native-table-probe/Palana-Native-Drag-Probe.app` | New standalone probe, not a release build; self-check only |
| `appkit-batch-a.*`, `swiftui-control-a.*`, `final-*.txt` | Earlier destination comparison and clean replay results |

Additional fixture root: `../palana-drag-native/.fixtures/handcheck/`.
`Arduino/` mirrors the local directory for consent-prompt-free testing.
`recordings/hands-1044.jsonl` contains the original recorded sequence.
`handcheck.sh setup` is not a safe unattended launcher: it uses the normal SSH
config, opens other apps and starts recording. Read and adapt it rather than
running it wholesale. Use the isolated profile and localhost config below.

SSH fixture config: `../palana-drag-native/.fixtures/ssh_config`.
It maps `fixture` to localhost port 2223 and user `palana`. Its key files stay
outside Git. Remote fixture directory: `/tmp/palana-remote-drag`, containing
`3ping.msi`, `a.txt`, `b.txt`. Use `PALANA_SSH_CONFIG` and `CFFIXED_USER_HOME`
when launching, not the practitioner's live storage-host configuration.

The latest replay profiles live under `signing-comparison/{saved,release}/`.
Both point left at the Arduino mirror and right at the localhost fixture.
Main window AX position was (241,162), size (909,703); translation was
dx=-350, dy=20. That mapped the source to `3ping.msi` and the target to the
left `DrawingGlove` folder. Re-measure before reuse. Drop plans were not run.

CUA `getApp`/`getAXState` can launch an exited app on its default profile.
This happened during initial selection and final closure verification; those
instances were stopped without a file operation. Avoid accidentally opening
the normal profile while trying to prove a test process is gone. Process
inspection is sufficient for that last check. Screen was handed back explicitly.

## Historical private records to consult

- `reviews/2026-11-15-drag-freeze-diagnosis.md`: original stacks, breakpoints,
  custom-source proposal and failed physical validation.
- `reviews/2026-11-15-drag-freeze-writeup.md`: earlier narrative; read as history.
- `reviews/2026-11-16-drag-freeze-fix.md`: destination comparison, subsequent
  remote recurrences, failed formation guard and selection regression.
- `agent-tasks/agent-task-2026-11-16-drag-freeze-frontier.md`: original handoff;
  several current-state/acceptance statements have since been superseded.
- `reviews/apple-feedback-2026-11-15-drag-freeze/`: draft report, minimal SwiftUI
  reproducer and debugger captures. Filing/Feedback ID remains unconfirmed.

Some historical reports use conclusive language that later incidents disproved.
The public issue record and this handoff take precedence. No quantity of unit
test passes, signing checks or unreproduced replay attempts should be restated
as proof that this intermittent fault is resolved.

## Abandoned worktree cleanup — 2026-11-17

Practitioner authorized removing `../palana-drag-out` after verifying that the
investigation was preserved. Git reported no tracked modifications or untracked
nonignored files. Ignored content included unique trackpad recordings, debugger
captures, fixture data and an old app, in addition to disposable build products.

Before removal, `.fixtures/` and `dist/` were copied to the parent checkout's
`.fixtures/archives/drag-out-2be783e/`. All 23 regular files were SHA-256 compared
against their sources: 49,295,854 bytes verified. `manifest.json` records the
original commit and per-file hashes. The archive is ignored by Git, and its
root is mode 0700; it includes local fixture SSH material and must not be
published or committed. Raw recordings remain available there rather than
being represented only by a prose summary.

`git worktree remove ../palana-drag-out` completed; the checkout no longer
exists and is absent from `git worktree list`. Branch `drag-out` remains at
`2be783e`, retaining source history for recreation. The `.build/` cache was not
archived. Current app, release artifacts and all other worktrees are untouched.
