# Changelog

All notable changes to pālana. Each version is a git tag. The signed,
notarized macOS app is sold at [palana.sageframe.net](https://palana.sageframe.net);
the source builds free at every version.

## v1.0 — 2026-11-15

The first full release. pālana is a native Mac file manager for the machines
you run yourself: two keyboard-driven panes, each on this Mac or an SSH host,
using your own `ssh`. Every file and ZFS operation is composed as a plan first.
You read the real commands, then press Enter.

**Changes since v0.8-beta**

- ⌘1–⌘9 open the first nine favorites in the focused pane, numbered in the
  favorites panel's order (Global first, then each host). The panel shows each
  row's number. When the panel holds the keyboard, a number opens the favorite
  in the pane the panel's destination selector points to.
- Favorites can be reordered by dragging them in the panel, or with ⌥↑ / ⌥↓ on
  the row under the cursor. A favorite moves only within its own group (Global
  or one host), so reordering never changes its scope or host, and the sections
  keep their order. The ⌘ numbers follow the new order, and ⌘Z undoes a move.
- Starring the current folder moves from ⌘8 to ⇧⌘8. The shifted 8 is `*`, the
  favorites key. `8` still stars the highlighted entry.
- ⌘Q while a transfer runs, or while saved edits are still going back to their
  server, asks first: Keep Running, Quit When Finished, or Stop and Quit. Quit
  When Finished waits for the transfer and the queued saves, then quits; if any
  of them fails or is stopped, pālana stays open with the failure on screen.
- **Moves keep metadata where they can.** A move asks rsync for extended
  attributes and Finder tags (`-X`) and ACLs (`-A`, between hosts of the same OS)
  when both ends carry them; otherwise the plan names what will not be kept.
- **A failed move still accounts.** When a move's transfer fails or is
  cancelled, the run still names every selected source that remains.
- **Send-back without hard links.** On a destination that cannot make hard links
  (exFAT, many FUSE mounts, some SMB shares) the safe replace refuses with
  nothing changed, and the panel offers to replace by rename instead, saying
  what that risks.
- **Drag out.** Local files and folders, including marked groups, can be dragged
  into Finder, a browser, or Mail. Finder drag-out copies; ⌘-drag to move is
  deferred to [#6](https://github.com/sageframe-no-kaji/palana/issues/6).
  Remote files and folders still drag between pālana's panes; remote drag-out
  to other apps is on hold, so copy to a local pane first.
- Mouse selection follows Finder: Shift-click selects a continuous range,
  ⌘-click adds or removes individual rows, and a plain click selects only that
  row. Dragging a selected row keeps the marked group.
- Pane and folder drops use an AppKit receiver that leaves the native drag
  animation untouched.
- Known issue: an intermittent row drag can leave the window ignoring clicks.
  Tracked in [#4](https://github.com/sageframe-no-kaji/palana/issues/4); the
  [investigation record](docs/known-issues/drag-freeze.md) keeps the failures,
  attempted fixes, verification limits, and next diagnostic steps.
- The signed app is sold at palana.sageframe.net for US $29, including 1.x
  updates. GitHub releases now carry release notes only; the launch update
  check reads their tags and links to the site.

**What 1.0 contains**

- **Plans before actions.** Copy, move, delete, rename, create, and touch each
  compose a plan: the entries and their size, the kind of operation, the source
  and destination, destination collisions, the transport and how it
  authenticates, and the exact commands in order. Enter runs it; Esc dismisses
  it.
- **Server-to-server transfers.** With rsync 3.1 or later on the source, rsync
  on the destination, and a forwarded SSH agent, copies and moves between two
  hosts run host to host. Otherwise copies
  stream through the Mac with tar. A move across filesystems or hosts uses rsync
  with `--checksum --remove-source-files`, warns that an interruption may split
  the selection, and is refused when a required endpoint lacks a supported
  rsync. The tar fallback is copy-only.
- **ZFS where ZFS exists.** Dataset boundaries decide whether a move is a rename
  or a copy with source removal. Whole-dataset copies and moves between ZFS
  hosts use `zfs send -R | zfs receive -u`. ZFS mode (`Z`) creates, destroys,
  and renames datasets; creates, destroys, and rolls back snapshots; sets or
  inherits mountpoints; and mounts and unmounts. Every mutation is a plan.
- **The field.** `f` shows each host's reachability, capabilities, pools, and
  datasets from cached, dated facts; `F` opens the host map with mounts. Facts
  are read only on request.
- **The shell.** `` ⌘` `` opens an interactive terminal for the focused host in
  the plan panel.
- **Preview.** `v` makes the right pane preview the left pane's file: text,
  images, and PDFs locally, and text, images, PDFs, and SVG files from remote
  hosts.
- **Remote editing.** Saved edits to a fetched remote file upload when the
  remote copy is unchanged, and ask first when it has changed.
- **And:** drag and drop between panes, from Finder, and into folders;
  appearance (System, Light, or Dark); one zoom for the whole window
  (`⌘+` / `⌘−` / `⌘0`); favorites; adding and hiding hosts in Settings; the
  operations log; and a launch update check that can be turned off.

**Under it**

- PalanaCore, a headless library, holds the logic, at 97.5% line coverage
  against a 90% floor. The app is a thin surface over it.
- pālana uses your own `ssh` (your `~/.ssh/config`, keys, agent, and ProxyJump)
  and has no embedded SSH stack. It runs while the app is open and installs no
  background process.

Signed with Developer ID, notarized, and stapled. Universal (Apple silicon and
Intel), macOS 14 or later. Source under GPL-3.0.

## v0.8-beta — progressive moves

- File moves across filesystems and hosts use content-checked rsync, removing
  each source file only after its destination copy lands. Empty source
  directories are removed afterward, and anything retained is reported.
- The plan warns before enactment that files move progressively and that neither
  location should change during the operation.
- The release build produces a universal Apple Silicon and Intel application
  without depending on SwiftPM's broken combined-architecture Metal path.
- About, Settings, and bug reports identify the build as `0.8.0 beta` while the
  update comparator retains the numeric bundle version.

Signed, notarized, and stapled for macOS 14 or later.

## Earlier

| Tag | What it marked |
|---|---|
| v0.8-beta | Progressive content-checked file moves and the repaired universal release build. |
| v0.7-beta | Feature-complete beta after the whole-codebase safety review. |
| v0.6 | The v1 polish — universal text-scale, dark mode, drag-into-folders, the preview pane. |
| v0.5 | The Workbench (ZFS tool, pane mode, mount seam) and the interactive terminal. |
| v0.4-beta | First public build — signed, notarized `.dmg`. |
| v0.4 | Surface UX — favorites, host onboarding, settings, mounts. |
| v0.3 | The Surface — panes, plan → enact, field view. |
| v0.2 | PalanaCore — the headless engine complete. |
| v0.1 | Foundation verified — the spike answered *go*. |
