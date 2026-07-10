---
created: 2026-07-10
status: complete
type: ho-document
project: palana
ho: 9.7
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-08-the-surface-plan-and-enact
  - ho-10-the-workbench
agent-tasks:
  - Ho-9.7-AT-01.md
  - Ho-9.7-AT-02.md
---

# ho-9.7 — Design Polish

The polish ho was named at Checkpoint 3 and then kept landing early—fragments shipped inside other hos' hands sessions because the practitioner's eye doesn't wait for a slot. This ho consolidates the ledger: it names what already landed so the record stops owing it, and executes what's still queued. Design polish is a real deliverable in a tool whose whole thesis is terminal power under a calm native surface—the calm is engineering.

**Already landed, named here so the ledger closes** (the fragments live in ho-10's and the post-beta commits): the titlebar mark and the macOS 26 glass-platter resolution (each toolbar item wears its own OS platter—never fight it again), text zoom `⌘+`/`⌘-`/`⌘0` scaling pane rows and terminal mono together, header-click sort, the visible close on every summonable surface grown into title-bar rows (`OverlayCloseButton`, `OverlayHeader`), title-to-content spacing at ~8pt, toolbar and chip hover, the workbench chip grid, footer breathing room, the go/hold return-prompt color, moss toggles over system blue (9.2), the field/map drive glyphs over the diamonds (9.3).

**Still queued, this ho executes:** the NSMenu refit on his attributedTitle right-tab-stop spec, the plan panel's go-again verb keys styled as key glyphs, the terminal popout control in the pane, the palette-and-glyph pruning audit, and the help-card cmd-swallow verification debt.

**Out of scope:** proper NSTableView row hover (killed in ho-10—needs the underlying table view, not worth it yet). The f/F card-merge question (his hands kept them split; reopens only on his word). New surfaces of any kind. Andrew's icon churn in `design/`—his, untouched, always.

---

## Phase 1 — Think

### Decision 1 — The NSMenu refit lands where NSMenu lives, and names the SwiftUI boundary honestly

His spec: menu items carry the label left and the key hint right-aligned, `NSMenuItem.attributedTitle` with a right tab stop—the native menu look for sequence hints that can't be real key equivalents. The refit applies where the app owns the menu: the hand-popped host menu and any hand-built panel menus. SwiftUI-owned menus (the menu bar's commands, the table's context menu) regenerate their items outside our hands—the AT probes what a post-pass on `NSApp.mainMenu` survives, lands it only if it's stable across SwiftUI's rebuilds, and otherwise reports the boundary instead of shipping a menu that flickers back to plain titles. Sequence hints that stay SwiftUI-side keep the final spaced-suffix verdict.

### Decision 2 — The go-again keys become key glyphs, in place, transient

The finished panel's hint line—`esc hides · y m r R a t T go again`—styles each key as a small key-cap chip: rounded rect, mono glyph, faint at rest. His accepted-pending call from the ho-10 session: they stay in the hint line, contextual and transient, never a persistent rail competing with the tools strip.

### Decision 3 — The popout is one small control where the terminal's absence is felt

His ask: a control in the pane that pops the terminal. One glyph button on the pane footer's right edge (the terminal glyph, `ToolbarGlyphButton` voice), wired to the same show the backtick already owns. Both panes get it—it's about where the mouse is when the wish arrives.

### Decision 4 — Pruning is an audit with receipts, not a restyle

One pass over the app target: every color through a `Theme` token, icon sizes consistent within a surface family, no stray system blues, no orphaned styles. Deviations fixed where mechanical, reported where they're a taste call—the taste calls go to his hands, not into the diff.

### Decision 5 — The cmd-swallow debt closes with a verified reading

The old bug: the help card swallowed `⌘Q`. Both branches were fixed in different rounds; the debt is a verification, not a build—read the key monitor's card branches, confirm every cmd-chord passes through on every card, and record the reading in the report. If a branch still swallows, fix it in this diff.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. The ATs are independent—AT-02 does not wait on AT-01.

### Ho-9.7-AT-01 — The NSMenu refit

The attributedTitle right-tab treatment on the host menu, the main-menu post-pass probe, the honest boundary report. → `ho-process/agent-tasks/Ho-9.7-AT-01.md`

### Ho-9.7-AT-02 — Key glyphs, the popout, the pruning, the debt

The go-again key-cap chips, the pane-footer popout control, the palette/glyph audit with fixes, the cmd-swallow verification. → `ho-process/agent-tasks/Ho-9.7-AT-02.md`

### Done means

- Host-menu items carry right-aligned key hints in the native voice; the SwiftUI boundary is landed-or-named, never half-shipped
- The finished panel's go-again keys read as key caps; the hint line's rhythm survives
- A footer control pops the terminal from either pane
- The audit's mechanical fixes are in; its taste calls are listed for his hands
- The cmd-swallow reading is recorded (or the fix is in the diff)
- Verification rhythm green

---

## Phase 3 — Reflect

**The NSMenu refit's premise had dissolved, and the honest deliverable was the finding.** The queued snippet targeted menus carrying sequence-suffix key hints—and the app has none. The host menu's items are plain labels, there are no `.commands` builders (the menu bar is the OS default), and the only hint-carrying items live in SwiftUI context menus, where the spaced-suffix verdict already stands and an `NSApp.mainMenu` rewrite would flicker on regeneration. The agent shipped a helper applied to zero items—reverted in review; dead code is not infrastructure. If a hand-built menu ever grows key hints, the attributedTitle right-tab treatment is a twenty-line helper away, and this paragraph is where to find that decision.

**The chips and the popout landed as sealed.** Go-again keys wear key-cap chips in the transient hint line—contextual, faint, no persistent rail. Each pane's footer carries one terminal popout glyph on backtick's exact show path. Both are one-look hands questions.

**The audit found the palette already clean—the fragments-landing-early pattern did the pruning as it went.** No stray system colors, no dead style code. The taste-call ledger, untouched and left for his eye: the white ✕ on the alarm circle (traffic-light metaphor), the black scrim at 0.12 on the field and settings backdrops, the 15pt pālana mark, the 10/12pt label-vs-hint split in the workbench chips, the 11pt disclosure triangle, and the 10/11/12pt hierarchy inside the cards. Each reads as deliberate; none was changed.

**The cmd-swallow debt closes verified, not asserted.** The `!token.contains("cmd-")` guard in `handleActiveOverlay` covers the help, settings, and field branches uniformly; the panel's priority handler falls through to an unmatched grammar press. Every ⌘-chord passes through every surface. The reading is recorded with the guard lines in the AT report; no fix was needed.

**Closed by his hands (2026-07-10), which grew the polish past the ho's own scope.** The chips he asked to be "always there" became a permanent verb rail, dimmed while a plan runs. The floating keys panel then paid three rounds of debt in one day: a trapped drop-shadow reading as a border (the panel double-wrapped the card—chromeless now), a resize-too-small crash that persisted its own trigger (the crash-loop law was born: persisted state that crashes must never re-crash—clamp on restore, always), and finally his ruling that killed the whole continuous-scale system: five fixed sizes on ⌘1–⌘5, window and text as one value applied in one place, no edge-drag, no delegate feedback, nothing to fight. His close: "thats it. finially." The footer strip and the taste ledger went unremarked—they stand.

---

_Authored: 2026-07-10 (Think phase). Executed same day—two agent tasks on claude-sonnet-4-6, reviewed by the session; AT-01 produced a finding, not a diff. Seventh on the Checkpoint 3 slate—consolidated after its fragments kept landing early._
