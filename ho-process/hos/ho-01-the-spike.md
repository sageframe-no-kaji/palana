---
created: 2026-07-03
status: complete
type: ho-document
project: palana
ho: 01
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-00-orientation
---

# ho-01 — The Spike

The go/no-go. The seed named one part of the architecture as unproven: a SwiftUI table holding a file-manager-density listing—a few thousand rows—under keyboard navigation with no perceptible lag. This ho builds the smallest thing that can answer that question honestly: a minimal SSH execution path, one real listing of 5,000 entries fetched over the wire, and a SwiftUI `Table` rendering it under sustained navigation, measured by frame.

Spike code is throwaway. It is committed once so the public record holds it, then deleted—Phase 2 starts clean. The findings graduate into this document and into ho-07's design. The code does not.

**Out of scope:** production code of any kind. Error taxonomy, session pooling, parsing rigor, the committed FileEntry model—all Phase 2.

**Resolves deferred decisions** (from the ho-overview):

- SwiftUI table vs `NSTableView` under a SwiftUI shell (deferred decision 1)

---

## Phase 1 — Think

### Decision 1 — Listing source: Docker sshd container, generated 5,000-entry tree

The listing comes over real SSH from a disposable `linuxserver/openssh-server` container on localhost:2222, authenticated by a spike-only keypair generated in the session scratchpad, reading a generated 5,000-entry directory tree bind-mounted read-only. Two alternatives were checked and rejected on this machine. The Mac's own sshd is running but has no authorized key for the account, and adding one is a persistent change to the practitioner's SSH surface that a spike does not justify. A live homelab host would be read-only and therefore legal under the hard limit—but there is no reason to stand near that line when a container gives exact control of row count and dies afterward. This also front-runs ho-02's fixture direction: the integration story is a local sshd container, and the spike is its first rough draft.

### Decision 2 — Evidence shape for "no perceptible lag": in-app frame instrumentation, internally driven

The practitioner's hands are not in this session, so feel is approximated by frame. The spike app instruments itself: a `CADisplayLink` (via `NSView.displayLink`, macOS 14+) records frame timestamps while an internal driver fires selection movement at keyboard-repeat cadence—single steps, page jumps, home/end sweeps—through the same state path a keystroke would take. Synthetic system-level key events were rejected: `CGEvent` injection needs an accessibility grant, which is a system permission the practitioner would have to click, and the delta it would add—NSEvent dispatch overhead—is negligible against the render cost being measured.

The verdict thresholds, committed before measurement:

- Sustained navigation at keyboard-repeat rate holds a median frame interval ≤ 16.7ms (60fps) with no hitch over 100ms.
- Time from data-ready to first rendered frame of the 5,000-row table under 1 second.
- Memory for the table stays flat during navigation (no unbounded growth).

If SwiftUI `Table` meets all three, SwiftUI wins and ho-07 builds on it. If it misses any, the committed fallback—`NSTableView` under `NSViewRepresentable`—gets the same protocol, and the verdict records both sets of numbers. Feel-validation by hand still happens at ho-07's UI/UX session; this verdict is the technology commitment, not the final word on feel.

### Decision 3 — Where spike code lives: `spike/`, its own package, deleted at close

The spike is a standalone SwiftPM package under `spike/`—not a target in the root package. The root package stays exactly as the scaffold left it, the coverage floor never sees spike code, and deletion at close is one directory. The spike is committed once (the record), then deleted in the closing commit (recoverable from history, absent from HEAD). Lint configs get a `spike/` exclusion only if the hooks demand it, removed in the same closing commit.

### Decision 4 — Spike data model is throwaway by construction

A minimal `SpikeEntry`—name, size, mtime, kind—parsed loosely from `find -printf` output. Deliberately not the committed FileEntry model, which is ho-04's decision to make with parsing rigor and both userlands in view. Nothing from this type survives the ho.

### Discovery (deferred to execution) — the numbers themselves

Frame statistics, first-render time, and memory behavior on this hardware (Apple Silicon, macOS 15) are the discovery. Recorded in Phase 3.

---

## Phase 2 — Execute

One bounded conversation—no agent-task decomposition. The seams here are artificial; the work is a single build-measure-record arc. Model: `claude-fable-5`.

The arc:

1. Stand the fixture up—container, keypair, generated tree (5,000 entries, mixed sizes and depths, some long names).
2. Minimal conduit: `Process` wrapping `ssh -p 2222`, one command, streams captured per the ho-00 primer (concurrent pipe drain, continuation on termination).
3. Fetch the listing—`find -printf` with tab-separated fields—and parse into `[SpikeEntry]`.
4. The spike app: SwiftUI `Table` over the 5,000 entries, keyboard-navigable for completeness, instrumented per Decision 2, internal driver, metrics written to a JSON file on quit.
5. Run, collect, and if thresholds fail, repeat with `NSTableView`.
6. Verdict into Phase 3, spike committed then deleted, overview updated with Checkpoint 1.

### Done means

- The 5,000-row verdict is recorded below with the measured numbers, and deferred decision 1 is resolved for ho-07.
- The spike code is deleted from HEAD. The findings are not.
- Checkpoint 1 (first contact with the stack) is recorded in the overview with a continue/replan recommendation.

---

## Phase 3 — Reflect

### The verdict: SwiftUI `Table`. `NSTableView` not needed.

Deferred decision 1 resolves for SwiftUI. The numbers, from `ho-01-metrics-swiftui.json` (raw evidence, committed alongside this document), on the practitioner's hardware—Apple Silicon, 120Hz display, 8.33ms frame budget:

| Measure | Threshold | Measured |
|---|---|---|
| Sustained arrows (300 down + 200 up, 30Hz) | median ≤16.7ms, no hitch >100ms | median 8.33ms, max 19.6ms, zero hitches >33ms |
| Page-down sweep (60 pages, 10Hz, full table) | no hitch >100ms | median 8.33ms, 5 hitches >33ms (worst 40.1ms), zero >100ms |
| End → Home → End jumps | no hitch >100ms | 2 hitches >33ms (worst 35.0ms), zero >100ms |
| First render, 5,080 rows | <1s | 164ms |
| Memory across full traversal | no unbounded growth | 25MB → 56MB, bounded row materialization |

Run validity: the table held key focus (`tableFocused: 1`), selection moved 501 times through the real event dispatch path, fetch was 198ms and parse 53ms for 5,080 entries over real SSH. The table never dropped below the display's own refresh cadence during sustained navigation. The go/no-go answers go.

### Where the ho-00 primer was wrong, and the correction

The primer offered `FileHandle.bytes` as one of two acceptable drain patterns. It is not acceptable. Its iterator issues a blocking `read()` on a cooperative-pool thread, and with two pipes to drain, the second reader starved while ssh blocked writing into the full 64KB stdout pipe—a deadlock observed and sampled, not theorized: the remote `find` had finished, the ssh client sat alive mid-write, and one cooperative thread held a bare `read` syscall. The correction: `readabilityHandler` feeding an `AsyncStream`, which drains on its own dispatch queue and delivers EOF as empty `availableData`. **ho-02's Conduit builds on the readabilityHandler pattern.** The rest of the primer held—termination race handled by setting the handler before `run()`, concurrent drain before awaiting exit.

### What first contact surfaced for Phase 2

- Container-local listing round-trip: ~200ms for 5,080 entries, 353KB, cold ControlMaster-less connection each time. Session reuse (ho-02) attacks exactly this.
- macOS key semantics at the table: arrows move selection, page/home/end scroll without moving it. The measured final selection index (2156) reflects mixed semantics worth pinning down when the keyboard grammar is designed—ho-07 territory, noted here so it isn't rediscovered.
- Two spike conveniences worth keeping as patterns, not code: the headless probe target (UI and wire isolated from each other when something hangs) and the watchdog (a hung GUI run self-reports and exits nonzero instead of eating minutes).
- The sshd fixture stood up in one `docker run` with a spike-only keypair—ho-02's fixture story is confirmed cheap. The spike container is removed with the spike; ho-02 builds its own with a committed script.

### Checkpoint 1 — first contact with the stack: continue as planned

The one genuine go/no-go answered go with an order-of-magnitude margin. SSH orchestration from Swift concurrency surfaced one real trap, now named and corrected into ho-02's design input. No process-handling friction beyond it, no listing-latency surprise, no concurrency behavior that reshapes the plan. **Recommendation: open Phase 2 as planned. No insertions, no replan.** Spike code deleted at close; Phase 2 starts clean.

---

_Authored: 2026-07-03 (Think phase)._
_Executed and reflected: 2026-07-03. Spike committed, then deleted—findings graduate, code does not._
