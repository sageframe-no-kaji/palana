---
created: 2026-11-15
type: writeup-draft
status: draft — for the practitioner to edit and place
project: palana
---

# A drag that froze the window: NaN in macOS 27's drag animation

pālana is a dual-pane file manager for Mac, written in SwiftUI. A week before
1.0 a tester (me) dragged a folder from one pane to the other, both showing the
same folder. The drop was refused, correctly, as "same location", and then the
window stopped responding to clicks. It took most of a day to learn that
nothing in pālana was wrong, and three attempts to work around it. This is the
record.

## It isn't hung

The first move with a frozen Mac app is `sample`. The main thread was idle:

```
4320 -[NSApplication run]
  ...
  4319 __CFRunLoopServiceMachPort → mach_msg2_trap
```

CPU 0.4%. No deadlock, no spin. One extra thread stood out:

```
4320 Thread_…: HIE: M_ 5615c6bf77f1ceb6 2026-11-15 15:23:10.176
  SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION  (in HIServices)
    thread_suspend
```

HIServices parks a thread with that name when an Objective-C exception is
thrown and caught inside AppKit's own event handling. The timestamp matched the
drag. The unified log named it:

```
*** Canceling drag because exception was raised during a dragging session.
Exception: CALayerInvalidGeometry <redacted reason>
```

## The reason, unredacted

The reason was `<private>`. A debug build under lldb with a breakpoint on
`objc_exception_throw` gave the whole thing:

```
CALayer position contains NaN: [nan nan].
Layer: <CoreDragDraggingLayer…; bounds = CGRect (0 0; 193.5 26)>

#3  QuartzCore  -[CALayer setPosition:]
#4  HIToolbox   UpdateLayerPositions(OpaqueCoreDrag*)
#5  HIToolbox   UnflockAnimationTimerCallback
#13 AppKit      NSCoreDragTrackingProc
#19 AppKit      -[NSCoreDragManager _tryCatchDragUntilMouseUp:…]
```

The layer is the dragged row's image: 193.5 × 26 points, one table row. The
drag animation in HIToolbox computed a NaN position for it. AppKit's drag loop
caught the exception and cancelled the drag, and the window was left without
mouse input. No pālana frame is on that stack.

## Who moves the drag mid-flight

Breakpoints on `-[NSDraggingItem setDraggingFrame:]` and
`setDraggingFormation:`, printing `d0–d3` (the CGRect arrives in floating-point
registers on arm64), showed the sequence before the NaN:

1. `-[NSTableView _performFlockedDragOfIndexes:hitRow:event:gestureRecognizer:]`:
   SwiftUI's `Table` is an `NSOutlineView` underneath, and it starts a *flocked*
   drag.
2. `AppKitOutlineTableCoordinator.outlineView(_:draggingSession:willBeginAt:forItems:)`
   sets `draggingFormation = .default`.
3. `_PlatformDraggingDestinationView.draggingEntered` →
   `Drop.PhaseHandler.handleDropPhase`, which is SwiftUI's `.onDrop`, sets the
   formation again and rewrites every item frame.
4. Some 18 points later a second, nested `.onDrop` (the folder row's) does the
   same.
5. The next unflock tick sets NaN.

Every frame going in was finite. The NaN comes from inside HIToolbox, when its
opening animation is interrupted by drop targets rewriting the drag.

## It only happens with a trackpad

I gave the terminal Accessibility permission and posted CGEvent drags: down,
move, up, at several speeds down to 2 points every 8 ms. Twelve runs, nine drag
sessions, no exceptions. The same drag by hand froze the app most of the time.
A trackpad sends pressure and gesture phases that posted mouse events do not,
and AppKit takes a different road for them: the table's drag arrives through
`-[NSTableView _handleDragAndDropGestureRecognizer:]` and the private
`-[NSView beginDraggingSessionWithItems:gesture:source:]`, not through
`mouseDown:`.

That made every fix attempt cost a hand test. Everything else (does the drag
still carry three files, does Finder get them, does the plan compose) moved into
a macOS 27.2 guest under Tart. There the same harness posts events and takes
screenshots without touching the real desktop. One thing to know: a posted drag
onto Finder needs a few movement events over the target before the mouse-up,
or the drag never lands.

## Three attempts

**1. Take the drag away from the table.** The table drags only its own selected
row, and pālana's table selection is a single cursor, so multi-file drag-out was
broken anyway. pālana now answers the table's own drag call on both of its
roads: the public `beginDraggingSession(with:event:source:)` and the private
`…gesture:source:` variant. It does this with a one-time method replacement on
the table's class, and starts its own session from the table's scroll view:
one item per selected file, file URLs written eagerly, remote files as
`NSFilePromiseProvider`s. Synthetic drags were all fine. The trackpad froze
it. The log showed pālana's own session running, then the same NaN 140 ms
later.

**2. Start that session through the event road.** Maybe any session started
from a gesture was the problem. The gesture road now starts pālana's session
through the public `event:` method. Five same-folder trackpad drags passed.
The next one, a remote file toward Chrome, froze 38 ms after it began, while
the pointer was still over the pane it came from.

**3. Get SwiftUI's drop targets out of the way.** That was the common factor all
along. A drag begins over its own pane. The pane was a SwiftUI `.onDrop`, and
every folder row was another one nested inside it. Each one rewrites the drag's
formation and frames on entry. pālana's panes now have a single AppKit view as
their drop target:

- registered for pālana's selection type and file URLs;
- returning `nil` from `hitTest(_:)`, so clicks reach the table beneath (drag
  routing still finds a registered view under the pointer);
- reading the pasteboard on drop, finding the folder row under the pointer from
  the table itself, and handing the drop to the same handlers as before;
- never touching the dragging items.

The drop decisions and plans behind it did not change.

## Smaller things found on the way

- **A row's file URL was written lazily.** `NSItemProvider` →
  `registerObject(url as NSURL)` reached the drag pasteboard as a 0-byte
  `public.file-url` promise. CFPasteboard then said *"Sandbox extension data
  required immediately for flavor public.file-url, but failed to obtain"*, so
  browsers and chat apps received nothing. Writing the URL string into an
  `NSPasteboardItem` up front fixes it.
- **An empty item provider throws.** Rows need *some* provider so the table
  treats them as draggable. A provider with no types makes
  `NSDraggingSession`'s initializer raise `NSGenericException` on the gesture
  road. The rows now carry a process-only marker type.
- **A recognizer in front of the table's pans doesn't work.** When a click lands
  on a cell's SwiftUI hosting view, the event is forwarded up the responder
  chain to `-[NSTableView mouseDown:]`, which tracks the drag in its own loop
  and never feeds the recognizer.
- **`dragContainer` is macOS 26.0,** not 15, and `TableRow` is not a view, so
  `draggable(containerItemID:)` cannot go on it anyway.
- **`log` in zsh is a builtin.** Use `/usr/bin/log`.

## Where it stands

- Reported to Apple through Feedback Assistant with a 70-line sample: two
  SwiftUI `Table`s, rows with `itemProvider`, `.onDrop` on the table and the
  cells. FB number: (to fill in).
- pālana works around it in v1.0: pālana starts its own drags, and AppKit
  handles its drops.
- The general lesson for SwiftUI apps on macOS 27: if a drag can begin over a
  SwiftUI `.onDrop` view, a trackpad user can freeze your window. An AppKit
  `NSDraggingDestination` that leaves the dragging items alone avoids it.
