---
created: 2026-07-15
status: ready
type: ho-document
project: palana
ho: 15
kamae: 5
shape: ha
phase: 6 — the v1 polish
builds-on:
  - design/palana-design-system.md
reference-implementation: /Users/atmarcus/Vaults/sageframe-no-kaji-dev/sharibako/Sources/Sharibako/Color+Theme.swift
---

# ho-15 — Dark mode

pālana's `Theme` is hardcoded light-only literals. This ho makes every token
appearance-aware and adds a System / Light / Dark toggle. It is a **port, not a
design gamble**: the sibling project **Sharibako** already built dark mode for
*this exact design system*, and its own code says its dark values are "the
candidate to bring pālana in line later." We bring pālana in line.

**Reference (read it first):**
`~/Vaults/sageframe-no-kaji-dev/sharibako/Sources/Sharibako/Color+Theme.swift`
(the `RGBA` / `Palette` / dynamic-`NSColor` pattern) and
`.../Sharibako/AppAppearance.swift` (the System/Light/Dark model).

**Out of scope:** per-view dark overrides; theming the terminal (SwiftTerm renders
its own colors). Keep the warm register — never pure black/white, one moss accent,
one rust alarm (design system §1–2).

---

## Phase 1 — Think

### Decision 1 — Port Sharibako's Palette pattern
Introduce, in pālana's `Theme.swift`:
- `struct RGBA: Sendable, Equatable { red, green, blue, alpha: Double; var nsColor }`
- `struct Palette: Sendable, Equatable { let light, dark: RGBA; func resolved(dark:) -> RGBA; var nsColor (dynamic NSColor(name:nil){appearance in …}); var color: Color }`
Each `Theme` token becomes a `Palette(light:dark:)` exposing `.color`. The dynamic
`NSColor` re-resolves on appearance change with **no asset catalog**. The pure
`resolved(dark:)` seam is unit-tested per token (no running scene needed).

### Decision 2 — The dark palette (authoritative values, from Sharibako)
Map pālana's eight tokens to light (design system §2, unchanged) + dark:

| Token | light (sRGB) | dark (sRGB) |
|---|---|---|
| `ground` | 0.9804, 0.9686, 0.9529 | 0.1059, 0.1020, 0.0902 |
| `groundDeep` | 0.9569, 0.9451, 0.9176 | 0.1412, 0.1333, 0.1176 |
| `ink` | 0.1137, 0.1059, 0.0941 | 0.9255, 0.9059, 0.8745 |
| `inkFaint` | ink @ 0.55α | ink-dark @ 0.60α |
| `accent` | 0.3529, 0.4588, 0.3216 | 0.4941, 0.6078, 0.4471 |
| `panelGround` | 0.9294, 0.9333, 0.9451 | 0.1255, 0.1333, 0.1647 |
| `alarm` | 0.5961, 0.3020, 0.2353 | 0.7725, 0.4196, 0.3412 |
| `plugin` | 0.58, 0.36, 0.18 | **derive** ~0.75, 0.54, 0.32 |

`plugin` (burnt umber) is pālana-specific — Sharibako has no equivalent. Derive its
dark by the same "lift toward warm+bright" ratio the accent/alarm pairs show
(light→dark lifts luminance while holding hue); the suggested value keeps it
distinct from the lifted moss and rust. Tune in-flight if it muddies against
accent; note the final value in Reflect.

### Decision 3 — The appearance toggle
Port `AppAppearance` (`.system`/`.light`/`.dark`, `@AppStorage("appearance")`,
`.colorScheme` mapping) and apply `.preferredColorScheme(appearance.colorScheme)`
at the window root. Add a Settings row (a segmented/picker control) bound to the
same stored key. `.system` (nil) follows the OS.

### Decision 4 — No view spells a hue
Audit every `Color(red:…)`, `Color.white/.black/.gray`, and `NSColor` literal
across `Sources/Palana/` and route each through a `Theme` token's `.color`. The
opacity system (design system §4) stays — apply opacity to the token color, not a
new literal. A hardcoded hue that survives the audit is the bug this ho exists to
kill.

---

## Phase 2 — Execute (ho-15-AT-01)

- The `RGBA`/`Palette` layer in `Theme.swift`; all eight tokens as `Palette`.
- `AppAppearance` + `@AppStorage("appearance")` + `.preferredColorScheme` at root.
- Settings picker bound to the appearance key.
- The full hue-literal audit across the views onto `Theme` tokens.
- Unit tests: `resolved(dark:)` per token (light + dark values pinned);
  `AppAppearance.colorScheme` mapping.

### Done means
- Flipping System/Light/Dark in Settings recolors the whole surface; `.system`
  follows the OS live.
- Dark is warm and legible — never pure black/white; moss accent and rust alarm
  read correctly; no light-mode hue leaks through in dark.
- No view holds a raw hue; every color is a `Theme` token.
- Tests pin every token's light+dark and the appearance mapping.
- Verification rhythm green; the `Theme`/`Palette` seam is testable and NOT
  coverage-excluded (only the declarative `View` bodies are). Coverage floor held.

---

## Phase 3 — Reflect
_Waits on execution and his hands (does dark hold the notebook voice; is `plugin`'s
derived dark right; any hue-leak the audit missed; does `.system` switch live)._
