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

## State summary — 2026-07-15, tenth block — THE MOUNT SEAM PROVEN AND CLOSED; 10.3, 10.1, 11 CLOSED — PHASE 4/5 DONE

**COMPLETED**
- **ho-10.4 (The Mount Seam) fully proven on his hands and CLOSED.** Three ATs
  beyond AT-01, each built by agent (sonnet), reviewed from the diff, hands-verified:
  - **AT-02 (`b49e42f`)** — the implicit-unmount heal. destroy / set-mountpoint /
    clear-mountpoint on a MOUNTED dataset weave `sudo -n zfs unmount` ahead (+ a
    trailing `sudo -n zfs mount` for the two mountpoint verbs); `MutationInput` +
    `PlanRequest.targetMounted` carry the mounted fact from the surface to the pure
    composer. **F1**: the field view grew the `sudo` chip to match the host map.
  - **AT-03 (`dc6abf7`)** — `space` flips the recursive toggle (was mouse-only) in
    both the field-less (destroy) and text (snapshot/rollback) gathers; space over
    `r` because a typed name can hold `r`, never a space.
  - **AT-04 (`869763d`)** — set-mountpoint composes `zfs set -u` (no auto-mount →
    kills the mid-plan "insufficient privileges" warning). `zfs inherit` has no `-u`
    (only `-rS` on 2.4.1) so clear-mountpoint keeps its cosmetic warning; the
    explicit mount still lands it.
  - Verdicts: heal fired on a pane-driven destroy (`palana/armedguard`, "It worked");
    F1 chip shows; space toggle ("SMOOP"); `-u` set-mountpoint clean, no warning.
    Accepted as correct: clear = inherit parent path; set-mountpoint preserves mount
    state (unmounted stays unmounted — `m` mounts if wanted).
- **ho-10.3 (pane mode) CLOSED** — proven by all-session use; Reflect corrects
  Decision 3 (Z is the ONE zfs key, panel is click-only, umber badge).
- **ho-10.1 (zfs tool) and ho-11 (terminal) CLOSED on his hands.** 10.1 "is lean"
  — the snapshot loop, typed destroy, rename, create all read right; the
  seventh-block **second-press mystery did NOT resurface** (closed unreproduced,
  reopen forward if it returns). 11 — all seven criteria pass (shell summons,
  vim/htop/⌃C, ⌘\` focus in/out, ⌘-chords off the PTY, `exit` survives, failure
  over the shell). **Banked feel-question:** the shell binds to the summoning
  pane's host and does NOT follow pane focus ("stuck there… something weird,
  might just be comfort") — deliberate (a shell is a place), but a candidate for
  a future shell-UX rethink ho if it keeps reading wrong.
- **With these, every ho-10.x + ho-11 is closed — Phase 4 (Workbench) and Phase 5
  (terminal) are DONE.** Only the ship (ho-12) remains before v1.0.
- **Housekeeping:** the integration worktree was reaped from `/tmp` by macOS —
  branch ref lost but ALL commits intact; recreated `integration-shell-panemode`
  at `492e06a` in a DURABLE worktree `../palana-integration`. Three fully-contained
  per-ho pointer branches (10.3/10.4/11) deleted.

**NEXT**
- **THE CLOSE CASCADE, now unblocked** (all ho-10.x + 11 closed): **tag v0.5** on
  main → **merge `integration-shell-panemode` → main** (carries ho-11 + 10.3 +
  10.4 + the AT-02/03/04 heal work) → then **ho-12** (the ship) = v1.0.
- Fresh hos to open when he wants: **global UI text-scale** (⌘+/− everywhere,
  scales ALL chrome — a font-factory refactor, its own ho); the **sudo-explainer**
  (sudoers line at the refusal + settings reference — the last live piece of
  ho-10.2's old scope; `10.2` is a dead number, give it a fresh one); and a
  possible **shell-UX rethink** (the follow-the-host feel-question).

**ACTION ITEMS / BLOCKS**
- No blocks. App runs the integration build via HIS shell launch (`!` prefix —
  my background launches get reaped at turn boundaries; the `!`-owned one survives).
  Fixture VM `palana-zfs` UP.
- Pool is littered with `@save-it` snapshots on nearly every dataset — plain
  destroy hits "has children / use -r"; the space-toggle now reaches `-r`.
  `armedguard` destroyed this session; `children`/`pjb`/etc. remain as targets.
- Deferred (named in 10.4 Reflect): recursive-destroy of mounted CHILDREN;
  set-mountpoint auto-mount-on-unmounted (a preference, his call); `-u` version-gate
  for pre-2.2 hosts; sudo fixture `zfs-pool.json` re-capture.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; mount seam (10.4) + pane mode (10.3) CLOSED on the
  integration branch; v0.5 = his 10.1/11 verdicts + the merge away; v1.0 = ho-12.

---

## State summary — 2026-07-12, ninth block — THE VERDICT MARATHON: SHELL GREEN, ZFS HARDENED, THE MOUNT SEAM LANDS

**COMPLETED**
- **Shell 5–9 ALL YES; zfs 12/13/16/17 YES; #20 CLOSED** (fixed by the
  plan-owns-the-panel redesign; unreproducible). His hands drove ~six
  more fix rounds on the integration branch, all rhythm-green:
  - `/` type-to-jump (his ask: a MODE, not suppression — grammar stands
    down, cursor chases, footer shows the buffer).
  - Round-9 fixes: shift-click selects (NSEvent.modifierFlags class
    property — the Table's setter fires after the event passes);
    selection.json leak sealed (.ownProcess); esc-hides lie fixed;
    invisible-shell trap closed (shellVisible requires panelShowing;
    ⌘` on hidden panel re-summons whole; plan-owned = silent decline).
  - Esc hands the panel back to the shell (dismiss + keep panel up);
    rail names the road.
  - Rollback -r as a plainly-worded toggle (destroysNewer — GatherSpec
    grew toggleLabel); dead-end gathers self-dismiss AND stay visible;
    sshFailure renders as a sentence; relative mountpoints refuse in
    words; double-click descends a mounted dataset; snapshot verbs
    validate typed names against the listed truth; destroy label
    shouts DESTROY; recursive toggles name what they take (snapshots
    ARE children — his question, answered in the label).
  - Squat panel (3rd appearance): first-layout fitting-height squeeze —
    step size reasserted post-front + a turn later; panel owns its own
    origin persistence (frame autosave FIRED — legacy key + frame saved
    on a disconnected display); stale defaults keys purged.
  - zfs-mode host-follow: refresh moved from point() to commit() —
    reads are async, the old placement refreshed the OLD host.
- **ho-10.4 (The Mount Seam) authored, built by agent, reviewed,
  MERGED into integration** (8b62150): HostFacts.sudoNoPassword
  (sudo -n true, never-fatal, 4th discover round trip, host-map token);
  .mount/.unmount composing `sudo -n zfs mount/unmount` read IN the
  plan; keys m/u, set-mountpoint → p; CapabilityRequirement.zfsMount
  gating on BOTH facts with the exact refusal sentence. 736 tests.
  Corpus fixture zfs-pool.json predates the probe — re-capture when
  hands are on the VM (flagged, nothing asserts on it).
- **Time-machine revelation banked** (snapshots = browsable past via
  .zfs/snapshot; works TODAY via address bar; READmade copy commitment;
  likely roadmap reorder). Preview-pane seed banked earlier.

**NEXT**
- **His mount hands-round** (m/u on the fixture, sudo token in host
  map, p for set-mountpoint, refusal on koan) + retests: panel open
  size (post-front reassert), host-follow in mode, dead-end note
  visible, DESTROY label, sandwich destroy with the renamed -r toggle.
- Then THE CLOSE CASCADE: his final verdicts → close ho-10.1 → tag
  v0.5 on main → merge integration branch to main → close ho-11/10.3/
  10.4 with hands-session Reflects (amend docs: ⌘` not t/⌘Esc, Z
  ungated, panel click-only, mount seam) → README polish LEADING with
  browse-your-snapshots → Dave (still parked).

**ACTION ITEMS / BLOCKS**
- No blocks. App running merged build; fixture VM up.
- Banked: selection rows want a highlight wash (design polish); zfs
  pane-mode dataset jump; auto-mount after create; preview pane;
  snapshot-history surface (Kamae-4 slots when board clears).
- Reentrant-NSTableView launch warnings still unchased (pre-close).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 = his verdicts away; integration
  branch carries ho-11 + 10.3 + 10.4 hands-hardened; v1.0 = ho-12.

---

## State summary — 2026-07-11, eighth block — THE INTEGRATION HANDS SESSION: FIVE ROUNDS ON THE SHELL AND THE BOUNDARY

**COMPLETED**
- **He asked for the merge early** ("i want to test the terminal and the
  pane zfs setup") — branch `integration-shell-panemode` (worktree
  /tmp/palana-ho11) merged ho-11 + ho-10.3 ahead of the v0.5 tag; one
  conflict (both branches re-extracted handle()'s text-entry priority;
  10.3's handleTextEntryPriority subsumed ho-11's inline form). Main
  UNTOUCHED. Then five live hands rounds on the integration build:
  1. **`exit` killed the app silently** — nothing heard the child die;
     keystrokes wrote into a closed/recyclable fd → SIGPIPE, no crash
     report. Fixed threefold (0591f4e): store is processDelegate and
     drops dead sessions firing onSessionEnded; shell mode exits with a
     transcript note; SIGPIPE ignored app-wide. Two tests pin it.
  2. **⌘Esc provably never reaches the app** (key trace: the system eats
     ⌘Esc AND ⌘.) and `t`-for-shell fired file-touch seven times on his
     hands. ⌘` became the shell key (his fingers pressed it four times
     looking for the exit); t means touch again (94970c8).
  3. **The demoted overview panel was cramped and mute** — tree uncapped
     (the 180pt cap was for the deleted verb rows), copy names Z
     (b4783cb); then the WINDOW size bug: setFrameAutosaveName restores
     size too, stale frame defeated the stepped sizing — step size
     re-asserted after restore (0d91efd).
  4. **The zfs pane boundary too quiet; ⌘⇧Z 'WTH is that?'** — header
     wears a solid umber ZFS badge in the chip's style, wash 0.12, the
     chord is DEAD: panel is click-only on its chip; Z is the one zfs
     key (0d91efd).
  5. **'Z isnt working' + 'can I bring the shell in and out of focus?'**
     — Z was gated on strip focus (my ho doc's error; type-ahead ate it)
     → ungated, works at pane focus. And the focus model landed
     (682250f): shellMode (view) splits from shellFocused (keyboard);
     ⌘` MOVES THE KEYBOARD while the view stays — engagement line +
     dim + footer words say who is listening; first responder follows
     deferred a turn; ONE LAW replaced the failure hook's special case:
     the plan owns the panel whenever an operation exists, the shell
     shows in the idle gaps.
- Every round: full rhythm green (714 tests incl. 2 natural-exit).
- **Late add, his ask ("I am already reaching for palana ALL the
  time!"): drag-out** — a local pane's drag registers the real file URL
  beside the pane-to-pane payload, so the same gesture lands on browser
  uploads, Finder, Mail. Remote drag-out (file-promise that downloads
  through the transport on drop) BANKED as its own item. Internal drops
  prefer json — pane-to-pane untouched.
- A 20-item numbered test list was handed to him (drag-out 1–4, shell
  5–11, zfs pane mode 12–18, 10.1 remainders 19–20); his replies come
  as numbers.
- **SEEDED, his revelation ("WAY more useful than any of this... like
  time machine!"): SNAPSHOT HISTORY BROWSING** — the pattern he
  actually lives by: reach into `.zfs/snapshot/<name>/` and copy out,
  never rollback. The reframe: snapshots are a TIME DIMENSION of the
  filesystem — Time Machine for the homelab, over ssh. Works TODAY by
  typing the .zfs path into the address bar (restore = ordinary yank
  through the gate, source read-only by construction). The real
  feature: a history surface — stand on a file/dir, summon its past,
  pick a snapshot by age (field-view vocabulary), browse in a pane,
  restore with y. Engine has the facts, transports move the bytes,
  gate reads the plan; only the surface is missing, and pane modes are
  a solved shape. Wrinkle to solve: .zfs is invisible to listings by
  design (snapdir=hidden) — the surface erases that invisibility.
  LIKELY REORDERS THE ROADMAP (his energy says this beats 10.2's sudo
  work); his call at the next Kamae-4 pass. THIS is the Dave pitch.
  HIS COPY COMMITMENT ("we need to put this in the copy"): the README
  polish step LEADS the ZFS story with browse-your-snapshots ('browse
  the past like a directory; restore is just a copy'), ahead of the
  verb list. Mac-local ZFS asked and answered: possible (OpenZFS kext,
  Reduced Security on Apple Silicon) but recommended NO — the Mac is
  the operator; possible v-next: history surface abstracts snapshot
  providers (ZFS remote + APFS local).
- **SEEDED, his ask ("it would be life changing"): the PREVIEW/INFO
  pane mode** — paneMode grows .preview; the right pane follows the
  LEFT pane's cursor. Local: QLPreviewView (Quick Look) + an info card
  assembled from facts we already gather (FileEntry, treeSizes, ◆).
  Remote text: Listing.readFile head-read. Remote binary: fetch-to-
  cache on the ho-9.10 round-trip machinery — needs a Think phase
  (size caps, cursor-motion debounce, eviction). Sizing: local+info =
  one ho; remote-binary its own follow-up. Wants a Kamae-4 slot when
  the board clears. Also noted: 3 reentrant-NSTableView warnings at
  launch on the integration branch — run down before the branch closes.

**NEXT**
- **His verdicts**: the ⌘` keyboard loop, Z-from-pane zfs circuit
  (verbs on the tree cursor, Enter-into-mountpoint, post-enact tree
  truth, typed destroy), vim/htop/⌃C in the shell — plus the ORIGINAL
  10.1 list (snapshot loop feel) and the second-press one-liner still
  owed. Then: close 10.1 → tag v0.5 on main → fold the integration
  branch's fixes back into ho-11/ho-10.3 closes (the branch IS the
  hands session record) → merge to main → hands-verified close of both.

**ACTION ITEMS / BLOCKS**
- No blocks. App instance quit (his ⌘Q, ~00:00); relaunch:
  `cd /tmp/palana-ho11 && .build/debug/Palana` (run_in_background).
- Fixture VM left RUNNING for the resumed hands session (stop with
  `scripts/zfs-fixture.sh stop` when the walk is done).
- Post-merge follow-ups from the seventh block still open (tree-walk
  unit tests; SwiftTerm same-day-tag note for the v1.0 audit).
- ho-11/ho-10.3 docs need their Reflect sections amended with the
  hands-session corrections (⌘` not t/⌘Esc; Z ungated; panel click-only
  — my Decision-3 ⇧Z text was wrong in the app's grammar).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 waits on his 10.1 verdicts; ho-11 +
  ho-10.3 hands-session-hardened on the integration branch; v1.0 =
  ho-12 after.

---

## State summary — 2026-07-10, seventh block — THE HANDS ROUND BUILT LIVE; TWO HOS EXECUTED IN PARALLEL WORKTREES

**COMPLETED**
- **ho-10.1 hands round, built live on his verdicts** (three commits on
  main after the click fix): panel text scales with the size steps
  (keys-panel ruling applied); the tree reads cache-then-discovers-then-
  re-reads (angrybird-missing and create-not-showing both dead); every
  ready plan says "⏎ press enter to run this plan" in green in the term
  + the header's armed-Return block grew words; rollback/destroy-snapshot
  gathers list the dataset's snapshots under the field (ShellQuote went
  public for it); **typed destroy** — the word arms the verb, setting
  `confirmDestroyTyped` (default ON) in the new Workbench settings
  section frees it. Fixture pool mountpoints chowned to the ssh user
  (yank l→r was EACCES on root-owned /palana — machinery held, gates
  held); zfs-fixture.sh patched to chown on create.
- **His sequencing call, ratified**: "I DO want to wire up the terminal
  and the pane solution." ho-11 + ho-10.3 authored (Kamae 5, Think
  sealed at the top) and EXECUTED in parallel worktrees on sonnet;
  both reviewed at the top, both independently verified green.
  - **ho-11-terminal branch** (a4df114, /tmp/palana-ho11): SwiftTerm
    1.14.0 app-target-only; per-host LocalProcessTerminalView over the
    operator's own `ssh <alias>` (same config, same masters); plan panel
    third mode on `t` at terminal focus; Esc passes to vim, ⌘Esc comes
    home; failure law wired (onEnactmentFailed). 714 tests. NEW: a
    PalanaTests app-target test target exists at last.
  - **ho-10.3-pane-mode branch** (bc9eb72, /tmp/palana-ho103): pane
    Mode .files|.zfs, plugin-hued boundary, one cursor targets every
    verb, Enter-on-mounted exits into the mountpoint, panel DEMOTED
    (verb rows gone, zero mutation paths — grep-verified), afterZFS
    refresh mode-aware. Agent's flagged call: Z and ⇧Z are one token in
    this grammar, so bare Z = pane mode, panel moved to ⌘⇧Z. 708 tests.
- **ssh config gained an Include** of .fixtures/zfs-ssh-config (top of
  ~/.ssh/config) so the app + plain ssh resolve zfs-self; session.json
  pointed the right pane at zfs-self:/palana. Fixture VM RUNNING.

**NEXT**
- **His remaining 10.1 verdicts** (typed destroy live in the running
  build; snapshot loop; the click list) + the SECOND-PRESS mystery
  (Images #4/#5/#6 — something reappears on the second Enter; his one-
  line description still owed) → close ho-10.1 → **tag v0.5** → merge
  ho-11-terminal then ho-10.3-pane-mode (hand-merge: both reshape
  PalanaSession.swift; expect conflicts in monitor/extraction areas) →
  hands session per branch → README polish.

**ACTION ITEMS / BLOCKS**
- No blocks. Both branches wait on the v0.5 tag, not on build work.
- Post-merge follow-up: write the tree-walk unit tests ho-10.3 skipped
  (no app test target existed on its branch; ho-11's PalanaTests target
  arrives in the merge and unblocks them).
- SwiftTerm 1.14.0 was tagged upstream the same day it was pinned —
  builder diffed it vs 1.13.0 (iOS-side changes); Package.resolved pins
  exact. First dependency in the project; note for the v1.0 audit.
- Feel-checks queued: `t`-for-shell vs touch muscle memory; Z / ⌘⇧Z
  split; vim/htop/⌃C/resize in the shell.
- Session end: fixture VM to stop (`scripts/zfs-fixture.sh stop`);
  ~/.ssh/config Include line stays (inert when fixture is down) or
  comes out — his call. Dave still parked.

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 is his verdicts away; ho-11 and
  ho-10.3 built and reviewed, awaiting merge; v1.0 = ho-12 after.

---

## State summary — 2026-07-10, sixth block — THE CLICK HUNT ENDS: CODE, NOT MACHINE

**COMPLETED**
- **The click-offset bug is FOUND and FIXED** (50f34fb). The fifth
  block's "environmental" verdict was WRONG — post-reboot the bug
  persisted, the bare v0.4-beta binary clicked perfectly on the same
  loaded machine, and a five-step bisect across v0.4-beta..1e80c10
  landed on 9808498: the supplementary `.onDrag` added to nameCell
  (drag attempt three's belt-and-suspenders). A cell-level drag source
  wraps cell content in its own drag-hosting view and desyncs SwiftUI's
  drawn rows from AppKit's hit rects — hit zones one row high, top row
  under the header. Removed outright; TableRow.itemProvider carries
  pane-to-pane drag alone (he verified live: clicks true AND file
  dragged across panes, on 1e80c10 + removal).
- **Why the earlier exoneration lied**: PALANA_NO_DRAG stripped only the
  row itemProvider; the cell-level `.onDrag` stayed live. Banked.
- **The styler reentrancy fix committed as its own keeper** (f82ba7a):
  every table mutation deferred a runloop turn — AppKit's "reentrant
  operation in its NSTableView delegate… will become an assert" warning
  answered. Found en route, kept on merit; NOT the click cause.
- **Hunt fully torn down**: scratch gates (PALANA_NO_STYLER/NO_DRAG/
  CLICK_DEBUG) stripped, bisect + v0.4 worktrees removed, his real app
  state restored from `palana.click-quarantine`. Verification: format +
  lint strict green, 704 tests green (sshd-fixture integration suites
  skipped — Docker daemon down by design this session; failures were
  connection-refused only, untouched by this UI-only diff).

**NEXT**
- **The two small 10.1 fixes** (pool-root refusal; panel pre-select
  follows pane cursor on dataset mountpoints), then his close verdicts →
  close ho-10.1 → **tag v0.5, ZFS badged beta** → README/docs polish →
  he writes to Dave (ysap.sh; counsel: name the root wall, lead with the
  snapshot loop).

**ACTION ITEMS / BLOCKS**
- No blocks. The reboot-gate in the fifth block is CLEARED (bug was
  code, now fixed).
- Restarting integration fixtures (sshd container, `make zfs-fixture`)
  wants Docker Desktop up — start before the next integration-touching
  session; run the full suite then.
- Sequencing after v0.5 still HIS CALL (ho-11 first vs 10.2 first).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 is one ho-close + two small fixes
  away; v1.0 = ho-11 + ho-12.

---

## State summary — 2026-07-10, fifth block — THE HANDS SESSION, FOUR ROUNDS DEEP, REBOOT PENDING

**COMPLETED**
- **Four feedback rounds built live on his hands** (5d46527, 5508ebc,
  f35a833, e58cae2, 06707d7 — all CI-green; one runner flake rerun to
  green): the ZFS POP-OUT PANEL (first plugin panel, FavoritesPanel
  lineage, keys-panel stepped sizing ⌘1–5/⌘+/−), the two-column strip
  (plugins LEFT, solid cream-on-burnt-umber chips, Theme.plugin, green
  engagement line beside reads / umber line on the plugin edge), THE
  DATASET TREE in the panel (selection = target, ↑↓ walk, unmounted
  selectable and '· unmounted' in words, pre-select from pane path,
  right-click menu with all verbs + open-in-pane, ⇧⌘←/→ point a pane),
  panel persistence (Esc/✕ only). Create's verify reads name,mounted.
- **The Linux root wall fully mapped in anger**: delegated create lands
  unmounted; delegated destroy of a MOUNTED dataset fails (cannot
  unmount, permission denied). Works delegated: the whole snapshot loop,
  create(-unmounted), destroy-unmounted. THE PITCH LEAD: snapshot/
  rollback/destroy-snapshot over plain ssh, readable plan, native Mac —
  nobody else has it.
- **The two-cursor failure witnessed**: his destroy aimed at pool root
  (panel tree selection) while his pane cursor sat on angrybird — the
  panel-as-primary-mutation-surface is structurally confusing. His
  framing sealed: ZFS management is a SEPARATE activity → pane MODE with
  explicit boundary (background shift) is the right surface (ho-10.2/3).
- **Click-zone "bug" diagnosed ENVIRONMENTAL**: broken everywhere, on
  YESTERDAY'S binary too (bisect worktree, cleaned up) → his Mac: swap
  12.6/13GB, WindowServer 1.2GB after days of memory max. REBOOT is the
  fix; he's rebooting. Not pālana's code.

**NEXT**
- **Post-reboot, one pass**: restart fixture (`make zfs-fixture`), CLEAR
  STALE `.fixtures/zfs.env` first if suites dial a dead port, relaunch
  current build on fixture config, he clicks to confirm the heal.
- **Then two small 10.1 fixes**: verbs refuse the POOL ROOT dataset with
  a plain sentence (destroy/rename must not compose on it); panel
  pre-select follows the pane CURSOR when it sits on a dataset
  mountpoint (not just the directory). Then his close verdicts →
  close ho-10.1 → **tag v0.5, ZFS badged beta** → README/docs polish →
  he writes to Dave (ysap.sh, ZFS fiend, positioning review — counsel
  given: name the root wall in the README, lead with the snapshot loop).
- Sequencing HIS CALL, recommendation pending his word: v0.5 → ho-11
  terminal → ho-12/v1.0 → 10.2 (sudo mount capability + pane mode +
  settings trio) as first post-1.0 feature; alternative is 10.2 before
  ho-11.

**ACTION ITEMS / BLOCKS**
- BLOCKED only on his reboot + click confirmation.
- ho-10.2 SEALED scope grew: sudo -n mount capability + settings trio
  (sudoers helper, per-tool plugin toggles) + likely the pane mode
  (his ratified instinct; panel demotes to launcher/overview).
  Installable third-party plugins: post-v1 seed thinking, banked.
- ho-10 is CLOSED (read-only Workbench) — no gap before ho-11.
- Fixture VM dies with his reboot; angrybird mounted manually by him
  (root); t62-prx-* leftovers still in pool (fine — destroy targets).

**PROJECT LIFECYCLE**
- `beta` — v0.4-beta public; v0.5 (ZFS tool, beta badge) is one close +
  two small fixes away; v1.0 = ho-11 + ho-12.

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
  no per-action gate). Also sealed for ho-10.2's settings work: per-tool
  toggles for built-in plugins ("lets do 1 for now… its low cost");
  INSTALLABLE third-party plugins banked as post-v1 seed-level thinking,
  not a ho.
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
| **v0.5** | Phase 4 (Workbench — ZFS tool, pane mode, mount seam) + Phase 5 (interactive terminal) complete — the mutating ZFS story hands-hardened; integration branch merged to main (`8004eb2`), 781 tests |
