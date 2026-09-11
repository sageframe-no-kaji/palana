# pālana 1.0

*Tend your field.*

The first full release. pālana is a native Mac app for tending a homelab — calm,
keyboard-first, dual-pane, over your own `ssh`. Every operation is planned before
it enacts: you read the real commands, then press Enter. Supported cross-host
moves travel host to host; your Mac never carries the bytes.

**Get it:** **[palana.sageframe.net](https://palana.sageframe.net)** · macOS 14+ ·
signed & notarized · source here under GPL-3.0.

### What's in 1.0

- **Plan → enact** — copy, move, delete, rename, create; the exact commands shown
  before anything runs.
- **Server-side transfers** — copies use direct rsync or a tar fallback. File
  moves require supported rsync, compare contents, and remove each source file
  after transfer. The plan warns that interruption may split files across both
  locations.
- **ZFS, natively** — dataset boundaries as facts, `zfs send/receive` for whole
  datasets, and a workbench for datasets and snapshots — every mutation a plan.
- **The field view** — your machines, pools, and datasets, one keystroke away.
- **The live shell** (`⌘\``), the **preview pane** (`v`, local + remote text and
  images), **drag-and-drop**, **dark mode**, and **one-key zoom**.
- **Launch update check** — pālana tells you when a new version is out.

Runs when you open it, stops when you close it. Nothing watches while you're away.

---

*The `.dmg` is at [palana.sageframe.net](https://palana.sageframe.net). This
release page tracks the version and the changelog; the source lives in this repo.*
