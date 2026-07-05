---
created: 2026-07-05
status: draft
type: ho-document
project: palana
ho: 9.2
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-03-the-field
  - ho-09-the-surface-field-view
  - ho-9.1-rename-and-create
agent-tasks:
  - Ho-9.2-AT-01.md
  - Ho-9.2-AT-02.md
---

# ho-9.2 — Settings

The operator's defaults get a surface, and the github aliases finally leave the field. Two sealed directions from the third hands session govern: `# palana: hide` comments in `~/.ssh/config` are the host filter—the config stays the only registry, the marker lives in the operator's own file—and settings live in pālana's own popped panel first, mirrored to Apple's Settings scene, "for people who don't understand what it is." His words on the mechanism: "i love that that is the control, and palana:hide is the way to go."

**Out of scope:** verb-time overrides (choosing an alternate transport or flags at plan time)—that is plan-panel work, its own ho, not a stored default. Host onboarding—ho-9.5, full Think phase. Settings that nothing reads yet—the panel offers exactly what the system consumes today. Sync of settings between machines.

**Resolves deferred decisions:** none from the overview—born at Checkpoint 3 from the practitioner's sealed direction.

---

## Phase 1 — Think

### Decision 1 — The hide marker: one comment line inside the Host block

A line matching `# palana: hide` anywhere inside a `Host` block hides every alias that block declares. `SSHConfigParser` grows the awareness: the existing `hosts(in:)` keeps answering every alias (the Field's truth doesn't shrink), and a new `hiddenHosts(in:)` answers the marked set—the Surface subtracts. A hidden host disappears from the host menus and the field view but stays reachable by typed address: typing a name is explicit intent, and the filter is a curtain, not a lock.

### Decision 2 — Writing the marker: a pure text transform, a backup, an atomic write

The hide editor is a pure function in the core—`(config text, alias, hide/show) → new text`—that inserts or removes exactly one comment line in the right block and touches nothing else, byte for byte. Unit-tested against config shapes including multi-alias `Host` lines (hiding one alias of a shared block hides the block—the surface says so rather than pretending finer grain). The app side writes it: one backup at `~/.ssh/config.palana-backup` refreshed before every write, then the atomic replace, then a hosts reload. Tests operate on strings and temp files only—never the operator's real config, never a live host.

### Decision 3 — The rsync default rides PlanFacts, and the plan still shows everything

One transfer setting in v1: extra rsync flags, a string appended to every rsync compose (`--exclude .DS_Store` is the canonical want). `PlanFacts` grows `rsyncOperatorFlags: String?`—the engine stays pure, the operator's choice arrives as a fact, and the composed command in the panel carries the flags visibly like everything else. Empty means absent. No validation beyond trimming—the panel shows the exact command, and a bad flag fails typed at enactment, which is the system's honesty working.

### Decision 4 — Two surfaces, one model, cmd-comma summons

A `SettingsModel` owns the truth: the hidden-host set (read live from the config), the rsync flags (stored in `settings.json` beside `session.json` in Application Support). Surface one is pālana's own—an in-window card on the field view's machinery, summoned by `⌘,` and by the titlebar gear, which arrives now ("a small setting icon for when we get settings"—they exist as of this ho). Two sections: Hosts (every alias, a hide toggle each) and Transfers (the flags field). Surface two is the standard `Settings` scene—the same model, the same two sections, so the Mac's own muscle memory also lands somewhere true. Esc dismisses the card; the grammar stands down while a field is being typed in, the naming precedent.

### Decision 5 — Hidden means hidden everywhere the list renders

`PalanaSession.hosts` becomes the visible list (all minus hidden); the host menus, the go-to picker, and the field view all inherit the filter through it. The field view shows what the session shows—a hidden github alias stops renting space in the map. The settings card is the one place every host renders, hidden ones marked.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.2-AT-01 — The core: hide parsing, the hide transform, the flags fact

`SSHConfigParser.hiddenHosts(in:)`, the pure hide/show text transform, `PlanFacts.rsyncOperatorFlags` through the composes, full battery. → `ho-process/agent-tasks/Ho-9.2-AT-01.md`

### Ho-9.2-AT-02 — The Surface: the card, the gear, the mirror

`SettingsModel` + `settings.json`, the ⌘, card, the titlebar gear, the Apple Settings scene, the visible-hosts filter through the session, config writing with backup. → `ho-process/agent-tasks/Ho-9.2-AT-02.md`

### Done means

- Toggling a host hidden removes it from the menus and the field instantly, writes exactly one comment line into `~/.ssh/config` (backup refreshed first), and toggling it back removes exactly that line
- The rsync flags default appears in every rsync compose in the panel, visibly
- `⌘,`, the gear, and Apple's Settings all reach the same truth
- Verification rhythm green, coverage floor holds, no test ever touches the real config or a live host

---

## Phase 3 — Reflect

*To be filled after execution. Prompts: did the hide toggle feel instant? Did the shared-block grain surprise him? What does the settings card want next?*

---

_Authored: 2026-07-05 (Think phase)._
_Execution and Reflect: pending._
