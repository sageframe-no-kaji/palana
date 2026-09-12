# pālana v0.8 beta

pālana is a native Mac application for tending filesystems, remote hosts, and
ZFS infrastructure through a plan-first interface. Every operation shows its
real commands before Enter enacts it.

## What changed

- Moves across filesystems and hosts now use content-checked rsync, removing each
  source file only after its destination copy lands.
- Empty source directories are removed afterward, while retained entries are
  named instead of hidden.
- The plan states before enactment that the move is progressive and neither
  location should change during it.
- The universal Apple Silicon and Intel build no longer depends on SwiftPM's
  broken combined-architecture Metal path.
- About and Settings identify this release as `0.8.0 beta`.

## Requirements

- macOS 14 or later
- SSH configured through the Mac's standard `~/.ssh/config`, keys, and agent
- rsync on both required endpoints for copy-based file moves

The application is Developer ID signed, notarized, and stapled. The containing
DMG is separately notarized and stapled. Source remains available under
GPL-3.0.

SHA-256: `09ce5bad719032d6c698e31e6d15ac60eb7e25f5cedc612a56b60edee2263543`
