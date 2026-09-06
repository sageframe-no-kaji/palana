---
created: 2026-09-06
type: agent-task
status: complete
project: palana
---

**Goal**

A transfer that runs on this Mac uses the operator's real rsync, and the plan
names that binary by absolute path. Today a Finder-launched pālana finds only
Apple's `openrsync`, so `--info=progress2` never rides and no progress bar can
appear. After this task the plan reads
`/opt/homebrew/bin/rsync -a -s --partial --info=progress2 …`, the bar fills,
and the command pastes into a terminal and runs the same binary.

**Problem**

Measured on the practitioner's machine, 2026-09-06, mid-transfer:

- The running app's environment is `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. A
  Finder-launched Mac app never sources a shell profile, so `/opt/homebrew/bin`
  is not on it.
- His shell finds `/opt/homebrew/bin/rsync` → **3.4.1**. The app finds
  `/usr/bin/rsync` → `openrsync: protocol version 29`.
- `HostFacts.rsyncVersion` requires a dotted version, deliberately, so
  openrsync cannot masquerade as real rsync. "protocol version 29" has no dot
  → nil → `PlanEngine.modernRsync` false.
- So `rsyncFlags` takes the floor branch, `-a --partial`. No `progress2` output
  means `RsyncProgress` has nothing to parse and `PlanPanel.progressBar` is
  never reached.

The same root cause produces a second visible symptom, which is how it was
confirmed: remote paths came back inner-quoted
(`'koan:'\''/citadel-rex/…'\'''`), the `remotePath` branch that only runs when
`modernHere` is false.

Nothing is broken — openrsync transfers correctly and the degrade is by design.
The design simply assumed a Mac carrying openrsync *is* an openrsync Mac. It
does not account for a modern rsync being installed but unreachable, which is
the normal state of every Homebrew user, i.e. most of the beta audience.

It also dents the product's central promise: the plan shows `rsync -a --partial
…`, and pasting that into a terminal runs a *different program* than the app
ran. Same text, different binary.

**Context**

Decided with the practitioner, 2026-09-06, over two alternatives (extend the
app's PATH silently; add a Settings field). Naming the absolute path won because
it keeps the plan literally true about what will run. The PATH search is still
needed underneath it — without it the probe cannot *find* 3.4.1 to name.

Scope is **local only, by design, not by timidity**. Remote hosts are probed
over ssh with the remote's own non-interactive PATH, which is exactly the PATH
the operator gets from `ssh host 'rsync …'`. Remote plans are already truthful,
so they must stay byte-identical. Verified this session: `ssh koan` reports
rsync 3.2.7 correctly today.

Three couplings that will silently defeat a naive implementation:

1. **`Transports.swift:122` gates progress parsing on
   `step.command.hasPrefix("rsync ")`.** Naming the binary absolutely breaks
   that prefix and disables the very parsing this task exists to enable. This is
   the trap; change 4 exists for it.
2. **`RecordedConduit` lookup is exact `(host, command)`.** Changing the shared
   `CapabilityProbe.command` string invalidates `probe-container.json` and
   `zfs-pool.json`. A separate local-only command avoids all fixture churn —
   take that route.
3. **`HostCapability` is `Codable` and cached to disk** by the Field. A new
   field must be optional with a default so existing cache files still decode.

**Files**

- Modify: `Sources/PalanaCore/Field/HostFacts.swift` — `rsyncPath` on
  `HostCapability`
- Modify: `Sources/PalanaCore/Field/CapabilityProbe.swift` — a local-only probe
  command; `parse` learns one optional marker
- Modify: `Sources/PalanaCore/Plan/PlanEngine.swift` — compose the invocation
  from the resolved path
- Modify: `Sources/PalanaCore/Transports/Transports.swift` — recognize rsync by
  its binary name, not by a bare prefix
- Modify: `Sources/Palana/OperationModel+Gather.swift` — `localCapability()`
  runs the local probe
- Modify/Create: tests in `Tests/PalanaCoreTests/` per that target's conventions
  (`CapabilityProbeTests.swift`, `PlanCompositionTests.swift` have the natural
  homes; create `RsyncResolutionTests.swift` only if neither fits)

**Required Changes**

1. **`rsyncPath: String?` on `HostCapability`** — the absolute path the probe
   resolved, nil when it did not resolve one. Optional with a default so the
   existing four-argument `init` keeps compiling and cached JSON written before
   this change still decodes. Document it as local-only today: remote probes
   leave it nil on purpose.

2. **`CapabilityProbe.localCommand`** — a second command string beside the
   existing `command`, which is **not to be edited**. Same markers, plus
   `palana:rsyncpath:$(command -v rsync 2>/dev/null)`, and the whole thing run
   with a widened PATH so a Homebrew or MacPorts rsync is visible:
   `PATH=/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$PATH`. Because the
   PATH is widened for the whole command, the `palana:rsync:` version line
   reports **the same binary** `rsyncpath` names — they cannot disagree.
   `parse` gains `rsyncPath: nonEmpty(markers["rsyncpath"])`; the marker is
   absent from remote output and that stays nil, no branching.

3. **`PlanEngine` names the resolved binary.** Add a helper beside
   `rsyncFlags` — e.g. `rsyncInvocation(runningOn:operatorFlags:)` — returning
   `"\(capability?.rsyncPath ?? "rsync") \(rsyncFlags(...))"`. Replace the three
   `"rsync \(rsyncFlags(...))"` interpolations (currently lines ~306, ~353,
   ~398) with it. Pass the same capability each site passes today and change
   nothing else about them: a remote capability has a nil `rsyncPath` and yields
   bare `rsync`, so remote composition stays byte-identical and the local/remote
   asymmetry falls out of the data rather than a special case.

4. **`Transports` recognizes rsync by binary name.** Replace
   `step.command.hasPrefix("rsync ")` with a check on the **last path component
   of the command's first token** — `rsync` and `/opt/homebrew/bin/rsync` both
   match, `rsyncd` and `myrsync` do not. Put the predicate in a small testable
   function rather than inline in the enactment path, and keep the existing
   comment's intent (every rsync step, same-host copies included).

5. **`localCapability()` uses the local probe.** In
   `Sources/Palana/OperationModel+Gather.swift`, run
   `CapabilityProbe.localCommand` instead of `CapabilityProbe.command`. The
   memoization and nil-on-failure behavior stay exactly as they are.

6. **Tests.** Parser: `localCommand` output carrying `palana:rsyncpath:` parses
   into `rsyncPath`; remote-shaped output without the marker parses to nil;
   an empty marker value is nil, not `""`. Composition: a local capability with
   `rsyncPath` and a modern rsync composes
   `/opt/homebrew/bin/rsync -a -s --partial --info=progress2 …`; a capability
   with nil `rsyncPath` composes bare `rsync` **unchanged** (a regression test
   that pins remote plans byte-for-byte). Transports: the rsync predicate is
   true for `rsync -a …` and `/opt/homebrew/bin/rsync -a …`, false for
   `rsyncd …`, `myrsync …`, and `tar …`. Decode: JSON written without
   `rsyncPath` decodes with nil.

**Acceptance**

- [ ] A local capability carrying `rsyncPath` composes a plan naming that
      absolute binary, with `-s` and `--info=progress2` present
- [ ] A capability with nil `rsyncPath` composes exactly what it composes today
      — no remote plan text changes
- [ ] The progress predicate matches an absolute-path rsync command
- [ ] `CapabilityProbe.command` is unchanged, and
      `Tests/PalanaCoreTests/Fixtures/` is untouched
- [ ] A `HostCapability` JSON without `rsyncPath` decodes with nil
- [ ] `swift-format lint --recursive --strict Sources Tests` clean
- [ ] `swiftlint lint --strict` clean
- [ ] `swift build` and `swift test` pass; PalanaCore coverage stays ≥90%

**Verification**

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test

# Coverage floor
swift test --enable-code-coverage && scripts/coverage-floor.sh 90

# The shared probe and the recorded fixtures are untouched
git diff --stat -- Sources/PalanaCore/Field/CapabilityProbe.swift
git diff --exit-code -- Tests/PalanaCoreTests/Fixtures/ && echo "fixtures untouched"

# The prefix trap is gone
grep -n 'hasPrefix("rsync ")' Sources/PalanaCore/Transports/Transports.swift \
  && echo "STILL PRESENT — change 4 not done" || echo "ok"

# The resolved path reaches composition
grep -n "rsyncPath" Sources/PalanaCore/Plan/PlanEngine.swift
```

Hands check, after the build — the machine cannot prove this one. Rebuild the
app (`ARCH_FLAGS="" ./scripts/build_macos.sh`), launch it **from Finder** (a
terminal launch inherits the operator's PATH and hides the bug), and copy a file
large enough to see: the plan should name the absolute rsync and the bar should
fill.

**Do Not**

- Do not edit `CapabilityProbe.command` or anything in
  `Tests/PalanaCoreTests/Fixtures/`. Remote probing and its recorded transcripts
  are correct today; touching the shared command invalidates them for no gain.
- Do not set `process.environment` in `SSHConduit.spawn`. Widening the PATH for
  every spawned process — `ssh` included — is a larger change than this task
  authorizes, and the resolved absolute path makes it unnecessary.
- Do not add an rsync-path Settings field. It was considered and set aside.
- Do not change how `modernRsync` decides, or the dotted-version requirement.
  Both are correct; they were being fed a worse binary.
- Do not touch the zfs or tar transports.

**Stop Condition**

If `command -v rsync` under the widened PATH resolves to a binary whose
`--version` reports **no dotted version** on the practitioner's machine, stop
and surface it: the premise is that a modern rsync exists and is merely
unreachable, and if that is false the remedy is a different one.

If naming the absolute path turns out to break a plan-composition test that this
spec did not anticipate — anything beyond the three call sites in change 3 —
stop and report which, rather than widening the change to make it pass.

**Commit**

Single commit, repo message style (lowercase summary, no attribution trailers):

```
plans name the rsync they will actually run

A Finder-launched app inherits a minimal PATH, so pālana found Apple's
openrsync and never the operator's rsync 3.4.1 — no -s, no progress2, no
progress bar, and a plan whose text ran a different binary than the one it
named. The local probe now searches the usual prefixes and reports the
absolute path; local rsync steps name it. Remote plans are unchanged.
```
