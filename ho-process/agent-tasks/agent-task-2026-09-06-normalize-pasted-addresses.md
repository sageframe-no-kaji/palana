---
created: 2026-09-06
type: agent-task
status: ready
project: palana
---

**Goal**

Make the pane address field and `⇧⌘G` go-to sheet accept pasted paths reliably through one parser. Bare path input resolves deterministically to this Mac, explicit `host:` input resolves remotely, and clipboard quoting or escaping is removed without executing shell syntax.

**Problem**

The current `TypedAddress.classify` trims only spaces, treats `~/notes` as a host alias, and treats the first colon anywhere as a host separator. The go-to sheet has a separate host picker and always prepends that selected host, so pasting a local path while a remote pane is focused sends the input to the remote host.

Copied paths may also arrive with a trailing newline, enclosing straight or smart quotes, `file://` encoding, or shell-style escaped spaces. Those wrappers currently become literal pathname characters and make valid pastes fail.

**Context**

Practitioner decisions, 2026-09-06:

- No setting controls bare-path scope. The same pasted address must mean the same thing on every installation.
- `/path` and `~/path` mean this Mac, regardless of the focused pane or whether the path also exists remotely.
- `local:/path` is explicitly local.
- `koan:/path`, `koan:~/path`, and `koan:` explicitly name a remote host; an empty remote path means that host's home.
- `:/path` is the explicit shorthand for the current pane's host.
- The interface shows the resolved host before navigation.

This task supersedes the remote-fallback portion of `ho-process/agent-tasks/agent-task-2026-07-27-bare-path-address-local-first.md`. A bare path no longer probes the current remote host after a local miss; local is a semantic default, not an existence-based guess.

Sequence this task after the full-review repair tasks `repair-ssh-configuration` and `enforce-path-and-read-safety`, because all three touch address or path boundaries.

**Files**

- Modify: `Sources/PalanaCore/Surface/TypedAddress.swift`
- Modify: `Sources/Palana/PaneModel+Address.swift`
- Modify: `Sources/Palana/PaneModel.swift` (`pointBarePath` and obsolete remote-fallback helpers)
- Modify: `Sources/Palana/GoToBar.swift`
- Modify: `Sources/Palana/SurfaceView.swift`
- Modify: `Sources/Palana/PalanaSession.swift`
- Modify: `Tests/PalanaCoreTests/TypedAddressTests.swift`
- Modify: `Tests/PalanaTests/BarePathResolutionTests.swift` or replace it with an address-routing suite matching the new deterministic contract
- Modify/Create: focused go-to tests under `Tests/PalanaTests/`

**Required Changes**

1. **One pure normalization and parsing boundary.** Replace the current whitespace-only classifier with a pure `PalanaCore` parser that returns either a typed address or a specific parse error. Both the pane header and go-to sheet must call this same parser through `PaneModel.pointAddress`; no second parser or host-prepending path may remain.

2. **Normalize clipboard wrappers without guessing pathname content.** In order:
   - Remove leading and trailing Unicode whitespace and line terminators, a byte-order mark, and zero-width edge characters.
   - Remove exactly one matched pair of enclosing straight single quotes, straight double quotes, matching smart single quotes, or matching smart double quotes.
   - Decode common shell-copy escaping such as `My\ Folder`, escaped quotes, and escaped backslashes with a purpose-built lexer. Never invoke a shell.
   - Parse `file:///...` as a local file URL and percent-decode it through `URL`, refusing non-file URL schemes.
   - Preserve internal quotes, apostrophes, colons, spaces, and Unicode characters exactly.
   - Reject unmatched enclosing quotes, NUL characters, empty normalized input, and multiple pasted lines carrying more than one address. Do not silently take the first line.

3. **Apply a stable grammar after normalization.** Classification order must prevent colons inside local paths from becoming host prefixes:
   - `/path`, including `/tmp/a:b`, is a local path.
   - `~/path` and `~` are local paths.
   - `file:///path` is a local path after URL decoding.
   - `local:/path`, `local:~/path`, and `local:` are explicit local addresses.
   - `host:/path`, `host:~/path`, and `host:` are explicit host addresses; empty path means `~`.
   - `:/path`, `:~/path`, and `:` use the current pane host; refuse with a specific error when the pane has no host.
   - Preserve the existing colon-free bare-host shorthand (`koan` means `koan:~`) for compatibility. Other colon-free relative text is not newly interpreted as a local relative path.

4. **Bare local means local only.** Remove the existence-based `resolveBarePath` local-then-remote fallback and its remote probe. A normalized bare path points to `PalanaCore.localHostName` directly; normal pane reading still decides whether it is a directory, a file to reveal in its parent, or absent.

5. **Replace the go-to sheet's dual authority.** `GoToBar` becomes one address field rather than a host picker plus independent path field. Prefill it with the current pane's explicit address (`host:path`) so the existing location remains visible, but replacing it with a pasted bare path changes the resolved scope to local.

6. **Show resolution before commit.** While the field contains a valid address, show a quiet resolved-scope line such as `this Mac · /Users/...`, `koan · /srv/...`, or `current pane: koan · /srv/...`. Show parse errors inline and disable Go until the address parses.

7. **Do not perform shell expansion.** `$HOME`, command substitution, backticks, pipes, redirects, semicolons, and glob characters are never executed or expanded. They remain literal pathname characters only where the grammar already establishes a path; otherwise the parser refuses them as malformed host input.

8. **Tests.** Add a table-driven hostile clipboard corpus covering:
   - trailing newline and surrounding whitespace;
   - straight-quoted and smart-quoted local and remote addresses;
   - escaped spaces, quotes, backslashes, and apostrophes;
   - `file:///Users/Andrew/My%20File`;
   - `/tmp/a:b` remaining local;
   - `~/notes` and `~` resolving local;
   - `koan:/tank`, `koan:~/notes`, and `koan:`;
   - `:/tank` with a remote, local, and absent current host;
   - `local:/Users` and `local:`;
   - matched quotes removed once while internal quotes remain;
   - unmatched quotes, NUL, non-file URLs, and multi-address pastes refused;
   - shell expressions never evaluated;
   - a bare local miss never probing or falling back to the pane's remote host;
   - both the header field and go-to sheet routing through the same function.

**Acceptance**

- [ ] Pasting a quoted, newline-terminated, escaped, or `file://` local path into `⇧⌘G` resolves to this Mac.
- [ ] Bare `/...` and `~/...` input never depends on pane focus, a preference, path existence, or a remote probe.
- [ ] Explicit `host:` and `:/path` forms resolve according to the grammar above.
- [ ] A colon inside an absolute local path does not create a host prefix.
- [ ] The go-to sheet has one address authority and shows the resolved host before navigation.
- [ ] Malformed or multi-address input produces a visible refusal and no navigation.
- [ ] No pasted content is executed or expanded by a shell.
- [ ] Existing bare-host-to-home behavior remains covered.
- [ ] Format, lint, build, tests, and PalanaCore coverage pass.

**Verification**

```bash
xcrun swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict --quiet
swift build --disable-sandbox
swift test --disable-sandbox
swift test --disable-sandbox --enable-code-coverage
scripts/coverage-floor.sh 90

# One parser funnel: inspect every caller after tests pass.
grep -RIn "TypedAddress\|pointAddress" Sources/Palana Sources/PalanaCore

# The obsolete existence-based remote fallback is gone.
grep -RIn "resolveBarePath\|existsThere" Sources Tests \
  && echo "obsolete bare-path fallback remains" && exit 1 || true
```

Manual check after automated verification:

1. Focus a pane on a remote host.
2. Open `⇧⌘G` and paste a local Finder path surrounded by quotes and ending in a newline.
3. Confirm the sheet shows `this Mac` before Go and the pane lands locally.
4. Repeat with `koan:/...` and `:/...`; confirm each shows its resolved remote host before Go.

**Do Not**

- Do not add a default-host setting.
- Do not use the selected or focused pane as an implicit fallback for bare paths.
- Do not invoke `/bin/sh`, `wordexp`, or any command-line parser on clipboard content.
- Do not strip unmatched quotes or arbitrary leading characters; refuse ambiguous input instead.
- Do not normalize the path internally beyond removing documented clipboard wrappers.
- Do not change SSH alias validation; the full-review SSH configuration task owns it.

**Stop Condition**

If replacing `GoToBar`'s host picker conflicts with an accessibility or navigation contract not represented in current tests, stop and surface that contract before retaining two independent address authorities.

If shell-style escape decoding cannot distinguish a copied wrapper from a literal backslash without corrupting an existing valid pathname, stop and present the ambiguous cases rather than deleting backslashes heuristically.

**Commit**

Single commit, repo message style, with subject:

```text
pasted addresses resolve through one grammar
```

The body should name the stable local default, explicit current-host shorthand, clipboard normalization, removal of remote fallback, and test count.
