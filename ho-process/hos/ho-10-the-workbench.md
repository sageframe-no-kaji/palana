---
created: 2026-07-06
status: closed
type: ho-document
project: palana
ho: 10
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-02-the-conduit
  - ho-03-the-field
  - ho-08-the-surface-plan-and-enact
  - ho-9.3-the-mounts-fact-and-the-host-map
agent-tasks:
  - Ho-10-AT-01.md
  - Ho-10-AT-02.md
---

# ho-10 — The Workbench

The Workbench API is the commitment kamae-2 made and never cashed: hand a plugin the Conduit, the Field, and a surface slot, and the core stays closed. This ho builds that boundary and proves it by use—not with the full ZFS tool the overview named, but with the read-only tools strip the practitioner asked for after driving the map. Simple buttons on the right side of the terminal—`df`, `zfs list`, `zpool status`—each one a command run against a host with its raw output dropped into the transcript, no parsing, no interpretation. The transparency is the feature. He watched `zpool status` be the only place a pool's drives live and said the tool should just show it.

The reshaping, named plainly: the overview's ho-10 (Phase 4) reads "Plugin API + the ZFS tool as proof—dataset CRUD, snapshots, pool visualization." That was mutating work. The practitioner sealed a smaller first cut—read-only reads as the Workbench's first consumer, mutation deferred—and this ho honors it. The boundary still gets built and still gets proven by a real tenant. What changes is the tenant: reads now, writes later. **This is a forward-only reduction of ho-10's first-consumer scope, recorded in the kamae-4 build record, flagged here for the overview—the deferred ZFS mutating tool (dataset CRUD, snapshots, mountpoint set and clear) wants its own ho on the same interface, a kamae-4 amendment this ho does not make.**

**Out of scope:** Every mutating verb. Dataset CRUD, snapshots, mountpoint management—all defer to the ZFS tool that fills the mutating seam this ho names but does not build. Parsing tool output into facts (the map's `zpool status` drives are a followup—raw text first, a fact only if the map later earns it). A dedicated host selector for the strip (v1 aims at the focused pane's host—Decision 1). Dynamically loaded bundles (kamae-2 prepared for them, does not build them; the tool is a compiled-in target). An interactive type-into-it terminal (kamae-2 holds it at "later"—the strip runs composed commands, it is not a shell).

**Resolves deferred decisions** (from the overview's Phase 4 and the practitioner's sealed direction): which host a button aims at, capability gating per host, whether the strip grows the terminal or opens its own surface, the shift-tab focus story, and the plugin verb seam where mutation lands.

---

## Phase 1 — Think

### Decision 1 — A button aims at the focused pane's host

The Workbench reads the ground the operator is already looking at. A tool button runs against `focusedPane.state.host`—no new host-picker ceremony, no parallel selector. The field view and the host map answer "which hosts exist"; the focused pane answers "which host now," and the strip follows it. Local is a host—the `LocalConduit` path ho-07's promotion built—so `df` and `zpool status` read this Mac exactly as they read koan. When the focus moves, the strip re-gates against the new host (Decision 2). A dedicated Workbench target—pinning the strip to a host regardless of pane—is a refinement the hands may ask for; v1 follows the focus.

### Decision 2 — Each tool declares a capability, gated against the Field's facts

A button offers itself only when the focused host can answer it. Each tool verb carries a capability requirement checked against `HostFacts` before the button is live:

- `df` requires reachability alone—POSIX everywhere, BusyBox included.
- `zfs list` and `zpool status` require zfs present—the same signal the field card renders as its `zfs` token, the presence of a `zfsTopology` fact after discovery.

A button whose requirement the focused host does not meet renders disabled with a plain reason in reach of the cursor—"koan has no zfs," "not yet probed—the Field hasn't reached this host." An unprobed host disables the zfs buttons and names why; the operator probes from the field or the map, exactly as today. No silent absence—the map's law that a count is never hidden governs here too. Gating asks the Field's cached facts and never probes on its own; the tool is a reader, not a discoverer.

### Decision 3 — The terminal grows the strip; the Workbench is the plan panel come of age

The strip mounts on the right of the terminal that already exists—the plan panel's `EchoBuffer` transcript, the one real terminal surface kamae-2 permits. Two constraints from the system design decide this against a second, separate surface. Monospace appears exactly once, by commitment, and that once is the plan panel; a free-standing Workbench terminal would make it twice. And the plan panel is already a pane the grammar flows through—round 5's ruling—toggled by the backtick, persistent, focusable. It is the terminal the practitioner meant by "the right side of the terminal." The strip is a vertical column of buttons pinned to its trailing edge.

One rule keeps the plan panel's kamae-2 claim intact—that its transcript shows *the plan's* commands, checkable by watching them run. The terminal is either serving a plan or serving the tools, never both at once. While an operation gathers, is ready, or enacts, the strip disables—the transcript belongs to the plan. When the terminal is idle, the strip is live and its reads own a fresh transcript. A read never lands mid-plan, so the plan's claim never blurs.

The fuller Workbench surface—a home with its own chrome for mutating tools that need controls beyond a button, the surface slot kamae-2 promised its plugins—grows from here when a mutating tool needs it. v1 is the strip beside the one terminal. The seam (Decision 5) is what makes that growth additive rather than a rebuild.

### Decision 4 — Shift-tab is the door into the terminal

Tab switches panes—unchanged. Shift-tab moves focus into the terminal, and shift-tab (or tab) moves it back out to the panes. The focus model grows a third target: the two panes and the Workbench terminal, cycled by the tab pair. While the terminal holds focus, the transcript scrolls under `j`/`k` and the strip's buttons answer their key hints (each button names its key, the menu's precedent), so a read is a two-keystroke reach—shift-tab, then the letter—without leaving the keyboard. Focus leaving the terminal returns the grammar to the focused pane. This is the calm keyboard-first commitment reaching the Workbench: the strip is a mouse convenience and a keyboard verb both, never mouse-only.

### Decision 5 — The verb seam: reads run-and-echo, mutations compose-and-arm

The Workbench protocol is small. A `WorkbenchTool` declares an id, a label, and a set of verbs; on registration it receives the Conduit and the Field—kamae-2's two capabilities handed in—and nothing of PalanaCore's internals. A verb carries a label, a key hint, a capability requirement, and a kind. The kind is the seam:

- A **read** verb composes a command and a host, runs it through the Conduit, and streams the raw bytes to the transcript. No classification, no plan—a query is transparent by construction, the command shown and the output unparsed. This is the whole of v1: `df`, `zfs list`, `zpool status`, three read verbs on one read-only tool.
- A **mutation** verb composes a `PlanRequest`, hands it to the Plan Engine, and lets the plan render in the terminal for Enter to arm—the same trust placement every file operation already uses. The Surface never composes a mutating command; the Plan Engine classifies it, exactly as kamae-2 requires. Mountpoint set and clear, dataset create and destroy, snapshots—every one of them is a mutation verb the ZFS tool will declare, and every one rides the read-plan-then-Enter gate the operator already trusts.

v1 builds only the read path. The mutation path is the named seam: the protocol carries the verb kind, the routing distinguishes the two, and the read tool exercises the boundary end to end. The ZFS mutating tool, when its ho opens, is a second `WorkbenchTool` declaring mutation verbs—no new surface machinery, no core opened, the boundary proven read-only first and grown into writes deliberately. That is the overview's proof condition met: a diff of PalanaCore across the ZFS-tool ho will show the API growing or holding, never a plugin reaching inside.

### Discovery (deferred to execution) — where the protocol's types live

The Workbench protocol hands out the Conduit and the Field, both PalanaCore types, so the protocol can live in PalanaCore and the read tool beside it as a testable core type—the composition and gating are pure, the Conduit is already recorded in the test corpus. Whether the tool warrants its own target (`PalanaWorkbench`) or lands as a `Workbench/` group inside PalanaCore is an execution-time call: a single compiled-in read tool does not need a target boundary, and kamae-2's "compiled-in Swift target" is satisfied by either. The seam that matters is the protocol, not the target. Execution decides the file home against the code as it stands.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session—the ho-09 delegation verdict stands, reaffirmed across ho-9.1 through ho-9.3. The seam between the two tasks is exactly the Workbench API line: AT-01 is everything at or below it (the protocol, the read tool, the run path, the gating logic—testable against recorded and fixture conduits), AT-02 is everything above it (the strip, the focus story, the transcript wiring—hands-verified). AT-02 depends on AT-01.

### Ho-10-AT-01 — The Workbench protocol and the read-only tool

The `WorkbenchTool` protocol (registration, Conduit and Field handed in, verbs with kind and capability requirement), the read-verb run-and-echo path, the mutation-verb seam named and routed but unbuilt, and the first tool declaring `df`/`zfs list`/`zpool status` with their capability requirements. Full test battery: composition, gating against fact fixtures, the read path against a recorded Conduit, the seam's routing distinction. No Surface. → `ho-process/agent-tasks/Ho-10-AT-01.md` *(authored when execution opens, against the code as it stands)*

### Ho-10-AT-02 — The strip, the focus, the transcript

The tools strip on the terminal's trailing edge, capability-driven enable and disable with plain reasons, the read output wired into the `EchoBuffer` transcript with the plan-owns-it-or-tools-own-it rule, the third focus target and the shift-tab door, the button key hints. Hands-verified against the fixture and the practitioner's real config. → `ho-process/agent-tasks/Ho-10-AT-02.md` *(authored when execution opens)*

### Testing and iteration approach

Per-task verification is the standing rhythm—`swift-format lint --strict`, `swiftlint --strict`, `swift build`, `swift test`, coverage floor on PalanaCore, `gh run list` after push. AT-01 carries the coverage weight (the protocol and the tool are core); AT-02 is app-target surface with no test target, verified by build, lint, and the hands. The read commands run against the sshd container fixture (GNU), the local Mac (BSD), and—for the zfs verbs—the file-backed throwaway pool in the Lima VM. No mutating operation anywhere: every verb v1 ships is a read, and the fixtures are read only. A hands session at close drives the strip on the practitioner's real config, reads only, exactly as every UI/UX round has.

### Done means

- The Workbench protocol hands a tool the Conduit and the Field and a place to render, and PalanaCore is not opened to admit it—the boundary kamae-2 named, built and proven by a real tenant
- `df`, `zfs list`, and `zpool status` run against the focused host and drop raw, unparsed output into the terminal transcript
- A button gates on the focused host's facts—live when the host can answer, disabled with a plain reason when it cannot, never silently absent
- Shift-tab moves focus into the terminal and back, and the strip answers the keyboard as well as the mouse
- The mutation seam is named in the protocol and exercised by the read path's routing, so the ZFS tool's later ho declares mutation verbs without new surface machinery or a core change
- Verification rhythm green, coverage floor holds on PalanaCore, `gh run list` consulted after push, no verb mutates anything anywhere

---

## Phase 3 — Reflect

**The boundary held, and the read-only exercise was the right first proof.** The reads tool registered through the Workbench API and ran `df`, `zfs list`, `zpool status`, `zpool list` without reaching into PalanaCore—a diff of the core across execution shows the protocol added and nothing opened. The mutation seam (`VerbKind.mutation`, the `planRequest` hook) is named and tested-as-refused, but read-only exercise left the write path unexercised by design. ho-10.1 (the ZFS tool) is where the seam meets a real mutating consumer and either holds or shows its gaps.

**The reshape, named plainly—this ho is a split, not a shrink.** The overview's ho-10 was the plugin API *plus* the mutating ZFS tool (dataset CRUD, snapshots, pool visualization) as the proof. The practitioner sealed a smaller first cut: the protocol proven by a read-only consumer, mutation deferred. So ho-10 shipped the boundary and the reads tool. Nothing in the Workbench vision is dropped—it is sequenced along the split the overview already allowed. **ho-10.1 — The ZFS Tool** carries the mutating consumer the overview named. **ho-11 — The Interactive Terminal** carries the type-into-it shell kamae-2 held at "later." Both are on the forward plan now (kamae-4 amended); the plugin infrastructure they build on is done and proven.

**Decision review—terminal-grows-the-strip held under a hard hands session.** The strip lives on the plan panel's trailing edge, and across a long UI/UX session it earned its shape: fire-the-reads gating (dim only while a plan owns the terminal), the grid cells, hover-highlight, the key hints under an engage mode (backtick focuses the terminal, tool letters fire, every other key still reaches the panes), the reversed enact call-out, and a sizing floor that makes the smallest terminal hug the four chips. Aiming at the focused pane's host felt like the tool following attention—no host picker wanted. The grows-the-strip-versus-own-surface decision resolved by use: the strip is right, and the fuller Workbench surface waits for a tool that needs chrome beyond a button—ho-10.1's ZFS tool may be the one that asks.

**The focus story got reworked live.** shift-tab and backtick both engage the terminal, tool hints fire while the panes stay live, and esc out of a command now cancels it *and* drops into terminal focus with the tool keys hot. `⌘K` clears the transcript. `⌘+`/`⌘-`/`⌘0` zooms the panes and transcript together while the header chrome stays fixed.

**What broke that the tests could not catch—a night of layout and platform truth.** The macOS 26 toolbar glass platter cannot be removed per item—fought it a dozen rounds, then embraced it (each item wears its own clean platter, pālana split off with `ToolbarSpacer`). SwiftUI's `Table` swallows clean per-row hover (both `onHover` and `onContinuousHover` fired at random)—row hover was killed, and it needs the underlying `NSTableView` if ever wanted. Chip sizing, top-and-bottom clipping, and the "lampshade" (the panel overflowing the footer) were all layout math: the panel's floor must fit the whole strip, and the panes' floor must yield so the footer survives a small window.

**Followups.** ho-10.1 (the ZFS mutating tool—the seam's real test), ho-11 (the interactive terminal), a popout icon to open the terminal, the go-again verb keys (Y M R T) styled as menu glyphs in the hint line, the `zpool status` drives as a parsed fact for the map, and the design-polish this session pulled forward—the titlebar mark and platters, font zoom, header-click sort are 9.7/9.8 fragments that landed inside ho-10's commits, and the build-record entry names them so those hos know what is already done.

---

_Authored: 2026-07-06 (Think phase)._
_Closed: 2026-07-08—driven through a long UI/UX hands session, the practitioner's word "TIGHT." The Workbench boundary stands, proven read-only; the ZFS tool and the interactive terminal split forward to ho-10.1 and ho-11. 444 tests, 75 suites, CI green._
