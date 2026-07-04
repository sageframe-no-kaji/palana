---
created: 2026-07-03
status: draft
type: ho-document
project: palana
ho: 08
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-05-the-plan-engine
  - ho-06.1-the-transports-rsync-and-proxy
  - ho-06.2-the-transports-zfs
  - ho-06.5-recursive-size-facts
  - ho-07-the-surface-panes
---

# ho-08 — The Surface: Plan and Enact

The workflow the project exists for, made visible. Select the entries, press the verb, read the plan, press Enter—and everything that happens is something the operator saw first. The plan panel renders the committed Plan shape whole: classification, transport, auth path, exact commands, the recursive total ho-06.5 taught the engine to tell. Enter enacts through the Transports, and the panel's terminal surface echoes the truth live—real commands, real output, streaming, with progress from the event stream. The ho ends in the second UI/UX session: the practitioner reading plans and watching them run.

**Out of scope:** an interactive terminal—type into it, per host—is a Workbench tool for later; the v1 commitment is the echo, not the shell. Rename-in-place—`PlanRequest` carries a destination directory, not a target name, and growing the engine for renames is its own small ho, queued. A plan queue—one plan at a time in v1; the queue is post-release, and the Plan being a value is what makes it cheap later. Trash—remote hosts have no trash, and pretending otherwise is the kind of lie the panel exists to kill. BusyBox operations against zencat (ho-07.5). The field view (ho-09).

**Resolves deferred decisions** (from the ho-overview):

- Terminal surface implementation (deferred decision 7)—SwiftTerm embed vs a purpose-built streaming text view.

**Carries from the sessions between:** the practitioner's design input, verbatim—"a subtle directional arrow on selection showing send direction source→destination pane." And one verification debt from the fish wall: `SSHConduit` wraps every remote command in `sh -c`, but `SSHPipeline`'s remote halves are not yet wrapped—the proxied path against a fish-login host is unproven.

---

## Phase 1 — Think

### Decision 1 — Deferred decision 7 resolves: a purpose-built echo, not SwiftTerm

What the echo needs: append lines as chunks arrive, repaint the current line on a carriage return (`rsync --info=progress2` redraws in place), hold UTF-8 partials across chunk boundaries, never drop a byte, stay monospace. What it does not need: keyboard input, cursor addressing, alternate screens, a scrollback protocol. SwiftTerm is a terminal emulator with a keyboard—more than the echo needs, so the smaller thing wins, the overview's own criterion. The split follows ho-07's law: everything that can be wrong is a pure value in the core—`EchoBuffer`, fed `Data` chunks, producing lines, CR and partial-rune handling inside, floor-covered—and the Surface renders the buffer in a monospace text view and owns only scrolling.

### Decision 2 — The verbs: `y` copy, `m` move, `d` delete—one key, the other pane is the destination

kamae-2's core interaction commits the send model: "the move key goes down"—the focused pane's selection is the subject, the other pane's host and path are the destination. yazi's yank-then-paste is two placements of trust, and the panel-plus-Enter already holds the second one—a paste step on top would be ceremony. So the send verbs are one key each: `y` composes a copy toward the other pane, `m` a move, `d` a deletion (no destination). An empty selection means the cursor entry, the clipboard-verb precedent. Nothing enacts on the verb—the verb composes, the panel shows, Enter is the only trigger.

### Decision 3 — Local endpoints are in scope, and the plan never claims a forwarding that isn't happening

"local" heads the host menu and is the go-to default—an operation surface that refuses the local pane guts the workflow on day one. Two additions carry it. A `RoutingConduit` in the core dispatches by the reserved name—`local` to the `LocalConduit`, everything else to SSH—so the Transports enact mixed plans unchanged. And the auth path stays honest: with this machine at either end, rsync runs here and the operator's own agent authenticates—nothing is forwarded. `Transport` grows one case, `rsync from this machine · auth: this machine's agent`, and the engine selects it when either locus is local. The forwarding fact is not consulted for these plans because the question does not exist.

### Decision 4 — The forwarding fact gets its probe, in the Field, remembered

The system design's sentence—"the Field knows jodo can reach koan—probed once, remembered"—was never built. ho-05 and ho-06 composed against hand-fed facts, and today every cross-host plan would read proxied forever. The probe is one command on the source host through the Conduit: `ssh -o BatchMode=yes -o ConnectTimeout=5 <destination-alias> true`—exit 0 is `available`, anything else `unavailable`. It answers exactly the question the composed transfer will ask: the alias resolves in the source host's own ssh config AND the auth rides. `HostFacts` grows `forwarding`, keyed by destination alias and dated, cached in `field-cache.json` like every other fact. Gathered at plan time when missing, remembered after, re-probe belongs to the field view (ho-09).

### Decision 5 — The panel composes in the open: gather, then the Plan whole, then Enter arms

Composing needs round trips—capability discovery when a fact is missing, the forwarding probe the first time, `Listing.treeSizes` every time, fresh per plan. The panel opens on the verb immediately and names the gathering as it happens, one quiet line at a time. The Plan renders whole, once—nothing on a readable plan ever mutates, which is the value's contract made visual. Enter arms only when the plan is on screen. Esc dismisses at any point before it. `totalSizeComplete == false` renders as an explicit floor—the number is a floor, not a total, and the panel says which—with the final phrasing belonging to the hands session, per ho-06.5's handoff.

### Decision 6 — Enactment lives in the panel: echo, one bar, gates visible, Esc is cancel

Enter runs `Transports.enact` over the routing conduit and every event renders. `stepBegan` echoes the exact command—the same string the plan showed. Output chunks append through the `EchoBuffer`, stdout and stderr in arrival order. `ProgressReport` drives one bar—fraction when it can be stated honestly, indeterminate otherwise. Verification renders as its own lines: the counting command visible like everything else, then the counts and the verdict. `finished` refreshes both panes—one listing each—and the transcript stays until Esc, because reading what happened is the other half of reading what would. A failure stays on screen, typed, nothing auto-dismisses. During enactment Esc cancels the stream: gated steps never ran—that is the gate's whole law—and the cancellation line names what stopped where, including that an interrupted transfer may leave partial entries at the destination.

### Decision 7 — The send arrow, the practitioner's ask verbatim

"A subtle directional arrow on selection showing send direction source→destination pane." The divider between the panes carries a quiet arrow pointing from the focused pane toward the other whenever the focused pane has a subject—selection or cursor entry. The direction `y` and `m` would send, visible before any verb goes down. One glyph, accent-quiet, gone when there is nothing to send.

### Decision 8 — The panel is a bottom surface, and it holds the keyboard

The panel rises from the bottom, spanning both panes—monospace's only home in the app, per the design language. While it is up the pane grammar stands down, the same way the go-to bar and the help card hold the keyboard: Enter and Esc belong to the panel, `j`/`k` and the arrows scroll the transcript. The panes stay visible above it, dimmed the unfocused shade—the plan is about them.

### Discovery (deferred to execution) — throughput, the forwarding flag, and the fish wall

Whether the echo needs coalescing at `tar -v` line rates—batching appends per display tick if raw per-chunk appends stutter the register's cadence. Whether `SSHConfiguration` already carries `-A` where the probe and the forwarded transfer need it, or the flag arrives here. And the carried debt: whether `SSHPipeline`'s unwrapped remote halves misparse against a fish-login host—verified against the fixture, and if the wall is real, the fix is the same one round 5 landed: wrap at the one seam, `sh -c` with `ShellQuote`.

---

## Phase 2 — Execute

One bounded conversation—no agent-task decomposition. Model: `claude-fable-5`.

Order of work:

1. Core: `EchoBuffer`—chunks in, lines out, CR repaint, split-rune holds—synthetic battery first.
2. Core: `RoutingConduit` dispatching local vs SSH by the reserved name.
3. Core: the forwarding probe—`HostFacts.forwarding`, Field gathering, cache round trip.
4. Core: the engine's local branch—the new `Transport` case, selection when either locus is local, whole-dataset detection helper for the facts assembly—composition battery grown to match.
5. The app: `OperationModel` (compose → panel → enact → refresh), the plan panel with gathering lines and the echo view, the send arrow, three grammar rows.
6. Live against the fixtures: the kamae-2 §3 trace end to end—forwarded via the container's self-alias, proxied, local↔remote both directions, a deletion, gates observed, refused-walk floor rendered.
7. Full rhythm; floor holds; commit.
8. **The second UI/UX session: ping ntfy, the practitioner reads plans and watches them run.** Feel feedback lands in Reflect; findings queue as new hos.

### Done means

- A cross-host move traces end to end through the panel exactly as the system design's core interaction describes—plan read, Enter, echo streaming with no dropped lines, verification visible, gated delete after it, panes refreshed.
- Local↔remote copy and move work both directions, and their plans name this machine's agent, not a forwarding that isn't happening.
- A plan is never on screen in two states—it gathers openly, renders whole, and only then arms Enter.
- PalanaCore holds the floor; lint, format, build, test all green.
- The practitioner has read a plan, pressed Enter, and watched the truth run—feedback recorded, findings queued.

---

## Phase 3 — Reflect

*To be filled in after execution. Prompts:*

- **Did the echo hold at real line rates?** Where did the event stream surface what the recorded corpus didn't?
- **Decision review.** Was the purpose-built echo enough? Did the local branch and the probe land where the Think phase put them?
- **What the hands changed.** The second session's rounds, recorded.
- **Followups for ho-09 and Checkpoint 3.**

---

_Authored: 2026-07-03 (Think phase)._
_Execution and Reflect: pending._
