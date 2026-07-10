---
created: 2026-07-10
type: agent-task
project: palana
parent-ho: 9.7
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.7-AT-01 — The NSMenu refit

**Goal**

Menu items that carry key hints get them right-aligned in the native voice: `NSMenuItem.attributedTitle` with a right tab stop, applied where the app owns the NSMenu. Probe the SwiftUI main-menu post-pass; land it only if stable; report the boundary honestly either way.

**Context**

ho-9.7 Decision 1 governs (read `ho-process/hos/ho-9.7-design-polish.md`). Read:

- `Sources/Palana/HostMenuButton.swift` (~lines 74–125) — the hand-popped NSMenu (hosts, favorites section with scope toggles, type-an-address, edit-config, reload). This is the guaranteed landing zone.
- Search the app target for other hand-built NSMenus (KeysPanel, HostMapPanel, FavoritesPanel may pop them) and any menu item whose title carries a trailing spaced key hint (the `"star this location    ⇧⌘8"` pattern lives in a SwiftUI contextMenu — note it, leave it).
- The app's menu bar: find the `.commands` builders (search for CommandMenu/CommandGroup in Sources/Palana). Identify which items carry sequence hints as title suffixes.

**Required Changes**

1. **The treatment, one helper** — a small utility (e.g. `Sources/Palana/MenuKeyHint.swift`): given a label and a hint string, produce the `NSAttributedString` — label, tab, hint — with an `NSMutableParagraphStyle` carrying one right-aligned `NSTextTab` sized to the menu's width (compute from the menu font and the widest item, or use a generous fixed stop consistent across the menu), hint in the menu font with `.secondaryLabelColor`. Apply the same font NSMenu uses (`NSFont.menuFont(ofSize: 0)`) so the attributed title doesn't shift the item's metrics.

2. **Host menu** — every item that has a key hint (and the favorites scope-toggle sub-items if they carry hints) gets the treatment. Items without hints stay plain-title. Verify the menu still popUps at the right width (attributed titles change sizing — the right-pin math at popUp must still hold; read it).

3. **The main-menu probe** — if `.commands` items carry sequence-suffix titles: prototype a post-pass that walks `NSApp.mainMenu` (via an `NSMenuDelegate` or a `menuWillOpen` hook on the app delegate) rewriting suffixed titles to attributed form. Test it by hand-launching the app (`swift run Palana` builds — you cannot drive the UI, but you can verify the pass compiles and is wired). If SwiftUI's menu rebuilding makes the pass unreliable BY YOUR READING of how the items are regenerated, do not ship it — remove the prototype and report the boundary with the reasoning. A menu that flickers between styles is worse than the spaced suffix.

4. **No behavior changes** — actions, targets, enabled states, and ordering are untouched everywhere.

**Battery**

App-target only — no test target. The attributed-string builder is pure enough to live in core if any real composition logic accrues (tab-stop math beyond a constant); if it stays a 20-line AppKit helper, app-side is right.

**Do Not**

- Do not convert SwiftUI contextMenus or commands to NSMenu.
- Do not change which keys/hints exist — presentation only.
- Do not ship the main-menu pass if it's unstable; the report is the deliverable then.

**Acceptance**

- [ ] Host-menu hints right-aligned in the native voice, sizing intact; other hand-built menus treated where hints exist; main-menu pass landed-or-reported.
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
