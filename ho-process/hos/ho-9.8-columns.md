---
created: 2026-07-10
status: open
type: ho-document
project: palana
ho: 9.8
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-04-the-listing
  - ho-07.5-the-busybox-userland
  - ho-9.4-favorites
agent-tasks:
  - Ho-9.8-AT-01.md
  - Ho-9.8-AT-02.md
---

# ho-9.8 — Columns

The pane shows name, size, and modified. His hands asked for the rest: drag the edges, choose which columns show, see created and last-changed, and—queued from ho-9.4—a star column marking the directories favorites already knows. The listing gathers permissions, owner, and group on every userland and then tells no one; the columns ho lets the gathered truth onto the screen and grows the two timestamps the listing doesn't gather yet.

Already landed, named so this ho doesn't rebuild it: header-click sort arrived inside ho-10's hands session (`Table` sortOrder through `PaneModel.applySort`).

**Out of scope:** type-to-jump—the Think question the ho-9.3 close queued here is answered below and the implementation deferred; it is a search feature, not a columns feature, and this ho is already the listing-surgery ho. Column reordering by drag (v1 keeps fixed order; the platform customization may give it free—if it does, take it, don't build it). Editing permissions/owner from the table. Per-host column sets—one customization serves the operator everywhere.

**Resolves the queued Think question (type-to-jump):** letters are verbs, so bare type-to-jump can't exist. The direction sealed here for a future slot: `/` opens a filter-jump field on the pathEditing stand-down lineage, filtering the visible rows as it types, Enter landing the cursor. Not built in this ho.

---

## Phase 1 — Think

### Decision 1 — The column set is the gathered truth plus two new timestamps and the star

v1 columns: name (fixed, always first), size, modified, created, changed, permissions, owner, group, ★. Default visible: name, size, modified—today's exact surface. Everything else arrives hidden, one right-click away.

### Decision 2 — created and changed gather at flavor fidelity, and a missing fact reads as a dash

`FileEntry` grows `created: Date?` and `changed: Date?`. The fidelity, sealed per userland to dodge vendor cliffs: **BSD** gathers both (`stat` speaks birth time and ctime—this Mac's APFS carries real birth times). **GNU** gathers `changed` (`find -printf '%C@'`, coreutils-stable) and leaves `created` nil—Linux birth time hides behind statx, `find` doesn't speak it portably, and a vendor-dependent flag is how ho-9.1 nearly shipped `mv -n`. **BusyBox** gathers neither—the date ladder stays untouched. Nil renders as a dash, and the column header tooltip names why. One round trip stays the law on every flavor.

### Decision 3 — The listing corpora re-record with the commands, recorder first

The GNU and BSD listing commands change, so their recorded corpora re-record—and the recorder re-learns the exchange before the corpus does; ho-9.3's review caught a recorder blind to a new exchange once and doesn't get to catch it twice. BusyBox commands don't change; that corpus stands.

### Decision 4 — Visibility and widths ride the platform's customization, persisted beside the session

SwiftUI's `tableColumnCustomization` (macOS 14, exactly our floor) gives the Finder-style header right-click—show, hide, resize, persist—without building a picker. The customization value persists to `columns.json` beside `session.json`, silent-fail like every store. If the platform API proves less Codable than advertised, the fallback is a small own-model visible-set persisted the same way—the AT names the escape hatch so the agent doesn't improvise one.

### Decision 5 — The star column shows favorites' truth and toggles it

★ renders on directories whose `host:path/name` favorites already holds—`FavoritesList.isFavorited`, the ho-9.4 truth, no second registry. A click toggles, same as `8` on the row. Files show nothing (a favorite is a location). Sortable so starred directories can gather at the top; sorting by a bool is stable and cheap.

### Decision 6 — New sort keys are core

`PaneState.SortKey` grows created, changed, permissions, owner, group, starred. Nils sort last, stably, whatever the direction—a column of dashes never shuffles.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.8-AT-01 — The engine: the timestamps, the listing surgery, the sort keys

`FileEntry.created/.changed`, GNU/BSD listing composes and parsers, recorder-then-corpus re-record, `SortKey` growth with nils-last, unit battery. → `ho-process/agent-tasks/Ho-9.8-AT-01.md`

### Ho-9.8-AT-02 — The Surface: the columns, the customization, the star

The six new TableColumns, `tableColumnCustomization` with `columns.json` persistence, the ★ column wired to favorites, sort wiring for the new keys. → `ho-process/agent-tasks/Ho-9.8-AT-02.md`

### Done means

- Right-click on the header shows/hides columns Finder-style; widths and visibility survive a relaunch
- created/changed carry real dates at each flavor's sealed fidelity and dashes where the flavor can't say
- permissions, owner, group columns show what the listing always gathered
- ★ marks favorited directories, toggles on click, sorts
- Header-click sort works on every visible column; nils sort last
- Both re-recorded corpora replay green; the recorder learned the exchange first
- Verification rhythm green, PalanaCore coverage floor holds

---

## Phase 3 — Reflect

_Filled at close._

---

_Authored: 2026-07-10 (Think phase). Born at Checkpoint 3's round-3 amendment—his hands on the column edges; the star column queued from ho-9.4._
