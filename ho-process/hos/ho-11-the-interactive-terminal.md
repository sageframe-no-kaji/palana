---
created: 2026-07-10
status: complete
type: ho-document
project: palana
ho: 11
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-02-the-conduit
  - ho-08-plan-and-enact
  - ho-10-the-workbench
agent-tasks:
  - Ho-11-AT-01.md
---

# ho-11 — The Interactive Terminal

The shell the v1 chain always promised. ho-08's `EchoBuffer` made good on the echo — commands display, enactment streams, one way. This ho makes good on the other half: a real type-into-it terminal, per host, over the same trust surface every read and transfer already uses. Phase 5 is its own phase because this is its own animal: not a Workbench tool, not a plugin verb — a live PTY session the operator inhabits.

**Out of scope:** Tabs and multiplexing — one session per host. Session persistence across app restarts. Scrollback search. Local-shell polish beyond parity (the local shell is the same machinery pointed at `/bin/zsh -l` instead of ssh). tmux/screen integration.

---

## Phase 1 — Think

### Decision 1 — SwiftTerm, resolved at last (deferred decision 7, second half)

ho-08 weighed SwiftTerm for the echo and built `EchoBuffer` instead — right call, the echo needed no emulation. The interactive shell needs real emulation: cursor addressing, control sequences, alternate screens (vim, htop), colors. Building a VT emulator by hand is a project, not a ho. **SwiftTerm** (`migueldeicaza/SwiftTerm`, MIT, the established Mac terminal widget) enters `Package.swift` as the app target's dependency — PalanaCore stays dependency-free; the emulator is chrome, not engine.

### Decision 2 — The PTY is local; ssh carries it (the same trust surface, literally)

SwiftTerm's `LocalProcessTerminalView` runs a process on a forkpty and handles bytes, resize (TIOCSWINSZ), and termination. The process it runs is **the operator's own `ssh <alias>`** — the same binary, the same `~/.ssh/config`, the same ControlMaster sockets the Conduit already maintains, so sessions ride existing masters and open instantly. No parallel auth path, no credential ceremony — ssh or bust, exactly as sealed. The local shell is the same view running the user's login shell. PalanaCore is not involved: the Conduit's `run(on:_:)` contract is one command per exchange, and a PTY session is not that. The terminal goes THROUGH ssh beside the Conduit, not through the Conduit — stated plainly in code and docs.

### Decision 3 — The plan panel grows a third mode; monospace keeps one home

Kamae-2's claim: the plan panel is monospace's only home. A second monospace surface would split it. The plan panel region gains a **terminal mode**: summoned by `t` (terminal-focus grammar; `t` is unbound today), it replaces the transcript area with the live session for the focused pane's host, full height of the panel. Esc leaves terminal mode (the session stays alive underneath); the enactment-failure law holds — a failed plan forces the transcript back to front regardless of mode. One session per host, created lazily on first summon, kept alive until app quit; switching the focused pane switches which session shows.

### Decision 4 — The keyboard belongs to the shell while it shows

Terminal mode is inhabited: every key goes to the PTY except ⌘-chords (ho-9.7's law — ⌘Q, ⌘comma, the menus keep working) and the summon toggle path out. The window-level key monitor stands down by first-responder identity when the SwiftTerm view is key — the same stand-down discipline the naming field and path editing already use. Esc is the one seam: SwiftTerm wants Esc (vim), so **Esc passes to the shell; ⌘Esc leaves terminal mode.** The footer states both.

### Decision 5 — Fixture-only proof, live shells are the operator's

Automated tests cannot drive a PTY session meaningfully from this harness (the ho-09 lesson: hands sessions are the only interactive verification). The build proves: session spawn against the sshd container fixture, bytes round-trip (`echo marker` typed → marker read from the emulator's buffer), resize propagation, session-per-host isolation, teardown on quit. XCTest drives `LocalProcessTerminalView` headless where possible; what it can't reach, the hands session verifies (vim opens, htop paints, ⌃C interrupts).

---

## Phase 2 — Execute

One agent task — the shape is one seam (the terminal view + mode plumbing), not a decomposition.

### Ho-11-AT-01 — SwiftTerm in, terminal mode on the panel

`Package.swift` gains SwiftTerm (app target only). `TerminalSessionStore` (per-host `LocalProcessTerminalView` instances, lazy, quit teardown). PlanPanel terminal mode: `t` summons, ⌘Esc exits, failure law preserved, footer copy. Key-monitor stand-down by responder identity. Fixture tests per Decision 5. → `ho-process/agent-tasks/Ho-11-AT-01.md`

### Done means

- `t` at terminal focus opens a live shell on the focused pane's host; typing works; vim/htop render; ⌃C interrupts
- Sessions are per-host, survive mode exits, die at app quit
- ⌘-chords and the menus never reach the PTY; ⌘Esc always comes home
- A failing enactment surfaces its transcript over an open terminal
- Verification rhythm green; PalanaCore untouched (coverage floor moot — app-target work)

---

## Phase 3 — Reflect

**Built** (AT-01, `a4df114`): SwiftTerm 1.14.0 (app-target only, first project
dependency); a per-host `LocalProcessTerminalView` running the operator's own
`ssh <alias>` (same config, same masters); the plan panel's third mode; the
failure law wired (`onEnactmentFailed` surfaces the transcript over an open shell).

**Corrected in the eighth-block hands session** (the grammar reality):
- **⌘\` is the shell key, not ⌘Esc/`t`.** ⌘Esc provably never reaches the app (the
  system eats ⌘Esc and ⌘.), and `t` fired file-touch. ⌘\` toggles the keyboard
  into the shell and home; ⌘Esc also comes home from within.
- **`exit` is an ending, not a murder** (`0591f4e`): the store is the process
  delegate and drops dead sessions firing `onSessionEnded`; shell mode exits with
  a transcript note; SIGPIPE ignored app-wide. `exit` used to silently kill the
  whole app.
- **The focus model** (`682250f`): `shellMode` (the view) splits from
  `shellFocused` (the keyboard); ⌘\` MOVES the keyboard while the view stays. One
  law replaced the failure hook's special case — the plan owns the panel whenever
  an operation exists, the shell shows in the idle gaps.

**His hands verdicts (2026-07-15, fixture):** shell summons and types (1); vim /
htop render, ⌃C interrupts (2); ⌘\` focus in/out (3); ⌘-chords stay off the PTY
(5); `exit` dies clean and the app survives (6); a failing enactment surfaces its
transcript over the terminal (7). All pass.

**Open feel-question, banked (not a blocker):** the shell binds to the focused
pane's host at summon and does NOT follow pane focus — per-host, stateful,
switch by ⌘\`-home → focus the other pane → ⌘\`. His read: "shelled into whatever
pane you were in and then stuck there… something weird about the shell, might
just be comfort." Deliberate (a shell is a place, not a view that teleports
hosts), but if it keeps reading wrong it's a **design rethink** — should the shell
follow the focused host, should host-switching be one keystroke — and that's its
own future ho, not a patch.

---

_Authored: 2026-07-10 (Think phase, top tier). Ran in a worktree parallel to
ho-10.3; merged into `integration-shell-panemode` (2161be8). The practitioner
ratified the parallel run mid-session ("I DO want to wire up the terminal and the
pane solution"). Closed 2026-07-15 on his hands verdicts._
