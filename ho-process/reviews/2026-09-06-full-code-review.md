# Full Codebase Review — 2026-09-06

## Ruling

The review found 28 actionable defects: 5 Critical, 14 Major, and 9 Minor. The findings cover the complete Swift codebase rather than a recent diff.

The Critical findings can cause destructive action against the wrong dataset, deletion after an inadequately verified transfer, or automatic overwrite of remote work. They should block release until repaired and tested.

## Verification Performed

- Reviewed all 22,956 lines under `Sources/Palana` and `Sources/PalanaCore`.
- Traced trust boundaries through SSH configuration, shell composition, cached host facts, plan composition, enactment, process ownership, and round-trip editing.
- Ran `swift build --disable-sandbox`; it passed.
- Ran `swift test --disable-sandbox`; 946 tests in 143 suites passed, with the fixture-dependent ZFS suites skipped.
- Ran `xcrun swift-format lint --recursive --strict Sources Tests`; it passed.
- Ran `swiftlint lint --strict --quiet`; it passed.
- Reproduced `find missing-path | wc -l` returning status 0 despite the `find` error.
- Reproduced the create guard missing a dangling symlink and `touch` creating its target.

Passing tests do not invalidate the findings because the coverage floor excludes the application layer where several failures live, while existing transport tests assert count equality rather than content identity.

## Required Repair Order

1. Establish real process ownership and cancellation.
2. Replace count-based move verification with identity verification.
3. Refresh and bind plan-critical topology facts.
4. Make round-trip conflict detection fail closed.
5. Bind asynchronous operations to immutable source and destination identities.
6. Repair SSH parsing, alias validation, and configuration transactions.
7. Correct ZFS postcondition verification.
8. Bound remote reads and retire temporary resources.
9. Repair remaining state races and misleading classifications.
10. Expand tests around the application orchestration layer.

This order is intentional. Process cancellation and verification are shared foundations, so repairing higher-level workflows before them would either duplicate work or preserve unsafe behavior underneath a cleaner surface.

## Findings

- SEVERITY: Critical
- WHERE: `Sources/Palana/OperationModel+Gather.swift:38`, `Sources/PalanaCore/Field/Field.swift:83`, `Sources/PalanaCore/Plan/PlanEngine.swift:218`
- ISSUE: Destructive ZFS plans trust topology and mount facts cached across launches. `ensureFacts` never refreshes an already-known host, while failed topology probes retain older values, so a changed mountpoint can make Palana send and then destroy a dataset unrelated to the selected path.
- FIX: Refresh every plan-critical topology fact immediately before composition, attach its generation to the plan, and revalidate dataset identity and mountpoints before enactment.

- SEVERITY: Critical
- WHERE: `Sources/PalanaCore/Transports/Transports.swift:59`, `Sources/PalanaCore/Transports/Transports.swift:187`, `Sources/PalanaCore/Transports/Transports.swift:213`
- ISSUE: Move verification compares only recursive object counts before releasing source deletion. Equal counts do not prove equal bytes, types, permissions, links, or names, while `find ... | wc -l` returns success when `find` fails; a missing-path reproduction returned status 0 and count 0.
- FIX: Generate exact manifests containing relative paths, types, sizes, and hashes, require every producer command to succeed, and delete the source only after exact manifest agreement.

- SEVERITY: Critical
- WHERE: `Sources/Palana/PaneModel.swift:597`, `Sources/Palana/PaneModel.swift:612`, `Sources/Palana/PaneModel.swift:629`
- ISSUE: Remote-open records use the pane's current directory after the asynchronous download finishes rather than the directory where the file was opened. Navigating during the download therefore records another directory, and the default automatic send-back can overwrite a same-named file there.
- FIX: Capture the host, directory, full remote path, and operation generation before downloading, then construct the record only from those immutable values.

- SEVERITY: Critical
- WHERE: `Sources/Palana/OperationModel+RoundTrip.swift:153`, `Sources/Palana/OperationModel+RoundTrip.swift:180`, `Sources/Palana/SettingsModel.swift:100`
- ISSUE: Any error while checking the remote destination is converted into "no conflict." Because automatic send-back is enabled by default, a timeout, permission failure, malformed listing, or lost connection disables the overwrite guard and immediately authorizes the upload.
- FIX: Return `clean`, `conflict`, or `unavailable`; only `clean` may auto-send, while `unavailable` must block until a successful recheck or explicit override.

- SEVERITY: Critical
- WHERE: `Sources/Palana/OperationModel+RoundTrip.swift:166`, `Sources/PalanaCore/Surface/RoundTrip.swift:325`, `Sources/PalanaCore/Listing/BSDListingParser.swift:23`
- ISSUE: Remote deletion is not treated as a conflict, and existing files are compared only by size and modification time. A deletion is silently undone, while a same-length edit within BSD's integer-second or BusyBox's coarser timestamp resolution is overwritten automatically.
- FIX: Treat absence as a conflict, record a content digest when fetching, and perform a conditional atomic replacement only when the current remote digest still matches.

- SEVERITY: Major
- WHERE: `Sources/Palana/OperationModel.swift:388`, `Sources/PalanaCore/Conduit/Conduit.swift:29`, `Sources/PalanaCore/Conduit/SSHConduit.swift:148`
- ISSUE: Cancellation changes the UI state but provides no way to terminate the operating-system process. An `rm -rf`, `zfs destroy`, rollback, copy, or SSH process can continue after the interface reports cancellation, while abandoned pipes can leave processes blocked indefinitely.
- FIX: Make `RunningCommand` own idempotent process-group termination, invoke it from cancellation handlers, drain or close every pipe, and report cancellation only after all child processes exit.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/Transports/SSHPipeline.swift:23`, `Sources/PalanaCore/Transports/SSHPipeline.swift:90`
- ISSUE: The producer process is launched before the consumer, but consumer-launch failure does not terminate the producer. The same pipeline has no cancellation handler, so either half can survive a failed or abandoned transfer.
- FIX: Retain both `Process` objects, terminate the producer when consumer startup fails, and use structured cleanup that always closes and awaits both halves.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/Field/SSHConfigParser.swift:328`, `Sources/PalanaCore/Field/SSHConfigParser.swift:343`, `Sources/PalanaCore/Field/SSHConfigParser.swift:410`
- ISSUE: SSH block boundaries recognize only the next `Host`, not `Match`. Removing a host can therefore delete the following `Match` policy through the next host or end of file, while removing one alias from `Host foo bar` deletes both aliases and their shared settings.
- FIX: Parse both `Host` and `Match` boundaries, remove only the requested alias token from shared blocks, and preview all affected policy before writing.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/Field/SSHConfigParser.swift:181`, `Sources/PalanaCore/Field/HostBlock.swift:63`, `Sources/PalanaCore/Plan/PlanEngine.swift:385`
- ISSUE: Host aliases accept shell metacharacters and leading hyphens, then several tar and ZFS commands interpolate those aliases into shell syntax without quoting. This permits command or SSH-option injection through an alias that the application itself considers valid.
- FIX: Restrict aliases to a safe SSH destination grammar, reject leading `-`, quote every alias that reaches a shell, and execute pipelines with argument arrays rather than composed shell text.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/PalanaCore.swift:17`, `Sources/PalanaCore/Conduit/RoutingConduit.swift:30`, `Sources/Palana/PalanaSession.swift:209`
- ISSUE: The string `local` is both a valid SSH-config alias and the magic local-machine sentinel. A real `Host local` is shown in the host list but every operation against it executes on the operator's Mac instead.
- FIX: Represent endpoints as `.local` and `.ssh(alias)` values rather than strings, or reject the reserved alias during parsing and onboarding.

- SEVERITY: Major
- WHERE: `Sources/Palana/RoundTripCenter.swift:61`, `Sources/Palana/RoundTripCenter.swift:109`
- ISSUE: The round-trip queue has one slot, so a save from file B replaces a pending save from file A. A's watcher event has already been consumed, which can leave A's edit permanently unsent.
- FIX: Queue records by stable identity and coalesce only repeated saves of the same record.

- SEVERITY: Major
- WHERE: `Sources/Palana/PalanaSession+RoundTrip.swift:49`, `Sources/Palana/RoundTripCenter.swift:174`, `Sources/PalanaCore/Surface/RoundTrip.swift:262`
- ISSUE: Every successful copy into a watched host and directory refreshes every watcher in that directory. If that refresh reaches a watcher before an already-pending filesystem event, its baseline advances and the unsent edit is discarded as unchanged.
- FIX: Carry the exact round-trip record identifier through the plan and completion event, then refresh only that record after its confirmed upload.

- SEVERITY: Major
- WHERE: `Sources/Palana/RoundTripCenter.swift:33`, `Sources/Palana/RoundTripCenter.swift:88`, `Sources/Palana/PaneModel.swift:618`
- ISSUE: Every remote open creates another permanent watcher and temporary directory, with no deduplication, close operation, eviction limit, or cleanup. Repeated opens consume two file descriptors per record and retain downloaded remote data until process or operating-system cleanup.
- FIX: Add record retirement, watcher cancellation, temporary-directory deletion, duplicate reuse, and bounded session-level eviction.

- SEVERITY: Major
- WHERE: `Sources/Palana/PaneModel.swift:606`, `Sources/PalanaCore/Listing/Listing.swift:84`, `Sources/PalanaCore/Conduit/Conduit.swift:66`
- ISSUE: The 50 MB open limit checks stale listing metadata, then `cat` and `collect()` accumulate the actual file without a byte ceiling. A file that grows or is replaced after listing can consume arbitrary memory and disk; remote binary preview uses the same whole-file path.
- FIX: Enforce the limit while streaming, terminate at limit plus one byte, add a timeout, and write bounded chunks directly to the temporary file.

- SEVERITY: Major
- WHERE: `Sources/Palana/SettingsModel.swift:245`, `Sources/Palana/SettingsModel.swift:273`
- ISSUE: `addHost` converts any read or UTF-8 decoding failure into an empty configuration, then backs up that empty string and replaces the real SSH config with only the new block. All config mutations also lack a content-version check, so concurrent edits from another program can be silently overwritten.
- FIX: Fail closed on reads, preserve raw bytes, lock or coordinate the transaction, compare the original digest before replacement, and retain versioned backups.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/Plan/PlanEngine.swift:528`, `Sources/PalanaCore/Plan/PlanEngine.swift:534`
- ISSUE: The create guard uses `test -e`, which is false for a dangling symbolic link, then `touch` follows that link. A reproduced create left the link intact and created its target outside the chosen directory.
- FIX: Refuse when either `test -e` or `test -L` succeeds, then verify with `lstat` semantics that the created directory entry itself is a regular file.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/Listing/FileEntry.swift:124`, `Sources/Palana/PaneModel.swift:253`, `Sources/Palana/PaneModel.swift:597`
- ISSUE: `FileEntry.name` is explicitly a lossy display string, but navigation, opening, preview, favorites, and round-trip paths use it as identity. Invalid UTF-8 names can target a different replacement-character entry, fail unpredictably, or upload an edited copy under the wrong filename.
- FIX: Construct paths from `nameData` through byte-preserving filesystem APIs, or refuse actions on names that cannot be represented exactly.

- SEVERITY: Major
- WHERE: `Sources/PalanaCore/Plan/PlanEngine+ZFSComposition.swift:204`, `Sources/PalanaCore/Plan/PlanEngine+ZFSComposition.swift:242`, `Sources/PalanaCore/Plan/PlanEngine+ZFSComposition.swift:263`
- ISSUE: ZFS property, mount, and unmount verification checks only whether `zfs get` or `zfs list` exits successfully. It never asserts the requested mountpoint value or expected mounted state, so a failed state transition can be reported as "every step ran and checked out."
- FIX: Parse the returned value and require exact equality with the requested property or mounted state.

- SEVERITY: Major
- WHERE: `Sources/Palana/OperationModel.swift:562`, `Sources/Palana/PalanaSession+ZFS.swift:304`
- ISSUE: Workbench reads drain stdout completely before beginning stderr. A command that fills stderr while stdout remains open deadlocks both the child and application task, and the function never checks the command's exit status.
- FIX: Drain both streams concurrently, await exit, retain bounded stderr, and surface every nonzero result.

- SEVERITY: Minor
- WHERE: `Sources/PalanaCore/Plan/PlanEngine+SameFilesystem.swift:6`, `Sources/PalanaCore/Plan/PlanEngine.swift:279`
- ISSUE: Every local move without contrary facts is labeled a same-filesystem instant rename. Cross-volume `mv` is actually copy-then-delete, so progress, duration, interruption behavior, and risk are misrepresented.
- FIX: Compare source and destination device identifiers before classifying the move; use an explicit verified copy/delete route when equality is unproven.

- SEVERITY: Minor
- WHERE: `Sources/Palana/OperationModel+ZFS.swift:120`
- ISSUE: Snapshot-context tasks are neither stored nor tied to a host, dataset, or gather generation. A late result from gather A can populate or reset gather B, showing the wrong snapshot names and rejecting valid input.
- FIX: Cancel the prior task and commit results only when a captured generation, host, dataset, and verb still match current state.

- SEVERITY: Minor
- WHERE: `Sources/Palana/DragDrop.swift:414`, `Sources/Palana/DragDrop.swift:445`
- ISSUE: Finder-drop destination host and path are read after awaiting the source listing. If the destination pane navigates during that interval, the plan targets the new location rather than the location receiving the drop.
- FIX: Capture the destination locus synchronously when the drop occurs and use it unchanged.

- SEVERITY: Minor
- WHERE: `Sources/Palana/OperationLog.swift:74`
- ISSUE: Directory creation, file opening, seeking, and writing errors are all swallowed, while the interface can still report full success. Disk-full or permission failures therefore erase the operation record without any warning.
- FIX: Track log health separately from transfer success, surface a persistent warning, and explicitly flush and close the handle.

- SEVERITY: Minor
- WHERE: `Sources/PalanaCore/Field/SSHConfigParser.swift:147`, `Sources/PalanaCore/Field/SSHConfigParser.swift:186`
- ISSUE: Tokenization does not implement inline SSH-config comments. `Host source-host # production` produces bogus aliases `#` and `production`, while commented text after `Include` is treated as more include paths.
- FIX: Stop tokenization at an unquoted `#` according to OpenSSH configuration rules.

- SEVERITY: Minor
- WHERE: `Sources/PalanaCore/Conduit/SSHConduit.swift:26`, `Sources/PalanaCore/Conduit/SSHConduit.swift:126`
- ISSUE: `ControlPersist=yes` leaves authenticated SSH master sessions running indefinitely after a crash, despite the comment claiming a later startup sweep. `closeAll` knows only hosts opened by the current process, and no startup sweep exists.
- FIX: Use a finite persistence interval and remove or close stale owned sockets during startup.

- SEVERITY: Minor
- WHERE: `Sources/PalanaCore/Plan/Collision.swift:203`, `Sources/Palana/PlanPanel.swift:152`, `Sources/Palana/PalanaSession.swift:487`
- ISSUE: A kind collision is displayed as "won't work," but the plan remains ready and Enter still executes it. Multi-entry commands can mutate earlier entries before failing on the known-invalid collision, leaving a partial destination.
- FIX: Refuse plan composition when any kind clash exists, or disable enactment until the clash is resolved.

- SEVERITY: Minor
- WHERE: `.github/workflows/ci.yml:47`, `Scripts/coverage-floor.sh:13`
- ISSUE: The coverage gate explicitly excludes the entire `Sources/Palana` application layer, which contains the cancellation, remote-editing, configuration, and orchestration failures above. The passing 946-test suite therefore does not exercise several highest-risk state transitions.
- FIX: Include application logic in coverage and add deterministic tests for `OperationModel`, `RoundTripCenter`, `SettingsModel`, stale topology, and process cancellation.

- SEVERITY: Minor
- WHERE: `Sources/Palana/SettingsModel.swift:307`
- ISSUE: Settings encoding, directory creation, and atomic writing failures are silently discarded. The interface reflects changed safety settings even when they will revert at restart.
- FIX: Retain persistence status, report failed writes, and distinguish saved values from unsaved in-memory state.

## Handling Recommendation

Do not assign all findings to one agent in one pass. Split the repair into dependency-ordered tasks, require a separate commit and focused tests for each task, and run the full suite after every task that changes process, plan, or transport contracts.

The first implementation task should combine process ownership with cancellation because every later bounded read and transfer fix depends on a command that can actually be stopped. The second should replace move verification, and the third should establish fresh, version-bound topology facts before changing ZFS routing.

Round-trip editing should then be repaired as one bounded subsystem because its five findings share identity, queue, baseline, and lifecycle contracts. SSH parsing and configuration writes form another bounded subsystem, while ZFS postcondition checks, byte-honest paths, and the remaining races can follow independently.

Each repair task should contain its own adversarial acceptance cases rather than treating the current green suite as sufficient evidence. The Critical findings should remain open until their failure scenarios are reproduced by a failing test and then made to pass by the implementation.
