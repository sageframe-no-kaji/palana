---
created: 2026-11-19
type: review-closure
project: palana
cycle: palana-final-2026-11-18
---

# Final codebase review — owner closure

Cycle `palana-final-2026-11-18`: an independent final codebase review under the `ho-antagonist-review` skill. The full record (three reviewer reports, two builder responses, handoffs, evidence, and the skill snapshot that governed the cycle) lives in the external review directory `Documents/Codex/2026-11-18/` (`palana-review-pass-1/`, `-pass-2/`, `-pass-3/`). This file is the canonical summary and the owner's decision.

## Reviewer record

| Pass | Endpoint | Assessment |
|---|---|---|
| 1 | `3d7c1bc` | Return. F01–F03 critical (requirement conflicts), F04–F09 major, F10–F12 moderate |
| 2 | `ba32525` + first repair patch | Return. F03 regression (the proof read its own snapshot) and F05 incomplete (a queued save could start work after quit) |
| 3 | `ba32525` + second repair patch | **Pass.** F01–F12 resolved |

- Pass 1 had two contributors (Sol and Luna) consolidated into one assessment.
- Pass 3 used a fresh reviewer under the owner's budget exception (2026-11-19: "we will run the cycle until we are done").
- The repair builder was Claude, acting as builder and coordinator.

## Owner rulings

These supersede the named recipes in closed documents. Under forward-only discipline, the closed hos themselves are not edited.

- **F01 — keep dirty copies** (2026-11-18). Round-trip retirement deletes a per-open copy only when its bytes equal the record's confirmed remote version. Otherwise it keeps the copy and names it in the transcript and run record. Supersedes the cleanup clause of `agent-tasks/agent-task-2026-09-06-harden-round-trip-integrity.md`.
- **F02 — ask the filesystem** (2026-11-18). For arriving names with no byte-exact listing match, the destination is asked whether each name already resolves. A hit is a collision named with the listing's spelling. A failed probe, or a hit that matches no single listed name, makes collisions unknown. Supersedes ho-9.9's byte-exact-only recipe.
- **F03 — fence and prove** (2026-11-18). A whole-dataset move unmounts the source tree before its snapshot, and a busy dataset refuses. It destroys the source only when `written@<token>` is 0 for every live dataset (`-t filesystem,volume`); otherwise the source is kept and named. Supersedes ho-06.2's receive-equals-release recipe.

## Endpoint

The passed endpoint is base `ba325258c8be52cfc124ea842998743d1578b957` plus the second repair patch, a manifest of 485 files. It was committed byte-identically as seven commits on `repair/final-review-pass1`, ending at `ce53aa3`, and opened as PR #13 for the owner to merge.

## Owner decision (2026-11-19)

- **Acceptance: accepted with named limitations.** This is the owner's acceptance, separate from the reviewer's Pass.
- **Integration:** commit, push the branch, and open a PR; merging is the owner's.
- **Recordkeeping:** this file and the state memory.
- **Fixture:** stop `palana-zfs`.

## Limitations accepted

- **Not exercised:**
  - the SSH-container fixture suites;
  - corpus recording;
  - the opt-in no-hard-link volume test.
- **ZFS:** live evidence is from OpenZFS 2.4.1 on the Ubuntu Lima fixture only. FreeBSD/TrueNAS, other versions, zvols, and concurrent administrative changes after the proof read were not exercised. If a later step fails (send, receive, or verify), the source stays unmounted until the operator remounts it.
- **Not driven:**
  - the AppKit termination sequence;
  - physical keyboard and drag input;
  - a real external editor;
  - Quick Look rendering;
  - signed artifacts, packaging, and release.
- **Behavior:**
  - quitting stops a running transfer, with no confirmation;
  - kept F01 copies have no in-app discard;
  - the F02 probe adds one remote command per gather;
  - pane and preview reads sit outside the shutdown gate.
- **Previously accepted, unchanged:**
  - drag freeze (#4);
  - disabled remote external delivery;
  - deferred Finder Command-move;
  - opt-in rename race (#11);
  - non-root ownership loss;
  - retained send-back staging;
  - one-Enter naming.
