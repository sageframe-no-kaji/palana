---
created: 2026-07-16
status: ready
type: ho-document
project: palana
ho: 12
kamae: 5
shape: ha
phase: 7 — the ship
builds-on:
  - kamae-2-palana-system-design
  - v0.4-beta release pipeline
---

# ho-12 — The ship (v1.0) + auto-update

The release. Most of the machinery already exists — it was built ahead at
v0.4-beta (`scripts/build_macos.sh`, `scripts/entitlements.plist`,
`RELEASING.md`, the notarization profile). This ho **formalizes** that, adds the
two things a shipped product needs that the beta skipped — a true icon and an
**automatic update signal** — and cuts **v1.0**.

**Positioning (from the v0.6 review):** v1.0 leads with what's differentiated —
a calm, fleet-wide file manager over your own ssh, every operation planned
before it enacts, ZFS present natively (snapshots especially). The ZFS *dataset
management* is the proven workbench tool, shipped as-is; it is **not** the
headline and does not grow here. Snapshot-history is the v1.1 story, not v1.0.

**Out of scope:** the App Store (never — `Process`/ssh/filesystem freedom); a
self-hosted update server (the appcast is a static file on the release/site);
delta updates (full-dmg updates are fine at this cadence).

---

## Phase 1 — Think

### Decision 1 — Formalize the existing pipeline, don't rebuild it
`build_macos.sh` already produces a universal (`arm64+x86_64`) `.app`,
hand-assembled with `Package.swift` canonical (no Xcode project), signs with the
`Developer ID Application` cert, notarizes app then dmg via `notarytool`, and
staples both. ho-12 verifies it end-to-end on a clean checkout, fixes whatever
drifted since the beta, and documents the one-command release in `RELEASING.md`.

### Decision 2 — A true icon
The beta icon was 1024×1059, padded to a transparent square to avoid squish.
Re-export a real 1024² master and rebuild the `.icns` (the build already
generates it at build time; the generated file stays gitignored).

### Decision 3 — Auto-update: a launch-time signal on the tag, not Sparkle
The M4Bookmaker shape, chosen over Sparkle: no framework, no appcast to host, no
EdDSA keys — and it ships **in v1.0 now** rather than delaying it. On launch (and
on demand), pālana asks GitHub for the latest release tag and, if it's newer than
the running build, **announces** it with a link to the release page. It never
installs anything — the operator clicks through and updates by hand.
- **The signal is the tag.** Cutting a release (a `vX.Y` GitHub Release) is what
  a running older build sees; the compare is `ReleaseVersion` (pinned in core).
- **In-app:** a quiet footer line (`vX.Y available ↗`, click to open) and a
  Settings › Updates section — current version, "Check now", the result.
- **bīja-consistent:** opt-out (`checkForUpdates`, default on), launch-only (no
  poll), one outbound call to GitHub, transparent in Settings. A dev build (no
  bundle version) never announces a phantom update.
- Sparkle (silent in-app install) stays a *later* option if the cadence ever
  wants it; the tag-announce is the right weight for v1.

### Decision 4 — The release cut: Payhip for the binary, GitHub for the source
The binary is **sold on Payhip**, not published as a public GitHub download.
So: build + notarize the `.dmg` locally, upload it to **Payhip** (his hands), and
cut a **notes-only GitHub Release** per version (tag `v1.0`, changelog, a link to
Payhip, **no binary attached**) — that public tag is what the update check reads.
The in-app links (Help menu, About, update announce) point at the **site**
(`palana.sageframe.net`, `/help`) and the public repo, never at a GitHub
download. Update the README off the beta framing (download → the site), and mark
the lifecycle `production`.

---

## Phase 2 — Execute (ho-12-AT-01)

- Verify + document the existing sign/notarize/dmg pipeline on a clean build.
- Re-export the 1024² icon; rebuild the `.icns`.
- Integrate Sparkle: framework embed, `SUFeedURL` + `SUPublicEDKey`, the
  EdDSA keypair (private key never committed — in the credentials store beside
  the notary profile), the "Check for Updates…" item + Settings toggle.
- Extend `RELEASING.md` and the release script: the tag step signs the dmg for
  Sparkle and publishes the appcast entry.
- Cut v1.0.

### Done means
- A clean checkout produces a signed, notarized, stapled `.dmg` in one command.
- The app carries a real 1024² icon.
- A tagged release publishes an appcast entry; a running older build detects it,
  shows the notes, and updates only on the operator's yes.
- README/RELEASING current; lifecycle `production`; v1.0 tagged and released.

---

## Phase 3 — Reflect
_Waits on the cut (does the notarize round trip cleanly; does the Sparkle update
install and relaunch; does the automatic check stay quiet enough). His hands and
a real weeks-long dogfood precede this — v1.0 ships when the product has proven
stable in daily use, not before._
