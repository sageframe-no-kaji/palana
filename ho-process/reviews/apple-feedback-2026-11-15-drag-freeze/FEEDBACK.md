# Feedback Assistant draft — drag freezes the app (CALayerInvalidGeometry in UnflockAnimationTimerCallback)

**Area:** AppKit (Drag and Drop) · also SwiftUI (Table, onDrop)
**Type:** Incorrect/Unexpected Behavior
**Reproducibility:** Intermittent with a physical trackpad; the recorded trackpad event stream also reproduces it. Plain synthesized mouse drags have not reproduced it.
**Seen on:** macOS 27.0.1 (Apple silicon), Xcode 27.1, Swift 6.4. App's minimum deployment target macOS 14.

---

## Title

Drag session cancels during startup, sometimes with CALayerInvalidGeometry in UnflockAnimationTimerCallback, and leaves stale destination tracking

## Description

During a drag started with a trackpad, HIToolbox raises
`CALayerInvalidGeometry` from its drag animation. AppKit catches it, logs
"Canceling drag because exception was raised during a dragging session", and
cancels the drag. Afterwards the window does not respond to clicks; the app has
to be force-quit. The process is not hung: the main thread is idle in
`-[NSApplication run]`, and a thread is parked in
`SOME_OTHER_THREAD_SWALLOWED_AT_LEAST_ONE_EXCEPTION`. Tens of thousands of
`[com.apple.HIServices:DragAndDrop] Drag reference does not have any info.`
errors follow in the log.

The exception is thrown about 40–140 ms after the drag starts, while the pointer
is still over or near the source view, and only when SwiftUI drop destinations
(`.onDrop`) are under the pointer. With lldb breakpoints on
`-[NSDraggingItem setDraggingFrame:]` and `setDraggingFormation:`, the frames
going in are all finite. The sequence is:

1. The drag session begins (in our case `-[NSTableView _performFlockedDragOfIndexes:hitRow:event:gestureRecognizer:]`; see "Also reproduced" below).
2. `_PlatformDraggingDestinationView.draggingEntered` → `Drop.PhaseHandler.handleDropPhase` sets `draggingFormation = .default` and rewrites the item frames.
3. A second, nested SwiftUI drop destination does the same a few milliseconds later.
4. The next `UnflockAnimationTimerCallback` tick sets a NaN position on the `CoreDragDraggingLayer`.

## Exception and stack

```
*** Canceling drag because exception was raised during a dragging session.
Exception: "CALayerInvalidGeometry" reason: "CALayer position contains NaN: [nan nan].
Layer: <CoreDragDraggingLayer:0x…; position = CGPoint (869.5 686); bounds = CGRect (0 0; 193.5 26); …>"

frame #0  libobjc.A.dylib   objc_exception_throw
frame #1  CoreFoundation    +[NSException raise:format:]
frame #2  QuartzCore        CA::Layer::set_position(CA::Vec2<double> const&, bool)
frame #3  QuartzCore        -[CALayer setPosition:]
frame #4  HIToolbox         UpdateLayerPositions(OpaqueCoreDrag*)
frame #5  HIToolbox         UnflockAnimationTimerCallback(__CFRunLoopTimer*, void*)
frame #6  CoreFoundation    __CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__
 …
frame #13 AppKit            NSCoreDragTrackingProc
 …
frame #18 AppKit            -[NSCoreDragManager _dragUntilMouseUp:location:modifiers:]
frame #19 AppKit            -[NSCoreDragManager _tryCatchDragUntilMouseUp:location:modifiers:]
```

## Second failure signature: cancellation without an exception

With native table drags and eagerly written pasteboard items, the session can
end within 40–70 ms without a logged exception. Drag-server connections close,
but destination tracking continues and logs `Drag reference does not have any
info` repeatedly. The main thread remains idle. Physical trackpad use has left
the window unable to take clicks; an automated coordinate click after one
recorded-event reproduction still selected a row, so the stale tracking errors
alone do not establish complete loss of mouse input.

Both signatures were reproduced on 2026-11-16 with the same instrumented
pālana build and the same recorded `3ping` drag. Three control replays with
SwiftUI destinations produced three starts, two NaN exceptions, and 525
invalid-reference messages. A preceding ten-replay batch using the native
table source with an AppKit destination delivered all ten drops with neither
signature. The AppKit destination does not modify dragging formation or images.
This is a controlled app-level workaround experiment, not proof of the
internal macOS cause.

## Steps to reproduce (attached sample: DragFreezeRepro)

The sample's physical-trackpad reproduction remains unconfirmed. The captured
stacks and replay comparison above come from pālana.

1. Build and run DragFreezeRepro (`./make-app.sh`, then open `DragFreezeRepro.app`).
   Two SwiftUI `Table`s side by side; rows drag via `TableRow.itemProvider`;
   each table has `.onDrop(of: [.fileURL])`, and each name cell has its own
   `.onDrop`.
2. Using a **trackpad**, press with one finger and drag with another onto a row
   of the other table, or within the same table. Three-finger dragging is not
   required and was not used by the reporter. Repeat.
3. Within a few drags the drag disappears and the window stops responding to
   clicks.

## Expected

The drag completes or is cancelled, and the window keeps accepting input.

## Actual

The drag is cancelled by an exception raised inside HIToolbox's drag animation;
the window ignores all further mouse input until the app is force-quit.

## Also reproduced

- With the app's own drag session instead of the table's: the app started the
  drag itself with `-[NSView beginDraggingSession(with:event:source:)]`
  (one `NSDraggingItem` per file, finite frames), and the exception still came
  38 ms in, while the pointer was over a SwiftUI `.onDrop` view.
- Replacing both the drag source and the SwiftUI destinations did **not** fix
  the physical-trackpad freeze: the custom-source variants also ended early.
  The narrower native-table-source/AppKit-destination comparison above is a
  separate experiment, retaining the existing native drag lifecycle.

## Related observations (may deserve separate reports)

- **Lazy file URL from `TableRow.itemProvider`.** A provider created with
  `registerObject(url as NSURL, visibility: .all)` is written to the drag
  pasteboard as a 0-byte `public.file-url` promise. CFPasteboard then logs
  `Sandbox extension data required immediately for flavor public.file-url, but
  failed to obtain. (-3)`, and sandboxed receivers (browsers, chat apps) get no
  usable file.
- **Empty provider throws on the gesture path.** A `TableRow.itemProvider`
  returning an `NSItemProvider` with no registered types makes
  `-[NSDraggingSession _initWithPasteboard:draggingItems:clippingRect:source:isTouch:]`
  raise `NSGenericException` inside `-[NSTableView _handleDragAndDropGestureRecognizer:]`;
  AppKit logs "An uncaught exception was raised sending gesture action".

## Attachments

- DragFreezeRepro (sample project, this folder).
- sysdiagnose taken right after a freeze (Feedback Assistant collects it; take
  it while the window is still frozen).
- `sample` of the frozen process and two lldb transcripts (from the pālana
  investigation): `palana-hang.txt`, `lldb-run1.log`, `lldb2.log`.
