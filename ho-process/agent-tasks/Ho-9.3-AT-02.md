---
created: 2026-07-05
type: agent-task
project: palana
parent-ho: 9.3
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.3-AT-02 — The Surface: the pinned panel, the summons, the hollow diamond

**Goal**

The host map becomes visible: a floating pinned panel on the KeysPanel lineage rendering `HostMap`, summoned by `F` and a titlebar glyph, with per-host probe buttons, and the pane rows grow ◇ beside ◆—the plain-mount boundary mark. Requires Ho-9.3-AT-01 landed.

**Context**

ho-9.3 Decision 4: the practitioner asked for "an info pane, like ??, pulled up from the top bar menu"—pinned, floating, alive while the panes work. The `??` machinery is `KeysPanel.swift`: a hand-built borderless NSPanel owned by a controller singleton, with Esc and chords handled in the key monitor *by window identity*, because SwiftUI's Window scene reasserted titlebars and stale frames three rounds running and the responder chain lost `onExitCommand`. That law governs here. Read before writing: `KeysPanel.swift`, `FieldOverlay.swift` (fact-line rendering and the probe pattern), `PalanaSession.swift` (monitor, `handle`, the `f` special case), `SurfaceView.swift` (toolbar), `PaneModel.swift` (`commit`, `isDatasetMountpoint`), `PaneView.swift` (where the ◆ renders), `SettingsCard.swift` (type-splitting discipline—SwiftLint's type-body budget is real, split subviews early).

**Files**

- Create: `Sources/Palana/HostMapPanel.swift` (controller + panel + content views; split into a second file if the type-body budget threatens)
- Modify: `Sources/Palana/PalanaSession.swift` (own the model, `F` toggle, monitor identity branch)
- Modify: `Sources/Palana/SurfaceView.swift` (titlebar glyph)
- Modify: `Sources/Palana/PaneModel.swift` (gather mount targets at commit, boundary-mark resolution)
- Modify: `Sources/Palana/PaneView.swift` (render ◇ beside ◆, tooltips)
- Modify: `Sources/Palana/HelpOverlay.swift` (the `F` vocabulary line)

**Required Changes**

1. **`HostMapModel`** — `@MainActor @Observable`, the `FieldViewModel` pattern: holds a `HostMap?`, a `probing: Set<String>`, `probeErrors: [String: String]`. `refresh(hosts:)` reads `engine.field.allFacts()` and rebuilds (local first, the `summon` ordering). `probe(_ host:)` mirrors `FieldViewModel.reprobe`: guard local and in-flight, `discover`, record a plain-sentence error on throw, rebuild after. The session owns one instance beside `fieldViewModel`.

2. **`HostMapPanelController.shared`** — the KeysPanel lineage, adapted:

   - Identifier `palana-hostmap-window`. Borderless, `.nonactivatingPanel`, `.resizable`, floating level, `canBecomeKey`, movable by background, content ground filling the frame to a rounded edge (no band—the law).
   - Free resize with a sane `minSize`—no aspect lock, the content scrolls. Frame remembered via `setFrameAutosaveName`.
   - `show(model:)` refreshes the model then fronts the panel, `toggle(model:)` for the summons, `close()`. One instance, `windowWillClose` clears it.

3. **The content view** — renders `hostMap.sections` in a `ScrollView`, the card ground and type scale of the field card, hosts at 14pt medium (the settings round-three verdict):

   - Per section: alias + the fact line (`FieldOverlay`'s voice: "this machine" / "never visited" / "probing…" / "reachable · 2h ago" / plain-language refusals through `FieldOverlay.plainRefusal`), the flavor/zfs/rsync tokens, and a quiet `probe` text button (hidden for local, "probing…" while in flight).
   - Mount rows indented under the section: `◆` (accent) when `isDatasetMountpoint`, `◇` (ink-faint) otherwise, then target (ink, medium), fstype (ink-faint), source (ink-faint, middle-truncated), and an `ro` token when read-only.
   - After the rows, when `systemMountCount > 0`: "N system mounts not shown" at 10pt ink-faint. When mounts were never gathered: "not yet asked—probe gathers the ground".
   - The mounts age renders once per section when present ("ground as of 2h ago", `FieldAge.describe`).
   - Footer: `esc closes · probe refreshes a host · ◆ dataset · ◇ mount`.
   - Split subviews freely—section view, row view—keeping every type inside the lint budgets.

4. **Session wiring.**

   - `F` beside the `f` special case in `handle`—bare token `"F"`, `pendingPrefix` empty—toggles the panel through the controller with the session's model and `hosts`.
   - The key monitor's identity branch grows the map panel: Esc closes it, nothing else is consumed. Follow the existing KeysPanel branch shape exactly.
   - The panel is independent of the in-window overlays: opening help, settings, or the field view does *not* close it, and the `helpVisible` onChange in `SurfaceView` keeps closing only the keys panel.

5. **The titlebar glyph.** A third `paneVerb` in the toolbar's trailing cluster—`server.rack`, help text "the host map — F"—placed before the gear. It toggles the panel exactly as `F` does.

6. **The hollow diamond.** `PaneModel.commit` gathers, in the same no-wire facts hop, `MountTable.targetSet` from the remembered mounts fact (empty for local, absent facts, or no fact—the `datasetMountpoints` shape). A `boundaryMark(for row:)` resolution replaces the bare `isDatasetMountpoint` call site in `PaneView`: dataset mountpoint → ◆ (unchanged rendering), plain mount target → ◇ at the same size in ink-faint. Tooltips: "dataset mountpoint — a filesystem boundary" / "mount point — a filesystem boundary".

7. **The vocabulary.** `HelpOverlay` actions gain `F` → "host map — floats". Nothing else in the card changes.

**Do Not**

- Do not host the panel in a SwiftUI `Window` scene, a sheet, or an in-window overlay. The hand-built NSPanel is the law, written in blood across three rounds of ho-08 errata.
- Do not make the map modal, give it a keyboard cursor, or wire pointing from its rows—out of scope, feedback rounds decide.
- Do not add probe-all. Per-host only.
- Do not add `F` to the `Grammar.bindings` table—`f`'s special-case-in-`handle` is the precedent (the bindings dispatch pane intents, the summons are session verbs).
- Do not modify PalanaCore. AT-01 landed everything the surface needs—if something is missing, stop and surface it.

**Stop Condition**

If the panel machinery fights the monitor or the nonactivating focus in a way the KeysPanel precedent does not answer, stop and surface rather than reaching for a Window scene or a third event path.

**Acceptance**

- [ ] `swift build` clean
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift test` green — the full existing suite, nothing skipped that ran before
- [ ] `swift run Palana` against the fixture config shows: `F` summons the panel, it floats while panes navigate, Esc closes it, the glyph toggles it, probe fills a never-visited host in place
- [ ] The fixture host's pane rows wear ◇ at mount boundaries after a probe (and ◆ still renders on the zfs fixture when it is up—do not start the VM for this, assert only if already running)

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test 2>&1 | tail -20   # then check the run line itself
scripts/sshd-fixture.sh start
PALANA_SSH_CONFIG=.fixtures/ssh_config swift run Palana   # hands check per acceptance
```

**Commit**

Single commit. Message format:

```
ho-9.3: the host map — pinned, summoned, and the ground marked

HostMapPanel on the KeysPanel lineage (F + titlebar server.rack,
esc by window identity), per-host probe, mounts rendered storage and
network with the system count named. Pane rows: ◆ dataset, ◇ mount.
```

No AI attribution tags, no Co-Authored-By—categorical.
