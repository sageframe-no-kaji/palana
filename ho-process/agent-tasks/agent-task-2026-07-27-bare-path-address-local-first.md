---
created: 2026-07-27
type: agent-task
status: ready
project: palana
---

**Goal**

A bare absolute path typed or pasted into the address field or the go-to
sheet — no `host:` prefix — resolves as a path, local first: if it exists on
this Mac, the pane points there; otherwise, if the pane is on a remote host,
try that host; otherwise refuse naming both places looked. `host:path` and
bare-host-alias input keep their exact current behavior.

**Problem**

`pointAddress` (`Sources/Palana/PaneModel.swift:483`) has two branches:
colon → split into `host:path`; no colon → the entire input is treated as a
host alias (`point(host: typed, path: "~")` — the "bare host means home"
feature). A pasted Mac path like
`/Users/atmarcus/Library/CloudStorage/GoogleDrive-atmarcus@gmail.com/My Drive/Job Search/2026/57`
contains no colon, so it is never considered as a path, and the operator is
forced to type `local:` first. Observed in the field 2026-07-27.

**Context**

Practitioner decision: resolution order is **local first** — the dominant
case is pasting a path from Finder or another Mac app. Named tradeoff,
decided, not to be relitigated in this task: a path that exists both locally
and on the pane's remote host (`/tmp`, `/etc`) resolves local under this
rule; an operator who means the remote one types `host:path`.

A file path landing in its parent folder with the file revealed is existing
go-to behavior (commit 53de538) — reuse it, don't reimplement. Host aliases
cannot begin with `/`, which is what makes the classification unambiguous.

**Files**

- Create: a typed-address classifier in `Sources/PalanaCore/Surface/`
  (pure: input string → host+path | bare path | bare host), named per the
  neighborhood's conventions (`PaneIntent.swift` is the register to match)
- Modify: `Sources/Palana/PaneModel.swift` (`pointAddress` resolves through
  the classifier; bare-path resolution order lives here)
- Modify: the go-to sheet's commit path if it does not already funnel
  through `pointAddress` — both entry points resolve through one function
  after this task
- Create/Modify: classifier tests in `Tests/PalanaCoreTests/`; resolution
  tests in `Tests/PalanaTests/` per that target's conventions

**Required Changes**

1. **Classifier in PalanaCore** — a pure function mapping trimmed input to
   one of: `hostPath(host, path)` (colon present, current split semantics),
   `barePath(path)` (begins with `/`, no colon), `host(alias)` (everything
   else — current bare-host behavior). `~`-leading input keeps its current
   meaning (the pane host's home); it is not part of the bare-path rule.

2. **Resolution in `pointAddress`** — `barePath` resolves in order:
   local existence check first — a directory points the pane at
   `local:` that directory; a file points at its parent with the file
   revealed (the 53de538 behavior). Not found locally and the pane is on a
   remote host: same check there, same directory/file handling. Found
   nowhere: a refusal in the existing error surface naming both attempts —
   e.g. `not found on this Mac or koan: <path>`. `hostPath` and `host`
   cases behave byte-for-byte as today.

3. **One funnel** — the pane address field and the go-to sheet (⇧⌘G) both
   commit through the same resolution function. If the go-to sheet currently
   has its own parse, unify; do not leave two parsers.

4. **Tests.** Classifier (Core): the Google Drive path above (spaces, `@`,
   no colon) → `barePath`; `koan:/tank` → `hostPath`; `koan` → `host`;
   `local:/Users` → `hostPath`; `/` → `barePath`; `~/notes` → not
   `barePath`. Resolution (app target, with existence checks injectable):
   local hit → local point; local miss + remote hit → remote point; both
   exist → local wins; neither → refusal names both.

**Acceptance**

- [ ] Classifier exists in PalanaCore with the three-case behavior above,
      fully covered by Core tests
- [ ] Pasting a colon-free absolute path that exists locally points the pane
      at it without a `local:` prefix (app-target test)
- [ ] Both-exist resolves local; neither-exists refusal names both places
      (app-target tests)
- [ ] `host:path` and bare-alias inputs unchanged (regression tests present)
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift build` and `swift test` pass; PalanaCore coverage stays ≥90%

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test

# Coverage floor (on demand)
swift test --enable-code-coverage

# One funnel: the go-to sheet and address field share the resolver
grep -rn "pointAddress" Sources/Palana | head
```

**Do Not**

- Do not probe the remote host when the local check succeeds — local-first
  is the decided order, and no network round trip should precede a local hit.
- Do not change `~` semantics anywhere; the site documents `~` as the remote
  user's home and this task doesn't touch that contract.
- Do not add a "did you mean host X?" inference from `@` or dots in the
  input. `/`-leading is a path; everything colon-free that isn't is a host
  alias, exactly as today.

**Stop Condition**

If the go-to sheet's file-reveal path (53de538) cannot be reused without
restructuring it, stop and surface — unifying the two flows may be its own
task, and this one shouldn't grow into it.

**Commit**

Single commit, repo message style (lowercase summary, no attribution
trailers):

```
address field: a bare absolute path resolves as a path, local first

Colon-free /-leading input is classified as a path, checked on this Mac
first, then the pane's remote host; refusals name both places looked.
host:path and bare-alias behavior unchanged.
```
