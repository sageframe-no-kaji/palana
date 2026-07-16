---
created: 2026-07-15
status: ready
type: ho-document
project: palana
ho: 13
kamae: 5
shape: ha
phase: 6 — the v1 polish
builds-on:
  - kamae-2-palana-system-design
  - design/palana-design-system.md
---

# ho-13 — Universal text-scale

Today only the "keys" panel scales its type; the rest of the surface is hardcoded
`.font(.system(size: N))`. This ho makes **⌘+ / ⌘− / ⌘0 zoom the whole surface** —
every chip, footer, path, and row — through one persisted scale factor, exactly as
the design system §3 already prescribes ("body text multiplies by a user
`fontScale` … thread a single scale factor rather than hard-coding sizes").

**Out of scope:** the SwiftTerm terminal font — it has its own sizing and stays
independent (note it, don't touch it). No per-view scale overrides; one global
factor.

---

## Phase 1 — Think

### Decision 1 — One factor, one font factory
`Theme` gains `fontScale` (a `Double`, persisted via `@AppStorage("fontScale")`,
default `1.0`) and a factory:
`Theme.font(_ size: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font`
returning `.system(size: size * scale, weight: weight, design: design)`. Because
`@AppStorage` can't be read from a static, the scale is held on an
`@Observable`/`ObservableObject` app-scope model (mirror how the keys panel's size
already flows) and the factory reads it; if a static seam is cleaner in this
codebase, a `Theme.scale` current-value read is acceptable so long as changing it
re-renders. The pure `size * scale` math lives in a testable function.

### Decision 2 — Every `Text` routes through the factory
Sweep `Sources/Palana/` for `.font(.system(size:` and `Font.system(size:` and
route each through `Theme.font(...)`. The monospace zones (plan/command area, key
caps — design system §3) pass `design: .monospaced`. This is the broad,
mechanical heart of the ho — miss none, or the surface zooms unevenly.

### Decision 3 — The keys and the global chords
`⌘+` (and `⌘=`) steps scale up, `⌘−` down, `⌘0` resets to `1.0`. Steps of `0.1`,
clamped to `[0.8, 1.6]` (a tight, legible range — the design system's 10–14pt
world must stay coherent). Bind in the main key grammar, not a menu; the existing
keys-panel stepped sizing folds onto this one factor (its ⌘1–5 may remain as
presets that set `fontScale` to fixed values, or be retired — builder's call,
noted in Reflect).

### Decision 4 — Persistence and reset
`fontScale` persists across launches (`@AppStorage`). `⌘0` is the escape hatch.
On a corrupt/out-of-range stored value, clamp on read (never crash on restore —
the ho-9 keys-panel law).

---

## Phase 2 — Execute (ho-13-AT-01)

- `Theme.fontScale` + `Theme.font(...)` factory (pure `size*scale`, tested).
- Global `⌘+`/`⌘=`/`⌘−`/`⌘0` handlers stepping/clamping/resetting the factor.
- The full sweep of `Sources/Palana/` font call sites onto `Theme.font(...)`.
- Persist via `@AppStorage`; clamp on read.
- Leave SwiftTerm's font path untouched.

### Done means
- ⌘+/⌘−/⌘0 visibly zoom **all** UI text — chips, footers, rows, panels — smoothly.
- The terminal font is unaffected.
- Scale persists across relaunch; ⌘0 resets; out-of-range restores clamp.
- Tests: the `size*scale` math, the clamp bounds, the persistence default.
- Verification rhythm green; PalanaCore coverage floor held (this is app-target
  work — cover the pure scale math).

---

## Phase 3 — Reflect
_Waits on execution and his hands (does the whole surface zoom coherently; is the
0.8–1.6 range right; do the keys-panel presets stay or retire)._
