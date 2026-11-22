# Changelog

## 1.0.0 — 2026-11-22

- Press ⌘1 through ⌘9 to open your first nine favorites. Reorder them within their groups by dragging or with ⌥↑ and ⌥↓. Use ⇧⌘8 to star the current folder.
- If you interrupt an rsync copy, run the same copy again to reuse the data already received. Until it finishes, the incomplete file stays in a hidden `.palana-partial` directory at the destination. Rsync skips directories with that reserved name inside your selection. pālana refuses copy flags that change how interrupted data is kept or reused, including `--partial`, `--inplace`, `--append`, `-P`, `--whole-file`, and `--remote-option`.
- When you quit during a transfer or upload, choose **Keep Running**, **Quit When Finished**, or **Stop and Quit**. While a quit waits, pālana sets aside unstarted file plans. Enter can still send a saved edit back, including a retry using “replace by rename.” If a transfer fails or stops, the app stays open and holds queued saves until you dismiss the failed plan or choose Quit When Finished again.
- Before an rsync move, the plan tells you which extended attributes and access permissions the hosts can preserve. Rsync removes each source file after its destination copy matches. If the move stops, check both locations. The panel reports selected source paths that remain.
- Moving a whole ZFS dataset unmounts its source tree before taking a snapshot. After the receive, pālana checks for writes since the snapshot before it destroys the source.
- If a remote filesystem cannot create the hard link needed to replace an edited file, you can choose to replace it by rename. A concurrent write between the final check and the rename can be overwritten.
- Local files and folders can be dragged into Finder, browser upload fields, and Mail. Finder receives a copy even if you hold Command. A drag from a remote pane works only within pālana. To send a remote file to another app, copy it to a local pane first. An intermittent [row-drag freeze](docs/known-issues/drag-freeze.md) remains open.
- Shift-click selects a range, Command-click adds or removes individual rows, and dragging a selected row keeps the group. AppKit handles drops onto panes and folders.
- The update check reads GitHub’s latest release tag and links to the product site when a newer build is available.

## v0.8-beta — progressive moves

- File moves across filesystems and hosts use content-checked rsync, removing
  each source file only after its destination copy lands. Empty source
  directories are removed afterward, and anything retained is reported.
- The plan warns before enactment that files move progressively and that neither
  location should change during the operation.
- The release build produces a universal Apple Silicon and Intel application
  by building each architecture separately and combining the executables.
- About, Settings, and bug reports identify the build as `0.8.0 beta` while the
  update comparator retains the numeric bundle version.

Signed, notarized, and stapled for macOS 14 or later.

## Earlier

| Tag | What it marked |
|---|---|
| v0.7-beta | Feature-complete beta after the whole-codebase safety review. |
| v0.6 | The v1 polish — universal text-scale, dark mode, drag-into-folders, the preview pane. |
| v0.5 | The Workbench (ZFS tool, pane mode, mount seam) and the interactive terminal. |
| v0.4-beta | First public build — signed, notarized `.dmg`. |
| v0.4 | Surface UX — favorites, host onboarding, settings, mounts. |
| v0.3 | The Surface — panes, plan → enact, field view. |
| v0.2 | PalanaCore — the headless engine complete. |
| v0.1 | The initial prototype established that development could proceed. |
