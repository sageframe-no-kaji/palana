---
created: 2026-07-08
type: agent-task
project: palana
parent-ho: 9.5
task: 01
model: claude-sonnet-4-6
status: ready
---

# Ho-9.5-AT-01 — The engine: HostBlock, validation, add and remove

**Goal**

Add the host-block value type and its ssh-config transforms to `PalanaCore`: `HostBlock` with validation and `compose()`, and `SSHConfigParser.adding`/`removing` as pure text transforms, with a full unit battery. Pure core work—no app target, no wire, no UI, no process execution.

**Context**

ho-9.5 Decisions 1–2 govern (read `ho-process/hos/ho-9.5-host-onboarding.md`). Read `Sources/PalanaCore/Field/SSHConfigParser.swift` in FULL first—you are extending it, and you must reuse its existing machinery, not duplicate it:

- `isAlias(_:)` — the rule for what's a real host alias vs a wildcard pattern (`*`/`?`/`!`). Alias validation reuses this logic.
- `findBlock(for:in:)` / `findBlockEnd(from:in:)` — block boundary finders used by `hiding`/`showing`. `removing` reuses them; `adding` uses `findBlock` to detect a duplicate alias.
- `hiding(alias:in:)` / `showing(alias:in:)` — the existing text-in/text-out transform shape (return `String?`, nil on no-op). Match it exactly.
- `blockIndent(lines:block:)` — reads the config's own indent; a new block uses four-space indent.

DocC on every public decl, one-line-summary-then-blank, in the committed-vocabulary voice.

**Files**

- Create: `Sources/PalanaCore/Field/HostBlock.swift` (`HostBlock`, its validation error type, `compose()`)
- Modify: `Sources/PalanaCore/Field/SSHConfigParser.swift` (add `adding(_:to:)`, `removing(alias:from:)`)
- Create: `Tests/PalanaCoreTests/HostBlockTests.swift` and add to the existing SSHConfigParser suite (or a new `SSHConfigAddRemoveTests.swift`—your call after reading the existing parser tests)

**Required Changes**

1. **`HostBlock`** — `public struct HostBlock: Codable, Sendable, Equatable` with `alias: String`, `hostName: String`, `user: String?`, `port: Int?`, `identityFile: String?`. A `validate() -> [HostBlockError]` (or throwing init—match whatever the codebase prefers; check how existing core types report validation) returning one error per broken rule:
   - alias empty, or not a single token (contains whitespace), or a wildcard/negation (fails `isAlias`)
   - hostName empty
   - port present and outside 1...65535
   `compose() -> String` renders the canonical block with four-space indent, emitting only lines whose value is present (always `Host` + `HostName`; `User`/`Port`/`IdentityFile` only when non-nil/non-empty). No trailing blank line inside the block.

2. **`SSHConfigParser.adding(_ block: HostBlock, to text: String) -> String?`** — returns nil when `block.alias` already exists in `text` (use `findBlock`); otherwise appends `block.compose()` at top level, separated from prior content by exactly one blank line (handle empty/whitespace-only input cleanly—no leading blank lines). Assumes the block is valid; validation is the caller's gate (but do not crash on an invalid one).

3. **`SSHConfigParser.removing(alias: String, from text: String) -> String?`** — returns nil when the alias isn't present; otherwise strips its block via `findBlock`/`findBlockEnd`, leaving surrounding blocks and `Include` lines intact, without leaving a double blank line where the block was.

**Battery**

- `compose`: full block (all fields), minimal block (Host + HostName only), each optional independently present; exact-string assertions on indent and line set.
- validation: each rule fires independently (empty alias, spaced alias, wildcard alias, empty hostName, port 0, port 70000); a fully valid block yields no errors.
- `adding`: into empty text, into text with existing blocks (appended after, one blank separator), duplicate alias returns nil, alias that is a substring of another alias is NOT a false duplicate.
- `removing`: a middle block (neighbors intact, no double blank), the only block, a block at EOF, an absent alias returns nil, an alias hidden by a `# palana: hide` comment still removes.
- Round-trip: `adding` then `removing` the same alias returns text equivalent to the original (modulo trailing whitespace—assert normalized).

Reuse the config-text fixtures the existing parser tests use. Assert long text by structure/anchors where exact strings get unwieldy.

**Do Not**

- Do not touch `Sources/Palana/` — that is AT-02.
- Do not execute any process, run ssh, or touch the filesystem outside test temp dirs — these are pure text transforms.
- Do not duplicate `findBlock`/`isAlias`/`blockIndent` — reuse them.
- Do not alter `hiding`/`showing` — `removing` is a distinct operation (truly strip vs curtain).

**Acceptance**

- [ ] `HostBlock` composes valid blocks and validates every rule; `adding`/`removing` transform text correctly and refuse the no-op cases with nil.
- [ ] Full suite passes (fixture-gated suites self-skip if fixtures are down).
- [ ] `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

Check the test run line itself — `swift test | tail` masks exit codes in chains.

**Commit**

Do not commit. The session reviews and commits.
