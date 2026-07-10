---
created: 2026-07-09
updated: 2026-07-09
status: living
type: state-memory
project: palana
stage: kamae-6
kamae-chain: seed → system-design → readme → ho-overview → hos → **state-memory**
---

# pālana — State Memory (Kamae 6)

The fixed handoff surface. Every session and ho closes by updating the
state-summary block below — verbatim field labels, parseable shape — so the next
session (and any hook) knows exactly where the build stands. Newest block on top.

---

## State summary — 2026-07-09

**COMPLETED**
- Shipped **v0.4-beta** — the first public build — as a signed, notarized macOS
  `.dmg` on GitHub Releases (prerelease). App + dmg both notarized and stapled;
  Gatekeeper-accepted (`source=Notarized Developer ID`, team `3N8F759K8D`).
- Built the macOS release pipeline, effectively ho-12's ship machinery, ahead of
  its ho: `scripts/build_macos.sh` (universal `arm64+x86_64` build → hand-
  assembled `.app`, `Package.swift` stays canonical, no Xcode project → sign →
  notarize app then dmg → staple both), `scripts/entitlements.plist` (hardened
  runtime, empty by design — pure Swift, no dynamic code), and `RELEASING.md`.
- App icon in place (`packaging/palana.png`, built to `.icns` at build time;
  generated `.icns` gitignored). Bundle id `com.sageframe.palana`, min-macOS 14.
- README brought to v0.4-beta: beta download callout + feedback ask up top,
  Download section points at the release, license confirmed GPL-3.0. Reconciled
  the interactive terminal to a **v1.0** feature (Kamae-4 Phase 5), removing the
  stale "post-v1" entry.
- Repo made public-facing: description + homepage set; already public, GPL-3.0.

**NEXT**
- **ho-10.1 — the mutating ZFS Workbench tool** (dataset management, snapshots,
  pools), Phase 4, core unmodified. Then ho-11 (terminal), ho-12 (formalize the
  ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks.
- Non-blocking: the beta icon source was 1024×**1059** (not square); padded to a
  transparent square to avoid squish/clip. For v1.0, re-export a true 1024²
  square and rebuild (one command).
- Non-blocking: the ship pipeline now exists ahead of ho-12; when ho-12 opens it
  formalizes what's already built rather than starting cold.
- Notarization uses keychain profile `palana-notary`; signing identity
  `Developer ID Application: ANDREW TODD MARCUS (3N8F759K8D)`. See `RELEASING.md`.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. (Was `dev` through Phases 1–3 + the ho-9.x surface
  run.) Engine + Surface complete; ZFS Workbench tool and terminal remain before
  v1.0 / `production`.

---

## Build record (release tags)

| Tag | What it marks |
|---|---|
| v0.1 | Phase 1 — foundation verified, go/no-go answered *go* |
| v0.2 | Phase 2 — PalanaCore headless engine complete (173 tests, 97.69% cov) |
| v0.3 | Phase 3 — the Surface: panes, plan → enact, field view |
| v0.4 | Surface UX run complete — favorites, host onboarding, settings, mounts |
| **v0.4-beta** | First public build — signed, notarized `.dmg` on Releases |
