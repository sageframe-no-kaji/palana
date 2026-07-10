---
created: 2026-07-09
updated: 2026-07-10
status: living
type: state-memory
project: palana
stage: kamae-6
kamae-chain: seed → system-design → readme → ho-overview → hos → **state-memory**
---

# pālana — State Memory (Kamae 6)

The fixed handoff surface. Every session and ho closes by updating the
state-summary block below — verbatim field labels, parseable shape — so the next
session (and any hook) knows exactly where the build stands. Newest block on top.

---

## State summary — 2026-07-10, fourth block — ho-10.1 BUILT, HIS HANDS NEXT

**COMPLETED**
- **ho-10.1 AT-02 + AT-03 authored, built, committed, CI green by exit
  code** (1e80c10, 0d34e28). The Workbench mutation seam is FILLED:
  `planRequest(for:on:input:)` carries the gather (`MutationInput`:
  target dataset, text, recursive; `GatherSpec` on the verb), and
  `ZFSMutationTool` speaks the eight mutations. The app path stands:
  zfs section in the strip → dataset from where the focused pane stands
  → gather through the naming machinery (rename prefills the full name,
  destroy is a field-less toggle row, clear-mountpoint composes with no
  gather) → plan renders → **Enter enacts, nothing else** (Decision 4
  held structurally — no auto-enact anywhere in the zfs path). Finished
  runs refresh panes on the host and re-discover its facts.
- Review catches banked: stale zfs gather state would have misrouted the
  next file rename into the zfs path (cleared at every non-zfs begin);
  the field-less gather leaked plain keys to the Table's native
  selection (swallowed; ⌘-chords pass, ho-9.7's law); extraction-dropped
  law comments restored. 735 tests, 120 suites.
- Reflect filled in the ho doc (execution truths + hands-pending list).

**NEXT**
- **HIS HANDS — the mutation feel, fixture only.** The app is RUNNING on
  the fixture config (`PALANA_SSH_CONFIG=.fixtures/zfs-ssh-config`) —
  his real hosts are deliberately invisible; the only host is
  `zfs-self` (the Lima VM, pool `palana`). Point a pane at
  `zfs-self:/palana/tank`, probe (`r` in the field), and the zfs chips
  light. Two stale test datasets (`palana/t62-prx-*`) remain in the
  pool — good destroy targets. Verdicts → fill the close entry → close
  ho-10.1 → ho-11 (terminal), ho-12 (ship, v1.0).
- To get his real config back afterward: quit the app, relaunch plain
  (`swift run Palana`); stop the VM (`scripts/zfs-fixture.sh stop`) and
  clear `.fixtures/zfs.env` if suites later dial a dead port.

**ACTION ITEMS / BLOCKS**
- **SEALED (his word, 2026-07-10, mid-hands): the mount capability —
  ho-10.2.** Delegated creates land unmounted on Linux (mounting is
  root's; `zfs allow mount` is a dead letter there — proven live on the
  fixture with `palana/angrybird`, `mounted: no`). The no-sudo law gains
  ONE narrow exception: `sudo -n zfs mount/unmount`, capability-probed
  per host, composed only where the host grants NOPASSWD, always a
  visible plan step. Never prompts (sudo -n; the ssh channel has no TTY
  and pālana handles no secrets). Where ungranted: truthful refusal +
  the exact root command. Settings grows a helper showing the narrow
  sudoers line to copy ("counsel people to do that, if they want this
  feature" — his words). Unlocks mount/unmount verbs; heals
  set-mountpoint's remount. Root-helper daemon REJECTED (standing root,
  no per-action gate).
- **SEALED same day: the ZFS pane mode — ho-10.3** (per-pane dataset
  view, not hardcoded left; verb-grammar Think required — what does d
  mean on a dataset; dataset-y-equals-send convergence with ho-06.2).
- No blocks. Fixture VM `palana-zfs` UP and app running against it —
  both deliberately left up for his hands session (departure from the
  VM-stopped default, on purpose).
- Feel questions queued in the Reflect: twelve-chip strip weight,
  gather prompt wording, recursive-toggle keyboard reach, the destroy
  double-Enter rhythm, snapshot-name picker (v-next if hands ask).
- Debts carried: binding-table snapshot test before any key rename;
  light text editor as future Workbench plugin idea.
- Deferred stack unchanged (drag-out, width persistence, /-jump,
  verb-time re-choice, gather-the-starred, modal-sheet onboarding,
  ssh-actually deep link).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. ho-10.1 built, close pending his hands;
  the road to v0.5. Then ho-11, ho-12 to v1.0.

---

## State summary — 2026-07-10, third block — THE HO-9 SERIES IS CLOSED

**COMPLETED**
- **Hos 9.5 through 9.11 CLOSED on his word** ("thats it. finially. can we
  fucking close ho 9 now?"). All Reflects filled with his verdicts, all
  docs `status: complete`, the kamae-4 build record carries the series
  close entry. Phase 3.5 is done.
- Late closers this block: save-is-save default flip ("i concur. save is
  save" — auto-send default, changed-remote always asks, new stored key so
  old settings land on the new default); the keys panel executed its
  continuous-scale system after two crashes and a desynced render — five
  fixed sizes on ⌘1–⌘5, ⌘+/− step, no edge-drag, one authority; the
  trapped-shadow border removed (chromeless card inside the panel).
- Laws banked this block: persisted state that crashes must never
  re-crash (clamp on restore); never rebuild a SwiftUI tree inside a
  resize delegate's layout pass; platform features needing app-bundle
  registration (pasteboard types, notifications) must be proven in the
  bare-binary dev build.

**NEXT**
- **ho-10.1 resumes**: AT-02 (ZFSMutationTool fills the Workbench mutation
  seam) and AT-03 (the app mutation path — planRequest → plan → render →
  Enter, dataset targeting from the focused pane, hands against the Lima
  fixture pool). Then ho-11 (the terminal), ho-12 (the ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks. App running his real config with everything through cf27f3d+.
- Debts, named: binding-table snapshot test before any future key rename;
  light text editor queued as a future Workbench plugin idea (his).
- Deferred stack: drag-out to Finder, width persistence, /-jump,
  verb-time re-choice, gather-the-starred control, modal-sheet onboarding,
  ssh-actually deep link (guide not shipped).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. Phase 3.5 (the ho-9 series) COMPLETE.
  ho-10.1 (ZFS tool) is the road to v0.5; then ho-11, ho-12 to v1.0.

---

## State summary — 2026-07-10, second block (the hands session + the grammar)

**COMPLETED**
- **He drove the whole BIG PUSH live — nine fix/build rounds answered in
  session.** Columns sort (review-missed comparators fixed, ★ sorts via a
  routing token), drag-and-drop WORKS (third attempt: a bundle-less binary
  can't declare pasteboard types — payload moved to public.json; his word:
  "its working"), per-pane history (⌘←/⌘→ + chevrons, PaneHistory in core),
  one-Enter rename/create, loud prompts (accent naming field, the shouted
  send-back callout), the auto-send toggle (conflict always asks), the verb
  chips as a permanent rail (dimmed while a plan runs).
- **The language sweep** — six message-grammar rules installed at
  Collision.swift's header and applied across core + app + tests: plans
  speak future, runs speak past with proof, refusals name thing and reason,
  unknowns named, no jargon (enact/gather/compose are dead words),
  classification/transport render plain, raw values frozen. His wording
  verbatim in the collision note.
- **ho-9.11 THE GRAMMAR — proposed, ratified, executed in one day.**
  grammar-proposal.md (119-binding audit → five rules) → his marks → one
  atomic commit: d deletes, r renames, R/T unbound, 8 stars the entry,
  ⌘8 the directory, ⇧⌘8 dead, ? card teaches the rules, README keybindings
  table. 696 tests, 114 suites, CI green through the day.

**NEXT**
- His remaining feel verdicts: the round-trip loop end-to-end in his
  editor, the columns picker, the r/d retrain, the wash weight. Then close
  entries for 9.6–9.11 (and 9.5, still pending from before the push) →
  ho-10.1 resumes (AT-02 tool, AT-03 surface) → ho-11 → ho-12.

**ACTION ITEMS / BLOCKS**
- No blocks. App running his real config with the full day's work.
- Noted in 9.11's Reflect: no test pins the binding table — a snapshot
  test is cheap insurance before the next rename.
- Deferred stack unchanged (drag-out, width persistence, /-jump,
  verb-time re-choice, gather-the-starred).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; the ho-9 remainder + grammar executed toward
  the ho-9 close; ho-10.1 next toward v0.5.

---

## State summary — 2026-07-10 (the BIG PUSH — ho-9 remainder)

**COMPLETED**
- **The ho-9 remainder EXECUTED — hos 9.6 through 9.10 authored (Kamae 5,
  Think phases sealed) and built in one autonomous push.** Every AT on
  claude-sonnet-4-6, reviewed at the top from the diff, verification rhythm
  green at every commit, CI green through the run (`gh run` checked, one
  timing flake de-flaked). 682 tests, 113 suites.
  - **ho-9.9 Collision Facts** — the overwrite-safety teeth. `Collision` /
    `CollisionReport` in core, gathered fresh per plan through the panes'
    listing, alarm line under the size line (replaces · merges into · kind
    clash; "destination unread" when the gather fails; silence only when
    gathered-and-clean). Review catch: report keys on the destination, not
    the classification — the mv-move overwrite would have stayed unnamed.
  - **ho-9.10 Remote Round-Trip Editing** — the stranded-edit gap closed.
    Remote opens register a watch (dual DispatchSource — dir fd survives
    atomic-replace saves, file fd catches in-place; fd-capture cancel
    handlers, review catch); a debounced save summons the panel with the
    upload plan + collision line + changed-since-fetch note; busy panel
    never evicted; Esc declines, watch survives; baseline refreshes after a
    send. No panel pop at registration (Decision 5 held in review).
  - **ho-9.6 Drag-and-Drop** — DraggedSelection/DropDecision in core; rows
    drag the selection (Table → rows-builder form, behavior held); drop
    composes copy / option-move through the standing gather; Finder URLs
    resolve via local listing; self-drops refuse; accent wash on valid
    hover. Review catches: stale-drop refusal, O(n²) payload → once-per-render.
  - **ho-9.8 Columns** — FileEntry.created/.changed at sealed fidelity (BSD
    both via stat %B/%c, GNU changed via find %C@, BusyBox neither); GNU+BSD
    corpora re-recorded LIVE, recorder first; six new columns behind the
    platform header right-click; visibility persists to columns.json
    (TableColumnCustomization is NOT Codable — widths per-process, the named
    escape hatch); ★ column = display + toggle (the header cannot emit a
    starred comparator — KeyPathComparator<FileEntry> vs the one-registry
    law; dead sort branch cut in review).
  - **ho-9.7 Design Polish** — consolidation: early-landed fragments named
    in the doc; go-again keys as KeyCapChips (transient, hint line only);
    terminal popout glyph on each pane footer (backtick's exact path);
    pruning audit found the palette CLEAN (taste-call ledger in the doc);
    cmd-swallow debt closed by verified reading (no surface swallows
    ⌘-chords). NSMenu refit dissolved: NO menu carries sequence hints —
    finding recorded, no diff shipped.
- **ho-10.1 AT-01 reviewed + committed** (was left uncommitted by the prior
  session): the ZFS mutation engine, round trip proven LIVE on the Lima pool
  (create → snapshot → rollback → mountpoint set/clear → destroy). Fixture
  delegation grew rename,rollback. VM left stopped.
- Reflects filled in all five ho docs (execution truths + hands-pending
  lists); kamae-4 build record carries the batch entry; per-ho close entries
  wait on his verdicts, per precedent.

**NEXT**
- **ONE hands session over the five** — the overwrite line on a real
  collision, the round-trip loop in his editor (edit remote → save → panel →
  Enter), the drag between panes + from Finder, the header right-click
  columns + ★, the chips and the pane-footer popout (if the 24pt strip reads
  heavy, the glyph can move to the header). Verdicts → fill close entries →
  close 9.6–9.10. ho-9.5 close also still pending his onboarding verdicts.
- Then **ho-10.1 resumes**: AT-02 (`ZFSMutationTool` fills the Workbench
  seam) + AT-03 (app mutation path, hands against the fixture pool). Then
  ho-11 (terminal), ho-12 (ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks. App rebuilt and relaunched on his REAL config with the full
  push (reads only).
- Deferred, named in the docs: pane→Finder drag-out (file promises), width
  persistence across relaunch (own capture if missed), type-to-jump (`/`
  filter-jump direction sealed in ho-9.8, its own slot), verb-time re-choice
  in the panel after a drop, a gather-the-starred control if his hands ask.
- Carried: the README Kamae-3 refresh ("doesn't do it justice"); the
  modal-sheet onboarding variant offer (9.5).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. The ho-9 remainder executed toward the ho-9
  close; ho-10.1 in progress toward v0.5; then ho-11, ho-12 to v1.0.

---

## State summary — 2026-07-10

**COMPLETED**
- Post-beta surface polish (Opus + sonnet, all CI-green): a visible close on
  every summonable surface — an upper-left ✕ that reddens on hover like the
  system close, turned into a proper title-bar row (✕ + surface name: the field,
  the keys, settings, favorites, the host map), esc still closes everything;
  title-to-content spacing tightened to ~8pt on the cards. `OverlayCloseButton`
  and `OverlayHeader` are the shared components.
- **ho-10.1 OPENED** — the ZFS tool, Think phase authored (Opus). The mutation
  seam ho-10 named is the target: dataset create/destroy/rename, snapshot
  create/destroy/rollback, mountpoint set/clear, each composing a `zfs` command
  the operator reads in the plan panel before Enter enacts. Six Think decisions:
  a `ZFSMutation` payload on `PlanRequest` (op `.zfs`), one `Classification`
  `.zfsMutation`, transport `.local`, delegated no-sudo composes verified by
  reading state, destroy/rollback safe because the plan is read before Enter,
  verb targets the dataset the pane stands in, fixture-only (never a real pool).
  Three ATs named; AT-01 (core engine) authored and **building on sonnet now**.

**NEXT**
- Finish **ho-10.1**: review AT-01 (core ZFS mutation engine + fixture round
  trip), then author+build AT-02 (`ZFSMutationTool` fills the seam) and AT-03
  (app mutation path: planRequest → PlanEngine.plan → render → Enter, the
  parameter-gather, dataset targeting from the focused pane) — AT-03 is a hands
  session (the mutation feel, against the fixture pool). Then ho-11 (terminal),
  ho-12 (formalize the ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks. AT-01 must prove the create→snapshot→rollback→mountpoint→destroy
  round trip on the Lima fixture pool (`make zfs-fixture`), never a real pool.
- Deferred (named in the ho): pool create/destroy (viz only), `zfs clone`,
  non-mountpoint properties, `zpool status` drives-fact.
- Carried from the ho-9.x run: star column in the column picker → a future
  columns ho; the modal-sheet onboarding variant offered if the inline form
  still reads cramped.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. ho-10.1 (ZFS Workbench tool) in progress toward
  v0.5; then terminal (ho-11) and the formal ship (ho-12) before v1.0.

---

## State summary — 2026-07-09

**COMPLETED**
- Shipped **v0.4-beta** — the first public build — as a signed, notarized macOS
  `.dmg` on GitHub Releases (prerelease). App + dmg both notarized and stapled;
  Gatekeeper-accepted (`source=Notarized Developer ID`, team `3N8F759K8D`).
- Built the macOS release pipeline, effectively ho-12's ship machinery, ahead of
  its ho: `scripts/build_macos.sh` (universal `arm64+x86_64` build → hand-
  assembled `.app`, `Package.swift` stays canonical, no Xcode project → sign →
  notarize app then dmg → staple both), `scripts/entitlements.plist` (hardened
  runtime, empty by design — pure Swift, no dynamic code), and `RELEASING.md`.
- App icon in place (`packaging/palana.png`, built to `.icns` at build time;
  generated `.icns` gitignored). Bundle id `com.sageframe.palana`, min-macOS 14.
- README brought to v0.4-beta: beta download callout + feedback ask up top,
  Download section points at the release, license confirmed GPL-3.0. Reconciled
  the interactive terminal to a **v1.0** feature (Kamae-4 Phase 5), removing the
  stale "post-v1" entry.
- Repo made public-facing: description + homepage set; already public, GPL-3.0.

**NEXT**
- **ho-10.1 — the mutating ZFS Workbench tool** (dataset management, snapshots,
  pools), Phase 4, core unmodified. Then ho-11 (terminal), ho-12 (formalize the
  ship, v1.0).

**ACTION ITEMS / BLOCKS**
- No blocks.
- Non-blocking: the beta icon source was 1024×**1059** (not square); padded to a
  transparent square to avoid squish/clip. For v1.0, re-export a true 1024²
  square and rebuild (one command).
- Non-blocking: the ship pipeline now exists ahead of ho-12; when ho-12 opens it
  formalizes what's already built rather than starting cold.
- Notarization uses keychain profile `palana-notary`; signing identity
  `Developer ID Application: ANDREW TODD MARCUS (3N8F759K8D)`. See `RELEASING.md`.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public. (Was `dev` through Phases 1–3 + the ho-9.x surface
  run.) Engine + Surface complete; ZFS Workbench tool and terminal remain before
  v1.0 / `production`.

---

## Build record (release tags)

| Tag | What it marks |
|---|---|
| v0.1 | Phase 1 — foundation verified, go/no-go answered *go* |
| v0.2 | Phase 2 — PalanaCore headless engine complete (173 tests, 97.69% cov) |
| v0.3 | Phase 3 — the Surface: panes, plan → enact, field view |
| v0.4 | Surface UX run complete — favorites, host onboarding, settings, mounts |
| **v0.4-beta** | First public build — signed, notarized `.dmg` on Releases |
