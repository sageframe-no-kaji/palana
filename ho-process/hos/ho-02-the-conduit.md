---
created: 2026-07-03
status: draft
type: ho-document
project: palana
ho: 02
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-01-the-spike
---

# ho-02 — The Conduit

The single door to the hosts. This ho builds the component every other component talks through: `run(host, command)` behind a protocol, the ControlMaster session lifecycle per host, and the error taxonomy that types every failure before anything above the door has to interpret raw process noise. The RecordedConduit test infrastructure is built here too, because it is the seam the whole testing strategy hangs on. Phase 2 begins—this is production code, and the 90% floor starts counting.

**Out of scope:** anything above the door—parsing, topology, plans. No component but the Conduit spawns a process toward a host, ever.

**Resolves deferred decisions** (from the ho-overview):

- ZFS fixture mechanics—Lima vs OrbStack, pool setup script (deferred decision 2)

**Carries from ho-00/ho-01:** CI lands here. Pipe drain is `readabilityHandler` streams, never `FileHandle.bytes` (ho-01's observed deadlock).

---

## Phase 1 — Think

### Decision 1 — Protocol shape: streaming primitive, collected convenience

The system design commits `run(host, command) → (stdout stream, stderr stream, exit status)`, and the streams are load-bearing—ho-06 parses progress from them live. So the primitive streams and the convenience collects:

- `protocol Conduit: Sendable` with `run(on:_:) async throws -> RunningCommand`, `close(host:) async`, `closeAll() async`.
- `RunningCommand` exposes `stdout` and `stderr` as `AsyncStream<Data>` plus `exitStatus() async -> Int32`. The caller drains—the ho-00 primer's discipline made structural.
- `collect() async throws -> CommandResult` drains both streams concurrently, awaits exit, and applies the taxonomy—the one-call path every non-progress caller uses.

A remote command exiting nonzero is data, not an error—`CommandResult` carries the status. Errors are the door failing, not the command.

### Decision 2 — Error taxonomy: classify ssh's stderr at exit 255

ssh reserves exit 255 for its own failures; everything else is the remote command's status. The taxonomy is a pure function—`(exitStatus, stderr) → ConduitError?`—classifying by stderr pattern: connection refused, timeout, and no-route surface as `hostUnreachable`, permission denials as `authenticationDenied`, host-key trouble as `hostKeyVerificationFailed`, closed connections and broken pipes as `connectionLost`, a missing binary as `launchFailed`, and an unmatched 255 as `sshFailure` carrying the raw stderr—typed, never swallowed. Pure means unit-testable against recorded stderr samples, which is where the floor's coverage comes from. The ambiguity that a remote command could itself exit 255 is real, documented, and accepted—ssh's own limitation, not pālana's to fix.

### Decision 3 — ControlMaster lifecycle: implicit open, explicit close, sockets in a short-path dir

Every command carries `-o ControlMaster=auto -o ControlPath=<dir>/%C -o ControlPersist=yes`—first use opens the master, every later command multiplexes, exactly the primer's mechanics. Close is explicit: `ssh -O exit` per host in `closeAll()`, which the app's quit path owns (bīja: nothing outlives the window). The socket directory is `/tmp/palana-cm-<uid>/`, mode 700, created on first use—`%C` is 40 hex characters and the macOS socket-path cap is ~104 bytes, so Application Support's long path is disqualified by arithmetic. Crash caveat, named: a crashed app leaks masters until reboot or next launch's `closeAll()` sweep. Accepted for v1.

The conduit is an actor. `Process` is not Sendable and per-host state wants isolation—the spike proved the shape.

### Decision 4 — RecordedConduit: transcript JSON, exact-match lookup, a recorder that wraps the real thing

`RecordedConduit` conforms to `Conduit` and plays back transcript files: JSON arrays of `{host, command, stdout, stderr, exit}` with lookup by exact `(host, command)`. A miss is a test failure that names the unmatched command—silent fallthrough is how fixture rot starts. `RecordingConduit` wraps any live conduit and writes the same format, because kamae-2 commits to recording real `zfs` output from the throwaway pool later. Transcripts live under `Tests/PalanaCoreTests/Fixtures/`.

### Decision 5 — ZFS fixture: Lima (deferred decision 2 resolved)

Lima over OrbStack. Neither is installed on this machine, so the tiebreak is character: Lima is open source, brew-installable, and fully scriptable; OrbStack is commercial. Docker Desktop's VM is disqualified—no ZFS kernel module. `scripts/zfs-fixture.sh` (with `make zfs-fixture` sugar) stands up a Lima VM, installs `zfsutils-linux`, and creates a file-backed throwaway pool; `make zfs-fixture-destroy` deletes the VM whole. The two-minute criterion is measured against re-create with the VM image cached—the first-ever run pays a one-time image download that belongs to the network, not the script. Both numbers get recorded honestly in Reflect.

### Decision 6 — CI: macOS runner, coverage floor enforced, integration against the runner's own sshd

`.github/workflows/ci.yml`, macOS runner: format lint, SwiftLint strict, build, `swift test --enable-code-coverage`, and a `scripts/coverage-floor.sh` that fails under 90% line coverage on PalanaCore. Integration tests run in CI against the runner's own sshd—GitHub's macOS runners are throwaway VMs where enabling Remote Login and self-authorizing a generated key is exactly what they exist for. Locally the same tests read connection facts from an env file that `scripts/sshd-fixture.sh` writes after standing up the container—the tests don't know which fixture they got. Tests skip, visibly, when no fixture file exists.

### Discovery (deferred to execution) — the stderr corpus and the timing numbers

The classification patterns come from the fixture's real stderr, captured per failure class, not from documentation memory. Session-reuse timing (cold vs multiplexed round-trip) gets measured and recorded—it is the number ho-04's one-command-per-refresh budget stands on.

---

## Phase 2 — Execute

One bounded conversation, this session—no agent-task decomposition. The seams (protocol, taxonomy, fixtures, CI) share one mental context and the tests couple them. Model: `claude-fable-5`.

Order of work:

1. `Conduit` protocol, `RunningCommand`, `CommandResult`, `ConduitError` + classifier—pure shapes first.
2. `SSHConduit` actor—argument assembly as a pure, tested function; thin spawn path on the readabilityHandler drain.
3. `RecordedConduit` + `RecordingConduit` + transcript format.
4. `scripts/sshd-fixture.sh` + integration tests: session reuse proven (master socket exists, second command faster), every failure class captured and typed.
5. `scripts/zfs-fixture.sh` + Makefile—stand up the pool, record the timings.
6. CI workflow + coverage floor script. Full verification rhythm.

### Done means

- Commands run against the sshd fixture with sessions reused, and every failure class the fixture can produce surfaces as a typed error—transcript in Reflect.
- RecordedConduit plays back captured transcripts; the pattern is documented for every downstream ho.
- `make zfs-fixture` produces a throwaway pool; timings recorded against the two-minute criterion.
- CI green on push with the coverage floor enforced; PalanaCore ≥90%.

---

## Phase 3 — Reflect

*To be filled in after execution. Prompts:*

- **Did the protocol shape survive contact?** What did the streams' consumers-to-be reveal?
- **The stderr corpus.** Which failure classes did the fixture actually produce, and did any resist classification?
- **The timing numbers.** Cold vs multiplexed round-trip. ZFS fixture stand-up, cold and cached.
- **Coverage.** Where the floor landed and what stayed uncovered, named.
- **Followups for ho-03.**

---

_Authored: 2026-07-03 (Think phase)._
_Execution and Reflect: pending._
