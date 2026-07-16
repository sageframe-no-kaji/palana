---
created: 2026-07-16
status: ready
type: ho-document
project: palana
ho: 17
kamae: 5
shape: ha
phase: post-v0.6
builds-on:
  - ho-10.4-the-mount-seam
---

# ho-17 — The sudo-explainer

The last live piece of ho-10.2's old scope (`10.2` is a dead number — this is
its fresh one, forward-only). The mount seam (ho-10.4) gated mount/unmount on a
`sudoNoPassword` fact and refuses with a plain sentence when the host doesn't
grant it. This ho gives that refusal teeth: **the exact sudoers line to copy**,
shown where the operator hits the wall and in Settings, so enabling the feature
is one paste, not a hunt.

**Out of scope:** installing the line for the operator (never — pālana handles
no secrets and prompts for no password); a root-helper daemon (rejected in
ho-10.2's sealed thinking — standing root, no per-action gate). This is
*counsel*, the operator opts in.

---

## Phase 1 — Think

### Decision 1 — The line is narrow, and it lives in core
pālana composes exactly two privileged commands — `sudo -n zfs mount <ds>` and
`sudo -n zfs unmount <ds>` — and nothing else (create/destroy/snapshot/
properties are delegated via `zfs allow`, no root). So the grant must be **only
those two**, never a blanket `zfs`, which would be a root-escalation footgun.
`SudoGuidance` (PalanaCore) is the single source of truth for the line:

```
<user> ALL=(root) NOPASSWD: /usr/sbin/zfs mount *, /usr/sbin/zfs unmount *
```

The exact string is **pinned by tests** so it can never silently drift broad.

### Decision 2 — Prefill the user, with a clear fallback
The line's `<user>` is the login pālana connects as on the host. When the ssh
config names it (`User` on the alias's own block), prefill it —
`SSHConfigParser.user(for:in:)`, a pure best-effort resolver following
`Include`s. When it doesn't (wildcard `Host *`, a global default, an
unresolvable case), fall back to the clear `<user>` placeholder — **never a
wrong guess baked into a root grant**. The path defaults to `/usr/sbin/zfs`
with a "check `which zfs`" note (it's `/sbin/zfs` on some distros).

### Decision 3 — It appears at the refusal AND in Settings AND on the web
- **At the refusal:** when a mount/unmount verb fires and the host lacks the
  grant, the transcript carries the reason, then the exact line (prefilled),
  then "or mount from the shell — ⌘\`". The fix is right there.
- **In Settings › Workbench:** a "ZFS mount & unmount" block — the why in one
  sentence, the copyable line (prefilled from the focused host), a `copy`
  button, the `which zfs` note, and that it's optional.
- **On the help site:** a dedicated, linkable page (Fable writes it in
  `sageframe-dharma/palana`). The in-app surfaces deep-link to it once the site
  ships (the URL is not hardcoded until it exists).

---

## Phase 2 — Execute (ho-17-AT-01)

- `SudoGuidance` in core (the line, the path, the placeholder), pinned by tests.
- `SSHConfigParser.user(for:in:including:)` — the prefill lookup, tested
  (explicit user, no user → nil, other-block isolation, multi-alias, `=` form,
  first-wins, include-following).
- The refusal surfacing in `zfsMutationGuard` — reason + line + shell fallback,
  for `.zfsMount` verbs only.
- The Settings › Workbench "ZFS mount & unmount" block — prefilled, copyable.

### Done means
- Firing mount/unmount on a host without the grant shows the reason and the
  exact sudoers line (prefilled or placeholder) in the transcript.
- Settings › Workbench shows the same line, copyable, with the why and the
  optionality named.
- The line is narrow (mount/unmount only), the prefill is right when known and a
  clear placeholder when not.
- Verification rhythm green; the security-sensitive string and the resolver are
  covered in core.

---

## Phase 3 — Reflect
_Waits on his hands (does the refusal read helpful not scolding; is the prefill
right on his hosts; does the Settings block sit well) and on the help page
landing so the in-app surfaces can deep-link it._
