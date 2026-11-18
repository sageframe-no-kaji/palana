---
created: 2026-11-16
type: review
status: reopened; remote file drag toward Chrome reproduced CALayerInvalidGeometry
parent: agent-tasks/agent-task-2026-11-16-drag-freeze-frontier.md
project: palana
---

# Native table source with an AppKit destination

The missing comparison was the destination alone. Keep `drag-out-native`'s
native table drag and eager row writers; replace the pane and folder-cell
SwiftUI `.onDrop` destinations with one AppKit receiver per pane. This
combination passed the required thirty recorded-event replays on the host
where the SwiftUI-destination control reproduced both failure signatures.
The practitioner subsequently passed the physical freeze checks; see the
verdict below. Finder-style selection and a remote Chrome uploader check are
the remaining follow-up.

## Recurrence at 15:57, later 2026-11-16

The practitioner confirmed selection works, then froze `b5bda1f` while dragging
`storage-host:/pool-a/software/linkage2.msi` from the right pane toward Chrome.
The source writer is a remote file promise (3,760,128 bytes). Unified logs show
its writer at 15:57:10.841, drag-server connection at .894, geometry exception
cancellation at .937, and HIServices fault at .975. The live sample shows the
suspended swallowed-exception marker. Evidence is under
`.fixtures/drag-freeze-20261116/storage-host-recurrence/` in the implementation worktree.
The precise geometry caller remains unknown for this incident. The earlier
controlled destination comparison stands, but its fix is insufficient for
remote drag-out. No live host was touched and the app was not stopped.

## Practitioner verdict, later 2026-11-16

The practitioner reported checklist items 1–7 passing: ten physical trackpad
folder drags; small accidental drags; correct hover feedback; the existing
selection behavior; one multi-file pane plan; local files to Finder/Chrome
and a folder to Finder; and Finder drops into panes/folders. Item 4 was then
revised: Shift selects a continuous range, Command toggles arbitrary rows, and
an unmodified click clears the other selections. The old shift-to-unmark rule
is superseded. That follow-up adopts AppKit's selection directly in `b5bda1f`. Its separate
build is `../palana-drag-native/dist/Palana-Finder-Selection.app`, executable
SHA-256 `54e2e4a445e40faf77ac9f199e9aa9fc016f229f24c6a636486a56d8f813e4e3`.
The 44 targeted selection/drop/provider tests pass, as do strict lint, the
release build, and commit hooks. Physical selection confirmation is pending;
the original hands-approved app was retained unchanged.

The practitioner clarified that the remote question means individual remote
files dropped into a Chrome uploader, not recursive remote-folder export.
The implementation exists, but this specific receiver check is still open;
do not infer a remote Chrome pass from the initial enthusiastic item-8 reply.
The earlier automated mouse-control findings below remain historical evidence.

## Remote selection regression on the restriction build

Practitioner reported broken dragging/clicking on `ab6a156`, then narrowed it
explicitly to remote rows not selecting. PID 15891 was the expected
`Palana-Local-Drag-Only-ab6a156.app`. Its log/sample at roughly 16:27 showed no
drag geometry exception and no swallowed-exception marker; the main loop was
idle. Read-only accessibility inspection timed out; the following sample was
servicing accessibility queries, not blocked in a drag session.

The restriction had introduced conditional row structure: local rows carried
`.itemProvider`, remote rows did not. Restoring the previous unconditional row
structure is the bounded rollback under test. The provider itself still returns
nil for remote rows, and the native writer gate still prevents fallback, so
remote drag remains disabled. The precise click-regression cause is not yet
established. Minimal offscreen conditional-row tests passed programmatic
selection; an attempted mouseDown test exited without a completed test verdict,
so it supplies no mouse acceptance evidence. That experiment is archived under
`storage-host-recurrence/local-only-failure/TableRowStructureTests.swift`, outside source.

The restored structure passes 18 targeted gate, selection and drop checks.
Screen availability was requested for a one-minute isolated fixture check;
no pointer/keyboard control has resumed in this follow-up.

## Candidate failed; practitioner suspended remote dragging

The practitioner reported an immediate freeze, a successful remote-to-left-pane
drag, a Chrome attempt that did not freeze but delivered nothing, then another
freeze. Logs confirm the source-start guard executed before geometry exceptions
at 16:13:19.937 and 16:13:21.746 (PID 4698, `GearGenerator3.zip`) and
16:14:24.624 (PID 4926, `Mp3tag Installer.exe`). PID 4926 logged accepted
pane drops at 16:13:34.712 and 16:13:51.118. The candidate is rejected.
Evidence: `storage-host-recurrence/candidate-failure/events.log` under the fixture root.
Its source/test files were archived there and removed from the implementation.

The practitioner asked to put remote dragging on hold for release. The new
restriction removes the item-provider modifier from remote rows and refuses
both the custom and fallback pasteboard writers while the pane is remote or
unpointed. The native gate reads the model at drag request time, including
local-to-remote host switches. Remote pane-to-pane drags are disabled too;
keyboard/menu operations and incoming drops are unchanged. Remote footers show
`remote drag paused · y copy · m move`; README and CHANGELOG reflect the hold.

Three new tests exercise the actual Objective-C writer hook: no custom/fallback
writer for remote and unpointed hosts, local→remote→local reuse, and preserved
local fallback/unrelated-table behavior. Full suite: 250 app + 1194 core Swift
Testing and 81 XCTest, all pass. ZFS fixture and opt-in capture checks skipped.
Strict formatting/lint passed. The source restriction still needs a physical
check that remote dragging does nothing and local dragging remains usable.
It does not establish that every possible native drag freeze is eliminated.
No screen control was resumed and no live host was mutated.

## Source-start candidate after the remote recurrence

The source callback in the earlier exception trace sets `draggingFormation`
to `.default` while NSTableView's initial flocking animation is active. The
new recurrence does not establish that this call caused it; it makes this
remaining startup mutation the next bounded experiment. Apple's documentation
recommends never changing formation at drag start:
https://developer.apple.com/documentation/appkit/nsdraggingsession/draggingformation

Uncommitted candidate on `b5bda1f`: `TableDragStartup.swift` guards the
formation setter only for the particular session during a hooked pane table's
source willBegin callback. It calls the original source callback once, retains
its other bookkeeping, restores an outer guard after nested callbacks, and
forwards changes outside that callback. No new source session is constructed;
file promises and the destination receiver are unchanged. This is an
experimental workaround, not a verified repair.

Three new tests exercise actual Objective-C method dispatch through a fake
source and recording session: same-session suppression with other-session
forwarding, unhooked tables sharing the source class plus repeated installation,
and nested callback restoration. The artificial sessions log CoreDragDispose
-1850 on deallocation because they have no system drag; no pointer or real
system drag is created by these tests. The full suite passed: 250 application
Swift Testing, 1194 core Swift Testing, and 81 XCTest checks. ZFS fixture and
opt-in capture checks were skipped. Strict swift-format and SwiftLint pass.
No physical or replay acceptance is claimed for this candidate.

## Branch and artifact

- Commit `c3e6f38` on branch `drag-freeze-fix`, forked from `drag-out-native` at `ece6d46`, in the
  existing `../palana-drag-native` worktree. The original branch remains at
  `ece6d46`; neither branch was merged or pushed.
- App: `../palana-drag-native/dist/Palana.app`, native arm64, ad-hoc signed.
- Executable SHA-256:
  `12996eae6efa88279c5c2e896e98d00c2b1953653e3608c832292388b3bb3e1e`.
- Host: macOS 27.0.1 (26A434), Xcode 27.1 (27A9275).
- Evidence root: `../palana-drag-native/.fixtures/drag-freeze-20261116/`.
  `Baseline.app` preserves the incoming release build; `Matrix.app` preserves
  the experiment build. Temporary instrumentation sources, extracted recording,
  replay batch runner, logs, and test output are retained there, outside Git.

## Controlled comparison

The original `hands-1044.jsonl`, t=135.6–137.9, contains 398 events spanning
1.29 seconds from the first selected event to the last. `3ping.jsonl` extracts
those lines unchanged to avoid parsing the entire recording on every replay.
The existing replay executable restamps timestamps and clears the stale window
IDs. There was no event scaling, offset, or timing change. Both panes point to
the existing Arduino mirror; the drag starts on right `3ping` and drops on left
`DrawingGlove`. The test profile uses an empty SSH config.

| Build / destination | Attempts | Observed outcome |
| --- | ---: | --- |
| Incoming baseline `ece6d46`, SwiftUI | 1 | Invalid-drag-reference loop and retained drop caption. An automated coordinate click still selected a row afterwards; this establishes the failed drag/stale tracking, not complete mouse unresponsiveness. |
| Instrumented native source, AppKit destination | 6 initial + 1 traced | Normal source endings, no recorded failure signature; traced target received `DrawingGlove`. |
| Same instrumented build, AppKit destination (`appkit-batch-a`) | 10 | Ten begins, ten target drops, ten normal ends, zero invalid-reference messages or drag exceptions. |
| Same instrumented build, SwiftUI destination (`swiftui-control-a`) | 3 | Three begins, only two end callbacks; two `CALayerInvalidGeometry` cancellations, 525 invalid-reference messages. The two end callbacks report operation 0 while a mouse button is still pressed. |
| Clean final build (`final-a`, `final-b`, `final-c`) | 30 | Thirty row-writer invocations and thirty accepted folder drops; zero invalid-reference messages and zero drag exceptions. Correct one-entry copy plan visible afterwards. |

In the control, seq 569 begins at 12:12:27.675 and the NaN cancellation is logged
at 12:12:27.751; seq 570 begins at 12:12:29.583 and cancels at 12:12:29.625.
Source/destination trace hooks were removed from the final app. The final app
logs accepted native drops under `net.sageframe.palana:dragdrop`, without paths.

The experiment used `PALANA_DROP_MODE=appkit` or no override in the same
instrumented binary. A `PALANA_DRAG_NONE` experiment switch was prepared but
**never used**: the successful comparison retained the table's original
formation and cancellation animation. Both switches and their source hooks
were removed before the thirty-run acceptance batch.

This isolates an avoidable trigger at the SwiftUI destination boundary. It
does not establish the internal mathematical cause in HIToolbox, and it does
not rehabilitate the abandoned custom-source branch.

## Implementation

`PaneDropTarget` registers for the existing `public.json` selection payload and
file URLs. Hover inspects types and the table row under the pointer; it does
not enumerate drag items, change their frames or formation, or load payload
bytes. Release resolves the payload and calls one of the existing four plan
routes: internal selection or Finder URLs, onto the pane or a folder. A valid
internal payload returns before requesting any outbound file representation.

The view passes ordinary clicks through. Folder hit testing uses the existing
`TableRef` and checks that its table belongs to the receiver's window. The old
SwiftUI drop wrappers and their now-unused provider-resolution handlers are
removed. The native source, row writers, selection logic, plan engine,
transports, and move safety are unchanged.

## Verification

- Native release build succeeded: `ARCH_FLAGS='' ./scripts/build_macos.sh`.
- `swift test --enable-code-coverage` exited 0: 247 application Swift Testing
  tests, 1194 core Swift Testing tests, and 81 XCTest tests reported passing.
  The disposable localhost SSH fixture was running; its integration suite
  passed this run. The previously reported SSH timing flake was not diagnosed
  or repaired by this task.
- ZFS integration tests were skipped because the ZFS fixture was unavailable;
  opt-in corpus recording tests were also skipped.
- Core line coverage 97.74%, application logic 60.25%; floors 90% and 35% pass.
- Strict swift-format, strict SwiftLint, `git diff --check`, and the public
  process boundary check pass.
- New tests exercise real named pasteboards, selection priority, malformed JSON
  fallback, multiple Finder URLs, no outbound representation request for an
  internal drop, and directory-row targeting. A drag-info spy verifies hover
  never changes drag geometry or loads bytes; release dispatches exactly once.
- GUI on the final build: a remote folder from the disposable `fixture` SSH
  container composes a local-destination plan; a remote file dropped on local
  `sketch` composes a plan for that exact folder. Neither plan was executed.
- A keyboard-marked three-file cohort invoked all three row writers, but the
  short synthetic mouse drag did not deliver a drop. This is **not** recorded
  as a passed multi-file receiver test. Injected shift-click also did not
  establish mark/unmark behavior. The earlier physical confirmations on
  `drag-out-native` remain the evidence for those unchanged source features.

## Remaining hands check

The practitioner asked to use the computer, so all pointer/keyboard automation
stopped. No recorder or replay remains running. The final app is left open on
an isolated regression profile (only the localhost SSH fixture and local test
files); the ordinary profile was not modified.

When the practitioner is ready:

1. Point both panes at `/path/to/example-folder` and do ten physical trackpad folder
   drags between panes, including folder targets and refused same-place drops.
2. Confirm marked files to Finder and Chrome, a folder to Finder, shift mark
   and unmark, and one pane-to-pane plan for a marked cohort.
3. Remote drag-out to an outside receiver remains unverified by this session;
   the remote provider/download unit tests pass, and internal remote drops
   were exercised against the disposable fixture.

The Apple report draft now includes the silent-cancellation signature,
distinguishes recorded gestures from plain synthetic mouse events, states that
three-finger dragging was not used, retracts the failed custom-source workaround,
and identifies its small sample's hardware reproduction as unconfirmed. It was
not filed. No live infrastructure host was accessed.

## Authorized fixture check, 2026-11-17

On the restored-row build, CUA clicks selected remote a.txt, Command-click added
b.txt, and Shift-click selected the three-row range. After an attempted remote
drag toward the left pane, clicking still selected b.txt. No remote writer or
drop plan was observed. Local clicking selected readme.md. The subsequent local
drag toward sketch left the generic drop wash visible and no plan; Escape and
a click on photo.png did not change selection. This local check failed.

The log records a local writer at 06:41:16.997, with no captured geometry
exception or stale-drag-reference signature. It also records NSTableViewException
at 06:40:36.113, earlier in startup, reason redacted. That reason remains open.
The evidence does not establish the exact cause of the failed local drag.
SelectionCheck.app (PID 76146) was closed and the screen returned. No live-host
operation, merge, push or release occurred. Do not treat this as release
acceptance. Broader disabling of outgoing row drags requires a product ruling.
