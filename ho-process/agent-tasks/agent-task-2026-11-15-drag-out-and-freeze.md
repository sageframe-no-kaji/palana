---
created: 2026-11-15
type: agent-task
status: ready
parent: ho-process-private/hos/ho-12-the-ship.md
project: palana
---

**Goal**

Make dragging files out of pālana work the way a Mac user expects before v1.0 ships. Dragging a multi-selection from a local pane to Finder, a browser upload box, or Mail delivers every selected file. Dragging remote files out downloads them at the drop and delivers real files. Find and fix the freeze that follows a refused drop between two panes showing the same local folder.

**Context**

- Precondition: branch `v1-release` carries the committed pre-1.0 fixes, including `Sources/Palana/DragDrop.swift`'s main-actor `resolveDropProviders`. Verify `git log v1-release` shows them, and that `git status` is clean on that branch before you start. If not, stop and say so.
- Work on a new branch `drag-out` cut from `v1-release`, in a sibling worktree. Create the branch first, then the worktree: `git branch drag-out v1-release && git worktree add ../palana-drag-out drag-out`. The guard hook rejects `git worktree add -b`.
- Today's drag-out is one `NSItemProvider` per table row (`TableRow.itemProvider` in `Sources/Palana/PaneView.swift` near line 450, built by `itemProvider(for:localFileURL:)` in `Sources/Palana/DragDrop.swift`). It carries the `DraggedSelection` JSON with `.ownProcess` visibility for pane-to-pane drops. It also carries the file URL of the row under the mouse, local panes only. Drops between panes and from Finder work and must keep working.
- Do not put a drag source on the name cell. That desyncs SwiftUI's rows from AppKit's hit rects, so clicks land one row off. See the comment in `PaneView.nameCell` (bisected to `9808498`).
- Remote bytes come through the conduit: `Listing.fetchFile(on:path:to:limit:timeout:)` in `Sources/PalanaCore/Listing/Listing.swift` streams one file to a local URL and removes it on failure. Its default ceiling is the preview ceiling, so a drag needs its own limit.
- Minimum macOS is 14. A SwiftUI API that only exists on 15 or later goes behind `if #available`, with the current single-file behavior on 14.
- Practitioner-observed, 2026-11-15, on the 0.8 build. Multi-select drag delivers one file. Remote drag delivers nothing, either to a browser or to a chat app. With both panes on `local:/path/to/example-folder`, a drag from the right pane to the left showed "drop to copy · hold ⌘ to move" and was refused as the same location, then the app froze.
- `scripts/drop-inspector.html` shows exactly what a web page receives from a drop (types, files, strings). Open it in Chrome and Safari for the hands checks.

**Files**

- Modify: `Sources/Palana/DragDrop.swift`
- Modify: `Sources/Palana/PaneView.swift`
- Create: `Sources/Palana/DragOut.swift` (the outbound drag payload: which local URLs, which remote promises)
- Create: `Sources/PalanaCore/Surface/DragOutPlan.swift` (pure: from a pane's host, directory and dragged selection to the list of outbound items and refusals, no I/O)
- Create: `Tests/PalanaCoreTests/DragOutPlanTests.swift`
- Create: `Tests/PalanaTests/DragOutProviderTests.swift`
- Modify, if the freeze lives there: `Sources/Palana/PaneView+FolderDrop.swift`, `Sources/Palana/DropWash.swift`, `Sources/Palana/OperationModel.swift`
- Modify: `README.md` and `CHANGELOG.md` (one line each under v1.0 describing drag-out)
- Create: `ho-process-private/reviews/2026-11-15-drag-freeze-diagnosis.md` (the freeze's cause, with the sample or spindump excerpt that shows it)

**Required Changes**

1. **The freeze, first.** Reproduce it on the current build: `VERSION=1.0.0 ./scripts/build_macos.sh`, then open `dist/Palana.app` with both panes on the same local folder, drag a row from one pane to the other, and release. While it hangs, capture `sample Palana 5 -file /tmp/palana-hang.txt` (or `spindump`). Find the main-thread stack, fix the cause, and write the diagnosis file: the symptom, the stack, the cause, the fix. If it does not reproduce on the current build, record that, with what you tried, and go on.
2. **Outbound plan (core, pure).** `DragOutPlan` takes the pane's host, directory, the dragged names (the whole selection when the dragged row is inside it, as `dragPayload(for:selectedNames:)` decides today), and each entry's kind and size. It returns one outbound item per entry:
   - `.localFile(path)` for a local file or folder;
   - `.remoteFile(host, path, size)` for a remote regular file;
   - `.refused(name, reason)` for remote directories, symlinks to directories, and anything whose name is not representable.

   Remote folders are refused in v1.0. Unit-test every branch.
3. **Local multi-file drag-out.** Dragging any row inside a multi-selection from a local pane delivers every selected file to outside targets, as separate files. Find the mechanism that works with SwiftUI's `Table` on macOS 14:
   - `dragContainer`/`draggable(containerItemID:)` behind `#available(macOS 15, *)`;
   - an AppKit hook on the table's own drag (the `NSTableView` is already reached by `TableSelectionStyler`);
   - one `NSItemProvider` carrying several file representations.

   Pick one, and record why in the commit body. The pane-to-pane JSON payload stays in-process and still names the whole selection, so a drop on the other pane composes one plan for all of it.
4. **Remote drag-out by download at the drop.** For each `.remoteFile`, register a file representation (`registerFileRepresentation(forTypeIdentifier:fileOptions:visibility:loadHandler:)`, type from the file extension, falling back to `public.data`, `suggestedName` = the file name). The load handler fetches through `Listing.fetchFile` into a per-drag temp directory under `FileManager.default.temporaryDirectory/palana-dragout-<uuid>/`, using a drag ceiling of 4 GiB and a timeout scaled to that, and calls the completion with the URL when the bytes land.
   - Return a `Progress` whose `completedUnitCount` follows the bytes and whose `cancellationHandler` cancels the fetch task.
   - On failure, call the completion with the error. Never deliver a partial file.
   - Remove the temp directory after the receiver has copied the file. The completion's contract says the file is copied before it returns, so delete in the completion path, or on the next launch for any that remain.
5. **Feedback in the app.** A remote drag-out writes one line per file to the plan panel's transcript ("downloading storage-host:/path for a drop…", then done or the error). This is the operator's only sign that bytes are moving.
6. **Refusals are visible.** If a drag includes refused items (remote folders), the transcript names them ("storage-host:/srv/media is a folder — drag out files, or copy it to a local pane first"). The rest of the drag still delivers.
7. **Docs.** README and CHANGELOG say what drag-out does in v1.0: local files and folders, remote files downloaded at the drop, remote folders refused with the reason.

**Acceptance**

- [ ] `DragOutPlanTests` cover: local multi-selection → one `.localFile` per entry; remote file → `.remoteFile` with size; remote directory and remote symlink-to-directory → `.refused`; dragged row outside the selection → that row only.
- [ ] `DragOutProviderTests` drive the remote load handler against a fake `Listing` (the recording conduit pattern in `Tests/PalanaTests`, never a live `SSHConduit`). They show that bytes land at the delivered URL, that progress reaches the byte count, that cancelling stops the fetch and delivers an error with no file left behind, and that a fetch failure delivers an error with no file.
- [ ] The freeze diagnosis file exists and names a cause, or records that it does not reproduce on the current build and what was tried.
- [ ] Hands checklist, written into the diagnosis file's last section for the practitioner to run (you cannot drag). Each step uses `scripts/drop-inspector.html` in Chrome and Safari, plus Finder:
  1. Local, 3 files selected, dragged to the inspector and to Finder: 3 files arrive.
  2. Local folder dragged to Finder: the folder arrives.
  3. Remote file (fixture or the practitioner's host) dragged to the inspector and to Finder: the file arrives with the right size, and the transcript shows the download line.
  4. Remote folder: refused, with the transcript line.
  5. Pane-to-pane drag of a 3-file selection: one plan naming all 3.
  6. Same-folder drag between two local panes: refused, and the app stays responsive.
- [ ] The verification stack is green (below), with the sshd fixture running.

**Verification**

```sh
cd ../palana-drag-out
scripts/sshd-fixture.sh start
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test --filter 'DragOut'
swift test --enable-code-coverage
scripts/coverage-floor.sh 90 35
VERSION=1.0.0 ./scripts/build_macos.sh   # builds dist/Palana.app for the hands checklist
test -s ../palana/ho-process-private/reviews/2026-11-15-drag-freeze-diagnosis.md
```

**Do Not**

- Do not change the pane-to-pane or Finder-to-pane drop paths, except where the freeze fix requires it.
- Do not download remote folders (no recursive tar or rsync for drag-out in v1.0).
- Do not run anything against the practitioner's hosts. Tests use fakes and the sshd fixture only.
- Do not touch the plan engine, transports, or the move safety code merged today.
- Do not push, merge into `main`, or tag. The practitioner merges after the hands checklist.

**Stop Condition**

Halt and write findings into the diagnosis file, then ping the ntfy topic in `prompts/ntfy-topic.txt`, when any of these happens:

- No mechanism delivers several local files from SwiftUI's `Table` on macOS 14 without reintroducing the row hit-rect bug. Say which ones you tried, and what macOS 15-only support would give.
- The freeze reproduces but its cause is outside the drag and drop files.
- `registerFileRepresentation` does not get a file delivered to Finder or Chrome from a SwiftUI table row drag. Record what each target received, using the inspector.

**Commit**

Atomic commits on `drag-out`, one per change. Plain descriptive subjects, for example "drag a whole local selection out of a pane", "download remote files at the drop", "fix the freeze after a refused same-folder drop". A body explains the mechanism choice where one was made. No AI attribution of any kind: no `Co-Authored-By`, no "Generated with". Stage explicit paths, never `git add -A`.
