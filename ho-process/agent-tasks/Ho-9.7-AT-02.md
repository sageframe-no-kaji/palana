---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.7
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.7-AT-02 — Key glyphs, the popout, the pruning, the debt

**Goal**

Four bounded polish items: the finished panel's go-again keys styled as key-cap chips, a terminal popout control on each pane's footer, the palette/glyph pruning audit with mechanical fixes, and the help-card cmd-swallow verification. Independent of AT-01.

**Context**

ho-9.7 Decisions 2–5 govern (read `ho-process/hos/ho-9.7-design-polish.md`). Read:

- `Sources/Palana/PlanPanel.swift` (~line 122) — the hint line `esc hides · y m r R a t T go again` and how hints render per phase.
- `Sources/Palana/Theme.swift` — tokens. The workbench chips and `ToolbarGlyphButton` (find it) — the hover/voice precedents.
- The pane footer: find where each pane's footer/status strip renders (PaneView or a sibling) and where `OperationModel.showPanel()` lives (the backtick's target).
- The key monitor: `installKeyMonitor` / `handleHelpKey` / the card branches in `Sources/Palana/PalanaSession.swift` and friends — for the cmd-swallow reading.

**Required Changes**

1. **Key-cap chips** (Decision 2) — in the finished/failed/cancelled hint line, each verb key (`y m r R a t T`, and `esc`) renders as a chip: rounded rect (~3pt radius), `Theme.groundDeep` fill, hairline `Theme.inkFaint` stroke, mono glyph at the hint's size, inkFaint at rest. The connective words stay plain text. Extract a small `KeyCapChip` view; keep the line's height stable (chips must not grow the footer). Apply the same chip to other transient key hints in the panel ONLY if they share the exact hint-line mechanism — do not hunt new surfaces.

2. **The popout** (Decision 3) — one glyph button (SF Symbol `terminal` or `rectangle.bottomthird.inset.filled` — pick what reads at 12–13pt; note the choice) at the right edge of each pane's footer, `ToolbarGlyphButton` hover voice, `.help("terminal")`, wired to the exact show path backtick uses (`OperationModel.showPanel()` — visibility only, no phase change). Hidden while the panel is already visible if the footer knows; if plumbing visibility costs more than a line or two, always-shown is fine — it's a toggle-shaped wish either way (then wire toggle, matching backtick exactly).

3. **The pruning audit** (Decision 4) — sweep `Sources/Palana/` for: colors not drawn from `Theme` (raw `Color(...)`, `.blue`, `.red`, `NSColor` literals outside Theme.swift), SF Symbol point sizes that differ within one surface family (toolbar glyphs, card headers, footer glyphs), and dead style code. Fix what is mechanically unambiguous (a stray `.secondary` where siblings use `Theme.inkFaint`). LIST what is a taste call (a size that might be deliberate) in your report — do not change taste calls. `design/` is untouchable.

4. **The cmd-swallow reading** (Decision 5) — trace every overlay/card branch of the key monitor and answer per-surface: does a `⌘`-chord (⌘Q, ⌘W, ⌘,) pass through while that surface is open? Record the per-branch reading in your report, quoting the guard lines. If any branch swallows cmd-chords, fix it in the established pattern (the panel branch's release of cmd chords is the precedent) and say so.

**Battery**

App-target only — no test target. If `KeyCapChip` grows layout logic worth testing, it hasn't — keep it a dumb view.

**Do Not**

- Do not restyle anything beyond the four items.
- Do not touch `design/`, the tools strip, or the titlebar cluster.
- Do not add a persistent verb-key rail — the chips live in the transient hint line only.

**Acceptance**

- [ ] Chips in the go-again line, footer popout on both panes, audit fixes in with taste calls listed, cmd-swallow reading recorded per surface.
- [ ] Full suite passes; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; `swift build` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

SourceKit phantom errors on app files: `swift build` is the type checker of record.

**Commit**

Do not commit. The session reviews and commits.
