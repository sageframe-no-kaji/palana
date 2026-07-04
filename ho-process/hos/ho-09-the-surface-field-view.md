---
created: 2026-07-04
status: complete
type: ho-document
project: palana
ho: 09
commit: f69ed65..HEAD (author f69ed65, core c997005, mark d69ae6b, overlay 3bc8f0f, round 1 b6d16f5, openrsync errata at close)
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-03-the-field
  - ho-07-the-surface-panes
  - ho-07.5-the-busybox-userland
  - ho-08-the-surface-plan-and-enact
agent-tasks:
  - Ho-09-AT-01.md
  - Ho-09-AT-02.md
  - Ho-09-AT-03.md
---

# ho-09 — The Surface: Field View

The map, summoned. One keystroke brings the topology—machines, datasets, reachability—rendered instantly from what the Field remembers, every fact marked with when it was learned. Pick a node and a pane points there. Ask again and the Field looks again—the explicit re-probe ho-07.5 promised, the verb that clears zencat's stale flavor without deleting a file. Then it vanishes and the panes keep the whole window. The ho ends in the third UI/UX session, and Checkpoint 3 consolidates the findings from all three.

**Out of scope:** services in the overlay—the field view does not promise more than the Field can answer, and services arrive with the services plugin, post-v1. Any polling—discovery stays on demand, ho-03's law. A probe-all verb—the operator probes the host he is asking about, one at a time. Host onboarding—the "add a host" surface mutates `~/.ssh/config` and gets its own Think phase at Checkpoint 3. Filtering the `github-*` aliases out of the topology—a real want, queued for the hands session to confirm before it becomes code. Type-to-filter in the overlay—the host list is small and the vocabulary should stay small until hands say otherwise.

**Resolves deferred decisions** (from the ho-overview):

- Field view contents and summon key (deferred decision 8)—resolved here as engineering calls, validated by the practitioner's hands at session end. Summon, point a pane, dismiss—under two seconds end to end.

**Carries from the sessions between:** the explicit re-probe control (ho-07.5 Decision 4—zencat's cache may still say BSD, and the interim answer was deleting `field-cache.json`). Dataset and mount-boundary indicators in the pane (queued at ho-07's close—rides the Field's facts). And the field-use docs owe one operator truth: `~` on a remote means the remote user's home, which on the fixture container is `/config`—read twice as a bug by the practitioner's own hands.

---

## Phase 1 — Think

### Decision 1 — Presentation: an in-window overlay card, not a window

Three precedents exist. The help card is a SwiftUI `.overlay` on the panes. The plan panel is a `VSplitView` leaf. The keys card is a hand-built borderless `NSPanel`, and the reason it is one—it floats while the operator works elsewhere—is exactly what the field view never does. The field view is summoned, consulted, dismissed—it never coexists with typing in a pane. So it takes the help card's machinery: a centered card over the panes, panes dimmed beneath it, zero window ceremony, command-palette manners without a second window. `SurfaceView` gains one more `.overlay`, the key monitor gains one more branch. Under two seconds end to end is trivially met—the render is a cache read.

### Decision 2 — Summon is `f`, and the overlay has its own five-key grammar

`f` is unclaimed in the binding table and the word is the feature. yazi spends `f` on filter, but pālana's filter-someday belongs to `/`-territory—the find idiom—so claiming `f` for the field costs nothing the grammar will later want back. `f` toggles: summon, and dismiss unchanged. Inside the overlay the grammar is the overlay's own, routed by a `fieldVisible` branch the way `helpVisible` and `panelShowing` already route: `j`/`k` move the cursor, `l`/`h` expand and collapse a host's datasets, `r` re-probes the host under the cursor—`r` is delete outside, and the overlay branch makes the collision impossible—`Enter` points the focused pane and dismisses, `Esc` dismisses. `Tab` keeps its one meaning, switch pane, so the pointing target is always the focused pane and the focus dot says which. `f` does nothing while the plan panel is showing—the panel's keys are the panel's. Help and field never show together, the keys-card precedent.

### Decision 3 — Contents: hosts as an outline, datasets nested, exactly what the Field knows

Rows come from `hosts()` and remembered facts, nothing else. `local` first, then config order—the host menu's order. A host row carries the alias, the reachability verdict with its age, the userland flavor, and presence tokens for zfs and rsync—every one of them a cached fact, none of them a promise. A host never visited renders plain and says so—no facts is a fact. Expanding a host lists its remembered datasets: name and mountpoint, `legacy` and `none` mountpoints rendered but not pointable—a dataset you cannot stand in is not a destination. Enter on a host points the focused pane at `host:~`. Enter on a mounted dataset points at its mountpoint. The overlay's own footer names what `~` means—the remote user's home—because the practitioner's hands read `/config` as a bug twice and the docs owe him the sentence where he is looking.

### Decision 4 — Remembered is an age, and `r` is the only way to make it younger

Every fact group already carries `discoveredAt`—`Dated<Value>` is the whole staleness model, and this ho adds no second one. The host row wears one age—reachability's stamp, because every `discover` writes it—rendered relative and quiet ("just now," "3h ago," "2d ago") in `inkFaint`. `r` on any row re-probes that row's host through `Field.discover`: the row says "probing…" in place, the card updates when the answer lands, and an unreachable answer records as the typed fact it is—rust-colored detail, nothing thrown at the operator. This is the verb that heals zencat: `r`, one round trip, BusyBox replaces the remembered BSD, and the pane's next read resolves the corrected flavor from memory. No fan-out, no refresh-all—the no-polling law extended to its natural edge.

### Decision 5 — The outline is a pure value in the core, the Surface renders it

ho-07's law holds: everything that can be wrong is a pure value in the core. A `FieldOutline` in `Sources/PalanaCore/Surface/` builds display rows from `(hosts, facts, localHost)`—host rows, dataset rows, expansion state—and its transitions (cursor moves, expand, collapse, resolve-Enter into a pointing) are pure functions unit-tested to the floor. The relative-age rendering is a pure `(discoveredAt, now) → String` beside it, clock injected. The `Field` actor grows one method—`allFacts()`, a memory snapshot, never the wire—so the overlay reads everything remembered in one hop. The app side holds only a thin `@Observable` view model delegating every transition to the core, the `PaneModel` pattern.

### Decision 6 — The pane wears the dataset boundary as a quiet mark

The queued indicator lands here because it rides the same facts the overlay renders. A row in a pane whose full path is a remembered dataset's mountpoint gets one quiet glyph in `inkFaint`—the boundary made visible where the operator is actually standing, not a second topology. The test is an exact mountpoint match against cached topology—a pure function, no probe, no promise when facts are absent. Which glyph is the hands session's question—the code commits the seam, the session prunes the mark.

### Discovery (deferred to execution) — the overlay against the practitioner's real cache

The fixture cache holds one container host and a throwaway pool. The practitioner's real `field-cache.json` holds koan, kanyo, zencat, and the `github-*` aliases that pollute the menu—the overlay renders whatever is there, and the hands session judges the rendering against the real shape, including whether the alias pollution earns its filter now.

---

## Phase 2 — Execute

The work decomposes on the core/Surface seam plus one indicator. Implementation runs on `claude-sonnet-4-6`—per-task review and the verification rhythm stay with `claude-fable-5`, the session's own hands.

### Ho-09-AT-01 — FieldOutline in the core

The pure outline: rows from facts, transitions, relative-age rendering, `Field.allFacts()`. Unit battery to the floor. → `ho-process/agent-tasks/Ho-09-AT-01.md`

### Ho-09-AT-02 — The overlay in the Surface

The card, the `fieldVisible` branch, summon/point/dismiss, `r` wired to `discover` with in-place probing state. Depends on AT-01. → `ho-process/agent-tasks/Ho-09-AT-02.md`

### Ho-09-AT-03 — The dataset mark in the pane

The exact-mountpoint test in the core, the glyph in `PaneView`. Independent of AT-02. → `ho-process/agent-tasks/Ho-09-AT-03.md`

### Testing and iteration approach

Each task carries its own verification—lint, build, the full suite—and lands as its own commit after review. Core logic tests to the ≥90% floor with the outline's battery. The overlay itself is hands-validated like every Surface piece: first against the fixture (`PALANA_SSH_CONFIG=.fixtures/ssh_config swift run Palana`, sshd container up), then against the practitioner's real config, reads only, for the session. The ntfy ping fires when the overlay stands.

### Done means

- `f` summons the topology from the real cache instantly, every fact aged, never-visited hosts named as such
- Enter points the focused pane at a host or a mounted dataset and the overlay vanishes—under two seconds end to end
- `r` re-probes one host in place—proven against the fixture, and proven in kind against zencat's stale-flavor shape by a recorded-facts test
- Dataset mountpoint rows in the pane wear the mark when topology is remembered, and nothing probes to earn it
- The verification rhythm is green—lint, build, full suite, coverage floor—and the practitioner's feel feedback from the third session is recorded and carried to Checkpoint 3

---

## Phase 3 — Reflect

**The design held, and the real cache did the judging.** The overlay rendered his cache instantly—koan at 159 datasets, kanyo at 18, the github aliases as honest rust refusals—and the grammar carried the session without a collision. What the Think phase didn't anticipate came from the map being honest about what it knows: the github rows prompted the filter question the ho had deliberately held, kanyo prompted "what about the ground that isn't ZFS," and both resolved into direction rather than code.

**Decision review.** `f` drew no complaint. The in-window overlay held—no window machinery fought back. Decision 4 proved itself in anger: `r` on zencat traded the stale BSD for BusyBox in one keystroke, live, at 20:23—the cache shows the healing. And the config-as-control surface passed its deepest test unprompted: he asked "can I add to the field?", was told the ▾ menu edits `~/.ssh/config`, and chumon appeared in the map with 10 datasets before the session ended—edit, reload, probe, no code helping. His verdict on the mechanism, verbatim: "i love that that is the control."

**Delegation review.** All three agent tasks ran on `claude-sonnet-4-6` and came back spec-faithful and green. What the session's review caught is the argument for keeping review at the top tier: probe refusals held in state but never rendered (silence where the law says failures render in place), the missing scroll-follow (ho-07's first hands finding, about to be rediscovered), a cancellation seam opened by making `commit` async, and a type-body budget tipped at the brink.

**What broke that the tests didn't catch—and what CI caught that the session nearly didn't.** CI had been red since ho-08's first code push: the rsync floor compose carried `-s`, which openrsync refuses—hidden locally by this Mac's real rsync 3.4.1, declared "openrsync-safe" by the very test that asserted it. Under it a deeper incompatibility: rsync ≥3.2.4 protects remote args by default, so a floor-style inner quote arrives literal on a modern client—no one flag set serves an unknown local rsync. The errata makes `rsyncDirect` ask for both binaries known (unknown falls to tar), keeps `-s` for the modern compose, and inner-quotes remote paths for the floor. The routing live tests now probe this machine's own rsync and feed it as fact—modern proven here, floor proven on the runner, the self-skip the ho-08 record imagined replaced by a floor that works. Two session lessons re-learned the hard way: `swift test | tail` masked a failing run at one commit (the build record's own recorded trap), and the ho-08 scratch timing probe flaked against a mutating `/private/tmp`—deleted per its own header, and the finding that a directory changing between the listing's name pass and stat batch refuses as `malformedListing` is queued as a real v1 edge.

**The third session's queue, for Checkpoint 3.** Sealed direction: `# palana: hide` comments in `~/.ssh/config` as the host filter, edited by a settings surface for operators who don't speak ssh config. Settings live in pālana's own popped panels, mirrored to the Apple Settings scene; a settings gear joins the titlebar when they exist. The host map grows from a mounts fact (`findmnt`-shaped, new Field vocabulary)—all hosts, filesystems present including the non-ZFS ground kanyo asked about—surface decided when it opens. Built mid-session as round 1: the titlebar `?`. Standing from earlier sessions: create/rename, favorites, drag-and-drop, host onboarding, help-card cmd-swallow verify, design polish, the NSMenu refit.

---

_Authored: 2026-07-04 (Think phase). Executed same day—three agent tasks on claude-sonnet-4-6, reviewed and verified by the session._
_Third UI/UX session run live. 323 tests, 58 suites, PalanaCore 97.67% line coverage._
