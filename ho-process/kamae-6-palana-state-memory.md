---
created: 2026-07-09
updated: 2026-11-19
status: living
type: state-memory
project: palana
stage: kamae-6
kamae-chain: seed → system-design → readme → ho-overview → hos → **state-memory**
---

# pālana — State Memory (Kamae 6)

The fixed handoff surface. Every session and ho closes by updating the
state-summary block below — verbatim field labels, parseable shape — so the next
session (and any hook) knows exactly where the build stands. Newest block on top.

---

## State summary — 2026-11-19 — FINAL REVIEW CLOSED AND MERGED; QUIT PROMPT AND ITS FIXES ON MAIN

Supersedes the 2026-11-18 block below where they differ: the full codebase
review it named as NEXT is done, and its repairs and the quit prompt are on
`main`.

**COMPLETED**
- **Final codebase review closed** (cycle `palana-final-2026-11-18`; record in
  `reviews/2026-11-18-final-review-closure.md`).
  - Three reviewer passes: Return, Return, then **Pass** with F01–F12 resolved.
    Pass 3 ran under the owner's budget exception (2026-11-19: "we will run the
    cycle until we are done").
  - Owner acceptance is recorded separately: **accepted with named
    limitations**.
- **Owner rulings now in force.** They supersede closed recipes; the closed hos
  are not edited.
  - **F01, keep dirty copies.** Supersedes the cleanup clause of the September
    round-trip task.
  - **F02, ask the filesystem.** Supersedes ho-9.9's byte-exact-only rule.
  - **F03, fence and prove.** Supersedes ho-06.2's receive-equals-release
    recipe.
- **The repairs, as seven commits on `repair/final-review-pass1`** (`dc2d762`
  through `ce53aa3`). They are byte-identical to the passed endpoint, every
  pre-commit hook passed, and **PR #13 is merged** (`ecdfe5b`). The repair
  worktree and branch are removed.
  - Host-block quoting, checked by `ssh -G` (F08).
  - An exact-path link commit (F04).
  - Preview cache ownership (F10).
  - ZFS tree generation (F12).
  - Filesystem-resolved collisions (F02).
  - ZFS fence and proof, plus the tar status and shell-word option checks (F03,
    F06, F11).
  - Round-trip retention, baseline, receiver and shutdown admission (F01, F09,
    F07, F05).
- **Verification.**
  - 275 app tests, 1,240 core tests and 81 XCTest cases pass. PalanaCore line
    coverage 98.09%; application logic 65.80%.
  - The ZFS suites ran **live** on the `palana-zfs` fixture pool. That includes
    the new `FinalReviewZFSLiveTests`: a mounted-tree move, a write after the
    snapshot, a child created after it, a busy source, and the real
    `zfs get -r` domain.
  - The `palana/m10-*` mutation suite passed under a reviewer run the owner
    authorized.
- **Fixture.**
  - Inside the `palana-zfs` VM, a stale `localhost` host key was removed (the
    original is kept as `known_hosts.old` there).
  - The VM is **stopped**; its pool is kept.
  - Two datasets that are not part of the fixture remain untouched in the pool:
    `palana/stray-dataset` and `palana/tank/stray-child`.

- **The quit prompt (PR #15, merged `e11f629`).** It follows from F05 and the
  owner's decision. ⌘Q while a plan runs or saves are still going back asks
  first:
  - **Keep Running** (the default).
  - **Quit When Finished.** It holds new operator work, lets the running
    transfer and the queued round-trip saves finish, then quits. A failure or
    ⌃C cancels the quit and pālana stays open.
  - **Stop and Quit.**

  `QuitWhenFinishedTests` covers it. The README and CHANGELOG say so. CI passed.
- **Hands check of #15 found three faults, fixed in PR #16** (merged `7175659`):
  - Quit When Finished deadlocked. It called `NSApp.terminate` inside a
    main-actor task; terminate is now scheduled on the run loop.
  - The run record glued Stop and Quit's line onto rsync's carriage-return
    progress.
  - A stopped rsync copy left a fragment dated 1970 under the file's own name.
    rsync now runs with `--partial-dir=.rsync-partial`, and the next run
    resumes from that folder.

  Verified on the built app: a scripted Stop and Quit in an isolated instance,
  and the owner's hands check of Quit When Finished and of a resumed copy.
- **Issues filed:**
  - #14: an in-app discard for kept round-trip copies. An open question, not a
    commitment.
  - #17: the plan should say when a copy resumes.

**NEXT**
- **Independent check of #15 and #16** (`ecdfe5b..7175659`), the code that
  landed after the final review closed. The handoff is in the external review
  directory, under `2026-11-19/palana-quit-followup/`.
- **Then the release steps from the 2026-11-18 block, unchanged:**
  1. Retake Settings and the `?` card on the 1.0 build.
  2. Record the 15–20 s window video.
  3. Rebuild, sign and notarize `palana-1.0.0.dmg` from `main`.
  4. Create the Payhip product.
  5. Push `palana-web` and check the live URL (`/.git/HEAD` must return 404).
  6. Remove the beta DMG assets.
  7. Tag v1.0, last.

**ACTION ITEMS / BLOCKS**
- No merge, tag or release publication without explicit instruction.
  Everything in the 2026-11-18 ACTION ITEMS still stands.
- **Limits accepted with the review** (listed in full in the closure record):
  - The SSH-container fixture suites did not run.
  - ZFS was proven only on OpenZFS 2.4.1 under Ubuntu Lima: no FreeBSD/TrueNAS,
    no zvols.
  - If a ZFS move fails after its fence, the source stays unmounted until the
    operator remounts it.
  - The AppKit quit sequence and physical UI input were not driven.
- **Open question:** whether kept F01 copies should get an in-app discard
  (#14).
- **The quit prompt:** Esc is not mapped. Return gives Keep Running.
- **The `ho-antagonist-review` skill is untracked in ho-system.** It changed
  mid-cycle; the cycle used a snapshot. The reviewers' and coordinator's skill
  feedback is in the review reports and was given to the owner for the skill
  builder.

**PROJECT LIFECYCLE**
- `beta`. The 1.0 source, the review repairs, and the quit prompt are on
  `main`; the release is not cut.

---

## State summary — 2026-11-18 — MAIN CARRIES THE 1.0 SOURCE AND DOCS; RELEASE NOT CUT

Supersedes the 2026-11-17 entries below where they differ: `main` has advanced
and is pushed, the v1.0 draft release was deleted, and the signed DMG they
describe is obsolete.

**COMPLETED**
- **Pre-1.0 review closed.** `reviews/2026-11-15-pre-1.0-review.md` found 3
  release-blockers and 6 should-fix items. Fixed with failing-first tests:
  findings 1, 2, 3, 5, 6, 9, 10 and 12 (`604c9cd` and following), then 4, 7, 8,
  11 and 13 on `review-remainder` (`b0ed789`). Also fixed: the Swift 6.4 build
  (main-actor drop resolver, per-arch binaries copied aside before `lipo`,
  coverage over per-target test bundles) and rsync 3.5 progress lines.
- **`v1-docs` merged** (`d75008a`). The README is informational only:
  - mounted SMB, NFS and cloud storage are local paths;
  - the selling copy and the "does not do" list are gone;
  - it has a Known issues list.

  Also in the merge: the CHANGELOG's single v1.0 entry, CONTRIBUTING without the
  beta offer, and RELEASING, which now covers DMG signing. Dragging with ⌘
  moves (it was Option in error). Three screenshots; this closed #2.
- **#3, #10, #12 fixed** (`243b461`, `f20186a`). Each closed when `main` was
  pushed.
  - **#3:** a copy button in the plan panel. Its text comes from
    `PlanText.clipboardText` in core.
  - **#12:** program output keeps its columns, scrolling sideways.
  - **#10:** a retained note stays one line, with newlines written as `\n` and
    printed by `printf`, not dash's `echo`.

  Verification: 1,457 tests passed with the sshd fixture. PalanaCore line
  coverage 98.11%; application logic 63.53%.
- **Pushed.** palana `main` is at `3d7c1bc`; the notes repo is at `74d746c`, pushed after the public copy.
  - The public `ho-process` is regenerated, adding the review and the drag-freeze
    records.
  - `config/public-redactions.tsv` gained 5 rules: the test folder, an example
    home path, macOS's anonymized app path, and a version string that reads as
    an IPv4 address.
  - A sweep of the published copy found no home paths, accounts, addresses or
    host names.
- **GitHub.**
  - The v1.0 draft release was deleted on the practitioner's request. No `v1.0`
    tag ever existed.
  - Issues #7–#12 were filed: remote drag-out, send-back staging cleanup,
    non-root ownership, the newline note, the rename race, and `zpool status`
    wrapping.
  - Branches are `main` and `v1-release` (kept by ruling). The only worktree is
    the main checkout.
- **Site (`palana-web`, 27 commits, local only).**
  - Copy: an editorial pass (show, compare, explain; never pitch), the
    Ho-process colophon, a Buy button reading `site.buyUrl`, and "Drive your
    Mac and SSH hosts in two panes."
  - Screenshots: a coverflow slider; a light/dark compare slider (m4Bookmaker's
    handle); click-to-enlarge on every screenshot; a ZFS slider of the tree,
    `zpool status` and the host map; the key card.
  - The Build from source chip sits only in the Get pālana section.
  - Mounted storage is stated as local. The FAQ has a Known issues entry.
  - The Payhip gallery, images 1–7 at 1536×1024, plus the listing, are in
    `design/payhip/`. `compose.py` and `web-assets.py` rebuild them from the
    unframed shots in the gitignored `raw/`.
- **Practitioner's machine.** `~/.ssh/config` gained Host entries for source-host,
  keisu and samu. The previous file is `~/.ssh/config.bak-2026-11-15`.

**NEXT**
- **The practitioner is running a full codebase review.** Fold its findings into
  `main` before any release build.
- **Then, in order:**
  1. Retake Settings and the `?` card on the 1.0 build. Both current shots are
     from 0.8: one shows the 0.8.0 version line, the other `⌘8` and "? again
     floats it".
  2. Record a 15–20 s window video: select, `y`, plan, Enter, progress.
  3. Rebuild, sign and notarize `palana-1.0.0.dmg` from `main`.
  4. Create the Payhip product. Put its ID in `public/_data/site.json`
     (`buyUrl`) and in `design/payhip/payhip-listing.md`.
  5. Push `palana-web`; the push deploys the site. Check the live URL, including
     that `/.git/HEAD` returns 404.
  6. Remove the beta DMG assets from the v0.8-beta and v0.4-beta releases.
  7. Tag v1.0 with notes only, last.

**ACTION ITEMS / BLOCKS**
- No tag and no release publication without a new explicit instruction.
- `palana-web` is unpushed on purpose. A push goes live with the placeholder
  `PALANA_PAYHIP_ID` until step 4 is done. Its untracked `.keisaku.json` awaits a
  ruling: commit it, or ignore it.
- **The signed DMG is obsolete.** It was built from `ff203c7` and predates the
  README and the #3/#10/#12 fixes. The copy in `dist/` was overwritten by a
  11-17 19:56 ad-hoc dev build. The archived copy survives, SHA-256
  `c9b39f067ed5bb826936f27acb6c772fbb40967ae8bcb23121e3b928f7763412`, at
  `.fixtures/archives/worktree-cleanup-20261117/release/dist/palana-1.0.0.dmg`.
- **Open issues:**
  - #1 sync
  - #4 drag freeze (accepted known issue)
  - #5 exFAT hands test
  - #6 ⌘-drag into Finder (a real Finder drop still copies)
  - #7 remote drag-out
  - #8 staging cleanup
  - #9 ownership
  - #11 rename race

  The pane drop caption "hold ⌘ to move" stays, by ruling; it is true for drops
  into pālana.
- **Owed to the beta tester `robled`:** a single-use Payhip coupon (decided yes)
  and a note on closed #2. Do both once the product exists.
- **The sshd fixture was recreated.** On host-key failures, run
  `scripts/sshd-fixture.sh stop && scripts/sshd-fixture.sh start`.
- **Screenshot fixtures still on disk, all stopped:** the Tart guest
  `palana-shots` and the Lima clones `palana-source-host` and `palana-storage-host`
  (`scripts/shots-fixture.sh destroy`). Delete them when the shots are final.

**PROJECT LIFECYCLE**
- `beta`. The v1.0 source and docs are on `main` and pushed; the release is not
  cut.

---

**STATE-SUMMARY**


- **WORKTREE CONSOLIDATION — 2026-11-17** — Removed the three explicitly
  requested redundant checkouts: palana-dist, palana-drag-native and
  palana-release-20261117. Confirmed all source commits are in main and no
  uncommitted source was present. Signed app and DMG now live in the parent
  checkout `dist/`; signature and original DMG hash verified. Preserved native
  fixtures/candidate apps and signed artifacts under parent
  `.fixtures/archives/worktree-cleanup-20261117/`, verified 333 copied entries
  by hash, and documented the path mapping in the private handoff. Archive
  contains fixture SSH material; keep ignored/private. No rebuild/sign/tag.
  Only main and palana-v1-docs remain as registered worktrees. The unrelated
  local main commit caf4661 was left untouched and unpushed.


- **CLEANUP — 2026-11-17** — At practitioner request, removed the abandoned
  `../palana-drag-out` worktree after verifying it had no tracked changes or
  nonignored untracked files. Preserved `.fixtures/` and `dist/` under the
  parent checkout `.fixtures/archives/drag-out-2be783e/`, checked all 23 files
  by SHA-256, and recorded the manifest. Archive is private/ignored and includes
  fixture SSH material; do not commit it. Branch `drag-out` remains at 2be783e.
  Handoff document records archive location and recreation history. Other
  worktrees, current app and release artifacts unchanged.


- **COMPLETED** — 2026-11-17 — Practitioner authorized merge-down with the
  intermittent drag freeze retained as known issue #4, then explicitly asked
  for a thorough Markdown record. Local main fast-forwarded from e9861f1 to
  ff203c7 without conflicts; application source unchanged. Public record:
  `docs/known-issues/drag-freeze.md`. Private operational handoff:
  `reviews/2026-11-17-drag-freeze-handoff.md`, with eleven archived evidence and
  diagnostic-source files plus SHA-256 manifest. Public documentation corrects
  the claim that remote external-delivery restriction contains the freeze.
- **NEXT** — Main is committed and pushed as `78c0fd7`; issue #4 remains OPEN
  and links to the detailed Markdown record. Continue normal project work on
  main. No new build, signing run, tag or release publication was performed.
  Application source matches ff203c7 exactly, and the current app is unchanged.
  No screen access needed. Private evidence/handoff committed locally only;
  no process export or private push in this task.
- **ACTION ITEMS / BLOCKS** — Known defect remains open and root cause unproven;
  the maintainer has accepted merging with that known issue. Earlier agent
  language calling the merge blocked is superseded by this explicit decision.
  Stop diagnosis/replay/native-table work here unless requested again. Preserve
  remote pane transfers, local dragging and multiselection; external remote
  delivery stays disabled. No release tag without a new explicit instruction.
- **PROJECT LIFECYCLE** — beta; v1.0 source merge accepted, release unpublished.

---

## Earlier investigation state — superseded by accepted merge decision

- **NEXT EXPERIMENT — 2026-11-17 — OWNED NATIVE TABLE** — Practitioner asks
  for a release path and explicitly rejects stopping at another failed-to-
  reproduce batch. Prepared a standalone plain AppKit NSTableView experiment:
  `../palana-drag-native/.fixtures/drag-freeze-20261116/native-table-probe/`
  `Palana-Native-Drag-Probe.app`. Unique bundle ID, ad-hoc signed and verified.
  No SwiftUI, method swizzling, networking, file promises or drag-image changes.
  Two fixture panes: local URLs and a simulated remote-format internal payload.
  Drops only report receipt; no pane copy/move operation executes. Native
  multiselection is enabled. Compiled Swift 6; offscreen payload/cohort and
  programmatic selection checks passed. Actual gestures NOT TESTED; app not
  launched onscreen. This is a diagnostic experiment, NOT a release candidate
  or an already-chosen production rewrite. Screen remains with practitioner.
  If it establishes a reliable difference, replace the production table's
  drag machinery while preserving selection and both pane routes. Do not
  reintroduce the abandoned runtime-patched SwiftUI source implementation.

- **FOLLOW-UP — 2026-11-17 — SCREEN COMPARISON COMPLETE; STILL BLOCKED** —
  Practitioner authorized a short comparison and screen has been handed back.
  Exact saved candidate: 20 recorded replay attempts, 20 accepted fixture drops.
  Exact signed release: 20 attempts, 19 accepted drops; one attempt did not
  initiate a recorded drag. Neither emitted either known freeze signature;
  both still selected a different row afterward. This failed to reproduce the
  reported freeze and does not establish release safety or a signing cause.
  Tests used localhost SSH fixture, not storage-host; plans were not executed. No
  source changes. Logs and prepared signing variants are under implementation
  worktree `.fixtures/drag-freeze-20261116/signing-comparison/`. Signing variants
  were not run because the original builds did not separate. Offscreen view
  inspection found only intended Catcher drop receivers; native tables had no
  registered drag types. Compiled ARM64 drag code matches; three immediate
  differences elsewhere are diagnostic source-file-length arguments.
  No pointer replay remains running. No tag, publication or release approval.

- **RELEASE BLOCKED — 2026-11-17 13:54 EST** — Practitioner reports the first
  drag from storage-host locked up the delivered signed build. PID 17048 runs
  `../palana-release-20261117/dist/Palana.app/Contents/MacOS/Palana`.
  Unified logs show drag-server activation at 13:51:48.731, cancellation with
  `CALayerInvalidGeometry` at .773, and HIServices fault at .809. A live sample
  contains `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION`; the main
  thread is in its event loop. Remote external-delivery restriction did NOT
  contain this failure. Earlier physical passes and packaging verification
  do not establish release safety. Destination clarification is pending.
  Evidence saved under `../palana-drag-native/.fixtures/drag-freeze-20261116/`
  `signed-release-first-drag/`. No app changes, screen control, process
  termination, tags or publication performed in this follow-up. DO NOT RELEASE
  this candidate. Preserve local dragging, multiselection and the practitioner's
  required remote pane transfers; do not silently disable them as a workaround.

- **COMPLETED** — 2026-11-17 — DEFER FINDER MOVE; RELEASE ACCEPTED DRAG PATHS.
  Practitioner authorized leaving Command-move out, filing an issue, and
  finishing the release, with concern about crashes. Removed the failed move
  permission changes and the unverified local footer hint. Application source
  was compared to the archived pane-drag-restored snapshot and matches exactly.
  That is the source the practitioner passed for pane transfers, local external
  copies, selection and repeated drags. Remote external delivery stays disabled;
  the underlying freeze is not claimed fixed.
  Created https://github.com/sageframe-no-kaji/palana/issues/6 for local Finder
  Command-move. Corrected issue #4's status, reproduction history, containment,
  and premature Apple-filing claim. No known drag-freeze signature was found in
  the preceding hour's available logs; that is a limited observation.
  Commit `ee3c137` records the accepted scope. Merged into `v1-release` as
  `daf537f`; merged Sources/Tests/Package inputs match the verified branch.
  Pushed `v1-release` and created a notes-only DRAFT GitHub release for `v1.0`:
  https://github.com/sageframe-no-kaji/palana/releases/tag/untagged-42ec879c237c89946d1c
  Full coverage run: 251 app + 1194 core Swift Testing and 81 XCTest passed;
  PalanaCore 97.74%, application logic 63.51%. Opt-in ZFS/corpus checks skipped.
  Strict format/lint, commit hooks, public-boundary and diff checks passed.
- **NEXT** — Deliver the verified installer to the practitioner first:
  `../palana-release-20261117/dist/palana-1.0.0.dmg`.
  SHA-256 `c9b39f067ed5bb826936f27acb6c772fbb40967ae8bcb23121e3b928f7763412`.
  Universal arm64+x86_64, Developer ID signed; app and disk image notarized and
  stapled. App, container and mounted app pass signature/ticket/Gatekeeper
  checks; disk-image integrity verified. Installer mounted read-only and
  detached, app not launched. Signing the DMG container was missing from the
  existing script: fixed in `ff203c7`, pushed to `v1-release`; re-signed and
  re-notarized the container. Application source is unchanged from `daf537f`.
  Practitioner said Payhip setup needs the build first. Do not ask for the
  product link before handing over this artifact.
- **ACTION ITEMS / BLOCKS** — Practitioner explicitly ordered DO NOT TAG ANYTHING
  YET. Do not create a tag or publish a release, even after another test pass,
  without a new instruction. Verified `refs/tags/v1.0` does not exist remotely.
  The existing v1.0 release is an UNPUBLISHED DRAFT only. Main has not advanced;
  only `v1-release` was pushed. Site unchanged; no private-process export/push.
  All Finder-style selection and group dragging remain in the artifact.
  Command-move-to-Finder is deferred in #6; remote external delivery remains
  paused under #4. The earlier screen-check request is superseded; do not run
  the abandoned move trace if that answer arrives late. No screen control or
  live-host mutation performed. Preserve the existing untracked private reports.
- **PROJECT LIFECYCLE** — beta; v1.0 release artifact being prepared, publication pending.

---

## State summary — 2026-11-17 — LOCAL FINDER COMMAND-MOVE ONLY

**COMPLETED**
- Practitioner passed the pane-drag-restored build: both pane directions,
  groups, folders, folder targets, local Finder copy, local Chrome files,
  remote external refusal, selection, and repeated drags. Browser folder
  uploads were not established; the inspector does not enumerate folders.
- Practitioner clarified remote-to-Finder is a separate desired route from
  remote-to-browser, then explicitly ordered one change at a time: implement
  missing local-to-Finder Command-move and rebuild, then they test. Do not
  enable remote Finder delivery, change browser folder behavior, or release
  as part of this turn.
- Measured the actual native SwiftUI table callback offscreen: external source
  operations were copy-only (1). AppKit's public
  `setDraggingSourceOperationMask([.copy, .move], forLocal: false)` changes its
  modern source callback result to copy+move (17). No source-method swizzle or
  native dragging-animation change is needed.
- TableRowWriters now applies that external operation mask to local-file panes
  at attachment and subsequent updates. Remote panes keep copy-only. In-app
  operation masks are untouched. Finder receives the existing eager file URLs
  and owns the filesystem operation; no new Palana deletion callback exists.
- Focused native-table tests pass for single files, directories and groups,
  plus local/remote host switching. They assert modern source callback masks,
  unchanged in-app masks, pasteboard content and destination decode. These are
  offscreen callback tests, not an actual Finder drop. No screen automation.

**NEXT**
- Built and signature-verified, not launched:
  `../palana-drag-native/dist/Palana-Finder-Command-Move.app`.
  Executable SHA-256:
  `12782335e9ef93506a883ed9077136798d4d10fbe42fc5023351c35f8632921c`.
  Full suite: 251 app + 1194 core Swift Testing and 81 XCTest passed; opt-in
  ZFS/corpus checks skipped. Strict lint/format, diff check and release build
  passed. Evidence/source snapshot in worktree
  `.fixtures/drag-freeze-20261116/finder-command-move/`.
- Practitioner will test ordinary Finder copy, Command-drop move, and cancelled
  move with disposable fixtures. No claim of physical Finder acceptance yet.

**ACTION ITEMS / BLOCKS**
- Working changes remain uncommitted in `../palana-drag-native`. Earlier
  pane-transfer restoration remains in the candidate; remote external
  delivery remains disabled. No merge, push, release or live-host mutation.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-17 — RESTORE REMOTE PANE TRANSFERS; PAUSE EXTERNAL DELIVERY ONLY

**COMPLETED**
- Practitioner passed selection in the restored-row build, then reported that
  dragging selected rows instead of starting a drag. On clarification the
  source was the storage-host pane, not the local Arduino pane. This report does NOT
  establish a local-drag regression: the build intentionally blocked every
  remote-origin drag. The agent incorrectly treated the initial report as a
  confirmed local failure before identifying the source.
- Practitioner explicitly rejected blocking remote pane-to-pane dragging.
  Required scope: local dragging remains; remote files/folders still drag
  between panes; remote file delivery to Chrome/Finder/other apps is on hold.
  The earlier remote-source-wide restriction was too broad. Do not reintroduce
  it or ask to disable all dragging as release containment.
- Implementation now allows pointed remote sources but gives their native row
  writer only `net.sageframe.palana.internal-selection`, with no public JSON,
  URL, or file promise. The SwiftUI item provider retains only its own-process
  selection representation. The pane receiver accepts the new native type.
  Local export representations remain on the existing path. Footer and public
  product README/CHANGELOG now describe the narrower scope.
- Native offscreen integration checks exercise the real two-pane SwiftUI view,
  drag eligibility, native data-source writer, pasteboard serialization and
  destination decoding. Single files, directories and marked groups pass.
  These checks do NOT start a native mouse drag or establish freeze freedom.
- Full suite passed (251 app + 1194 core Swift Testing, 81 XCTest); opt-in ZFS
  and corpus checks skipped. Expanded targeted suite passed (12 tests, with
  two integration cases). Strict lint/format and diff checks passed. No screen
  control, live-host mutation, merge, push, or release.

**NEXT**
- Prepared and signature-verified (not launched):
  `../palana-drag-native/dist/Palana-Pane-Drag-Restored.app`.
  Executable SHA-256:
  `d5b5a398353e2f0dee1dca653ff3aff6aa0e1bea83aae71bb60e088f4c0e6d09`.
  Source diff, added integration test and verification logs preserved under
  worktree `.fixtures/drag-freeze-20261116/remote-internal-only/`.
  Practitioner must test storage-host-to-local-pane dragging, then local external
  dragging and selection.
  Their earlier instruction authorizes release with issue #4 left open ONLY
  after acceptance; no release is authorized by a failed or incomplete check.

**ACTION ITEMS / BLOCKS**
- Native physical drag and freeze acceptance remain unverified. Source changes
  are uncommitted atop ab6a156 in `../palana-drag-native`; the earlier restored
  TableRow structure remains part of the change. Do not hand back the remote-
  source-disabled builds as candidates for this scope.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-17 — LOCAL DRAGGING MUST REMAIN; CORRECT CONFIDENCE CLAIMS

**COMPLETED**
- Practitioner rejected disabling all row dragging: local dragging was working
  and must remain available. Remote dragging alone stays on hold. Do not ask
  again to remove local dragging as the release containment choice.
- Compared current source to hands-tested `b5bda1f`: native local row writer,
  item-provider construction, selection model and AppKit destination code are
  unchanged after the row-structure rollback. The added gate checks the current
  host; local sources take the prior writer/fallback path. Remote footer and
  remote-source rejection are the remaining behavioral changes.
- Corrected the agent's overstatement: earlier local/replay passes established
  one working path, not a comprehensive freeze fix. Later remote failures and
  the conditional-row selection regression do not invalidate the practitioner's
  earlier physical local-drag passes. The failed automated local check is not
  by itself proof that physical local dragging regressed.

**NEXT**
- Preserve local dragging and the restored row structure. Keep remote-origin
  drags blocked. Resolve the automated check's limitation or obtain a controlled
  physical comparison before claiming either a local regression or release
  acceptance. No new source change is justified solely by that failed check.

**ACTION ITEMS / BLOCKS**
- No screen use, merge/push/release this turn. One uncommitted PaneView rollback
  remains; prepared restored-row app is still available, not release-certified.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-17 — REMOTE SELECTION PASSES; LOCAL DRAG CHECK FAILS

**COMPLETED**
- Practitioner authorized the one-minute screen check. Launched only the
  isolated SelectionCheck.app (PID 76146) with its fixture profile and localhost
  SSH config. No live-host operation. Test app closed afterwards; PID absent.
- Restored-row build: remote click selects a.txt; Command-click adds b.txt;
  after an attempted remote-to-left drag, click selects b.txt; Shift-click
  3ping.msi selects all three. Local click selects readme.md. These are observed
  UI selection passes on the fixture, not a physical-trackpad acceptance run.
- The remote drag attempt produced no plan and selection remained usable.
  No remote writer or accepted drop was logged. No claim about every gesture.
- Local readme.md drag toward sketch left the generic drop wash visible with
  no plan. Escape followed by a click on photo.png did not change selection.
  Failed local GUI check. Log contains its local row writer at 06:41:16.997;
  no CALayerInvalidGeometry or stale-drag-reference signature was captured.
  Do NOT conflate this with a confirmed recurrence of the earlier signature.
- Log also contains NSTableViewException at 06:40:36.113, before that local drag;
  its redacted reason is not diagnosed. Similar startup exception appeared in
  the preceding diagnostic fixtures and may deserve a separate captured stack.
- Evidence: worktree `.fixtures/drag-freeze-20261116/storage-host-recurrence/local-only-failure/hands-20261117.log`.

**NEXT**
- Build remains unfit for release acceptance. Remote-only restriction has not
  yielded a verified usable drag workflow. Consider suspending all outgoing
  row dragging for release, but that broader feature restriction needs the
  practitioner's ruling; keyboard/menu transfer routes remain available.
- Preserve the one-file row-structure rollback; no new build change this turn.

**ACTION ITEMS / BLOCKS**
- Screen returned; no automation or test app running. No merge/push/release.
- Row rollback is still uncommitted atop ab6a156. Do not ship prior candidates.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-eighth block — REMOTE CLICK REGRESSION; ROW ROLLBACK AWAITS HANDS CHECK

**COMPLETED**
- Practitioner rejected `ab6a156`: remote pane rows will not select. The running
  PID 15891 was the expected local-drag-only build. Logs/sample show no drag
  geometry exception or swallowed-exception marker for this incident. Read-only
  CUA accessibility queries timed out; no pointer or keyboard action was made.
- Restored the prior unconditional `TableRow(entry).itemProvider` structure in
  `PaneView.swift`. Remote `rowProvider` still returns nil and native writer
  gate still blocks custom/fallback writers; remote dragging remains disabled.
  This is a bounded rollback, not a demonstrated explanation of the regression.
- Eighteen gate/selection/drop checks pass. Strict format/lint and release build
  pass; signature verified. No full suite repeated for the row-only rollback.
- Minimal offscreen conditional-row experiment passed programmatic selection.
  Its mouseDown attempt exited without a test verdict; not click evidence.
  Experiment removed from test source and archived in
  `.fixtures/drag-freeze-20261116/storage-host-recurrence/local-only-failure/`.
- Build prepared, NOT launched:
  `../palana-drag-native/dist/Palana-Remote-Drag-Paused-Rows.app`.
  SHA-256 `b95c9515426968a28fc32c12483e5ac42d4df99b8ef886f3e33924ce46a5d74d`.
  Separate fixture-only `local-only-failure/SelectionCheck.app` has bundle ID
  `com.sageframe.palana.rowcheck`; its profile uses local fixture paths and the
  localhost SSH fixture only. Source worktree has one uncommitted PaneView diff.

**NEXT**
- Awaiting practitioner's async reply: may we use the screen for one minute to
  check actual remote clicks and blocked drags in the isolated fixture app,
  or should the prepared build be handed back for their check? No permission
  inferred from silence. No UI automation currently running.
- If permitted, launch SelectionCheck.app with CFFIXED_USER_HOME pointing to
  `local-only-failure/profile` and PALANA_SSH_CONFIG to worktree `.fixtures/ssh_config`.
  Remote fixture has `3ping.msi`, `a.txt`, `b.txt` at `/tmp/palana-remote-drag`.
  Verify actual clicking changes selection, attempted remote drag does nothing,
  and clicks still work afterwards. Then local selection/drag sanity check.
- Do not declare release-ready or freeze-fixed. Issue #4 remains open.

**ACTION ITEMS / BLOCKS**
- No merge, push, release publication or live-host mutation. Screen remains free.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-seventh block — REMOTE DRAGS DISABLED FOR RELEASE TESTING

**COMPLETED**
- Source-formation candidate FAILED the practitioner's hands test. Its guard
  ran before three CALayerInvalidGeometry cancellations at 16:13:19.937,
  16:13:21.746 and 16:14:24.624. Remote-to-pane drops succeeded in between;
  Chrome delivery did not. Candidate source/tests archived under
  `.fixtures/drag-freeze-20261116/storage-host-recurrence/candidate-failure/` and removed.
- Practitioner asked to suspend remote dragging for release. Commit `ab6a156`
  on `drag-freeze-fix` removes remote rows' item-provider modifier and blocks
  both custom/native fallback writers at request time. Remote-to-pane dragging
  is also disabled. Local row drags, incoming drops, selection and keyboard/menu
  transfers retain their existing routes. Remote pane footer names `y`/`m`.
- README/CHANGELOG corrected: remote drag support is on hold, freeze still open.
- Full suite: 250 app + 1194 core Swift Testing + 81 XCTest pass. ZFS fixture
  and opt-in capture checks skipped. Strict format/lint, commit hooks, release
  build, signature verification and diff checks pass. No new coverage run.
- App: `../palana-drag-native/dist/Palana-Local-Drag-Only-ab6a156.app`.
  Executable SHA-256:
  `163d9ecdd8f19ea27ba1e80c279a5bfbd800e97fec7fb4f45b454327c97f1498`.
  Built and packaged only; not launched. Source worktree clean.

**NEXT**
- Practitioner hands check: remote files/folders/marked rows must not start a
  drag toward Chrome or the other pane, including after switching local→remote.
- Recheck local files between panes and into Chrome; check keyboard/menu remote
  copy to a local pane, then drag the downloaded local copy.
- This removes the observed remote source route; it is not proof that all
  possible local native-drag freezes are gone. Do not mark issue #4 resolved.

**ACTION ITEMS / BLOCKS**
- No merge, push, release publication, live-host mutation or screen control.
- Prior candidate app is preserved for evidence, not for release.
- Private operational changes remain uncommitted; generated export untouched.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-sixth block — SOURCE-START CANDIDATE BUILT; HANDS TEST OPEN

**COMPLETED**
- Practitioner asked whether work continued after the screen handback. Resumed
  without screen control; added uncommitted `TableDragStartup.swift` and three
  runtime-dispatch tests on `b5bda1f` in `../palana-drag-native`.
- Candidate suppresses SwiftUI's formation setter only for the session inside
  a pane's source willBegin callback. Original bookkeeping still runs once;
  unrelated tables/sessions and later formation changes remain forwarded.
  This tests the source-side animation mutation seen in the earlier exception
  trace. It is NOT yet established as the cause of the storage-host recurrence.
- Full suite passes: 250 app + 1194 core Swift Testing + 81 XCTest. ZFS fixture
  and opt-in capture checks skipped. Strict format/lint, release build,
  signature verification, and diff checks pass.
- Candidate: `../palana-drag-native/dist/Palana-Remote-Drag-Candidate.app`.
  Executable SHA-256:
  `ac8602e342c1a5931552108c1663ed3d8cf02e825aad7a0dcec57de8ec21ba65`.
  Candidate was not launched; original app and older builds preserved.
- Evidence and limitations added to `reviews/2026-11-16-drag-freeze-fix.md`.

**NEXT**
- Practitioner hands test: the same remote-file drag toward Chrome, successful
  harmless-file upload, then local pane-to-pane drag. Repeated physical drags
  and a valid replay comparison are required before closing the freeze.
- `net.sageframe.palana:dragstartup` logs each suppressed startup setter, so
  verify the real SwiftUI callback traverses this guard during the hands test.

**ACTION ITEMS / BLOCKS**
- Worktree has three intentional uncommitted candidate files. No merge/push.
- Screen is free; no replay or diagnostic app running. No live host mutations.
- Freeze and remote Chrome delivery remain unresolved until hands evidence.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-fifth block — REMOTE DRAG FREEZE RECURRED

**COMPLETED**
- Practitioner confirmed Finder-style selection works on `b5bda1f`, then
  reported a freeze dragging an individual file from storage-host in the right pane
  toward Chrome. The prior local/replay passes do not close the freeze.
- Captured PID 87259 from `dist/Palana-b5bda1f-155507.app` without stopping it.
  Info logs identify `/pool-a/software/linkage2.msi`, 3,760,128 bytes,
  remote file-promise writer at 15:57:10.841; drag-server connection at
  15:57:10.894; `CALayerInvalidGeometry` cancellation at 15:57:10.937;
  HIServices exception fault at 15:57:10.975 (local EST).
- Five-second process sample at 15:57:57 shows the main event loop idle and
  `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION` suspended. No active
  download appears in that sample. This is the known exception signature;
  the exact geometry-changing caller for this recurrence is not yet captured.
- Evidence: `../palana-drag-native/.fixtures/drag-freeze-20261116/storage-host-recurrence/`
  (`sample.txt`, `system.log`, `drag-detail.log`). No live-host command or UI
  automation was used to gather it.

**NEXT**
- Isolate the remote file-promise/source-start path with local fixtures.
  Practitioner authorized a short fixture replay batch. The batch did NOT
  establish a valid reproduction: six single-replay setup probes produced zero
  row-writer/source-start callbacks; several reordered the header columns.
  Neither the control nor the source-formation suppression variant was tested
  successfully. Do not count these as passing drags.
- Keep the selection change; do not describe `b5bda1f` as freeze-fixed or remote
  Chrome upload as verified.

**ACTION ITEMS / BLOCKS**
- No merge, push, or live-host mutation. Existing app left running.
- Screen returned after the practitioner asked. Diagnostic processes stopped;
  no replay process remains. Experimental source removed from tracked source
  tree and retained under `storage-host-recurrence/DragSessionTrace.swift`; the build
  `storage-host-recurrence/DragStartup.app` is instrumentation only, not a fix.
- Diagnostic mode logs source formation call stacks. Environment variable
  `PALANA_SKIP_SOURCE_FORMATION=1` suppresses the formation setter only inside
  SwiftUI's source willBegin callback, preserving its other bookkeeping. This
  experiment remains UNTESTED, not a production change.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-fourth block — FREEZE HANDS PASSED; FINDER SELECTION BUILT

**COMPLETED**
- Practitioner passed the supplied checklist items 1–7 on `c3e6f38`: physical
  trackpad drags, small accidental drags, hover feedback, selection, multi-file
  pane plans, local files to Finder/Chrome plus folders to Finder, and Finder
  drops into panes/folders. The freeze now has both replay and hands evidence.
- Practitioner then revised selection: Shift selects a continuous range,
  Command toggles arbitrary rows, plain click clears the other selections.
  Commit `b5bda1f` on `drag-freeze-fix` adopts the native table selection and
  removes the custom modifier/range reinterpretation. Keyboard marking remains.
- Separate build: `../palana-drag-native/dist/Palana-Finder-Selection.app`.
  Native arm64, ad-hoc signature verified, executable SHA-256
  `54e2e4a445e40faf77ac9f199e9aa9fc016f229f24c6a636486a56d8f813e4e3`.
  The hands-approved `dist/Palana.app` remains byte-identical to `c3e6f38`.
- Selection/drop/provider targeted run: 32 application + 12 core tests passed.
  Strict formatting, lint, release build, and commit hooks passed. No full-suite
  rerun for this selection-only follow-up; the preceding full run is recorded
  in the twenty-third block.
- Fixed the drop test's dependence on the practitioner's physical Command key:
  its fake source now permits copy only. Production drop behavior unchanged.

**NEXT**
- Hands check the separate selection build: grow/shrink a Shift range, toggle
  nonadjacent rows with Command, plain-click to clear the other selections,
  then drag a selected cohort.
- Practitioner clarified the remote request means individual remote files into
  a Chrome uploader, NOT recursive remote folders. That implementation already
  exists; the specific remote-to-Chrome receiver check remains open. Do not
  record the original item-8 response as a verified remote upload.

**ACTION ITEMS / BLOCKS**
- No merge or push. Both app builds remain available; no UI automation was
  resumed during the selection follow-up, and the running app was not stopped.
- Private process edits remain uncommitted alongside inherited handoff files;
  generated public process export was not edited.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-third block — DRAG FIX PASSES 30 REPLAYS; HANDS CHECK PENDING

**COMPLETED**
- Commit `c3e6f38` on `drag-freeze-fix`, forked from `drag-out-native` at `ece6d46`, now occupies
  `../palana-drag-native`. The original branch still points at `ece6d46`.
  Keep the table's native source and row writers; replace only SwiftUI pane
  and folder drop targets with `PaneDropTarget`, which never changes drag
  images or formation. Removed the obsolete SwiftUI drop handlers.
- Controlled comparison in the same instrumented build: AppKit destination
  10/10 delivered; SwiftUI destination 3 starts, 2 NaN exceptions, 525 stale
  drag-reference errors. Clean final app: 30/30 accepted folder drops, no
  instance of either failure signature. Native release executable SHA-256
  `12996eae6efa88279c5c2e896e98d00c2b1953653e3608c832292388b3bb3e1e`.
- Full test suite passed with localhost SSH fixture: 247 + 1194 Swift Testing
  and 81 XCTest; core coverage 97.74%, app logic 60.25%; strict lint clean.
  ZFS fixture integration and opt-in corpus recording checks skipped.
- Final GUI: remote folder to local pane and remote file to local folder
  compose the correct plans against the disposable SSH fixture. No enactment.
- Evidence and implementation: `reviews/2026-11-16-drag-freeze-fix.md`.
  Raw logs, preserved baseline/experiment apps, and replay runner are in
  `../palana-drag-native/.fixtures/drag-freeze-20261116/` (outside Git).
- Apple report draft corrected for silent cancellation, the actual trackpad
  gesture, the failed custom-source workaround, and unverified sample
  reproduction. Not filed.

**NEXT**
- Practitioner physical-trackpad check: ten folder drags between panes on
  `/path/to/example-folder`. Then reconfirm marked files to Finder/Chrome, a folder
  to Finder, shift mark/unmark, and a marked cohort producing one plan.
- Do not call the freeze closed on replay evidence alone. No merge or push.

**ACTION ITEMS / BLOCKS**
- Practitioner asked to use the computer; pointer/keyboard automation stopped.
  No recorder or replay remains running. Final app left open with an isolated
  regression profile, local fixture files and the localhost SSH fixture only.
- A short synthetic three-file drag invoked all three row writers but did not
  deliver a drop; injected shift-click did not establish mark/unmark behavior.
  These are not new passes; prior physical drag-out confirmations stand.
- Remote drag-out to an outside app remains unverified. The previously noted
  SSH timing flake was not repaired; this run's SSH integration tests passed.
- Private record had existing uncommitted handoff/diagnosis work at entry;
  preserved. Public process export remains unchanged.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-16, twenty-second block — DRAG FREEZE HANDED OFF; DRAG-OUT WORKS ON `drag-out-native`

**COMPLETED**
- **Branch `drag-out-native`** (worktree `../palana-drag-native`, cut from `v1-release` at `b0ed789`, unmerged, unpushed) keeps 0.8's drag mechanics:
  - the table's selection is pālana's marks, so marked rows drag out together;
  - each row's pasteboard item is written up front (file URL or remote file promise);
  - ⇧-click marks or unmarks a run;
  - the folder-row light and caption;
  - the 1 GiB remote cap and the docs.
- Hands-verified 2026-11-16: marked files to Finder and Chrome, a folder to Finder.
- **The old `drag-out` branch is abandoned.** Its own drag source and AppKit drop target made trackpad drags end early and lock the window.

**NEXT**
- **The drag freeze is handed off:** `agent-tasks/agent-task-2026-11-16-drag-freeze-frontier.md`. It is still intermittent on `drag-out-native` (and in 0.8) for drags between panes over folder rows.
- Still to decide: merge `drag-out-native` into `v1-release` with issue #4 as a known issue, or wait for the handoff.
- Remote drag-out is not yet hands-checked.

**ACTION ITEMS / BLOCKS**
- **Apple report:** `reviews/apple-feedback-2026-11-15-drag-freeze/FEEDBACK.md` needs the three-finger mention removed and the silent-early-end signature added before filing.
- **Flaky test:** the SSH integration suite's "sessions are reused … faster" failed 2 of 3 back-to-back runs. Not yet checked on `v1-release`.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-15, twenty-first block — DRAG-OUT AND THE DRAG FREEZE FIXED ON `drag-out`

**COMPLETED**
- **Branch `drag-out`** (worktree `../palana-drag-out`, cut from `v1-release` at `26401dd`) runs `agent-task-2026-11-15-drag-out-and-freeze.md`. Not merged, not pushed. It merges cleanly into `v1-release` at `b0ed789` (merge-tree checked):
  - `5576390`: DragOutPlan.
  - `93c0cda`: remote download at the drop (file promises).
  - `8b85330`: pālana starts pane drags itself, which fixes the freeze and multi-select.
  - `489dc8b`: README and CHANGELOG.
  - `7de01b3`: trackpad (gesture) drags start pālana's session through the event road. The trackpad still froze afterwards.
  - `eb5e439`: the pane's drop surface moves from SwiftUI `.onDrop` to an AppKit `PaneDropTarget` that never touches the drag's items. SwiftUI's drop targets rewriting the drag during its opening animation were the common trigger. Guest checks A–J pass: pane to pane, folder row, same folder, Finder in and out, remote out, remote refused, remote onto a local pane.
- **The freeze** (GitHub issue #4) is a macOS 27 exception in the system's drag animation (`CALayerInvalidGeometry`, HIToolbox `UnflockAnimationTimerCallback`). It is triggered by the table's flocked row drag meeting SwiftUI's drop targets, and only with a real trackpad. Diagnosis and results: `reviews/2026-11-15-drag-freeze-diagnosis.md` (uncommitted).
- **Route A, ruled by the practitioner:** pālana answers the table's drag call on both of its roads (`event:` and the private `gesture:`) and starts its own session. The spec's `registerFileRepresentation` became `NSFilePromiseProvider`. The pane-to-pane payload moved to the private `com.sageframe.palana.selection` type, declared in Info.plist.
- **Verified:** strict lint clean; build clean; sshd fixture up; 1154 + 224 tests green; PalanaCore 97.62%; app logic 55.01%. GUI checks 1–6 passed in the `palana-shots` Tart guest (macOS 27.2) with posted events, remote files from the `storage-host` fixture.

**NEXT**
- **Hands check on `eb5e439`** (`../palana-drag-out/dist/Palana.app`): trackpad drags in and out of panes, including a remote file toward Chrome, with no freeze. Then merge `drag-out` into `v1-release` and remove the worktree.
- **Apple report:** confirm with the trackpad that `reviews/apple-feedback-2026-11-15-drag-freeze/DragFreezeRepro` freezes, then file `FEEDBACK.md` in Feedback Assistant with a sysdiagnose taken while frozen. The write-up draft is `reviews/2026-11-15-drag-freeze-writeup.md`.

**ACTION ITEMS / BLOCKS**
- **UI decision open:** a drag-out download writes its lines to the transcript, but the plan panel stays hidden unless it is open, the same as the existing drop-refusal notes. Should a remote drag-out open the panel?
- The push order and the "do not push until `drag-out` is merged" rule from the twentieth block still stand.

**PROJECT LIFECYCLE**
- beta (v1.0 release branch in progress)

---

## State summary — 2026-11-15, twentieth block — THE PRE-1.0 REVIEW'S REMAINDER CLOSED ON `review-remainder`

**COMPLETED**
- **Branch `review-remainder`** (cut from `v1-release` at `96d5d70`) is **merged into `v1-release` as `b0ed789`** (`--no-ff`; tree identical to the verified `feb7fc7`). Branch and worktree removed. Not pushed. It runs `agent-task-2026-11-15-review-remainder.md`, one commit per item:
  - `622da7c`: finding 4. A move asks for `-X` and `-A` where both rsyncs carry them; `-A` only on the same kernel. The plan carries one notice line naming what will not be kept. The probe reads rsync's capability list, and both probe corpora were re-recorded.
  - `cd7b276`: finding 7. A failed or cancelled transfer still runs the leftover-source report.
  - `42d7f6f`: finding 8. A hard-link probe before the set-aside refuses with exit 8. The original is restored with `mv -n`, and the staged edit is kept and named after the set-aside.
  - `a09f6e5`: finding 8 scope extension. The rename commit mode, plus the panel's "Replace without the safe check" offer.
  - `f8fd8c5`: finding 11. Notes are read line by line from the whole stderr stream.
  - `ded5a99`: finding 13. A retained note names the staging a failed send-back leaves.
  - `be2d32e`: Settings helper says copies only.
  - `feb7fc7`: README and CHANGELOG.
- **Practitioner rulings, this session.** D1: refuse, then offer rename (scope extended). D2: same-kernel `-A`. D3: keep the staged copy only after the set-aside. D4: a note for finding 13, with visible cleanup deferred. All recorded in the task file.
- **Fixture evidence.** `-X` from this Mac (rsync 3.4.1) to the Linux container (3.5.2) and back keeps a Finder tag and a custom attribute. `-A` Darwin→Linux aborts with exit 12.
- **Verification on `feb7fc7`.** Strict swift-format and SwiftLint clean; build clean; sshd fixture up; 1182 + 213 swift-testing and 81 XCTest, all green; PalanaCore line coverage 97.74%.

**NEXT**
- Finish the parallel `drag-out` branch and merge it into `v1-release`; only then push. The in-app hands test (rename offer on an exFAT stick attached to a Linux host; the move plan's notice line) is deferred to issue #5: https://github.com/sageframe-no-kaji/palana/issues/5. Both commit scripts were also run in the Linux test container (Alpine, GNU coreutils 9.11): refusal with the original unchanged, rename lands, normal path lands.

**ACTION ITEMS / BLOCKS**
- **Real-volume check done** on the SMB share `/Volumes/pool-a` and the exFAT stick `/Volumes/LINUXUSB`; on each: no hard links there; the safe replace refused with the original unchanged, and the rename commit landed the edit cleanly.
- **Do not push `v1-release` until `drag-out` is merged** (practitioner, 2026-11-15). The same holds for this private repo, which is ahead of `origin/main`. Push order when the time comes: `scripts/publish-public --apply`, review the public diff, push the public repo, then this one.
- **This repo's remote is `https://github.com/sageframe-no-kaji/palana-ho-process.git`, not the `git@github-no-kaji:` alias** the infrastructure rules require. Pending the practitioner's yes, switch it at push time.
- `reviews/2026-11-15-drag-freeze-diagnosis.md` (from the drag-out session) is untracked and was left for that session.
- Deferred items are listed at the end of `reviews/2026-11-15-pre-1.0-review.md`: visible staging cleanup, the rename-commit gap, ownership on non-root moves, and newline-in-path notes.
- A capability cache from before this branch reads xattrs/ACLs as unproven until the host is re-probed. Until then, moves show the "does not keep" notice.

**PROJECT LIFECYCLE**
beta

## State summary — 2026-09-16, nineteenth block — NUMBERED FAVORITES ON ⌘1–⌘9, AND THE ORDER IS DRAGGABLE

**COMPLETED**
- **`3cfe635` on branch `favorite-numbers` (not merged):** ⌘1–⌘9 point the focused pane at the first nine favorites, numbered in the favorites panel's display order (Global first, then hosts by first appearance), collapsed groups counted so a number is stable across hosts and folds. The panel shows each row's ⌘ number; with the panel holding the keyboard a number jumps where the panel's arrows aim. The list is uncapped; favorites past nine are unnumbered.
- **Practitioner rulings, this session:** nine, not ten — ⌘0 stays the zoom reset. Star-this-folder moves ⌘8 → ⇧⌘8 (shifted 8 is `*`, the favorites key), reversing ho-9.11's "⇧⌘8 dead" line; `8` still stars the highlighted entry. Grammar Rule 4 (⌘ = app plane) still holds.
- **Numbering and chord parsing are pure core** (`FavoritesOutline.numbered/favorite(number:in:)/numbers/number(forChord:)`) with a new core suite and a session suite over `TestSession`. Help card, README key table, CHANGELOG (Unreleased) updated. `palana-web` `3bed335` (local, not pushed or deployed) updates `keys.njk` and `surfaces.njk`; Eleventy wrote 17 pages cleanly.
- **Verification on `3cfe635`:** strict swift-format and SwiftLint clean; build clean; 1322 tests green except 16 sshd-fixture integration issues — the fixture env file exists so the suites enable, but the Docker daemon was not running; PalanaCore line coverage 97.46%.
- **`97b630c` makes that order the operator's:** favorites reorder by drag in the panel and by ⌥↑/⌥↓ on the row under the cursor. `FavoritesList.move(id:before:)` and `move(id:by:)` rewrite only the group's own slots, so a cross-group target is refused (scope stays with the pin control and ⇧↑/⇧↓) and the panel's sections cannot shuffle. One undo step per move; the ⌘ numbers follow. The drag payload is the favorite's id as plain text — a custom UTType has no bundle to be declared in, the ho-9.10 lesson. A row's upper half drops before it, the lower half after; the row measures itself and outlines while targeted.
- **Practitioner ruling, this session:** reorder within a group only, plus the ⌥ keyboard path.
- **Verification on `97b630c`:** strict swift-format and SwiftLint clean; build clean; 1334 tests, same 16 sshd-fixture issues and nothing else; PalanaCore line coverage 97.52%, `FavoritesList` branches 100%. `palana-web` `9cf99bd` documents the reorder; Eleventy wrote 17 pages cleanly.

**NEXT**
- **Hands try-out, the whole round:** press ⌘1–⌘9 from panes, `/` jump, and the shell; open the panel and judge the ⌘N row labels; confirm ⇧⌘8 stars; drag a favorite and judge the outline and the upper/lower-half landing; walk one with ⌥↑/⌥↓ and undo it. Then merge `favorite-numbers` to main and push `palana-web`. The prior NEXT still stands behind it: the cross-filesystem move acceptance and the next beta tag.

**ACTION ITEMS / BLOCKS**
- `favorite-numbers` unmerged (`3cfe635`, `97b630c`); `palana-web` `3bed335` and `9cf99bd` unpushed and undeployed.
- Drag reordering has never run under a human hand — no test drives a real drag, and the panel is a floating NSPanel. The upper/lower-half split and the drag preview are try-out items, not verified behavior.
- The sshd fixture suites fail rather than skip when the env file exists without a running container — start Docker before trusting a full `swift test`.

**PROJECT LIFECYCLE**
beta

## State summary — 2026-09-11, eighteenth block — FILE MOVES RELEASE PROGRESSIVELY THROUGH CONTENT-CHECKED RSYNC

**COMPLETED**
- **`def967f` restores conventional file-move behavior without restoring the old unchecked delete gate.** Same-filesystem moves still use `mv`, whole-dataset moves still use the bound ZFS release, and other supported file moves run rsync with engine-owned `--checksum --remove-source-files`. Source files leave only after their individual transfers; empty selected source directories are removed bottom-up with `rmdir`; every selected source entry still present is named through a `palana-retained:` recovery note and fails the run. Tar and `cp -a` remain copy-only, so a move with no supported rsync route refuses before enactment.
- **The checksum is an exercised safety requirement, not decoration.** A live adversarial test creates an existing destination with the source's size and modification time but different bytes. Plain rsync's quick check accepts that false match and removes the source; the committed command transfers the correct bytes before source removal. Engine-owned flags follow operator flags, and custom source-removal flags are refused, so settings cannot turn a copy into a move or disable the content check.
- **The operator contract is visible before Enter.** The plan panel says that files are removed after transfer, neither location may be modified during the move, and interruption may split the selection between source and destination. Decoded or mutated plans are refused unless source removal, transport, operation, cleanup, and retained-source accounting agree.
- **Documentation matches the implementation.** `README.md`, `CHANGELOG.md`, the system design, and release notes changed with the code. Public help, requirements, move, plan, and ZFS pages changed in `palana-web` at `6ca69f1`; the Eleventy build wrote all 17 pages cleanly.
- **Verification on `def967f`:** strict swift-format and SwiftLint clean; build clean; 1310 tests across Swift Testing and XCTest green with unavailable disposable SSH/ZFS fixture suites skipped; PalanaCore line coverage 97.50% (floor 90); application-logic line coverage 55.48% (floor 35). The site build is green. Both repositories are pushed.

**NEXT**
- **Release acceptance, not more code:** perform one cross-filesystem move in the app, confirm the warning sits above the commands, and confirm successful source removal and destination bytes. Then build and tag a new beta; `v0.7-beta` still points to `544661e`, whose file-move behavior is the earlier refusal, so that existing artifact must not be described as containing `def967f`.

**ACTION ITEMS / BLOCKS**
- No code block. The local Docker sshd and Lima ZFS fixtures were unavailable, so their integration suites did not run locally; pushed CI supplies the disposable sshd fixture, while ZFS remains a local-only integration path.
- The progressive rsync contract assumes a quiescent source and destination during the move. Cancellation or failure can leave complete files split between both locations; the retained-source result names what remains instead of claiming completion.

**PROJECT LIFECYCLE**
- `beta` — progressive moves and their documentation are implemented on `main`; one hands check and a replacement beta artifact remain before this behavior reaches downloaders.

---

## State summary — 2026-09-08, seventeenth block — THE HANDS ROUND ON THE REPAIRS; BETA IS THE NEXT GATE

**COMPLETED**
- **Two days of hands feedback on the repaired build, seven fixes, each its own commit off `main`:** `2e9eb2c` the active pane wears a hairline · `1a08689` the terminal opens where the pane stands · `cfb1262` the host menu says when the config is unreadable (scope-toggle rows out of the quick menu) · `3b38e6a` a merge is never a rename (the manifest gate is the subset rule now, his decision; merges complete and delete the source) · `0371daa` panes keep themselves current (local FSEvents watcher, remote 10 s poll while frontmost, re-list on activation) · `491c7c9` ⌘` always reaches the shell (supersedes round 9's decline; a click off the shell hands the keyboard back) · `8206bc4` the shell's caret rests when the panes have the keyboard (steady, faint). Plus `85de4e0` the recovery notice reads plainly and leaves on its own.
- **Two findings from the hands round itself:** `5b030e3` the sshd fixture named its host `palana@localhost`, which Task 6's grammar rightly refuses — every task worktree had skipped the fixture suites, main ran them and failed; `e316c9b` the directory watcher opened its descriptor asynchronously after `.ready`, so the first change after a landing could be missed — the widened watcher tests caught it under load.
- **`31d6f0a` the session takes its world as parameters:** `PalanaSession` has a designated initializer (config URL, SSH configuration, conduit with no defaults; store URLs with today's defaults); every live `SSHConduit` in PalanaTests is the recording fake; a guard test fails if the pattern returns; the suite passes with an empty `$HOME`.
- **Hands verdicts (2026-09-08):** all fourteen checks pass — panes, refresh, terminal directory, shell toggle over a settled plan and over a live run, host menu diagnostic, the merge move, address recovery, the resting caret ("fix is perfect").
- **Stack on `8206bc4`:** 1295 tests in 197 suites + 70 XCTest green with the sshd fixture live; PalanaCore 97.7%, application logic 52% (was 35 at the floor's birth). Pushed to `origin/main`.

**NEXT**
- **Beta.** His call (2026-09-08): this is the stopping point. The sequence lives in `palana-web/BETA-LAUNCH.md`: install the Metal toolchain component Xcode 26.3 no longer bundles (`xcodebuild -downloadComponent MetalToolchain`), the universal signed and notarized dmg, the site's first deploy with the publish-root check. No features before beta.

**ACTION ITEMS / BLOCKS**
- No blocks. CI on `8206bc4` to be read after the push.
- Carried limits: a quiet self-refresh clears `lastError`, so the unrepresentable-name banner clears on the next refresh; cancelled enactments have no re-read hook (the watcher or the poll covers it); a cursor color the shell sets while the caret rests is overwritten on wake; every typed remote pointing costs one `test` round trip; `HostOnboardingForm`'s remove preview still scans Host-only.
- The universal build needs the Metal component; `dist/Palana.app` today is native arm64, ad-hoc signed, for his Macs only.

**PROJECT LIFECYCLE**
- `beta` — the release-blocking findings are repaired, tested, and hands-verified; the dmg and the site are what stand between this build and beta testers.

---

## State summary — 2026-09-06, sixteenth block — THE FULL-REVIEW REPAIR PROGRAM INTEGRATED; ADDRESSES PARSE THROUGH ONE GRAMMAR

**COMPLETED**
- **All eight repair tasks from `ho-process/reviews/2026-09-06-repair-dispatch.md` built, verified, and integrated on `integration-review-repair`**, in the dispatch's wave order, one atomic commit each, each in its own sibling worktree: `f98d85e` commands stop before cancellation is reported (Task 1) · `a227d80` round-trip saves preserve remote identity (Task 4) · `d104491` ssh config edits preserve unrelated policy (Task 5) · `59f09af` moves delete only after content identity (Task 2) · `7de73f2` zfs plans bind to fresh topology truth (Task 3) · `6ebe5fb` ssh aliases never become command syntax (Task 6) · `def0809` file actions preserve exact path identity (Task 7) · `bdaee33` operation evidence fails visibly (Task 8). Then `b370281` pasted addresses resolve through one grammar (the address task he added mid-run) and `56e6445` pasted addresses recover conservatively (his amendment: exact path wins, one trailing prose character corrected only if the result exists, else the longest existing ancestor with the unresolved suffix shown, never `/` alone, never another host; `AddressRecovery` in PalanaCore, one probe per component). The integration gate ran after every merge and was green every time.
- **Every one of the 28 review findings closes on a test that fails against the old code**, per commit body. The critical five — stale-topology destroy, count-only move gate, wrong upload directory, fail-open collision check, weak remote identity — are covered by `TopologyBindingEnactmentTests`, `TransportsManifestTests`, `PaneModelRoundTripIdentityTests`, `RoundTripDispositionTests`, and `RoundTripEvaluateTests`.
- **Final stack on `56e6445`:** swift-format strict clean, swiftlint strict clean, build clean, **1221 tests in 184 suites + 53 XCTest cases green**, PalanaCore **97.48%** (floor 90), application logic **40.02%** (new second tier, floor 35). Fixture suites skipped (sshd container and zfs VM down, per precedent). Working tree clean.
- One merge conflict (Tasks 2 and 3, `OperationModel.swift`: an edit against a move of `addPlacementFacts`) resolved without semantic change, recorded in `66f4d16`.

**NEXT**
- **His hands.** The address task's manual check (remote pane → ⇧⌘G → quoted newline-terminated Finder path shows `this Mac` and lands locally; `storage-host:/…` and `:/…` show their hosts) and a feel pass on the new refusals: kind-clash plans no longer arm, merge-into-non-empty moves keep the source, unreadable SSH config shows a diagnostic instead of an empty host list, the cancel now waits for the process.
- Merge `integration-review-repair` into `main` and push; CI runs the new two-tier coverage gate (`scripts/coverage-floor.sh 90 35`).

**ACTION ITEMS / BLOCKS**
- No blocks. Nothing pushed; `main` still at `80344c1`.
- **Two orchestrator decisions to ratify:** (1) Task 5's stop condition — macOS has no atomic compare-and-replace against a non-coordinating editor; accepted the coordinated re-read/compare/backup/rename with its microsecond residual window (recorded in `d104491`). (2) Exact manifest agreement refuses source deletion for a move that merges into a non-empty directory; the old count gate already refused that case, so it is a carried limitation, not a regression — a subset check is the one-line relaxation in `VerificationReport.matched` if he wants merges to complete.
- **Test-rig hazard:** six PalanaTests rigs build `Engine` over a live `SSHConduit`; a path that reaches `engine.conduit(for: remote)` (e.g. `resolveTilde` on a remote `~`) goes to the real host. An intermediate run of the recovery task sent read-only `test -d` probes to storage-host before the probe moved onto the fake `Listing`. Committed tests avoid the door; a fake conduit for `Engine` would close the hazard.
- Every typed remote pointing now costs one `test` round trip before its listing (structured pointings untouched).
- Carried: `PalanaSession.init` is not instantiable under test (reads the real `~/.ssh/config`), which is why the application floor sits at 35; injectable init is the next ratchet. `HostOnboardingForm`'s remove preview still uses a Host-only scan (may over-warn about a following `Match`). Site never deployed; publish-root hazard; dmg held at his word.

**PROJECT LIFECYCLE**
- `beta` — the release-blocking critical findings are repaired and tested; beta launch remains the next gate after his hands pass.

---

## State summary — 2026-09-06, fifteenth block — PLANS NAME THE RSYNC THEY WILL ACTUALLY RUN

**COMPLETED**
- **`4eed995` — the Finder-launch rsync gap closed** (agent task `agent-task-2026-09-06-resolve-mac-rsync-path.md`, decided with him this morning mid-transfer). A Finder-launched app inherits `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, found Apple's openrsync, and the plan degraded by design to the `-a --partial` floor — no `-s`, no progress2, no bar, and a plan whose text ran a different binary than the one it named.
- **The fix, in the shape the spec drew.** `HostCapability.rsyncPath` (optional, default nil — old cache files decode). `CapabilityProbe.localCommand` = the shared `command` under `PATH=/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$PATH` plus a `palana:rsyncpath:` marker; the shared `command` and both recorded corpora are untouched. `PlanEngine.rsyncInvocation` names the resolved binary (through `ShellQuote`, so a path with a space still runs); nil path composes bare `rsync`, pinned byte-for-byte for forwarded, same-host, and unresolved-local plans. `Transports.isRsyncCommand` keys progress parsing on the first token's last path component — the `hasPrefix("rsync ")` trap is gone. `localCapability()` runs the local probe.
- **One deviation from the spec's file list:** `modernRsync`, `rsyncFlags`, `rsyncInvocation` moved to `PlanEngine+Rsync.swift` — the engine file was four lines past SwiftLint's 500-line budget and the extension pattern already stood in that directory.
- Stop condition checked first: the widened PATH resolves `/opt/homebrew/bin/rsync` → 3.4.1 here, so the premise held.
- 946 tests, 143 suites, all green with both fixtures up; PalanaCore 96.87%. Pre-commit clean.

**NEXT**
- **Hands verdict, same morning: "it worked."** Finder-launched `dist/Palana.app` at `4eed995` named `/opt/homebrew/bin/rsync` in the plan and the bar filled. The task is closed.
- Back to the beta-launch plan in `palana-web/BETA-LAUNCH.md` (unchanged from the fourteenth block).

**ACTION ITEMS / BLOCKS**
- No blocks. `4eed995` pushed; **CI green at `1674bb8`** (`gh run` checked). CI had been RED since `f133081` — the runner's newer SwiftLint carries `legacy_swiftui_aspect_ratio`, which local 0.65.0 does not; one line in `AboutWindow.swift` now reads `scaledToFit()`. Toolchain drift, not a code fault; a pinned SwiftLint version in CI would stop the next one.
- The zfs VM's self-hop key went stale again after this restart (`limactl shell palana-zfs -- ssh-keygen -R localhost` cleared it — the known cure). The sshd container is left up; the VM is left stopped, per precedent.
- Carried from the fourteenth block: the site has never been deployed; publish-root hazard; local parallel-run flakiness; dmg held at his word.

**PROJECT LIFECYCLE**
- `beta` — code hands-verified through August and green; this task is a beta-audience correctness fix (every Homebrew Mac is the case it covers). Beta launch remains the next gate.

---

## State summary — 2026-08-30, fourteenth block — CI GREEN AGAIN; THE HANG WAS SSH CONTENTION, NOT A SLOW TEST

**COMPLETED**
- **`7f3d36c` — main is green for the first time in three weeks** (3m30s). Three weeks of red were a 30-minute job kill with *nothing to read*: the runner killed the job from outside, so no stack and no test name ever reached the log. The run froze half a second in and went silent — including tests that carry their own deadlines, because the actor meant to enforce them was stuck.
- **Three hypotheses raised and killed by evidence before the fix.** The PTY tests and the RoundTripWatcher tests are all deadline-bounded already (`RoundTripTests` says so in its header). `BatchMode=yes` is on every `SSHConduit` invocation, so no ssh call can ever block on a password prompt. Naming them here so they are not re-suspected.
- **The real finding: ssh contention under parallel tests.** Each ssh integration suite opens a ControlMaster; enough at once trips sshd's `MaxStartups`. Locally that showed as `Connection closed by 127.0.0.1 port 2223` and a *different* set of sshd tests failing on each parallel run — reproducible flakiness, not a fluke. **Serialized, two consecutive runs came back byte-identical.**
- **The fix, in three parts.** `scripts/ci-test.sh` runs the suite under a watchdog and **samples the stuck processes before killing them**, so the next hang names its own blocked call stack. `--no-parallel` removes the contention and makes any future hang attributable to exactly one named test. The PTY suites (`TerminalSessionStoreTests`, `ShellNaturalExitTests`) skip on a headless runner via `TestEnvironment.isHeadlessCI` — no window server, no interactive login shell — and still run in full locally. Job cap 30 → 25 min.

**NEXT**
- **Beta launch, not 1.0.** `palana-web/BETA-LAUNCH.md` is the plan; Phase 3 (the four rooms) is gated on Phase 0–2, all `[you]`: price/domain/window, shots + the 50-second demo video, verify the `/compare/` cells, deploy the site, and a signed dmg at `/releases/latest`.
- The dmg build is **explicitly held at his word** ("I want to allow some last-minute changes").

**ACTION ITEMS / BLOCKS**
- No blocks. `7f3d36c` pushed; CI green.
- **The site has never been deployed.** `palana.sageframe.net` resolving to `private DNS address` is his dnsmasq and is CORRECT locally — not a fault, as first reported here in error. It simply has no public deploy yet. `public/_data/site.json` still says `v0.4-beta`, and the site's download buttons point at `/releases/latest`, which is still the July beta.
- **Publish-root hazard for the site deploy.** `palana-web` carries `node_modules/` and `_site/` beside `public/`. Per his standing rule, `.gitignore` is not a publish boundary — the deploy root must be `_site` alone, with an `.assetsignore`, verified against the live URL (fetch `/.git/HEAD`, expect 404).
- **Local parallel runs stay flaky** even after this fix — only CI was serialized. `CONTRIBUTING.md` tells contributors to run `swift test`, so they will meet it. Proposed, not done: `--no-parallel` in `make verify` too.
- ZFS VM was left **stopped** this session; the 5 ZFS tests fail locally until `scripts/zfs-fixture.sh start`. CI never runs them at all.

**PROJECT LIFECYCLE**
- `beta` — code hands-verified and green; nothing published. Beta launch is the next gate, 1.0 is 8+ weeks past it by his own exit criteria.

---

## State summary — 2026-07-29, thirteenth block — HANDS ROUND CLOSED, FIXTURES UP, FIRST FULLY GREEN RUN IN WEEKS

**COMPLETED**
- **His hands round on the three beta tasks, built live, three commits, all rhythm-green.**
  - **`3293c73`** — the destination arrows ACT (an arrow with a favorite under the cursor now opens it in that pane, not merely arms the next click); the **double-click-becomes-rename bug** fixed (a click now *arms* a rename and waits out the double-click interval, and any further click cancels it — the old predicate was right about the second click and wrong to act on the first); a click away commits.
  - **`ccb0f3e`** — the click-away commit REDONE after he reported it still dead. Focus was the wrong signal: this is a `.nonactivatingPanel`, and clicking its ground never takes first responder off the field editor. The field's text moved onto `FavoritesPanelModel` so anything can commit it — a panel-level click-catcher, another row, the arrows. **Tab** switches the focused pane from inside the column and the destination arrows follow it, closing the keyboard loop.
  - **`0fd4d9b`** — **all five glance panels now `hidesOnDeactivate`**. A `.floating` panel outranks every application on screen, so the favorites column sat above Mail and followed him out of pālana. This is a DIFFERENT bug from the Spaces one fixed at v0.6 (`.canJoinAllSpaces`) — that was the desktop dimension, this is the app dimension. Footer keys are now set apart from their verbs ("8 stars" had read as a count of stars, not the `8` key) and carry a full tooltip.
  - His verdicts: `r` works, `*` works, click works, open-in-Finder works, bare-path addresses work. **The panel key monitor DOES fire for the favorites panel** — the eleventh-block worry, and [[palana-panel-esc-key-monitor]], did not bite here.
- **BOTH FIXTURES BROUGHT UP AND THE SUITE IS FULLY GREEN — 936/936, first time since the fixtures went down.** Docker sshd container on 2223; Lima VM `palana-zfs` with pool `palana` ONLINE. PalanaCore line coverage **96.85%** (floor 90). `make verify` clean end to end.
- **The 27 "failures" were never code.** With fixtures up they fell to 3, all fixture-state drift from past hands sessions, now repaired in place:
  - `palana/stray-dataset` was **mounted at `/`**, where it shadowed every path lookup — which is why `/var/log/syslog` resolved to a dataset instead of nil. Moved to `/palana/stray-dataset`; **kept, not destroyed** (a `zfs destroy` was refused by the permission guard, correctly — and moving it was enough).
  - `palana/tank/media/photos` had been set to `/palana/children-moved`, and `palana/detached` to `/palana/tank/stray-child/temp`. Both inherited back to their defaults.
  - The VM's own `~/.ssh/known_hosts` carried a stale `localhost` ECDSA key, which failed the self-ssh forwarding test. Re-scanned.
- **`scripts/zfs-fixture.sh` is now self-healing** so this cannot cost a session again: `ensure` only ever created, so drift was silent. A new `reconcile` puts each designed dataset back at its designed mountpoint on every `start`, and datasets the fixture never made are **named on stderr, never destroyed** — a hands-session leftover is the operator's to remove, not a script's. Verified idempotent (a second run reconciles nothing and names `stray-dataset` + `tank/stray-child`).

**NEXT**
- **v1.0 / ho-12 (the ship).** The build is green, covered, and hands-verified; the pipeline already exists (`scripts/build_macos.sh`, notarize, `RELEASING.md`). Nothing technical is in the way — the remaining work is the ho itself and his word to tag.
- Carried: the **help pages** on the website; banked — snapshot-history surface, shell-UX rethink.

**ACTION ITEMS / BLOCKS**
- No blocks. Everything pushed to `main` (`0fd4d9b` and earlier); the fixture-script hardening is the only uncommitted work at the time of writing.
- **CI NEVER RUNS THE ZFS PATH.** `.github/workflows/ci.yml` brings up an sshd fixture on the runner but no Lima VM, so every ZFS integration test — mutation round trip, dataset boundaries, zfs send/receive transports — is proven ONLY on a local run with the VM up. Worth knowing before v1.0: green CI is not the same as a green wire.
- **Fixtures are UP and left up.** Stop with `scripts/sshd-fixture.sh stop` and `limactl stop palana-zfs`. The ZFS `destroy` target deletes the whole 100GiB VM, not just the pool — reach for the reconcile path first.
- Two strays remain in the pool by choice: `palana/stray-dataset`, `palana/tank/stray-child`. Harmless where they now sit; the fixture names them on every start.
- **DECISION STILL OWED** from the twelfth block: the go-to sheet and bare paths (a picked host is treated as an explicit host; local-first is only for input naming no host). Unchanged, his call.

**PROJECT LIFECYCLE**
- `beta` — v0.6 on main plus the three beta tasks and their hands round; fully green with fixtures up. v1.0 (ho-12, the ship) is the next move.

---

## State summary — 2026-07-27, twelfth block — THE THREE PRE-RELEASE BETA TASKS BUILT AND COMMITTED

**COMPLETED**
- **The three queued agent tasks in `ho-process/agent-tasks/` executed in order, one atomic commit each, full rhythm green at every commit** (swift-format strict, swiftlint --strict, build, test). All three specs now carry `status: complete` in the same commit as their work.
  - **`86b0adf` favorite labels — `r` renames a star.** `Favorite.label` already existed and both render surfaces already preferred it; what was missing was every way to *set* it. Added `FavoritesList.setLabel(id:label:)` (trims; nil/empty/whitespace clears) + the `FavoritesModel` shell in the `setScope` rhythm (snapshot → mutate → persist, so ⌘Z undoes it), `Favorite.displayTitle` as the one display rule, the `r` key in `handleFavoritesPanelLetter`, an inline name field (⏎ commits, esc cancels — esc unwinds the field before the panel), a row context menu (rename… / scope toggle / unstar), and Finder's second-click rename behind a pure `FavoriteRenameArming.shouldBeginEdit`. Footer now reads `esc closes · r renames · 8 stars · * opens`. Two structural moves the lint budget forced: rows extracted to `FavoritesPanelRow.swift` (file-length), and the panel's four callbacks bundled into `FavoritesPanelActions` (function_parameter_count).
  - **`66dd71e` open in Finder — local panes only.** `PaneModel.revealTargets(directory:selection:ids:)` is the pure resolver; selection manners match `operate()`/`dragPayload` exactly (clicked-inside → whole selection, clicked-outside → that row, empty → the directory). Paths join byte-accurately via `childPathData` (`FileEntry.ID` *is* `nameData`), and the menu item is absent — not disabled — on remote panes, gated on a new `PaneModel.isLocalPane` that wraps the existing `Engine.isLocal`, the one locality test. Surface-only diff; PalanaCore untouched, as the spec required.
  - **`9ab22c6` bare absolute paths resolve local first.** `TypedAddress.classify` in PalanaCore is the three-way split (`hostPath` / `barePath` / `host`), 100% covered; `PaneModel.resolveBarePath` holds the order (local hit → here; local miss + remote hit → there; both → local; neither → a refusal naming both) with injectable async existence checks, so "no round trip precedes a local hit" is pinned by a test rather than by a comment. The remote check is one `test -e` round trip. The file-reveal redirect from `53de538` is reused, not reimplemented — `read()` already turns a file path into parent-plus-reveal for both hosts. Address concern extracted to `PaneModel+Address.swift` (file-length).
- **A real bug caught by the byte-fidelity test, not by review**: `URL(fileURLWithFileSystemRepresentation:)` (the Swift overlay) replaces non-UTF-8 path bytes with U+FFFD; `NSURL`'s initializer carries them through intact. Measured, switched to `NSURL`, both round-trips pinned. (Also measured: APFS rejects non-UTF-8 names outright — `open()` returns `EILSEQ` — so this only bites on foreign mounts.)
- **Verification**: 932 tests, 143 suites. PalanaCore line coverage **93.00%** (`xcrun llvm-cov report … -ignore-filename-regex='(Tests/|\.build/|Sources/Palana/)'`), above the 90% floor — and measured with the SSH/ZFS fixtures DOWN, so CI reads higher.

**NEXT**
- **His hands on all three** — the rename gesture in particular: `r` in the panel, the second-click arming, and whether the row menu reads right. Then the two flagged decisions below.
- Carried from the eleventh block, unchanged: **v1.0 / ho-12 the ship**; the **help pages** on the website; banked — snapshot-history surface, shell-UX rethink.

**ACTION ITEMS / BLOCKS**
- No blocks. Three local commits on `main`, **not pushed**.
- **DECISION OWED — the go-to sheet and bare paths.** Task 3's spec said the sheet must funnel through one resolver; the sheet has no parser to unify, it has a *host picker*. I funneled it (`session.point` now composes `host:path` through `pointAddress`) which leaves its behavior byte-for-byte unchanged, on the reading that a picked host is an explicit host and local-first is for input naming no host at all. The alternative — a `/`-leading path in the sheet resolving local-first — would let an ordinary remote path like `/tank/media` be hijacked by a same-named local directory. Conservative choice made; his call to change it.
- **FLAGGED — the panel key monitor.** `handleFavoritesPanelKey` (and so the new `r`) routes through the app-wide `NSEvent` local monitor, which [[palana-panel-esc-key-monitor]] recorded as not firing while a floating nonactivating panel holds the keyboard. The mouse routes (second click, row menu) are unaffected and always work. If `r` proves dead on his hands, the fix is the panel answering its own `keyDown`, one method on `FavoritesFloatingPanel` — deliberately not done here as it would revive j/k/arrow nav beyond the spec's scope.
- **UNEXPLAINED — `CLAUDE.md` lost its "## Ho process" section** (11 lines listing the Kamae chain paths) during this session, by no edit of mine. Left exactly as found: not reverted, not swept into any commit. It shows as an unstaged modification. Restore with `git checkout CLAUDE.md` if unintended.
- The ~27 SSH/ZFS fixture-integration tests fail with the fixtures down (environmental, pre-existing — identical count before and after this session's work, verified by stashing).

**PROJECT LIFECYCLE**
- `beta` — v0.6 on main; these three are pre-release beta polish ahead of v1.0 (ho-12, the ship).

---

## State summary — 2026-07-16, eleventh block — PHASE 6 (THE V1 POLISH) BUILT AUTONOMOUS + HANDS-HARDENED; v0.6 ON MAIN

**COMPLETED**
- **The four Phase-6 hos built end-to-end in one autonomous run** (`agent-tasks/v1-polish-run-all.md`), each to its sealed ho doc, one atomic commit each, full rhythm green:
  - **ho-13 (`46652d2`) universal text-scale** — `Theme.font(_:)` factory the whole in-window surface draws through; pure `TypeScale` (multiply/clamp `[0.8,1.6]`/step) in core, `TextScale` @Observable holds+persists the factor; ~150 call sites swept.
  - **ho-15 (`f4a9b1e`) dark mode** — Sharibako's `RGBA`/`Palette`/dynamic-NSColor ported into `Theme`, all eight tokens light+dark (tests pin each), `AppAppearance` + `.preferredColorScheme` + Settings picker; hue-literal audit closed.
  - **ho-14 (`30c6f6e`) drag into folders** — `DropDecision.decideOntoFolder` (core, tested): a directory row is a drop target resolving to the folder path; accent hover wash; self/same-place refusals.
  - **ho-16 (`33c2480`) preview pane** — `PreviewRouter` (core, 100% line: text-vs-quicklook by ext + UTF-8/NUL sniff, 256 KB cap) + `PreviewController` (debounced follow, bounded read); `v` toggles, QLPreviewView, info card.
- **His hands review drove a long hardening pass** (commits `2b92d14`→`67138ae`), all rhythm-green:
  - **PERF (mine to own):** dark mode made every color token a computed property allocating a fresh dynamic `NSColor` per access → the Table's per-cell reads = a seconds-long nav stutter. Cached each token `static let` (still appearance-aware — the NSColor stays dynamic). Gone.
  - **Finder → folder** lands inside the folder (row target accepts `.fileURL` too, `routeFinderDrop` with a destination override).
  - **Preview reshaped:** `v` forces the RIGHT pane to preview, snaps focus LEFT and LOCKS it (nothing to click right); `v`/esc exits. **Remote text** now previews over the wire via a bounded `Listing.readFileHead` (`head -c`); remote binary stays info-only.
  - **ONE MASTER ⌘+/−:** the keys and zfs panels dropped their bespoke ⌘1–5 stepping and follow the global factor, resizing their window `base×factor` on change (one-way setFrame — none of the old resize-delegate crash). **The flat in-window `?` card is gone** — `?` opens the floating popout directly (helpVisible/floatingHelpTick/handleHelpKey all removed).
  - The `?` card went **three columns + a scrim**; the **floating panels no longer follow across desktops** (dropped `.canJoinAllSpaces`); the **host map follows global zoom**; the `?` card lists the **live zfs verbs**; and **the floating panels obey light/dark** via `NSApp.appearance` (his last note — `.preferredColorScheme` governs only the SwiftUI window).
- **v0.6 tagged; `phase-6-v1-polish` merged to main (`7fc13fd`).** 844 tests, PalanaCore line coverage 96.71%.

**NEXT**
- **ho-12 (the ship) → v1.0.** The pipeline already exists (built ahead at v0.4-beta: `scripts/build_macos.sh`, notarize, `RELEASING.md`); ho-12 formalizes it and cuts v1.0. Re-export a true 1024² icon (the beta one was padded).
- **The help pages** — web, in `sageframe-dharma/palana` (the website home); Fable writes them (native/in-app help retired in favor of the site). The `?` popout stays as the fast in-app reference.
- Banked, unchanged: **remote-binary preview** (fetch-to-cache on ho-9.10 machinery, its own Think); the **snapshot-history surface** ("Time Machine for the homelab" — his highest-energy seed, likely reorders the roadmap); the **shell-UX rethink** (follow-the-host feel); the **sudo-explainer** (dead number 10.2, give it a fresh one).

**ACTION ITEMS / BLOCKS**
- No blocks. **Tag v0.6 is LOCAL — not pushed** (push to the public repo is outward-facing, waits on his word). Branch `phase-6-v1-polish` merged; safe to delete once pushed.
- The ~17–19 SSH/ZFS fixture-integration tests fail when Docker/Lima are down (environmental, pre-existing) — CI-green with the fixtures up. The ~825 non-fixture + all new suites pass.
- His hands verdicts this phase, all YES: master zoom "boom boom," flat card gone, dark mode "GREAT," preview good — "Its GOOD now!"

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; **v0.6 = Phase 6, the v1 polish, hands-hardened, on main**; v1.0 = ho-12 (the ship) after.

---

## State summary — 2026-07-15, tenth block — THE MOUNT SEAM PROVEN AND CLOSED; 10.3, 10.1, 11 CLOSED — PHASE 4/5 DONE

**COMPLETED**
- **ho-10.4 (The Mount Seam) fully proven on his hands and CLOSED.** Three ATs
  beyond AT-01, each built by agent (sonnet), reviewed from the diff, hands-verified:
  - **AT-02 (`b49e42f`)** — the implicit-unmount heal. destroy / set-mountpoint /
    clear-mountpoint on a MOUNTED dataset weave `sudo -n zfs unmount` ahead (+ a
    trailing `sudo -n zfs mount` for the two mountpoint verbs); `MutationInput` +
    `PlanRequest.targetMounted` carry the mounted fact from the surface to the pure
    composer. **F1**: the field view grew the `sudo` chip to match the host map.
  - **AT-03 (`dc6abf7`)** — `space` flips the recursive toggle (was mouse-only) in
    both the field-less (destroy) and text (snapshot/rollback) gathers; space over
    `r` because a typed name can hold `r`, never a space.
  - **AT-04 (`869763d`)** — set-mountpoint composes `zfs set -u` (no auto-mount →
    kills the mid-plan "insufficient privileges" warning). `zfs inherit` has no `-u`
    (only `-rS` on 2.4.1) so clear-mountpoint keeps its cosmetic warning; the
    explicit mount still lands it.
  - Verdicts: heal fired on a pane-driven destroy (`palana/armedguard`, "It worked");
    F1 chip shows; space toggle ("SMOOP"); `-u` set-mountpoint clean, no warning.
    Accepted as correct: clear = inherit parent path; set-mountpoint preserves mount
    state (unmounted stays unmounted — `m` mounts if wanted).
- **ho-10.3 (pane mode) CLOSED** — proven by all-session use; Reflect corrects
  Decision 3 (Z is the ONE zfs key, panel is click-only, umber badge).
- **ho-10.1 (zfs tool) and ho-11 (terminal) CLOSED on his hands.** 10.1 "is lean"
  — the snapshot loop, typed destroy, rename, create all read right; the
  seventh-block **second-press mystery did NOT resurface** (closed unreproduced,
  reopen forward if it returns). 11 — all seven criteria pass (shell summons,
  vim/htop/⌃C, ⌘\` focus in/out, ⌘-chords off the PTY, `exit` survives, failure
  over the shell). **Banked feel-question:** the shell binds to the summoning
  pane's host and does NOT follow pane focus ("stuck there… something weird,
  might just be comfort") — deliberate (a shell is a place), but a candidate for
  a future shell-UX rethink ho if it keeps reading wrong.
- **With these, every ho-10.x + ho-11 is closed — Phase 4 (Workbench) and Phase 5
  (terminal) are DONE.** Only the ship (ho-12) remains before v1.0.
- **Housekeeping:** the integration worktree was reaped from `/tmp` by macOS —
  branch ref lost but ALL commits intact; recreated `integration-shell-panemode`
  at `492e06a` in a DURABLE worktree `../palana-integration`. Three fully-contained
  per-ho pointer branches (10.3/10.4/11) deleted.

**NEXT**
- **THE CLOSE CASCADE, now unblocked** (all ho-10.x + 11 closed): **tag v0.5** on
  main → **merge `integration-shell-panemode` → main** (carries ho-11 + 10.3 +
  10.4 + the AT-02/03/04 heal work) → then **ho-12** (the ship) = v1.0.
- Fresh hos to open when he wants: **global UI text-scale** (⌘+/− everywhere,
  scales ALL chrome — a font-factory refactor, its own ho); the **sudo-explainer**
  (sudoers line at the refusal + settings reference — the last live piece of
  ho-10.2's old scope; `10.2` is a dead number, give it a fresh one); and a
  possible **shell-UX rethink** (the follow-the-host feel-question).

**ACTION ITEMS / BLOCKS**
- No blocks. App runs the integration build via HIS shell launch (`!` prefix —
  my background launches get reaped at turn boundaries; the `!`-owned one survives).
  Fixture VM `palana-zfs` UP.
- Pool is littered with `@save-it` snapshots on nearly every dataset — plain
  destroy hits "has children / use -r"; the space-toggle now reaches `-r`.
  `armedguard` destroyed this session; `children`/`pjb`/etc. remain as targets.
- Deferred (named in 10.4 Reflect): recursive-destroy of mounted CHILDREN;
  set-mountpoint auto-mount-on-unmounted (a preference, his call); `-u` version-gate
  for pre-2.2 hosts; sudo fixture `zfs-pool.json` re-capture.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; mount seam (10.4) + pane mode (10.3) CLOSED on the
  integration branch; v0.5 = his 10.1/11 verdicts + the merge away; v1.0 = ho-12.

---

## State summary — 2026-07-12, ninth block — THE VERDICT MARATHON: SHELL GREEN, ZFS HARDENED, THE MOUNT SEAM LANDS

**COMPLETED**
- **Shell 5–9 ALL YES; zfs 12/13/16/17 YES; #20 CLOSED** (fixed by the
  plan-owns-the-panel redesign; unreproducible). His hands drove ~six
  more fix rounds on the integration branch, all rhythm-green:
  - `/` type-to-jump (his ask: a MODE, not suppression — grammar stands
    down, cursor chases, footer shows the buffer).
  - Round-9 fixes: shift-click selects (NSEvent.modifierFlags class
    property — the Table's setter fires after the event passes);
    selection.json leak sealed (.ownProcess); esc-hides lie fixed;
    invisible-shell trap closed (shellVisible requires panelShowing;
    ⌘` on hidden panel re-summons whole; plan-owned = silent decline).
  - Esc hands the panel back to the shell (dismiss + keep panel up);
    rail names the road.
  - Rollback -r as a plainly-worded toggle (destroysNewer — GatherSpec
    grew toggleLabel); dead-end gathers self-dismiss AND stay visible;
    sshFailure renders as a sentence; relative mountpoints refuse in
    words; double-click descends a mounted dataset; snapshot verbs
    validate typed names against the listed truth; destroy label
    shouts DESTROY; recursive toggles name what they take (snapshots
    ARE children — his question, answered in the label).
  - Squat panel (3rd appearance): first-layout fitting-height squeeze —
    step size reasserted post-front + a turn later; panel owns its own
    origin persistence (frame autosave FIRED — legacy key + frame saved
    on a disconnected display); stale defaults keys purged.
  - zfs-mode host-follow: refresh moved from point() to commit() —
    reads are async, the old placement refreshed the OLD host.
- **ho-10.4 (The Mount Seam) authored, built by agent, reviewed,
  MERGED into integration** (8b62150): HostFacts.sudoNoPassword
  (sudo -n true, never-fatal, 4th discover round trip, host-map token);
  .mount/.unmount composing `sudo -n zfs mount/unmount` read IN the
  plan; keys m/u, set-mountpoint → p; CapabilityRequirement.zfsMount
  gating on BOTH facts with the exact refusal sentence. 736 tests.
  Corpus fixture zfs-pool.json predates the probe — re-capture when
  hands are on the VM (flagged, nothing asserts on it).
- **Time-machine revelation banked** (snapshots = browsable past via
  .zfs/snapshot; works TODAY via address bar; READmade copy commitment;
  likely roadmap reorder). Preview-pane seed banked earlier.

**NEXT**
- **His mount hands-round** (m/u on the fixture, sudo token in host
  map, p for set-mountpoint, refusal on storage-host) + retests: panel open
  size (post-front reassert), host-follow in mode, dead-end note
  visible, DESTROY label, sandwich destroy with the renamed -r toggle.
- Then THE CLOSE CASCADE: his final verdicts → close ho-10.1 → tag
  v0.5 on main → merge integration branch to main → close ho-11/10.3/
  10.4 with hands-session Reflects (amend docs: ⌘` not t/⌘Esc, Z
  ungated, panel click-only, mount seam) → README polish LEADING with
  browse-your-snapshots → Dave (still parked).

**ACTION ITEMS / BLOCKS**
- No blocks. App running merged build; fixture VM up.
- Banked: selection rows want a highlight wash (design polish); zfs
  pane-mode dataset jump; auto-mount after create; preview pane;
  snapshot-history surface (Kamae-4 slots when board clears).
- Reentrant-NSTableView launch warnings still unchased (pre-close).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 = his verdicts away; integration
  branch carries ho-11 + 10.3 + 10.4 hands-hardened; v1.0 = ho-12.

---

## State summary — 2026-07-11, eighth block — THE INTEGRATION HANDS SESSION: FIVE ROUNDS ON THE SHELL AND THE BOUNDARY

**COMPLETED**
- **He asked for the merge early** ("i want to test the terminal and the
  pane zfs setup") — branch `integration-shell-panemode` (worktree
  /tmp/palana-ho11) merged ho-11 + ho-10.3 ahead of the v0.5 tag; one
  conflict (both branches re-extracted handle()'s text-entry priority;
  10.3's handleTextEntryPriority subsumed ho-11's inline form). Main
  UNTOUCHED. Then five live hands rounds on the integration build:
  1. **`exit` killed the app silently** — nothing heard the child die;
     keystrokes wrote into a closed/recyclable fd → SIGPIPE, no crash
     report. Fixed threefold (0591f4e): store is processDelegate and
     drops dead sessions firing onSessionEnded; shell mode exits with a
     transcript note; SIGPIPE ignored app-wide. Two tests pin it.
  2. **⌘Esc provably never reaches the app** (key trace: the system eats
     ⌘Esc AND ⌘.) and `t`-for-shell fired file-touch seven times on his
     hands. ⌘` became the shell key (his fingers pressed it four times
     looking for the exit); t means touch again (94970c8).
  3. **The demoted overview panel was cramped and mute** — tree uncapped
     (the 180pt cap was for the deleted verb rows), copy names Z
     (b4783cb); then the WINDOW size bug: setFrameAutosaveName restores
     size too, stale frame defeated the stepped sizing — step size
     re-asserted after restore (0d91efd).
  4. **The zfs pane boundary too quiet; ⌘⇧Z 'WTH is that?'** — header
     wears a solid umber ZFS badge in the chip's style, wash 0.12, the
     chord is DEAD: panel is click-only on its chip; Z is the one zfs
     key (0d91efd).
  5. **'Z isnt working' + 'can I bring the shell in and out of focus?'**
     — Z was gated on strip focus (my ho doc's error; type-ahead ate it)
     → ungated, works at pane focus. And the focus model landed
     (682250f): shellMode (view) splits from shellFocused (keyboard);
     ⌘` MOVES THE KEYBOARD while the view stays — engagement line +
     dim + footer words say who is listening; first responder follows
     deferred a turn; ONE LAW replaced the failure hook's special case:
     the plan owns the panel whenever an operation exists, the shell
     shows in the idle gaps.
- Every round: full rhythm green (714 tests incl. 2 natural-exit).
- **Late add, his ask ("I am already reaching for palana ALL the
  time!"): drag-out** — a local pane's drag registers the real file URL
  beside the pane-to-pane payload, so the same gesture lands on browser
  uploads, Finder, Mail. Remote drag-out (file-promise that downloads
  through the transport on drop) BANKED as its own item. Internal drops
  prefer json — pane-to-pane untouched.
- A 20-item numbered test list was handed to him (drag-out 1–4, shell
  5–11, zfs pane mode 12–18, 10.1 remainders 19–20); his replies come
  as numbers.
- **SEEDED, his revelation ("WAY more useful than any of this... like
  time machine!"): SNAPSHOT HISTORY BROWSING** — the pattern he
  actually lives by: reach into `.zfs/snapshot/<name>/` and copy out,
  never rollback. The reframe: snapshots are a TIME DIMENSION of the
  filesystem — Time Machine for the homelab, over ssh. Works TODAY by
  typing the .zfs path into the address bar (restore = ordinary yank
  through the gate, source read-only by construction). The real
  feature: a history surface — stand on a file/dir, summon its past,
  pick a snapshot by age (field-view vocabulary), browse in a pane,
  restore with y. Engine has the facts, transports move the bytes,
  gate reads the plan; only the surface is missing, and pane modes are
  a solved shape. Wrinkle to solve: .zfs is invisible to listings by
  design (snapdir=hidden) — the surface erases that invisibility.
  LIKELY REORDERS THE ROADMAP (his energy says this beats 10.2's sudo
  work); his call at the next Kamae-4 pass. THIS is the Dave pitch.
  HIS COPY COMMITMENT ("we need to put this in the copy"): the README
  polish step LEADS the ZFS story with browse-your-snapshots ('browse
  the past like a directory; restore is just a copy'), ahead of the
  verb list. Mac-local ZFS asked and answered: possible (OpenZFS kext,
  Reduced Security on Apple Silicon) but recommended NO — the Mac is
  the operator; possible v-next: history surface abstracts snapshot
  providers (ZFS remote + APFS local).
- **SEEDED, his ask ("it would be life changing"): the PREVIEW/INFO
  pane mode** — paneMode grows .preview; the right pane follows the
  LEFT pane's cursor. Local: QLPreviewView (Quick Look) + an info card
  assembled from facts we already gather (FileEntry, treeSizes, ◆).
  Remote text: Listing.readFile head-read. Remote binary: fetch-to-
  cache on the ho-9.10 round-trip machinery — needs a Think phase
  (size caps, cursor-motion debounce, eviction). Sizing: local+info =
  one ho; remote-binary its own follow-up. Wants a Kamae-4 slot when
  the board clears. Also noted: 3 reentrant-NSTableView warnings at
  launch on the integration branch — run down before the branch closes.

**NEXT**
- **His verdicts**: the ⌘` keyboard loop, Z-from-pane zfs circuit
  (verbs on the tree cursor, Enter-into-mountpoint, post-enact tree
  truth, typed destroy), vim/htop/⌃C in the shell — plus the ORIGINAL
  10.1 list (snapshot loop feel) and the second-press one-liner still
  owed. Then: close 10.1 → tag v0.5 on main → fold the integration
  branch's fixes back into ho-11/ho-10.3 closes (the branch IS the
  hands session record) → merge to main → hands-verified close of both.

**ACTION ITEMS / BLOCKS**
- No blocks. App instance quit (his ⌘Q, ~00:00); relaunch:
  `cd /tmp/palana-ho11 && .build/debug/Palana` (run_in_background).
- Fixture VM left RUNNING for the resumed hands session (stop with
  `scripts/zfs-fixture.sh stop` when the walk is done).
- Post-merge follow-ups from the seventh block still open (tree-walk
  unit tests; SwiftTerm same-day-tag note for the v1.0 audit).
- ho-11/ho-10.3 docs need their Reflect sections amended with the
  hands-session corrections (⌘` not t/⌘Esc; Z ungated; panel click-only
  — my Decision-3 ⇧Z text was wrong in the app's grammar).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 waits on his 10.1 verdicts; ho-11 +
  ho-10.3 hands-session-hardened on the integration branch; v1.0 =
  ho-12 after.

---

## State summary — 2026-07-10, seventh block — THE HANDS ROUND BUILT LIVE; TWO HOS EXECUTED IN PARALLEL WORKTREES

**COMPLETED**
- **ho-10.1 hands round, built live on his verdicts** (three commits on
  main after the click fix): panel text scales with the size steps
  (keys-panel ruling applied); the tree reads cache-then-discovers-then-
  re-reads (stray-dataset-missing and create-not-showing both dead); every
  ready plan says "⏎ press enter to run this plan" in green in the term
  + the header's armed-Return block grew words; rollback/destroy-snapshot
  gathers list the dataset's snapshots under the field (ShellQuote went
  public for it); **typed destroy** — the word arms the verb, setting
  `confirmDestroyTyped` (default ON) in the new Workbench settings
  section frees it. Fixture pool mountpoints chowned to the ssh user
  (yank l→r was EACCES on root-owned /palana — machinery held, gates
  held); zfs-fixture.sh patched to chown on create.
- **His sequencing call, ratified**: "I DO want to wire up the terminal
  and the pane solution." ho-11 + ho-10.3 authored (Kamae 5, Think
  sealed at the top) and EXECUTED in parallel worktrees on sonnet;
  both reviewed at the top, both independently verified green.
  - **ho-11-terminal branch** (a4df114, /tmp/palana-ho11): SwiftTerm
    1.14.0 app-target-only; per-host LocalProcessTerminalView over the
    operator's own `ssh <alias>` (same config, same masters); plan panel
    third mode on `t` at terminal focus; Esc passes to vim, ⌘Esc comes
    home; failure law wired (onEnactmentFailed). 714 tests. NEW: a
    PalanaTests app-target test target exists at last.
  - **ho-10.3-pane-mode branch** (bc9eb72, /tmp/palana-ho103): pane
    Mode .files|.zfs, plugin-hued boundary, one cursor targets every
    verb, Enter-on-mounted exits into the mountpoint, panel DEMOTED
    (verb rows gone, zero mutation paths — grep-verified), afterZFS
    refresh mode-aware. Agent's flagged call: Z and ⇧Z are one token in
    this grammar, so bare Z = pane mode, panel moved to ⌘⇧Z. 708 tests.
- **ssh config gained an Include** of .fixtures/zfs-ssh-config (top of
  ~/.ssh/config) so the app + plain ssh resolve zfs-self; session.json
  pointed the right pane at zfs-self:/palana. Fixture VM RUNNING.

**NEXT**
- **His remaining 10.1 verdicts** (typed destroy live in the running
  build; snapshot loop; the click list) + the SECOND-PRESS mystery
  (Images #4/#5/#6 — something reappears on the second Enter; his one-
  line description still owed) → close ho-10.1 → **tag v0.5** → merge
  ho-11-terminal then ho-10.3-pane-mode (hand-merge: both reshape
  PalanaSession.swift; expect conflicts in monitor/extraction areas) →
  hands session per branch → README polish.

**ACTION ITEMS / BLOCKS**
- No blocks. Both branches wait on the v0.5 tag, not on build work.
- Post-merge follow-up: write the tree-walk unit tests ho-10.3 skipped
  (no app test target existed on its branch; ho-11's PalanaTests target
  arrives in the merge and unblocks them).
- SwiftTerm 1.14.0 was tagged upstream the same day it was pinned —
  builder diffed it vs 1.13.0 (iOS-side changes); Package.resolved pins
  exact. First dependency in the project; note for the v1.0 audit.
- Feel-checks queued: `t`-for-shell vs touch muscle memory; Z / ⌘⇧Z
  split; vim/htop/⌃C/resize in the shell.
- Session end: fixture VM to stop (`scripts/zfs-fixture.sh stop`);
  ~/.ssh/config Include line stays (inert when fixture is down) or
  comes out — his call. Dave still parked.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 is his verdicts away; ho-11 and
  ho-10.3 built and reviewed, awaiting merge; v1.0 = ho-12 after.

---

## State summary — 2026-07-10, sixth block — THE CLICK HUNT ENDS: CODE, NOT MACHINE

**COMPLETED**
- **The click-offset bug is FOUND and FIXED** (50f34fb). The fifth
  block's "environmental" verdict was WRONG — post-reboot the bug
  persisted, the bare v0.4-beta binary clicked perfectly on the same
  loaded machine, and a five-step bisect across v0.4-beta..1e80c10
  landed on 9808498: the supplementary `.onDrag` added to nameCell
  (drag attempt three's belt-and-suspenders). A cell-level drag source
  wraps cell content in its own drag-hosting view and desyncs SwiftUI's
  drawn rows from AppKit's hit rects — hit zones one row high, top row
  under the header. Removed outright; TableRow.itemProvider carries
  pane-to-pane drag alone (he verified live: clicks true AND file
  dragged across panes, on 1e80c10 + removal).
- **Why the earlier exoneration lied**: PALANA_NO_DRAG stripped only the
  row itemProvider; the cell-level `.onDrag` stayed live. Banked.
- **The styler reentrancy fix committed as its own keeper** (f82ba7a):
  every table mutation deferred a runloop turn — AppKit's "reentrant
  operation in its NSTableView delegate… will become an assert" warning
  answered. Found en route, kept on merit; NOT the click cause.
- **Hunt fully torn down**: scratch gates (PALANA_NO_STYLER/NO_DRAG/
  CLICK_DEBUG) stripped, bisect + v0.4 worktrees removed, his real app
  state restored from `palana.click-quarantine`. Verification: format +
  lint strict green, 704 tests green (sshd-fixture integration suites
  skipped — Docker daemon down by design this session; failures were
  connection-refused only, untouched by this UI-only diff).

**NEXT**
- **The two small 10.1 fixes** (pool-root refusal; panel pre-select
  follows pane cursor on dataset mountpoints), then his close verdicts →
  close ho-10.1 → **tag v0.5, ZFS badged beta** → README/docs polish →
  he writes to Dave (ysap.sh; counsel: name the root wall, lead with the
  snapshot loop).

**ACTION ITEMS / BLOCKS**
- No blocks. The reboot-gate in the fifth block is CLEARED (bug was
  code, now fixed).
- Restarting integration fixtures (sshd container, `make zfs-fixture`)
  wants Docker Desktop up — start before the next integration-touching
  session; run the full suite then.
- Sequencing after v0.5 still HIS CALL (ho-11 first vs 10.2 first).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 is one ho-close + two small fixes
  away; v1.0 = ho-11 + ho-12.

---

## State summary — 2026-07-10, fifth block — THE HANDS SESSION, FOUR ROUNDS DEEP, REBOOT PENDING

**COMPLETED**
- **Four feedback rounds built live on his hands** (5d46527, 5508ebc,
  f35a833, e58cae2, 06707d7 — all CI-green; one runner flake rerun to
  green): the ZFS POP-OUT PANEL (first plugin panel, FavoritesPanel
  lineage, keys-panel stepped sizing ⌘1–5/⌘+/−), the two-column strip
  (plugins LEFT, solid cream-on-burnt-umber chips, Theme.plugin, green
  engagement line beside reads / umber line on the plugin edge), THE
  DATASET TREE in the panel (selection = target, ↑↓ walk, unmounted
  selectable and '· unmounted' in words, pre-select from pane path,
  right-click menu with all verbs + open-in-pane, ⇧⌘←/→ point a pane),
  panel persistence (Esc/✕ only). Create's verify reads name,mounted.
- **The Linux root wall fully mapped in anger**: delegated create lands
  unmounted; delegated destroy of a MOUNTED dataset fails (cannot
  unmount, permission denied). Works delegated: the whole snapshot loop,
  create(-unmounted), destroy-unmounted. THE PITCH LEAD: snapshot/
  rollback/destroy-snapshot over plain ssh, readable plan, native Mac —
  nobody else has it.
- **The two-cursor failure witnessed**: his destroy aimed at pool root
  (panel tree selection) while his pane cursor sat on stray-dataset — the
  panel-as-primary-mutation-surface is structurally confusing. His
  framing sealed: ZFS management is a SEPARATE activity → pane MODE with
  explicit boundary (background shift) is the right surface (ho-10.2/3).
- **Click-zone "bug" diagnosed ENVIRONMENTAL**: broken everywhere, on
  YESTERDAY'S binary too (bisect worktree, cleaned up) → his Mac: swap
  12.6/13GB, WindowServer 1.2GB after days of memory max. REBOOT is the
  fix; he's rebooting. Not pālana's code.

**NEXT**
- **Post-reboot, one pass**: restart fixture (`make zfs-fixture`), CLEAR
  STALE `.fixtures/zfs.env` first if suites dial a dead port, relaunch
  current build on fixture config, he clicks to confirm the heal.
- **Then two small 10.1 fixes**: verbs refuse the POOL ROOT dataset with
  a plain sentence (destroy/rename must not compose on it); panel
  pre-select follows the pane CURSOR when it sits on a dataset
  mountpoint (not just the directory). Then his close verdicts →
  close ho-10.1 → **tag v0.5, ZFS badged beta** → README/docs polish →
  he writes to Dave (ysap.sh, ZFS fiend, positioning review — counsel
  given: name the root wall in the README, lead with the snapshot loop).
- Sequencing HIS CALL, recommendation pending his word: v0.5 → ho-11
  terminal → ho-12/v1.0 → 10.2 (sudo mount capability + pane mode +
  settings trio) as first post-1.0 feature; alternative is 10.2 before
  ho-11.

**ACTION ITEMS / BLOCKS**
- BLOCKED only on his reboot + click confirmation.
- ho-10.2 SEALED scope grew: sudo -n mount capability + settings trio
  (sudoers helper, per-tool plugin toggles) + likely the pane mode
  (his ratified instinct; panel demotes to launcher/overview).
  Installable third-party plugins: post-v1 seed thinking, banked.
- ho-10 is CLOSED (read-only Workbench) — no gap before ho-11.
- Fixture VM dies with his reboot; stray-dataset mounted manually by him
  (root); t62-prx-* leftovers still in pool (fine — destroy targets).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 (ZFS tool, beta badge) is one close +
  two small fixes away; v1.0 = ho-11 + ho-12.

---

## State summary — 2026-07-10, fourth block — ho-10.1 BUILT, HIS HANDS NEXT

**COMPLETED**
- **ho-10.1 AT-02 + AT-03 authored, built, committed, CI green by exit
  code** (1e80c10, 0d34e28). The Workbench mutation seam is FILLED:
  `planRequest(for:on:input:)` carries the gather (`MutationInput`:
  target dataset, text, recursive; `GatherSpec` on the verb), and
  `ZFSMutationTool` speaks the eight mutations. The app path stands:
  zfs section in the strip → dataset from where the focused pane stands
  → gather through the naming machinery (rename prefills the full name,
  destroy is a field-less toggle row, clear-mountpoint composes with no
  gather) → plan renders → **Enter enacts, nothing else** (Decision 4
  held structurally — no auto-enact anywhere in the zfs path). Finished
  runs refresh panes on the host and re-discover its facts.
- Review catches banked: stale zfs gather state would have misrouted the
  next file rename into the zfs path (cleared at every non-zfs begin);
  the field-less gather leaked plain keys to the Table's native
  selection (swallowed; ⌘-chords pass, ho-9.7's law); extraction-dropped
  law comments restored. 735 tests, 120 suites.
- Reflect filled in the ho doc (execution truths + hands-pending list).

**NEXT**
- **HIS HANDS — the mutation feel, fixture only.** The app is RUNNING on
  the fixture config (`PALANA_SSH_CONFIG=.fixtures/zfs-ssh-config`) —
  his real hosts are deliberately invisible; the only host is
  `zfs-self` (the Lima VM, pool `palana`). Point a pane at
  `zfs-self:/palana/tank`, probe (`r` in the field), and the zfs chips
  light. Two stale test datasets (`palana/t62-prx-*`) remain in the
  pool — good destroy targets. Verdicts → fill the close entry → close
  ho-10.1 → ho-11 (terminal), ho-12 (ship, v1.0).
- To get his real config back afterward: quit the app, relaunch plain
  (`swift run Palana`); stop the VM (`scripts/zfs-fixture.sh stop`) and
  clear `.fixtures/zfs.env` if suites later dial a dead port.

**ACTION ITEMS / BLOCKS**
- **SEALED (his word, 2026-07-10, mid-hands): the mount capability —
  ho-10.2.** Delegated creates land unmounted on Linux (mounting is
  root's; `zfs allow mount` is a dead letter there — proven live on the
  fixture with `palana/stray-dataset`, `mounted: no`). The no-sudo law gains
  ONE narrow exception: `sudo -n zfs mount/unmount`, capability-probed
  per host, composed only where the host grants NOPASSWD, always a
  visible plan step. Never prompts (sudo -n; the ssh channel has no TTY
  and pālana handles no secrets). Where ungranted: truthful refusal +
  the exact root command. Settings grows a helper showing the narrow
  sudoers line to copy ("counsel people to do that, if they want this
  feature" — his words). Unlocks mount/unmount verbs; heals
  set-mountpoint's remount. Root-helper daemon REJECTED (standing root,
  no per-action gate). Also sealed for ho-10.2's settings work: per-tool
  toggles for built-in plugins ("lets do 1 for now… its low cost");
  INSTALLABLE third-party plugins banked as post-v1 seed-level thinking,
  not a ho.
- **SEALED same day: the ZFS pane mode — ho-10.3** (per-pane dataset
  view, not hardcoded left; verb-grammar Think required — what does d
  mean on a dataset; dataset-y-equals-send convergence with ho-06.2).
- No blocks. Fixture VM `palana-zfs` UP and app running against it —
  both deliberately left up for his hands session (departure from the
  VM-stopped default, on purpose).
- Feel questions queued in the Reflect: twelve-chip strip weight,
  gather prompt wording, recursive-toggle keyboard reach, the destroy
  double-Enter rhythm, snapshot-name picker (v-next if hands ask).
- Debts carried: binding-table snapshot test before any key rename;
  light text editor as future Workbench plugin idea.
- Deferred stack unchanged (drag-out, width persistence, /-jump,
  verb-time re-choice, gather-the-starred, modal-sheet onboarding,
  ssh-actually deep link).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. ho-10.1 built, close pending his hands;
  the road to v0.5. Then ho-11, ho-12 to v1.0.

---

## State summary — 2026-07-10, third block — THE HO-9 SERIES IS CLOSED

**COMPLETED**
- **Hos 9.5 through 9.11 CLOSED on his word** ("thats it. finially. can we
  fucking close ho 9 now?"). All Reflects filled with his verdicts, all
  docs `status: complete`, the kamae-4 build record carries the series
  close entry. Phase 3.5 is done.
- Late closers this block: save-is-save default flip ("i concur. save is
  save" — auto-send default, changed-remote always asks, new stored key so
  old settings land on the new default); the keys panel executed its
  continuous-scale system after two crashes and a desynced render — five
  fixed sizes on ⌘1–⌘5, ⌘+/− step, no edge-drag, one authority; the
  trapped-shadow border removed (chromeless card inside the panel).
- Laws banked this block: persisted state that crashes must never
  re-crash (clamp on restore); never rebuild a SwiftUI tree inside a
  resize delegate's layout pass; platform features needing app-bundle
  registration (pasteboard types, notifications) must be proven in the
  bare-binary dev build.

**NEXT**
- **ho-10.1 resumes**: AT-02 (ZFSMutationTool fills the Workbench mutation
  seam) and AT-03 (the app mutation path — planRequest → plan → render →
  Enter, dataset targeting from the focused pane, hands against the Lima
  fixture pool). Then ho-11 (the terminal), ho-12 (the ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks. App running his real config with everything through cf27f3d+.
- Debts, named: binding-table snapshot test before any future key rename;
  light text editor queued as a future Workbench plugin idea (his).
- Deferred stack: drag-out to Finder, width persistence, /-jump,
  verb-time re-choice, gather-the-starred control, modal-sheet onboarding,
  ssh-actually deep link (guide not shipped).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. Phase 3.5 (the ho-9 series) COMPLETE.
  ho-10.1 (ZFS tool) is the road to v0.5; then ho-11, ho-12 to v1.0.

---

## State summary — 2026-07-10, second block (the hands session + the grammar)

**COMPLETED**
- **He drove the whole BIG PUSH live — nine fix/build rounds answered in
  session.** Columns sort (review-missed comparators fixed, ★ sorts via a
  routing token), drag-and-drop WORKS (third attempt: a bundle-less binary
  can't declare pasteboard types — payload moved to public.json; his word:
  "its working"), per-pane history (⌘←/⌘→ + chevrons, PaneHistory in core),
  one-Enter rename/create, loud prompts (accent naming field, the shouted
  send-back callout), the auto-send toggle (conflict always asks), the verb
  chips as a permanent rail (dimmed while a plan runs).
- **The language sweep** — six message-grammar rules installed at
  Collision.swift's header and applied across core + app + tests: plans
  speak future, runs speak past with proof, refusals name thing and reason,
  unknowns named, no jargon (enact/gather/compose are dead words),
  classification/transport render plain, raw values frozen. His wording
  verbatim in the collision note.
- **ho-9.11 THE GRAMMAR — proposed, ratified, executed in one day.**
  grammar-proposal.md (119-binding audit → five rules) → his marks → one
  atomic commit: d deletes, r renames, R/T unbound, 8 stars the entry,
  ⌘8 the directory, ⇧⌘8 dead, ? card teaches the rules, README keybindings
  table. 696 tests, 114 suites, CI green through the day.

**NEXT**
- His remaining feel verdicts: the round-trip loop end-to-end in his
  editor, the columns picker, the r/d retrain, the wash weight. Then close
  entries for 9.6–9.11 (and 9.5, still pending from before the push) →
  ho-10.1 resumes (AT-02 tool, AT-03 surface) → ho-11 → ho-12.

**ACTION ITEMS / BLOCKS**
- No blocks. App running his real config with the full day's work.
- Noted in 9.11's Reflect: no test pins the binding table — a snapshot
  test is cheap insurance before the next rename.
- Deferred stack unchanged (drag-out, width persistence, /-jump,
  verb-time re-choice, gather-the-starred).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; the ho-9 remainder + grammar executed toward
  the ho-9 close; ho-10.1 next toward v0.5.

---

## State summary — 2026-07-10 (the BIG PUSH — ho-9 remainder)

**COMPLETED**
- **The ho-9 remainder EXECUTED — hos 9.6 through 9.10 authored (Kamae 5,
  Think phases sealed) and built in one autonomous push.** Every AT on
  claude-sonnet-4-6, reviewed at the top from the diff, verification rhythm
  green at every commit, CI green through the run (`gh run` checked, one
  timing flake de-flaked). 682 tests, 113 suites.
  - **ho-9.9 Collision Facts** — the overwrite-safety teeth. `Collision` /
    `CollisionReport` in core, gathered fresh per plan through the panes'
    listing, alarm line under the size line (replaces · merges into · kind
    clash; "destination unread" when the gather fails; silence only when
    gathered-and-clean). Review catch: report keys on the destination, not
    the classification — the mv-move overwrite would have stayed unnamed.
  - **ho-9.10 Remote Round-Trip Editing** — the stranded-edit gap closed.
    Remote opens register a watch (dual DispatchSource — dir fd survives
    atomic-replace saves, file fd catches in-place; fd-capture cancel
    handlers, review catch); a debounced save summons the panel with the
    upload plan + collision line + changed-since-fetch note; busy panel
    never evicted; Esc declines, watch survives; baseline refreshes after a
    send. No panel pop at registration (Decision 5 held in review).
  - **ho-9.6 Drag-and-Drop** — DraggedSelection/DropDecision in core; rows
    drag the selection (Table → rows-builder form, behavior held); drop
    composes copy / option-move through the standing gather; Finder URLs
    resolve via local listing; self-drops refuse; accent wash on valid
    hover. Review catches: stale-drop refusal, O(n²) payload → once-per-render.
  - **ho-9.8 Columns** — FileEntry.created/.changed at sealed fidelity (BSD
    both via stat %B/%c, GNU changed via find %C@, BusyBox neither); GNU+BSD
    corpora re-recorded LIVE, recorder first; six new columns behind the
    platform header right-click; visibility persists to columns.json
    (TableColumnCustomization is NOT Codable — widths per-process, the named
    escape hatch); ★ column = display + toggle (the header cannot emit a
    starred comparator — KeyPathComparator<FileEntry> vs the one-registry
    law; dead sort branch cut in review).
  - **ho-9.7 Design Polish** — consolidation: early-landed fragments named
    in the doc; go-again keys as KeyCapChips (transient, hint line only);
    terminal popout glyph on each pane footer (backtick's exact path);
    pruning audit found the palette CLEAN (taste-call ledger in the doc);
    cmd-swallow debt closed by verified reading (no surface swallows
    ⌘-chords). NSMenu refit dissolved: NO menu carries sequence hints —
    finding recorded, no diff shipped.
- **ho-10.1 AT-01 reviewed + committed** (was left uncommitted by the prior
  session): the ZFS mutation engine, round trip proven LIVE on the Lima pool
  (create → snapshot → rollback → mountpoint set/clear → destroy). Fixture
  delegation grew rename,rollback. VM left stopped.
- Reflects filled in all five ho docs (execution truths + hands-pending
  lists); kamae-4 build record carries the batch entry; per-ho close entries
  wait on his verdicts, per precedent.

**NEXT**
- **ONE hands session over the five** — the overwrite line on a real
  collision, the round-trip loop in his editor (edit remote → save → panel →
  Enter), the drag between panes + from Finder, the header right-click
  columns + ★, the chips and the pane-footer popout (if the 24pt strip reads
  heavy, the glyph can move to the header). Verdicts → fill close entries →
  close 9.6–9.10. ho-9.5 close also still pending his onboarding verdicts.
- Then **ho-10.1 resumes**: AT-02 (`ZFSMutationTool` fills the Workbench
  seam) + AT-03 (app mutation path, hands against the fixture pool). Then
  ho-11 (terminal), ho-12 (ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks. App rebuilt and relaunched on his REAL config with the full
  push (reads only).
- Deferred, named in the docs: pane→Finder drag-out (file promises), width
  persistence across relaunch (own capture if missed), type-to-jump (`/`
  filter-jump direction sealed in ho-9.8, its own slot), verb-time re-choice
  in the panel after a drop, a gather-the-starred control if his hands ask.
- Carried: the README Kamae-3 refresh ("doesn't do it justice"); the
  modal-sheet onboarding variant offer (9.5).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. The ho-9 remainder executed toward the ho-9
  close; ho-10.1 in progress toward v0.5; then ho-11, ho-12 to v1.0.

---

## State summary — 2026-07-10

**COMPLETED**
- Post-beta surface polish (Opus + sonnet, all CI-green): a visible close on
  every summonable surface — an upper-left ✕ that reddens on hover like the
  system close, turned into a proper title-bar row (✕ + surface name: the field,
  the keys, settings, favorites, the host map), esc still closes everything;
  title-to-content spacing tightened to ~8pt on the cards. `OverlayCloseButton`
  and `OverlayHeader` are the shared components.
- **ho-10.1 OPENED** — the ZFS tool, Think phase authored (Opus). The mutation
  seam ho-10 named is the target: dataset create/destroy/rename, snapshot
  create/destroy/rollback, mountpoint set/clear, each composing a `zfs` command
  the operator reads in the plan panel before Enter enacts. Six Think decisions:
  a `ZFSMutation` payload on `PlanRequest` (op `.zfs`), one `Classification`
  `.zfsMutation`, transport `.local`, delegated no-sudo composes verified by
  reading state, destroy/rollback safe because the plan is read before Enter,
  verb targets the dataset the pane stands in, fixture-only (never a real pool).
  Three ATs named; AT-01 (core engine) authored and **building on sonnet now**.

**NEXT**
- Finish **ho-10.1**: review AT-01 (core ZFS mutation engine + fixture round
  trip), then author+build AT-02 (`ZFSMutationTool` fills the seam) and AT-03
  (app mutation path: planRequest → PlanEngine.plan → render → Enter, the
  parameter-gather, dataset targeting from the focused pane) — AT-03 is a hands
  session (the mutation feel, against the fixture pool). Then ho-11 (terminal),
  ho-12 (formalize the ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks. AT-01 must prove the create→snapshot→rollback→mountpoint→destroy
  round trip on the Lima fixture pool (`make zfs-fixture`), never a real pool.
- Deferred (named in the ho): pool create/destroy (viz only), `zfs clone`,
  non-mountpoint properties, `zpool status` drives-fact.
- Carried from the ho-9.x run: star column in the column picker → a future
  columns ho; the modal-sheet onboarding variant offered if the inline form
  still reads cramped.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. ho-10.1 (ZFS Workbench tool) in progress toward
  v0.5; then terminal (ho-11) and the formal ship (ho-12) before v1.0.

---

## State summary — 2026-07-09

**COMPLETED**
- Shipped **v0.4-beta** — the first public build — as a signed, notarized macOS
  `.dmg` on GitHub Releases (prerelease). App + dmg both notarized and stapled;
  Gatekeeper-accepted (`source=Notarized Developer ID`, team `<team-id>`).
- Built the macOS release pipeline, effectively ho-12's ship machinery, ahead of
  its ho: `scripts/build_macos.sh` (universal `arm64+x86_64` build → hand-
  assembled `.app`, `Package.swift` stays canonical, no Xcode project → sign →
  notarize app then dmg → staple both), `scripts/entitlements.plist` (hardened
  runtime, empty by design — pure Swift, no dynamic code), and `RELEASING.md`.
- App icon in place (`packaging/palana.png`, built to `.icns` at build time;
  generated `.icns` gitignored). Bundle id `com.sageframe.palana`, min-macOS 14.
- README brought to v0.4-beta: beta download callout + feedback ask up top,
  Download section points at the release, license confirmed GPL-3.0. Reconciled
  the interactive terminal to a **v1.0** feature (Kamae-4 Phase 5), removing the
  stale "post-v1" entry.
- Repo made public-facing: description + homepage set; already public, GPL-3.0.

**NEXT**
- **ho-10.1 — the mutating ZFS Workbench tool** (dataset management, snapshots,
  pools), Phase 4, core unmodified. Then ho-11 (terminal), ho-12 (formalize the
  ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks.
- Non-blocking: the beta icon source was 1024×**1059** (not square); padded to a
  transparent square to avoid squish/clip. For v1.0, re-export a true 1024²
  square and rebuild (one command).
- Non-blocking: the ship pipeline now exists ahead of ho-12; when ho-12 opens it
  formalizes what's already built rather than starting cold.
- Notarization uses keychain profile `private-notary-profile`; signing identity
  `Developer ID Application: <release-identity>`. See `RELEASING.md`.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. (Was `dev` through Phases 1–3 + the ho-9.x surface
  run.) Engine + Surface complete; ZFS Workbench tool and terminal remain before
  v1.0 / `production`.

---

## Build record (release tags)

| Tag | What it marks |
|---|---|
| v0.1 | Phase 1 — foundation verified, go/no-go answered *go* |
| v0.2 | Phase 2 — PalanaCore headless engine complete (173 tests, 97.69% cov) |
| v0.3 | Phase 3 — the Surface: panes, plan → enact, field view |
| v0.4 | Surface UX run complete — favorites, host onboarding, settings, mounts |
| **v0.4-beta** | First public build — signed, notarized `.dmg` on Releases |
| **v0.5** | Phase 4 (Workbench — ZFS tool, pane mode, mount seam) + Phase 5 (interactive terminal) complete — the mutating ZFS story hands-hardened; integration branch merged to main (`8004eb2`), 781 tests |
| **v0.6** | Phase 6 — the v1 polish: universal text-scale, dark mode, drag-into-folders, preview pane; hands-hardened (one master ⌘+/−, the ? popout, Finder-into-folders, remote text preview, floating-panel appearance + desktop, host-map zoom). Merged to main (`7fc13fd`), 844 tests, PalanaCore 96.71% line |
