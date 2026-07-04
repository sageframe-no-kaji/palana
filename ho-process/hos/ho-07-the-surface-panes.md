---
created: 2026-07-03
status: complete
type: ho-document
project: palana
ho: 07
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-01-the-spike
  - ho-04-the-listing
---

# ho-07 — The Surface: Panes

The first visible surface. Dual panes on ho-04's `PaneState`, rendered on the SwiftUI `Table` ho-01's verdict committed, driven by a keyboard grammar that starts as yazi's vocabulary and ends wherever the practitioner's hands prune it. The engine is wired through PalanaCore only—the Surface renders state, forwards intent, decides nothing. The ho ends in the first UI/UX session: the practitioner driving the panes, feel feedback recorded, scope-reshaping findings queued as new hos.

This is also the ho where the Palana app target stops being a placeholder. The register is the design language's: the good notebook—calm, almost no chrome, one interactive accent, everything background until called.

**Out of scope:** the plan panel and enactment (ho-08). The field view (ho-09). Any operation verb—copy, move, delete compose plans, and plans are ho-08's surface. Opening files. Search.

**Resolves deferred decisions** (from the ho-overview):

- Keyboard grammar specifics (deferred decision 6)—the starting vocabulary is committed here, the pruning belongs to the practitioner's hands at the session this ho ends with.

**Carries from Checkpoint 2:** the recursive-size question rides to this ho's UI/UX session. Whether `Plan.totalSize` should promise recursive truth for directories must have the practitioner's word before ho-08 opens—if the answer is yes, a facts ho slots in as ho-06.5.

---

## Phase 1 — Think

### Decision 1 — The grammar splits: bindings in the Surface, machinery in the core

The Surface owns the keyboard grammar (kamae-2's component slice), and the 90% floor lives in PalanaCore—so the untestable part has to be the trivial part. Everything that can be wrong is a pure function in the core: a `PaneIntent` enum naming what a keystroke means (cursor moves, selection changes, descend, ascend, sort, toggles), pure `PaneState` transitions applying each intent, and a generic key-sequence recognizer that turns keystroke streams into intents through a binding table—`gg` and `cc` are two-key sequences, so the recognizer holds a pending prefix and a table lookup, nothing more. The Surface holds only the binding table itself (declarative data: which key names which intent) and the SwiftUI event plumbing. Pruning the grammar after the hands session is editing a table, not rewriting logic.

### Decision 2 — The starting vocabulary: yazi's verbs under Mac muscle memory

Committed as the session's starting point, pruned by feel—the table the practitioner drives first:

| Keys | Intent |
|---|---|
| `j` / `k`, arrows | cursor down / up |
| `h` | ascend to parent (no-op at `/`) |
| `l`, Return | descend into directory (no-op on files—opening is no ho's scope yet) |
| `gg` / `G`, Home / End | cursor to top / bottom |
| Ctrl-`d` / Ctrl-`u`, PageDown / PageUp | cursor a half page / full page |
| Space | toggle selection on cursor entry, advance |
| Cmd-`a` | select all |
| Esc | clear selection, clear pending prefix |
| Tab | switch pane focus |
| `cc` / `cd` / `cf` / `cn` | copy path / directory / filename / name sans extension to clipboard (yazi verbatim) |
| `.` | toggle hidden files |
| `,n` / `,s` / `,m` | sort by name / size / modified—repeat flips direction |
| Cmd-`r` | refresh the focused pane (one listing command, per ho-04's budget) |
| Cmd-Shift-`g` | point the pane (Decision 4) |

yazi semantics where yazi has an opinion, Mac muscle memory where the platform does (`Cmd-a`, `Cmd-r`, `Cmd-Shift-g`), and no F-key row anywhere—the pre-seed interview settled that.

### Decision 3 — Cursor and selection on the `Table`: one binding, one mark

ho-04's model separates cursor from selection—yazi's model, and the Plan Engine composes against the selection set. SwiftUI `Table` has a single selection concept, so the mapping is: the `Table` selection binding IS the cursor (single-select), and the selection set renders as a mark on each selected row in the accent color. ho-01 recorded macOS's mixed native semantics—arrows move `Table` selection, page/home/end scroll without moving it. The grammar unifies to yazi's: every navigation key moves the cursor, and the view scrolls to keep it visible. Page and home/end get intercepted and driven through intents; whether the arrows can stay native without double-handling is an execution discovery.

### Decision 4 — Pointing a pane before the field view exists: Cmd-Shift-G

ho-09 owns pointing panes from the topology. Until then a pane has to be pointable somehow, and the honest interim is the platform's own muscle memory: Cmd-Shift-G, Finder's go-to, summoning a one-line bar—host picked from `Field.hosts()` or typed, path typed. This is scaffolding that outlives its scaffold role: after ho-09, the field view points panes at hosts and datasets, and go-to remains the path-level verb inside a host.

### Decision 5 — The engine stack in the app: one session object, calm errors

One `@MainActor` `@Observable` session object owns the engine—`SSHConduit`, `Field`, `Listing`—and two pane models hang off it. Repointing a pane runs the ho-04 wiring exactly: ask the Field for facts, run `discover` if the capability fact is missing, pass the flavor to `list`. A repoint cancels the previous load. Every failure arrives typed—`ConduitError`, `ListingError`—and renders as a quiet line in the pane where the entries would be. No alert sheets, no dialogs: a pane that cannot read says so in place and waits. The app closes the Conduit's sessions on quit, because nothing outlives the window.

### Decision 6 — session.json lands now

Kamae-2's data model names it and the README's first session opens with it—"the panes are where you left them." A `SessionSnapshot` value in PalanaCore (Codable: each pane's host, path, sort, hidden-files toggle, plus which pane holds focus) with load/save against `~/Library/Application Support/palana/session.json`, tested in the core against temp directories. The app restores at launch—panes re-point and re-list from live truth, never from cached entries—and saves on change and at quit.

### Decision 7 — `PaneState` grows `showHidden`

The Listing returns dotfiles (`find -mindepth 1` sees them), so hiding is display state and belongs on `PaneState`: `showHidden: Bool`, default false, `.` toggles, `sortedEntries()` filters before ordering. ho-04's document committed the model and stands unedited—the code grows forward, and this is the record of the growth.

### Decision 8 — The visual first cut: the notebook, in placeholder values

Per the design language: system font, near-black ink on a warm quiet ground, one interactive accent carrying the cursor row, the selection marks, and the focused-pane indicator. Each pane gets a one-line header (`host : path`, quiet) and the window gets a one-line footer (entry count, selection count, pending key prefix, sort). No toolbar, no buttons, no sidebar. Directories distinguished by weight and a trailing slash, not iconography. Monospace appears nowhere—it is reserved for ho-08's plan panel. The palette values are placeholders for the hands session: feel feedback prunes them, and a design-polish ho queues if the gap demands one.

### Discovery (deferred to execution) — the Table's real manners

Whether native arrow handling and the grammar's cursor stay coherent or double-fire; how `Table` scroll-to-cursor behaves at 5,000 rows; whether re-sorting on every state change holds the ho-01 cadence or wants memoization; what a bare `swift run Palana` needs to front its window (activation policy). All answered against the running app and recorded in Reflect.

---

## Phase 2 — Execute

One bounded conversation—no agent-task decomposition. Model: `claude-fable-5`.

Order of work:

1. Core machinery: `PaneIntent`, pure `PaneState` transitions, the key-sequence recognizer, `showHidden`—full unit batteries.
2. `SessionSnapshot` with load/save, tested against temp directories.
3. The app: shell, dual panes on `Table`, binding table, event plumbing, go-to bar, session restore, the notebook first cut.
4. Live against the sshd fixture: both panes reading real listings, the vocabulary driven end to end.
5. Full verification rhythm; floor holds; commit.
6. **The first UI/UX session: ping ntfy, the practitioner's hands on the panes.** Feel feedback lands in Reflect; scope-reshaping findings queue as new hos; the recursive-size question gets his word.

### Done means

- `swift run Palana` opens dual panes that render real listings through PalanaCore and navigate without stutter—ho-01's 120Hz cadence is the reference.
- The starting vocabulary works end to end: navigation, selection, clipboard verbs, sort, hidden toggle, refresh, go-to, pane focus.
- The session restores where it was left.
- PalanaCore holds the floor; lint, format, build, test all green.
- The practitioner has driven the panes—feedback recorded, findings queued, the ho-06.5 bracket answered.

---

## Phase 3 — Reflect

**Did the Table hold at real density with the grammar on top?** At 3,000 fixture entries under live driving, yes — with one real gap the spike could not have seen: the `Table` does not follow programmatic selection, so a keyed cursor ran off screen ("screen doesn't scroll if you key past the bottom," the session's first finding). `ScrollViewReader.scrollTo` on cursor change fixed it. One resistance stands: the native selection row paints in the system accent, not the theme's — `.tint` does not reach it. Queued for the design-polish pass, not fought here.

**The UI/UX session, three rounds live.** The practitioner drove while the session ran, and the ho grew by feedback rounds instead of closing at first contact — the autonomous shape's version of the feedback loop working better than designed. What the hands changed: reads commit only on success — a bad pointing leaves the pane where it was and says why in a banner ("should not take you out of where you were"); the header path is click-to-type; the unfocused pane sits a shade dimmer; right-click carries the clipboard verbs; `?` summons the vocabulary card, because a grammar that lives in a notification is not discoverable; Enter and `l` open files through a size-guarded temp fetch — which sent `readFile` composition down into the core's Listing, where composition belongs. The verdict on the vocabulary itself: "i like the vim keys" — deferred decision 6 resolves as yazi-under-Mac, kept whole. Space stays selection over Finder-preview muscle memory, revisitable by feel.

**Decision review.** The bindings-data/machinery-core split held under pressure: three feedback rounds edited app-target views and one binding table; the core changed only to gain `readFile`, and the Surface still composes nothing. The rows-as-parameter correction (made before the app was built) was right — sorting per keystroke would have been the stutter the register forbids. The read-then-commit restructure is the one Think-phase miss worth naming: Decision 5's original shape mutated the pointing before the read, and the hands caught it inside an hour.

**The recursive-size word: "we NEED to know the WHOLE contents, not just the next level down. 100% recursive."** ho-06.5 slots in before ho-08, recorded in the overview.

**Followups queued, for Checkpoint 3's consolidation or the ho that owns them:** following symlinks on descend; the selection-color/system-accent question and palette values (design polish); Space-to-open reconsideration; dataset and mount-boundary indicators in the pane (rides the Field's facts, ho-09 territory); rename/copy/paste/delete are ho-08 as sequenced. One operator-truth note for the docs: on the fixture container home is `/config`, and `~` resolving there read as a bug twice — the field-use docs should name what `~` means on a remote.

---

_Authored: 2026-07-03 (Think phase). Executed and closed: 2026-07-03, through a live three-round UI/UX session._
_208 tests, 40 suites. PalanaCore holds the floor._
