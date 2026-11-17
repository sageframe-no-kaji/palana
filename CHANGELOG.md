# Changelog

All notable changes to pālana. Versions are git tags; the binary is a signed,
notarized macOS app at [palana.sageframe.net](https://palana.sageframe.net).

## Unreleased

- Finder drag-out remains copy-only. Command-drag moves are deferred to
  [#6](https://github.com/sageframe-no-kaji/palana/issues/6).

- Remote drag-out to other apps is on hold while the macOS 27 freeze remains
  unresolved. Remote files and folders still drag between pālana’s panes;
  their drag carries only an internal transfer descriptor, with no file URL
  or download promise. Copy to a local pane before dragging into a browser.
- Mouse selection follows Finder: Shift-click selects a continuous range,
  Command-click adds or removes individual rows, and a plain click selects
  only that row. Dragging a selected row keeps the marked cohort.
- Pane and folder drops use an AppKit receiver that leaves the native drag
  animation untouched. Local checks passed, but remote drags still reproduced
  the macOS 27 freeze; the issue remains open.
- ⌘1–⌘9 open the first nine favorites in the focused pane, numbered in the
  favorites panel's order (Global first, then each host). The panel shows each
  row's number; with the panel holding the keyboard, the number jumps where the
  panel's arrows aim.
- Favorites reorder by drag inside the panel, and by ⌥↑ / ⌥↓ on the row under
  the cursor. A favorite moves within its own group — Global or one host — so a
  drag never changes scope or host, and the sections never shuffle. The ⌘
  numbers follow the new order, and ⌘Z undoes a move.
- Starring the current folder moves from ⌘8 to ⇧⌘8 — the shifted 8 is `*`, the
  favorites key. `8` still stars the highlighted entry.

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

## v1.0 — the first full release

pālana is a native Mac app for tending a homelab: calm, keyboard-first,
dual-pane, over your own `ssh`. Every operation is planned before it enacts —
you read the real commands, then press Enter — and the bytes travel host to host
without ever routing through your Mac.

**The surface**

- **Plan → enact.** Copy, move, delete, rename, create, touch — each compiles to
  a plan first: the entries and sizes, the classification (within-dataset rename,
  cross-dataset copy-plus-delete, cross-host transfer), the transport and its auth
  path, and the exact commands. Enter enacts; Esc dismisses.
- **Server-side transfers.** Host-to-host copies and rsync moves run host to host.
  A file move compares contents, removes each source file after transfer, warns
  that interruption may split the selection, and refuses when a required
  endpoint lacks supported rsync. Tar fallback remains copy-only.
- **Moves keep metadata where they can.** A move asks rsync for extended
  attributes and Finder tags (`-X`) and ACLs (`-A`, between hosts of the same OS)
  when both ends carry them; otherwise the plan names what will not be kept.
- **A failed move still accounts.** When a move's transfer fails or is
  cancelled, the run still names every selected source that remains.
- **Send-back without hard links.** On a destination that cannot make hard links
  (exFAT, many FUSE mounts, some SMB shares) the safe replace refuses with
  nothing changed, and the panel offers to replace by rename instead, saying
  what that risks.
- **ZFS, natively.** Dataset boundaries are first-class; a cross-dataset move is
  named as what it is. Whole-dataset moves offer `zfs send | ssh | zfs receive`.
  The **ZFS workbench** manages datasets and snapshots (create, destroy, rename,
  snapshot, rollback, mount/unmount, mountpoint) — every mutation a plan you read
  first. Enter zfs mode with `Z`.
- **The field view.** One key summons the topology — machines, pools, datasets,
  reachability — as an overlay; point a pane, it vanishes. Discovery on demand.
- **The interactive shell.** `⌘\`` drops a real terminal into the panel, per host.
- **The preview pane.** `v` — the pane follows the other's cursor: text scrollable
  and monospace, images and PDFs via Quick Look, an info card always. Local files,
  plus remote text and images.
- **Drag-and-drop** between panes, from Finder, and into folders; **dark mode**
  (System / Light / Dark); **one master zoom** (`⌘+` / `⌘−` / `⌘0`); favorites,
  host onboarding, and a launch update check.
- **Drag out.** Local files and folders, including marked groups, can be dragged
  into Finder, a browser, or Mail. Remote drag-out is suspended; copy between
  panes first, then drag the local copy.

**Under it**

- **PalanaCore** — a headless library carrying all truth and logic, at ~97% line
  coverage. The app is a thin surface over it.
- Wraps your own `ssh` (your `~/.ssh/config`, keys, agent, ProxyJump) — no embedded
  SSH stack, no trust ceremony of its own. Runs when you open it, stops when you
  close it. Nothing watches while you're away.

Signed and notarized (Developer ID), macOS 14+. Source open under GPL-3.0.

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
