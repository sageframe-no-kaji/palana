# Changelog

All notable changes to pālana. Versions are git tags; the binary is a signed,
notarized macOS app at [palana.sageframe.net](https://palana.sageframe.net).

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
- **Server-side transfers.** Host-to-host moves run host to host — agent-forwarded
  direct when it can, proxied through your Mac when it can't. The plan names which.
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
| v0.6 | The v1 polish — universal text-scale, dark mode, drag-into-folders, the preview pane. |
| v0.5 | The Workbench (ZFS tool, pane mode, mount seam) and the interactive terminal. |
| v0.4-beta | First public build — signed, notarized `.dmg`. |
| v0.4 | Surface UX — favorites, host onboarding, settings, mounts. |
| v0.3 | The Surface — panes, plan → enact, field view. |
| v0.2 | PalanaCore — the headless engine complete. |
| v0.1 | Foundation verified — the spike answered *go*. |
