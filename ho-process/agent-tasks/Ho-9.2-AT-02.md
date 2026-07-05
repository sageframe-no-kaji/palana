---
created: 2026-07-05
type: agent-task
project: palana
parent-ho: 9.2
task: 02
model: claude-sonnet-4-6
status: ready
---

# Ho-9.2-AT-02 — The Surface: the card, the gear, the mirror

**Goal**

Settings become real: a `SettingsModel` over `settings.json` and the live ssh config, an in-window card summoned by `⌘,` and the titlebar gear, the standard Apple `Settings` scene over the same model, the visible-hosts filter through the session, and config writes with a backup. Depends on Ho-9.2-AT-01 being in the tree.

**Context**

ho-9.2 Decisions 1–5 govern (read `ho-process/hos/ho-9.2-settings.md`). AT-01 is in the tree: `SSHConfigParser.hiddenHosts(in:including:)`, the `hiding(alias:in:)`/`showing(alias:in:)` transforms (nil = no-write, including the alias-in-included-file case), `PlanFacts.rsyncOperatorFlags`. Read whole before writing: `Sources/Palana/PalanaSession.swift` (hosts list, `reloadHosts`, `editSSHConfig`, the key monitor's mode branches and stand-downs, `sshConfigURL`), `Sources/Palana/FieldOverlay.swift` (the card pattern to mirror), `Sources/Palana/SurfaceView.swift` (overlays, the toolbar), `Sources/Palana/OperationModel.swift` (where PlanFacts are assembled in `gather` — the flags join there), `Sources/Palana/App.swift` (the scene — the `Settings` scene joins it), and how `SessionStore`/`session.json` persistence works for the `settings.json` sibling.

**Files**

- Create: `Sources/Palana/SettingsModel.swift` (model + store + config writing)
- Create: `Sources/Palana/SettingsCard.swift` (the in-window card + the shared form the Settings scene reuses)
- Modify: `Sources/Palana/App.swift` (the `Settings` scene)
- Modify: `Sources/Palana/PalanaSession.swift` (visible-hosts filter, `⌘,` handling, settings visibility state, monitor stand-down while a settings field types)
- Modify: `Sources/Palana/SurfaceView.swift` (the gear `ToolbarItem`, the card overlay)
- Modify: `Sources/Palana/OperationModel.swift` (rsyncOperatorFlags into gathered facts)
- Modify: `Sources/Palana/HelpOverlay.swift` (`⌘,` row)

**Required Changes**

1. **`SettingsModel`** — `@MainActor @Observable`. Holds `rsyncFlags: String` persisted in `settings.json` beside `session.json` (same Application Support directory discipline, atomic write, corrupt-reads-as-empty), and answers host visibility from the parser: `allHosts` (every alias + hidden marking, from the config text) and the hide/show verbs. A hide/show verb: read the config text, run the AT-01 transform, nil → set a one-line notice on the model (e.g. "managed in an included file") and write nothing; otherwise refresh `~/.ssh/config.palana-backup` with the PREVIOUS text, atomic-write the new text, then tell the session to reload hosts. The config path comes from the session's existing `sshConfigURL` — respect `PALANA_SSH_CONFIG` exactly as the session does (the fixture keeps tests and dev launches off the real file).

2. **Visible hosts through the session.** `PalanaSession.hosts` becomes all-minus-hidden (recomputed on `reloadHosts` and after every hide/show). The menus, go-to, and field view already read `session.hosts` — verify they inherit, change nothing they don't need. Typed addresses stay unfiltered (Decision 1: the filter is a curtain, not a lock).

3. **The card** — `SettingsCard` on the field-overlay pattern (centered card, dimmed ground, Esc dismisses). Two sections: **Hosts** — every alias with a hide toggle, hidden ones rendered faint, the included-file notice shown when set; **Transfers** — one labeled text field for the rsync flags ("appended to every rsync command", monospaced), committing on submit/blur into the model. While any settings field is focused the key monitor stands down (the naming/pathEditing precedent — a flag the session checks). Mutual exclusion with help and field overlays, both directions, the established pattern.

4. **Summons.** `⌘,` in the key monitor's main path opens the card (it must also work while help/field are up — close them, open settings). The titlebar gains the gear (`gearshape`) beside the `?`, same `paneVerb` styling, toggling the card. The `?` card lists `⌘, settings`.

5. **The Apple Settings scene.** `Settings { }` in `PalanaApp` rendering the same two sections bound to the same `SettingsModel` instance (extract the shared form view so card and scene render one truth). Keep it plain — the scene is the mirror, the card is the primary.

6. **The flags reach plans.** Where `OperationModel.gather` assembles `PlanFacts`, set `rsyncOperatorFlags` from the model (trimmed, nil when empty). The composed command in the panel shows them — no other panel change.

**Do Not**

- Do not build a parallel host registry — visibility is computed from the config text every time (the file is the truth).
- Do not write the real `~/.ssh/config` from any test — tests use temp files and `PALANA_SSH_CONFIG`.
- Do not add settings nothing reads — two sections exactly (ho-9.2 out-of-scope).
- Do not hide hosts from typed addresses.

**Stop Condition**

If wiring one shared `SettingsModel` into both the `WindowGroup` session and the `Settings` scene fights the scene lifecycle (the Settings scene builds its own view tree), stop and surface the shape you'd choose rather than duplicating state silently.

**Acceptance**

- [ ] Toggling a host hidden in the card removes it from the host menus and the field view immediately; the config file diff is exactly one comment line; the backup file holds the pre-write text; toggling back restores the original text exactly.
- [ ] A multi-alias block's toggle hides all its aliases and the card says so; an included-file alias shows the notice and writes nothing.
- [ ] The rsync flags value appears in a composed rsync command in the panel.
- [ ] `⌘,`, the gear, and Apple's Settings menu item all reach the same values.
- [ ] Esc dismisses; typed letters never leak to the grammar while a settings field is focused.
- [ ] `swift-format lint --recursive --strict Sources Tests`, `swiftlint lint --strict`, `swift build`, `swift test` all green (read the run line).

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
# Live walk against the fixture config (never the real one):
scripts/sshd-fixture.sh start
PALANA_SSH_CONFIG=.fixtures/ssh_config swift run Palana
# cmd-, → card · hide fixture-self → gone from menus/field · check .fixtures/ssh_config diff + backup · unhide → byte-identical
```

Quit the app when done — the session re-walks the live check.

**Commit**

Do not commit. The session reviews and commits.
