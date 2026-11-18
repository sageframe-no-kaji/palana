---
created: 2026-11-15
type: review
status: superseded by 2026-11-16-drag-freeze-fix.md; hands acceptance pending
parent: ho-process-private/agent-tasks/agent-task-2026-11-15-drag-out-and-freeze.md
project: palana
---

# Drag freeze — original investigation

The conclusions below are historical; later trackpad failures invalidated the
claimed custom-source fix. See `2026-11-16-drag-freeze-fix.md` for the controlled
destination-only comparison and thirty-replay result. Physical acceptance of
that narrower fix is still pending.

Branch `drag-out` (worktree `../palana-drag-out`), cut from `v1-release` at
`26401dd`. Build: `VERSION=1.0.0 ./scripts/build_macos.sh`, unmodified. macOS
27.0.1. Raw evidence (sample, two lldb transcripts) is kept in
`../palana-drag-out/.fixtures/dragfreeze/evidence/` (gitignored).

## Symptom

Both panes on the same local folder of folders (fixture shaped like
`/path/to/example-folder`). Drag the folder row `blink` from the right pane onto the
left pane's `blink` row. The window stops taking clicks. Reproduced by hand
three times on 2026-11-15, once on the release build and twice on a debug build.
A fourth freeze came from what the practitioner meant as a click on a row: a
small movement during the click was enough to start a drag.

## The process is not hung

`sample` of the frozen release build (`palana-hang.txt`): the main thread is
idle in the event loop (4319 of 4320 samples in `mach_msg` under
`-[NSApplication run]`). CPU 0.4%. There is no deadlock and no busy loop. One
extra thread is parked in
`SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION` (HIServices), created at
the moment of the drag. HIServices creates that marker when an Objective-C
exception is thrown and caught inside AppKit's event handling.

## The exception

Unified log, release build:

```
15:23:10.118 E [com.apple.AppKit:DragAndDrop] *** Canceling drag because exception was raised during a dragging session. Exception: CALayerInvalidGeometry
15:23:10.179 F [com.apple.hiservices:HIExceptions] FAULT: CALayerInvalidGeometry
```

Caught under lldb on `objc_exception_throw`, debug build (`lldb-run1.log`):

```
CALayer position contains NaN: [nan nan]. Layer: <CoreDragDraggingLayer …; bounds = CGRect (0 0; 193.5 26) …>
#1  CoreFoundation  +[NSException raise:format:]
#2  QuartzCore      CA::Layer::set_position
#3  QuartzCore      -[CALayer setPosition:]
#4  HIToolbox       UpdateLayerPositions(OpaqueCoreDrag*)
#5  HIToolbox       UnflockAnimationTimerCallback
 …
#13 AppKit          NSCoreDragTrackingProc
#18 AppKit          -[NSCoreDragManager _dragUntilMouseUp:location:modifiers:]
#19 AppKit          -[NSCoreDragManager _tryCatchDragUntilMouseUp:location:modifiers:]
```

The layer is the dragged row's image (193.5 × 26). macOS's own drag animation
computes a NaN position for it. AppKit catches the exception
(`_tryCatchDragUntilMouseUp`) and cancels the drag, and the window is left
without mouse input. No pālana frame is on the stack.

## What leads up to it

Breakpoints on `-[NSDraggingItem setDraggingFrame:]`,
`setDraggingFormation:` and `outlineView:updateDraggingItemsForDrag:`
(`lldb2.log`), in order:

1. `-[NSTableView _performFlockedDragOfIndexes:hitRow:event:gestureRecognizer:]`:
   the table starts a *flocked* drag of the row (frames all finite).
2. `AppKitOutlineTableCoordinator.outlineView(_:draggingSession:willBeginAt:forItems:)`
   (SwiftUI's table coordinator, the drag source) sets
   `draggingFormation = .default`.
3. `_PlatformDraggingDestinationView.draggingEntered` → `Drop.PhaseHandler.handleDropPhase`
   (SwiftUI `.onDrop`) sets `draggingFormation = .default` and rewrites the
   item frames (467, 663).
4. A second `draggingEntered` about 18 pt later (449, 659), from the folder row's
   `.onDrop` nested inside the pane's, does the same.
5. The next `UnflockAnimationTimerCallback` tick raises the NaN.

`outlineView:updateDraggingItemsForDrag:` is never called. Every frame value
pālana's code (via SwiftUI) passes in is finite, so the NaN is computed inside
HIToolbox.

## Experiments

- **Folder-row `.onDrop` switched off** (env-guarded debug build, reverted): it
  still froze, from a drag that started as a click. The nested row target is
  not required. So the trigger is the table's flocked drag meeting SwiftUI's
  drop handling, not the row target alone.
- **Synthetic drags** (CGEvent mouse down / drag / up, posted after the
  practitioner granted Accessibility): 12 runs at three speeds, down to 2 pt
  every 8 ms. Drag sessions started in 9 of them. **0 exceptions.** The freeze
  reproduces with the practitioner's trackpad and not with synthetic mouse
  events. Synthetic events carry no pressure or gesture phases, so the device's
  event stream is part of the trigger.

## Cause

The cause is outside pālana's drag-and-drop files: an exception in macOS's drag
animation (HIToolbox `UnflockAnimationTimerCallback`). It is reached when the
table's own flocked row drag (SwiftUI `Table`, `TableRow.itemProvider`) runs
while SwiftUI's `.onDrop` destinations change the drag's formation and frames.
pālana supplies no geometry. This matches the task's stop condition "the freeze
reproduces but its cause is outside the drag and drop files", so the work is
halted here.

## Related findings for drag-out

1. **Multi-select drags one file.** `PaneView`'s `Table` binds `selection:` to
   `cursorBinding`, a single `FileEntry.ID?`; pālana's multi-selection lives in
   `PaneModel.state.selection`. AppKit sees one selected row and drags one row.
   A probe app confirmed that SwiftUI's coordinator implements
   `outlineView(_:pasteboardWriterForItem:)` and calls each dragged row's
   `.itemProvider` closure, so AppKit would carry one URL per dragged row if
   it dragged them all.
2. **Local file URLs are written lazily, and sandboxed receivers can't use them.** At
   drag start the log shows `public.file-url` written as a 0-byte promise, then
   `Sandbox extension data required immediately for flavor public.file-url, but
   failed to obtain. (-3)`. Sandboxed receivers (browsers, chat apps) get no
   usable URL. That likely explains "drag to a browser delivers nothing" for
   local files as well as remote ones.
3. `dragContainer` / `draggable(containerItemID:)` are macOS **26.0**, not 15
   (SDK interface checked).
4. `NSItemProvider` is not `NSPasteboardWriting` in AppKit's public headers.
   An AppKit-owned drag session cannot carry the spec's
   `registerFileRepresentation` providers; remote files would go through
   `NSFilePromiseProvider` instead.

## Decision needed

Two routes. Both change the drag source.

**A. Own the drag session in AppKit (recommended).** A per-pane bridge on the
table (found the same way `TableSelectionStyler` finds it) returns no pasteboard
writer for rows, so the table never starts its flocked drag. A mouse-drag
monitor then starts pālana's own `beginDraggingSession` from the pane, with:

- one dragging item per entry in the selection;
- an `NSURL` written directly for each local entry, so the sandbox extension is
  made immediately;
- `NSFilePromiseProvider` for remote files;
- the `DraggedSelection` JSON for pane-to-pane drops.

This takes the table's flocked drag (step 1 above) out of the path, which should
remove the freeze, and it solves multi-file and the sandbox failure in the same
change, on macOS 14+. The cost: it departs from the spec's
`registerFileRepresentation` for remote files, and browser support for file
promises varies by receiver. The JSON would also need a type outside apps
ignore, which touches the drop side's type list.

**B. Keep SwiftUI's row drag.** Wrap the table's data source in a stand-in that
expands the drag to the whole selection at `willBegin`. The spec's
`registerFileRepresentation` route stays for remote files. The freeze is left
to Apple, with a feedback report; the flocked drag stays, so the freeze stays
possible on trackpads.

Neither route's freeze fix can be verified without the practitioner's hands,
since synthetic drags do not reproduce it.

## Resolution (route A, chosen 2026-11-15)

Commits on `drag-out`: `5576390` (plan), `93c0cda` (remote download),
`8b85330` (drag source), `489dc8b` (docs). GitHub issue #4 records the bug.

pālana answers the table's own drag call instead of letting the table start
its flocked drag. The table reaches a drag by two roads, and both are covered:

- the public `beginDraggingSession(with:event:source:)`, which mouse
  tracking uses;
- AppKit's private `beginDraggingSessionWithItems:gesture:source:`, which the
  drag gesture (the trackpad's road) uses.

pālana's session starts from the table's scroll view, with one item per
selected entry. Local entries carry file URLs written up front (the sandbox
failure is gone). Remote files are `NSFilePromiseProvider`s fetched at the
drop. The pane-to-pane payload sits under the private
`com.sageframe.palana.selection` type.

Three things learned on the way:

- A pan recognizer in front of the table's pans does not work. When the click
  lands on a cell's hosting view, the table's mouse-down tracking starves the
  recognizer.
- An empty row provider makes AppKit throw (`NSGenericException` building the
  session). Rows now carry a process-only marker type.
- The first cut patched only the `event:` road. Folder rows then took the
  gesture road and slipped past it.

**Checked in the `palana-shots` Tart guest (macOS 27.2) with posted events:**

| Check | Result |
|---|---|
| 1. Three local files to Finder | 3 files arrive; the originals stay (copy) |
| 1. Three local files to Safari's drop inspector | `types: ["Files"]`, 3 files with the right sizes; no selection data reaches the page |
| 2. Local folder to Finder | the folder arrives with its contents |
| 3. Two remote files (fixture `storage-host`) to Finder | 300,000 and 6 bytes arrive; transcript shows "downloading … for a drop…" then "… delivered to the drop"; no temp directory left. Safari also accepted the promises |
| 4. Remote folder to Finder | nothing arrives; transcript: "storage-host:/tmp/dragout/folder is a folder — drag out files, or copy it to a local pane first" |
| 5. Pane-to-pane, 3 files | one plan, "3 entries · 20 kB" |
| 6. Same-folder drag, both panes on the fixture folder | no exception; the next click moves the cursor |

Posted events never froze the old build either, so check 6 above does not
prove the fix. The trackpad check below does.

Not covered in the guest: Chrome (not installed there).

## Trackpad round (2026-11-15, evening)

**First try on `489dc8b`: froze.** The log showed pālana's own session
running (`drag out: 1 items` at 21:02:45 and 21:02:49), with the same
`CALayerInvalidGeometry` about 140 ms after each. The broken animation belongs
to any session started through AppKit's gesture road, whoever the source is.

**`7de01b3`** starts pālana's session through the public `event:` method even
when the trackpad's gesture asked for the drag.

**Second try on `7de01b3`: holds.** With the trackpad:

- five same-folder drags between panes on `/path/to/example-folder` were refused
  ("drop refused — same location"), and the app stayed responsive;
- a drop onto a folder row composed its plan (copy `3ping` into
  `AnalogReadSerial2`);
- three files reached Chrome's drop inspector with their sizes;
- a mixed drag of files and folders arrived as six entries. Chrome lists a
  folder with its own entry size, as browsers do for dropped folders.

## Hands checklist

Build: `../palana-drag-out/dist/Palana.app` (v1.0.0, built from `489dc8b`).
Quit your running pālana first; this build has the same bundle ID.

Use your trackpad for every step. Open
`scripts/drop-inspector.html` (in the main checkout) in Chrome.

1. ✅ (7de01b3) **The freeze.** Both panes on `/path/to/example-folder`. Drag a folder row from
   one pane to the other, five times, onto rows and onto empty space. Once more,
   starting as a click that moves a little. The app stays responsive throughout.
2. ✅ (7de01b3) Three local files selected, dragged to the inspector in **Chrome**: 3 files
   arrive. (Finder and Safari passed in the guest.)
3. One remote file from your own host, dragged to Finder: it arrives with the
   right size. Open the panel with `` ` `` to see the download line.
