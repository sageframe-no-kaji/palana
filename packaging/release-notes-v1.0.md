# pālana 1.0.0

*Tend your field.*

pālana is a two-pane file manager for the machines you run yourself. Each pane can open a local folder, a mounted drive, or an SSH host. Select files in one pane and press `y` to plan a copy to the other. The plan shows the commands, the destination, and the route before you press Enter.

## Changes since v0.8-beta

- Press ⌘1 through ⌘9 to open your first nine favorites. Reorder them within their groups by dragging or with ⌥↑ and ⌥↓. Use ⇧⌘8 to star the current folder.
- If you interrupt an rsync copy, run the same copy again to reuse the data already received. Until it finishes, the incomplete file stays in a hidden `.palana-partial` directory at the destination. Rsync skips directories with that reserved name inside your selection. pālana refuses copy flags that change how interrupted data is kept or reused, including `--partial`, `--inplace`, `--append`, `-P`, `--whole-file`, and `--remote-option`.
- When you quit during a transfer or upload, choose **Keep Running**, **Quit When Finished**, or **Stop and Quit**. While a quit waits, pālana sets aside unstarted file plans. Enter can still send a saved edit back, including a retry using “replace by rename.” If a transfer fails or stops, the app stays open and holds queued saves until you dismiss the failed plan or choose Quit When Finished again.
- Before an rsync move, the plan tells you which extended attributes and access permissions the hosts can preserve. Rsync removes each source file after its destination copy matches. If the move stops, check both locations. The panel reports selected source paths that remain.
- Moving a whole ZFS dataset unmounts its source tree before taking a snapshot. After the receive, pālana checks for writes since the snapshot before it destroys the source.
- If a remote filesystem cannot create the hard link needed to replace an edited file, you can choose to replace it by rename. A concurrent write between the final check and the rename can be overwritten.

## Dragging files

Drag local files or folders into Finder to copy them. Command-drag to move into Finder remains [open](https://github.com/sageframe-no-kaji/palana/issues/6). Remote files can move between panes through a plan. To drag one into another app, first copy it to a local pane.

On macOS 27, a row drag can occasionally leave the window ignoring clicks. Quit and reopen pālana to recover. The [investigation](https://github.com/sageframe-no-kaji/palana/blob/main/docs/known-issues/drag-freeze.md) records the observed failure and the limits of the replay tests.

[Get the signed 1.0.0 app](https://payhip.com/b/YZKXE) for macOS 14 or later on Apple silicon or Intel. The US $29 purchase includes all 1.x updates. The [source](https://github.com/sageframe-no-kaji/palana) is available under GPL-3.0.
