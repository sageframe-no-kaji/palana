# Phase 6 — the v1 polish: run ALL four, end to end

This is the orchestration brief for a fresh Claude Code session. Execute all four
hos in one run. Do not stop between them for approval — build, verify, commit,
move to the next. Surface only a genuine blocker (halt-on-surprise).

## The four (each ho document IS its spec — read it, build to it)

Execute in this order (they are independent subsystems; order only minimizes
Theme.swift churn):

1. `ho-process/hos/ho-13-universal-text-scale.md` — ⌘+/−/0 zoom the whole surface via one persisted fontScale + a `Theme.font()` factory.
2. `ho-process/hos/ho-15-dark-mode.md` — port Sharibako's `Palette` pattern + the dark values into `Theme`; System/Light/Dark toggle. (13 and 15 both touch `Theme.swift` — sequential, so no conflict.) **Read the reference impl first:** `~/Vaults/sageframe-no-kaji-dev/sharibako/Sources/Sharibako/Color+Theme.swift` and `.../AppAppearance.swift`.
3. `ho-process/hos/ho-14-drag-into-folders.md` — folder rows become drop targets; accent hover wash; falls through to pane cwd.
4. `ho-process/hos/ho-16-the-preview-pane.md` — a third pane mode (`v`) that previews the other pane's cursor: local text (scrollable mono), image/PDF (QuickLook), info card. Local only for v1.

## First, orient (do this before touching code)

Read, in order: `CLAUDE.md`, `ho-process/kamae-2-palana-system-design.md`, then
each ho doc as you reach it. The design system is `design/palana-design-system.md`
(gitignored but present locally) — every visual decision honors it: warm, calm,
one moss accent, one rust alarm, depth from opacity not new colors.

## Branch

Work on a new branch off `main` (which is at tag `v0.5`):
`git switch -c phase-6-v1-polish`. One atomic commit per ho. Do NOT merge to main
or tag — that's the practitioner's hands-review after.

## Per-ho loop (every one of the four)

1. Read the ho doc. Its Phase-1 Think decisions are SEALED — build to them, don't
   re-litigate. If one is genuinely unbuildable, halt and say so.
2. Implement. Match the surrounding idiom, comment density, naming — read
   neighboring code before editing. Swift 6 strict; explicit access modifiers; no
   force-unwrap without `// FORCE:`. Tests are specification — write them alongside.
3. Verification rhythm — ALL green before commit:
   - `swift-format lint --recursive --strict Sources Tests`
   - `swiftlint lint --strict`
   - `swift build`
   - `swift test`
4. One atomic commit, subject in the project's terse voice (see `git log --oneline`).

## Hard rules (non-negotiable)

- **NO AI attribution tags** anywhere — no `Co-Authored-By`, no "Generated with
  Claude Code", no contributor credit. Strip any template that adds them.
- **Fixtures only. Never mutate a live homelab host.** This is UI/Theme/pane work —
  it should not touch hosts at all. Don't start or drive the running app or the
  fixture VM; unit tests only.
- **PalanaCore coverage floor ≥90%.** These are app-target-heavy — cover the pure
  logic (scale math, palette `resolved(dark:)`, drop destination resolution,
  preview routing) in core/model; the declarative `View` bodies are the excluded
  part.

## About `swift test` and the sshd fixture

If Docker is down, ~19 sshd-fixture integration tests fail with
`connect localhost:2223 refused`. Those are **pre-existing and environmental**, not
your regressions — they pass under CI with the fixture up. Confirm the ~762
non-sshd tests stay green and your new tests pass. Do NOT try to "fix" them.

## When all four are done

Report per ho: commit SHA, what changed, the `swift test` count, and anything you
had to decide the ho doc didn't cover (halt-and-name, never silently choose
architecture). Leave the branch for the practitioner's hands review — dark-mode
look, preview feel, drag-into-folders, and the text-scale sweep all want a human
eye before merge. ho-12 (the ship — packaging/notarization) is separate and runs
after these land.
