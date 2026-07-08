---
created: 2026-07-08
type: agent-task
project: palana
parent-ho: 9.5
task: 02
model: claude-sonnet-4-6
status: ready
depends-on: Ho-9.5-AT-01
---

# Ho-9.5-AT-02 — The Surface: the guided add-and-remove flow

**Goal**

Build the guided host-onboarding surface: an add-a-host form that composes and confirms a `Host` block, writes it through `SettingsModel`'s backup path, a per-host remove, a first-reach probe, and key-setup guidance that links to the companion guide. AT-01 (the `HostBlock` type and `SSHConfigParser.adding`/`removing`) is merged before this starts.

**Context**

ho-9.5 Decisions 3–6 govern (read `ho-process/hos/ho-9.5-host-onboarding.md`). Read these before writing and match their idioms:

- `Sources/Palana/SettingsModel.swift` — the backup-then-write-then-reload path (`.palana-backup`, atomic replace, `onConfigChanged`; the `includedFileNotice` surface for reporting). Add-and-remove writes go through this SAME path — no backup, no write. Do NOT write ssh config any other way.
- `Sources/Palana/SettingsCard.swift` — the `hostsFooter` (~line 86) with the stub `Button("add a host — edit ~/.ssh/config…")` and the "A guided add-a-host is coming… Hiding never removes — edit the file to truly remove." note. This is where the form and the remove affordance land; the stub is replaced by the real flow.
- `PalanaCore`: `HostBlock` (AT-01), `SSHConfigParser.adding`/`removing`, and the discovery/probe path (how the host menu's "reload" / a probe reaches a host — grep for how ho-9.2/9.3 trigger a reload/probe; the first-reach reuses it).
- ho-9.2 already maps an auth failure to "no usable ssh key — key setup needed" — find that mapping and reuse its wording; the key-setup guidance builds on it.
- The `# palana: hide` curtain (ho-9.2) is separate and untouched — remove is a distinct, truly-strip action.

**Files** (your exact split is a judgment call after reading — likely:)

- Modify: `Sources/Palana/SettingsCard.swift` (the add form, the remove affordance, key-setup guidance)
- Modify: `Sources/Palana/SettingsModel.swift` (add `addHost(_:)` / `removeHost(alias:)` methods routing `SSHConfigParser.adding`/`removing` through the existing backup+write+reload, mirroring how `hiding`/`showing` are already invoked)
- New file(s) if the form warrants it (e.g. `Sources/Palana/HostOnboardingForm.swift`) — keep files within the length limit

**Required Changes**

1. **Model methods.** `SettingsModel` gains `addHost(_ block: HostBlock)` and `removeHost(alias: String)` that read current config text, apply `SSHConfigParser.adding`/`removing`, and — only on a non-nil result — run the existing backup+atomic-write+reload path. A nil transform (duplicate on add, absent on remove) surfaces a plain notice, no write. Match exactly how the hide/show methods already thread through the backup path.

2. **The add form.** Replace the stub button's action with a guided form (alias, hostname, user, port, identity file). On submit: build a `HostBlock`, run `validate()` — show field-named errors inline, don't write on any error. On valid: **show the composed block** (`HostBlock.compose()`) and require a confirm before the write. This is the plan-panel law applied to the file — the operator sees exactly what lands. Text fields must release focus cleanly (the ho-9.2/9.3 lesson: every focus flag releases on focus loss; a field that hoards focus wedges the app — follow how the existing settings fields behave).

3. **Remove.** Each host in the settings hosts list gains a remove affordance (distinct from the hide toggle). On invoke: show the block that will be stripped, confirm, then `removeHost`. This is the "truly remove" the footer note promised — update that note's wording now that it's real.

4. **First reach.** After a successful add, offer (do not force) a probe of the new alias through the existing discovery path. Surface the outcome: connected, unreachable, or auth-failure. An auth-failure routes into the key-setup guidance.

5. **Key-setup guidance (thin).** When reach fails on auth, show the ho-9.2 "no usable ssh key" wording plus the exact commands composed against the new alias — `ssh-keygen -t ed25519` (offer only when no local key is evident) and `ssh-copy-id <alias>` — as copyable text, with a link to the companion guide. **Do NOT execute ssh-keygen or ssh-copy-id in this task** (Decision 4 leaves running-it to the hands session; a real remote is never mutated in a test). Show and link only. For the guide link, use a plain external link to the ssh-actually site (the companion) — if no canonical URL is available in the repo, use `https://ssh-actually.sageframe.net` and leave a `// TODO` naming that the deep-link target firms up when the guide ships.

**Do Not**

- Do not write ssh config outside `SettingsModel`'s backup path.
- Do not execute any ssh / ssh-keygen / ssh-copy-id / process against a real or fixture remote in this task — compose and display the commands only.
- Do not modify `PalanaCore` — AT-01 owns the engine. If you need a core change, STOP and surface it.
- Do not touch the `# palana: hide` curtain logic — remove is separate.

**Acceptance**

- [ ] The form composes a valid block, shows it, and writes only after confirm + backup; the host list reloads with the new alias.
- [ ] A duplicate alias and each validation error surface a plain, field-named reason and do not write.
- [ ] Remove shows the block, confirms, backs up, strips, reloads; hiding is untouched and still separate.
- [ ] A newly added host can be probed; an auth failure shows "no usable ssh key" with the composed `ssh-keygen`/`ssh-copy-id` commands and the guide link.
- [ ] `swift build` clean; `swift-format lint --recursive --strict Sources Tests` and `swiftlint lint --strict` clean; full suite passes.

**Verification**

```bash
cd /Users/atmarcus/Vaults/sageframe-no-kaji-dev/palana
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

SourceKit may throw phantom "cannot find in scope" on app-target files — `swift build` is the type checker of record. Check the test run line; `swift test | tail` masks exit codes.

**Commit**

Do not commit. The session reviews and commits.
