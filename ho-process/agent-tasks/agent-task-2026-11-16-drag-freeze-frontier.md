---
created: 2026-11-16
type: agent-task
status: ready
parent: ho-process-private/agent-tasks/agent-task-2026-11-15-drag-out-and-freeze.md
project: palana
---

# Drag freeze in pālana on macOS 27: find the cause, make drags safe

## Goal

Dragging rows in pālana's panes, with the practitioner's trackpad on macOS
27.0.1, sometimes leaves the window unable to take clicks. Find a change that
makes drags reliable, keeping the drag-out features already working on branch
`drag-out-native`, or show conclusively that the freeze is inside macOS and
cannot be avoided from the app.

## Read first

- `ho-process-private/reviews/2026-11-15-drag-freeze-diagnosis.md`: stacks,
  breakpoint sequences, and every attempt up to Sunday night.
- `ho-process-private/reviews/apple-feedback-2026-11-15-drag-freeze/`: the
  Feedback Assistant draft, a 70-line SwiftUI sample, and the raw evidence
  (`palana-hang.txt`, `lldb-run1.log`, `lldb2.log`). The draft still says the
  trigger needs three-finger drag; that is wrong (see below).
- Branch `drag-out-native` (worktree `../palana-drag-native`), cut from
  `v1-release` at `b0ed789`.

## The app, briefly

- SwiftUI `Table` per pane (`Sources/Palana/PaneView.swift`); underneath it is
  an `NSOutlineView` (`SwiftUIOutlineTableView`), with SwiftUI's
  `AppKitOutlineTableCoordinator` as data source and delegate.
- Rows drag through `TableRow.itemProvider`.
- Drops are SwiftUI `.onDrop`: one on the pane, and one on every folder row's
  name cell (`PaneView+FolderDrop.swift`). The payload is a JSON
  `DraggedSelection` (`public.json`, process-only visibility) plus file URLs.
- `TableSelectionStyler` turns the table's native highlight off.

## Two freeze signatures

Both start within about 100 ms of a drag that begins over a pane, which is
always a SwiftUI drop target.

1. **NaN exception** (0.8 and early builds). AppKit logs `*** Canceling drag
   because exception was raised during a dragging session. Exception:
   CALayerInvalidGeometry` (`CALayer position contains NaN` on a
   `CoreDragDraggingLayer`), thrown from HIToolbox `UpdateLayerPositions` ←
   `UnflockAnimationTimerCallback`. Breakpoints showed SwiftUI's
   `Drop.PhaseHandler.handleDropPhase` (from
   `_PlatformDraggingDestinationView.draggingEntered`) setting
   `draggingFormation` and rewriting item frames twice in quick succession
   (pane target, then the nested folder-row target) just before. Every frame
   passed in was finite.
2. **Silent early end** (every build where pālana supplied the pasteboard
   items or the session). The drag-server XPC connections (`com.apple.ensemble.dragserver`,
   `com.apple.windowmanager.dragserver`) open, and the process cancels them
   40–70 ms later with no exception. A drop destination
   (`NSDragDestination _startDraggingUpdates`) keeps calling `draggingUpdated`
   on a timer for a drag that no longer exists, logging `Drag reference does
   not have any info` thousands of times, and the window takes no clicks. The
   main thread is idle (`sample` shows `mach_msg`).

In both cases the process is alive and idle; the window ignores the mouse
until force-quit.

## What has been tried (branch / commit → result with the practitioner's trackpad)

| Attempt | Result |
|---|---|
| 0.8 (`v1-release`) | Drags work; intermittent NaN freeze (the original report). Drag-out: one file only; remote and browser drops deliver nothing. |
| `drag-out` 489dc8b: replace the table's drag (swizzled `beginDraggingSession(with:event:source:)` and private `beginDraggingSessionWithItems:gesture:source:` on the table class), own session from the scroll view | Froze (NaN). |
| `drag-out` 7de01b3: same, starting gesture drags via the event: method | Mostly worked; one NaN freeze (remote file toward Chrome). |
| `drag-out` eb5e439: + AppKit drop target (overlay NSView, hitTest nil, never touches items) replacing all SwiftUI `.onDrop` | Every drag froze (silent early end). |
| `drag-out` e1a7613: revert 7de01b3 with the AppKit drop target | Silent early end. |
| `drag-out` 2be783e: 7de01b3 code + highlight | Silent early end on the first drag; next two fine. |
| `drag-out-native` 002fcf7 / ece6d46: table's own drag (0.8 mechanics); selection binding = pālana's marks so the table drags all marked rows natively; data source's `outlineView:pasteboardWriterForItem:` swizzled to return an eagerly written NSPasteboardItem (file URL + public.json) or an NSFilePromiseProvider (remote) | Multi-file to Finder and Chrome **works**, folder to Finder works. A folder drag between panes on /path/to/example-folder froze (silent early end). |

Ruled out: three-finger drag (enabled in prefs, never used; the
practitioner presses with one finger and drags with another); Reduce Motion
(off); Universal Control prefs (none).

## Tools that exist

- **Recorder / replay** (`../palana-drag-native/.fixtures/handcheck/`;
  sources in the session scratchpad, rebuildable): a listen-only CGEventTap
  that records pointer, click, scroll and gesture (type 29) events, never
  keys, as base64 CGEvent data. Replay must restamp each event's timestamp
  (`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)`) and zero
  `mouseEventWindowUnderMousePointer` and
  `…ThatCanHandleThisEvent`, or nothing happens. Replays need the window at
  the recorded position, and the terminal needs Accessibility (granted).
- **Recording of the freezing drag:** `recordings/hands-1044.jsonl`, segment
  t = 135.6–137.9 s (the `3ping` drag, right pane → left). Replaying it froze
  the `ece6d46` build on the first try against /path/to/example-folder. Later runs
  against a mirror folder were intermittent: 0/5 on the same build, 1/1 on a
  variant. **Reproduction is intermittent; any bisection needs many trials
  per variant (≥20), not 5.**
- **Tester:** `.fixtures/handcheck/handcheck.sh setup | report` launches the
  `dist` build on its own profile with the practitioner's ssh config, opens a
  Finder drop folder and the drop inspector in Chrome, starts recording, and
  reports what arrived plus counts of both freeze signatures.
- **Tart guest `palana-shots`** (macOS 27.2): posted events never reproduce
  either freeze there. Caveats found: Finder in the guest can get stuck and
  re-deliver a previous drag (`killall Finder` clears it); SwiftUI-lazy
  pasteboard items never reach outside apps there.
- Every rebuild gets a new ad-hoc signature, so macOS asks again for
  Documents access. Point panes at `.fixtures/handcheck/Arduino` (a mirror of
  /path/to/example-folder's 82 names) to avoid the prompt.
- `/usr/bin/log`, not `log` (a zsh builtin). Drag-server lines are
  Default-level; `--info` shows them on the host.

## Open hypotheses

1. The NaN and the silent end share one trigger: any drop destination that
   reacts during the drag's opening "flock" animation (SwiftUI's
   `handleDropPhase` updating items; possibly also NSTableView's own
   destination machinery, since SwiftUI registers the table for drags).
2. The silent end needs an item pālana writes itself (eager file URL plus
   public.json) and a drag starting over a destination that accepts
   `.fileURL`. In the one bisection run, removing the payload still froze.
   Unproven either way.
3. Drag server ("ensemble") timing on the practitioner's Mac (another
   display, Sidecar, Universal Control peers) differs from the guest.

## Suggested next steps

- Before any fix, build a reliable reproduction: replay the recorded segment
  20+ times per variant, alternating variants, and log both signatures.
- Test whether the source pane being a drop target matters: unregister the
  source pane's drop types for the duration of its own drag, re-registering in
  `draggingSession(_:endedAt:operation:)`. Does the silent end disappear?
- Test `NSDraggingSession.draggingFormation = .none` and
  `animatesToStartingPositionsOnCancelOrFail = false` set as early as possible
  (`draggingSession(_:willBeginAt:)` on the table's source).
- File the Apple report with the corrected trigger; ask Apple DTS whether
  `UnflockAnimationTimerCallback` NaN is known on 27.0.

## Constraints

- Never run anything against the practitioner's hosts; fixtures only (the
  sshd container, the Lima `palana-source-host`/`palana-storage-host` VMs).
- The trackpad freeze reproduces only on the practitioner's Mac. Borrow it
  sparingly, announce each replay, keep hands-off windows short.
- Don't change the plan engine, transports or move safety code.
- No AI attribution in commits. Stage explicit paths.

## Acceptance

- The `3ping` replay segment run 30 times without either freeze signature,
  and a hands check: 10 folder drags between panes on /path/to/example-folder,
  with no freeze.
- The `drag-out-native` features keep working: marked rows out to Finder and
  Chrome, a folder to Finder, ⇧ mark and unmark, pane to pane as one plan.
