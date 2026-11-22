# Intermittent row-drag freeze — issue #4

Updated: 2026-11-17. Status: open, root cause unproven.

Tracking issue: [#4](https://github.com/sageframe-no-kaji/palana/issues/4).
Separate limitation: [Command-drag moves into Finder, #6](https://github.com/sageframe-no-kaji/palana/issues/6).

## Symptoms and recovery

A row drag can stop almost immediately and leave the window ignoring clicks, even while the process is alive and its main thread is in the normal event loop. Quit and reopen pālana to recover. To transfer files without dragging, select the entries and press `y` for a copy plan or `m` for a move plan.

The maintainer accepted this defect when merging the release candidate into `main`. The application examined here is from `ff203c7`, which changed installer signing after the drag changes in `ee3c137` and merge `daf537f`. The merge did not produce a new signed build or release tag.

| Operation | Current behavior |
| --- | --- |
| Shift-click | Selects a continuous range |
| Command-click | Adds/removes individual rows, including noncontiguous rows |
| Plain click | Selects that row, clearing the other selections |
| Drag a selected row | Retains the selected group |
| Local files/groups/folders into Finder | Copy supported; Command-move deferred in #6 |
| Local files/groups into a browser | Supported; receiving website controls upload behavior |
| Remote files/folders between Palana panes | Enabled; carries an internal selection descriptor |
| Remote files/folders into Finder, Chrome or another app | Disabled; no external file URL or file promise advertised |
| Finder files dropped into Palana | Retained |

Remote rows still start a native drag for transfers between panes. The signed candidate froze on that path even after external delivery was disabled. The same build could fail on the first replay and then complete a batch without reproducing the freeze.

## Observed environment

The maintainer observed the freeze with a physical trackpad on macOS 27.0.1 (`26A434`) with Xcode 27.1 (`27A9275`). The gesture was a pressed click with one finger and movement with another. Plain generated
mouse events often failed to reproduce the problem; recorded trackpad events
include additional gesture information. A macOS 27.2 VM did not reproduce it
in the recorded testing and therefore was not an effective freeze control.

## Failure signatures

### 1. Invalid drag-animation geometry

AppKit logs cancellation after catching an exception:

```text
*** Canceling drag because exception was raised during a dragging session.
Exception: CALayerInvalidGeometry
CALayer position contains NaN: [nan nan]
QuartzCore  -[CALayer setPosition:]
HIToolbox   UpdateLayerPositions(OpaqueCoreDrag*)
HIToolbox   UnflockAnimationTimerCallback
AppKit     NSCoreDragTrackingProc
AppKit     -[NSCoreDragManager _tryCatchDragUntilMouseUp:location:modifiers:]
```

The detailed stack is from earlier debugger captures. The latest signed-build
incident recorded the same exception name but its reason was privacy-redacted;
do not claim a fresh full stack for that incident. A subsequent process sample
contained `SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION` in HIServices.

Earlier breakpoints showed the table starting its row-image animation, then
SwiftUI source/destination callbacks changing drag formation and item frames.
All observed incoming frames were finite; the invalid value appeared inside
the animation. This identifies the failure site and an implicated interaction,
not the ultimate cause or proof that only Apple code is responsible.

### 2. Early drag termination and stale tracking

Some attempts ended roughly 40–70 ms after the drag-server connections opened,
without the geometry exception. Destination updates could continue for the
ended drag, logging `Drag reference does not have any info` repeatedly. The
window could then stop responding while its main thread was idle.

A source-end callback with operation zero is not sufficient by itself to prove
this bug: ordinary cancelled drags also have no resulting operation. Correlate
the callback with input state, stale-reference errors and interaction afterward.
The two signatures may be related, but a common cause has not been established.

## Confirmed signed-candidate recurrence

On 2026-11-17 the maintainer reported that the first drag from a remote pane
locked up the delivered signed candidate. The intended destination was not
confirmed in that report; do not label it specifically a Finder, Chrome or
other-pane failure. Earlier remote-to-Chrome failures were separately confirmed.

| Event | Local time, EST |
| --- | --- |
| Process 17048 launched | 13:51:34.149 |
| Drag-server connections opened | 13:51:48.731 |
| Drag cancelled with `CALayerInvalidGeometry` | 13:51:48.773 |
| HIServices fault | 13:51:48.809 |
| Frozen process sampled | 13:54:09.125 |

The sampled ARM64 binary UUID was `C8A2B805-1469-381D-922D-E4BD42A894FC`.
It matches the delivered signed candidate and differs from the saved ad-hoc
candidate's `95B98F84-3F3B-3106-97C6-A0C862DD79F6`. The process path was also
checked at capture time. This incident was not explained by accidentally
running an older candidate.

The signed DMG's SHA-256 is
`c9b39f067ed5bb826936f27acb6c772fbb40967ae8bcb23121e3b928f7763412`.
Signing, notarization, Gatekeeper and image-integrity checks passed. Those
checks establish packaging properties, not drag reliability.

## Attempts and what they established

| Change or experiment | Result and limitation |
| --- | --- |
| Original 0.8 behavior | Intermittent geometry freeze already reported; not introduced solely by the new drag-out work |
| `489dc8b`: replace SwiftUI table drag entry points with an owned session, including its private gesture entry point | Physical trackpad still froze with invalid geometry |
| `7de01b3`: route the gesture path through the public event-based session entry point | Initial physical passes; later remote-to-Chrome recurrence |
| `eb5e439`, `e1a7613`, `2be783e`: custom source plus AppKit destination variants | Early termination persisted; one variant froze every tested trackpad drag. This branch is abandoned |
| `002fcf7` / `ece6d46`: retain the table's native drag; substitute eager pasteboard writers | Local groups reached Finder/Chrome and folders reached Finder; intermittent pane-drag freeze remained |
| `c3e6f38`: replace SwiftUI pane/folder drop targets with an AppKit receiver | Controlled comparison and subsequent local checks improved; later remote failures mean it was not a complete fix |
| `b5bda1f`: native Finder-style selection | Selection passed; remote file toward Chrome later froze |
| Temporary source-formation setter suppression | The guard executed before further exceptions. Failed candidate withdrawn; not in current source |
| `ab6a156`: disable remote row dragging entirely | Blocked required remote pane transfers. Conditional row structure also coincided with remote click failures; superseded |
| Restore unconditional row structure | Recovered the selection path. A separate automated local drag check still failed without a confirmed geometry signature; it did not establish the user's later report was a local regression |
| `ee3c137`: restore remote pane transfers using an internal-only writer | Passed the maintainer's checklist; external remote delivery remained disabled. Signed candidate later froze |
| Temporary Command-move-to-Finder experiment | Changed the native source operation mask and passed offscreen checks, but failed real Finder testing. Changes and misleading hint removed; deferred in #6 |
| `ff203c7`: sign DMG container before notarization | Fixes container acceptance only; no application source changes |
| Plain native-table diagnostic, prepared 2026-11-17 | Compiles and passes offscreen payload checks. No physical drag test; not merged or a demonstrated fix |

Do not retry the abandoned custom-source implementation under a new name.
It still modified a SwiftUI-owned table. The new standalone diagnostic instead
uses its own plain `NSTableView`, data source and delegate, without SwiftUI or
runtime method replacement. That distinction is an experimental variable,
not evidence that the new diagnostic solves the defect.

## Controlled destination comparison and later replay checks

An earlier instrumented binary switched only the destination implementation:

| Destination | Attempts | Observations |
| --- | --- | --- |
| AppKit receiver | 10 | Ten starts, drops and normal ends; no recorded failure signature |
| SwiftUI destination control | 3 | Three starts, only two end callbacks, two geometry cancellations and 525 stale-reference messages |
| Clean AppKit-receiver candidate | 30 | Thirty accepted folder drops, no recorded failure signature |

This supported removing that SwiftUI destination interaction. Subsequent
physical remote failures supersede any broad claim that thirty replays proved
the entire bug fixed.

On 2026-11-17 the saved candidate and signed release were compared using the
same recorded trackpad gesture and isolated localhost-SSH fixture:

| Build | Replay attempts | Recorded starts / accepted drops | Failure signatures |
| --- | --- | --- | --- |
| Saved ad-hoc candidate | 20 | 20 / 20 | None captured |
| Exact signed release | 20 | 19 / 19 | None captured |

Both selected a different row afterward. One signed replay did not initiate
a recorded drag and is not counted as a successful drag. These checks created
transfer plans only; no transfer was executed. They did not reproduce the
maintainer's signed-build failure or distinguish a signing-related cause.

Source comparison found no application-source difference between the saved
candidate and release. ARM64 section comparison found only five instruction
bytes differing, across three source-file-location arguments outside the drag
handlers; each immediate differed by the checkout-path length difference.
`Info.plist` matched. Copies with signing methods swapped were prepared but
not replayed because the original pair did not separate in that batch.

An offscreen inspection of the actual two-pane view hierarchy found only the
two intended AppKit drop receivers registered. The underlying SwiftUI tables
had no registered drop types. It did not reveal an extra SwiftUI receiver, but
does not rule out other source-side SwiftUI behavior.

## What is known, and what is not

- The captured failure occurs during drag startup; completion of a remote
  transfer is not required. Replacing SCP/SSH is not an evidence-based fix.
- The current remote writer has neither an external URL nor a file promise.
  Those representations are therefore not required for the latest recurrence.
- The animation's invalid geometry is known; the condition producing it is not.
- Selection, source callback timing, destination updates, geometry and system
  gesture behavior remain possible contributors. None is established as the
  remaining root cause. Signing has not been shown responsible or ruled out.
- Replacing the entire table is an untested proposal, not an approved completed
  production rewrite. A new capture mechanism was discussed but not implemented.
- The remote delivery helper code remains available, but disabling it is part
  of current product behavior. A startup fix would not automatically verify
  remote-to-Finder or remote-to-browser delivery.
- The drop-inspector HTML reports received files and sizes, not a network
  upload. It does not recursively enumerate folder contents. Do not turn its
  screenshot into a claim that all browser folder uploads work.
- An Apple feedback draft exists. No filing or Feedback ID has been confirmed.
  Earlier claims that it was filed, or required three-finger drag, were wrong.

## Reproduction and evidence capture on resumption

Use disposable local and localhost-SSH fixtures. Do not replay against live
hosts or execute transfer plans as part of a drag-start experiment. Preserve
the current binaries before building; the packaging script deletes `dist/`.
Coordinate screen use and announce short batches, then explicitly hand back
the screen. Mouse-event replay can operate unrelated windows if misplaced.

1. Record exact commit, executable path, architecture, UUID, hash, signing mode,
   OS build, fixture profile, source row, selection and intended destination.
2. Check the window position and row locations before replay. The recording
   contains 398 events over about 1.29 seconds, including gesture events.
   Restamp event times and clear recorded window IDs. Translation is allowed
   only after verifying the current geometry; do not assume saved offsets fit.
3. Log source writer, session begin/end, accepted drop, exception cancellation
   and stale-reference events. Count actual starts separately from attempts.
4. After each bounded batch, click another row and verify selection changed.
   A process that is alive is not evidence that its window remains usable.
5. If it freezes, capture logs and a process sample before restarting. Avoid
   recording credentials, private file contents or keyboard input.
6. Compare a reproducing control and one changed variable under the same input.
   If neither reproduces, report an inconclusive experiment. Do not substitute
   an arbitrary pass count for evidence of causality.

Useful read-only capture commands, with the actual process ID substituted:

```sh
pgrep -alf 'MacOS/Palana'
/usr/bin/log show --last 10m --style compact --info --predicate 'processID == PID'
/usr/bin/sample PID 3 -file /tmp/palana-drag-sample.txt
xcrun dwarfdump --uuid /path/to/Palana.app/Contents/MacOS/Palana
```

Private captures, recording paths, exact commands and diagnostic source are
indexed in the private process repository. They are deliberately not attached
to the public issue because they contain workstation paths and operational
details. This public record carries the technical conclusions and limitations.

## Requirements for a future fix

Explain the mechanism supported by the new evidence and compare against a
control that can fail. Retest physical trackpad starts, tiny accidental drags,
single/group/folder drags, cancellation, repeat attempts, and clicking afterward.
Preserve local external copies, remote pane transfers, folder targets and
Finder-style selection. Do not silently disable all remote drags or introduce
conditional row structure as a shortcut.

Restore remote drag-out only after separate real Finder and browser checks,
including successful byte delivery, refused folders/size limits, cancellation
and cleanup. Keep the copy/move plan engine and live-host safety boundaries
outside a drag-start fix unless new evidence specifically requires changes.

Existing automated tests cover payloads, native table writer callbacks,
selection and drop decoding. At the November 17 handoff, the suite passed 251 application Swift
Testing tests, 1194 core Swift Testing tests and 81 XCTest tests; opt-in
ZFS/corpus checks were skipped. Coverage was 97.74% for core and 63.51% for
application logic. None of these checks establishes native gesture reliability.

## Relevant source

- [PaneView.swift](../../Sources/Palana/PaneView.swift): SwiftUI table and row providers.
- [PaneView+DragOut.swift](../../Sources/Palana/PaneView+DragOut.swift): local versus remote payload scope.
- [TableRowWriters.swift](../../Sources/Palana/TableRowWriters.swift): table data-source writer replacement.
- [PaneDropTarget.swift](../../Sources/Palana/PaneDropTarget.swift): AppKit pane/folder receiver.
- [DragDrop.swift](../../Sources/Palana/DragDrop.swift): payload and provider helpers.
- [DragOut.swift](../../Sources/Palana/DragOut.swift): remote delivery helpers, not currently exported by remote rows.
- [TableDragIntegrationTests.swift](../../Tests/PalanaTests/TableDragIntegrationTests.swift): offscreen native-table checks.
- [Apple's table drag-source interface](https://developer.apple.com/documentation/appkit/nstableviewdatasource/tableview(_:pasteboardwriterforrow:)): reference for the standalone native-table experiment.
