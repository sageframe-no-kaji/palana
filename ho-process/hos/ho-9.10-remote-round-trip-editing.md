---
created: 2026-07-10
status: open
type: ho-document
project: palana
ho: 9.10
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-08-the-surface-plan-and-enact
  - ho-9.1-rename-and-create
  - ho-9.9-collision-facts
agent-tasks:
  - Ho-9.10-AT-01.md
  - Ho-9.10-AT-02.md
---

# ho-9.10 — Remote Round-Trip Editing

Enter on a remote file fetches a copy into a fresh per-open directory and hands it to the Mac's own editor. That much ho-9.1's errata made honest—no shared temp path, no second open destroying the first's edits. But the honesty stops at the fetch. The operator edits, saves, and the save lands in a temp directory nothing watches. The edit is stranded—silently, wearing saved-file clothes. ho-9.1's Reflect called it the data-loss gap, and the slate sealed the direction: watch the fetched copy, compose the upload as a plan when it changes.

The gate law holds the whole way. A save does not mutate the remote—nothing does without a plan read and Enter pressed. The save summons the plan; the operator sends it.

**Out of scope:** persistent watches across app launches—stranded edits from a previous run stay stranded honestly in their per-open directories, as they do today. Editing the remote file in place over the wire (a mount, an agent protocol)—the copy is the model. Conflict resolution beyond naming—when the remote changed since the fetch, the plan says so and the operator decides; no merge machinery. Watching local opens—local files open in place and need no round trip.

---

## Phase 1 — Think

### Decision 1 — The watcher is core, and it watches the directory, not the file

`RoundTripWatcher` lives in `PalanaCore`—it is local-filesystem machinery like `SessionStore`, and core residence puts it under the coverage floor where the tests can beat on it with real temp files. It watches the per-open directory's file descriptor (DispatchSource), not the file's: editors save by atomic replace—write-temp-then-rename—which silently kills a file-descriptor watch. The directory event plus a stat compare (size and mtime against last seen) is the change detector. Events debounce—an editor's save burst coalesces to one prompt.

### Decision 2 — The record remembers what was fetched

`RoundTripRecord`: host, remote directory, the `FileEntry` as fetched, the local URL. The fetch-time entry is the baseline for the changed-since-fetch question (Decision 4). Records live for the app's run; each remote open registers one.

### Decision 3 — A save summons the plan, and the panel is the surface

On a debounced change the app composes the upload—a copy plan, local temp file to the remote directory—through the standing engine and shows the panel in its ready phase, exactly as if the operator had pressed `y`. Enter sends. Esc declines and the watch keeps watching—the next save asks again. If a plan already owns the panel (gathering, naming, enacting), the upload waits and re-asks when the panel frees—no plan is ever evicted by a save. After a successful send the watch stays live and the baseline refreshes—the next save round-trips again.

### Decision 4 — The plan names a remote that moved underneath the edit

ho-9.9's collision line already names the overwrite—an upload always replaces the file it came from, and the line says so with the remote's current size and date. This ho adds the comparison that makes it a conflict fact: when the destination listing's entry differs from the fetch-time baseline (size or mtime), the gather notes it plainly—the remote changed since the fetch. The comparison is a pure core function. Naming, not resolving: the operator reads and decides.

### Decision 5 — The transcript says when a watch begins

A remote open notes `watching <name> — a save offers to send it back` in the terminal transcript. One line, no new surface, no indicator machinery—the watch's existence is legible where the operator already reads what pālana is doing.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01. ho-9.9 must be in the tree first—the upload plan's honesty rides its collision line.

### Ho-9.10-AT-01 — The engine: RoundTripRecord, the watcher, the baseline compare

`RoundTripRecord`, `RoundTripWatcher` (directory DispatchSource, stat compare, debounce), `changedSinceFetch`, unit battery with real temp files including the atomic-replace save. → `ho-process/agent-tasks/Ho-9.10-AT-01.md`

### Ho-9.10-AT-02 — The Surface: register, summon, send

Registration at the remote-open site, the round-trip center holding live watchers, the panel summon with wait-for-free, the changed-since-fetch note, the transcript line. → `ho-process/agent-tasks/Ho-9.10-AT-02.md`

### Done means

- A remote open registers a watch and says so in the transcript
- A save in any editor—including atomic-replace savers—summons the panel with the upload plan; Enter sends, Esc declines and the watch survives
- The collision line names the overwrite; a remote changed since fetch is named as such
- A busy panel is never evicted; the upload re-asks when it frees
- Nothing mutates the remote without Enter—the gate law is untouched
- Verification rhythm green, PalanaCore coverage floor holds

---

## Phase 3 — Reflect

_Filled at close._

---

_Authored: 2026-07-10 (Think phase). Queued from ho-9.1's Reflect—the open path ate an edit once; it doesn't get to again._
