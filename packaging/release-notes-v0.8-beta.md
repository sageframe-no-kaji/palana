# pālana v0.8 beta

pālana manages files on your Mac and SSH hosts, including hosts that use ZFS. Before a file move begins, you can read the commands and see where the files will go. Press Enter to run the plan.

## What changed

- Moves across filesystems and hosts now use content-checked rsync, removing each
  source file once its destination copy matches.
- pālana then removes empty source directories and lists entries that remain.
- Leave both locations alone during the move. The plan warns that an interruption can leave files split between them.
- The build script compiles for Apple silicon and Intel separately and combines the executables into one app.
- About and Settings identify this release as `0.8.0 beta`.

## Requirements

- macOS 14 or later
- SSH configured through the Mac's standard `~/.ssh/config`, keys, and agent
- rsync on both required endpoints for copy-based file moves

The application is Developer ID signed, notarized, and stapled. The containing
DMG is separately notarized and stapled. Source remains available under
GPL-3.0.

SHA-256: `09ce5bad719032d6c698e31e6d15ac60eb7e25f5cedc612a56b60edee2263543`
