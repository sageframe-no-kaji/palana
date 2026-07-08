---
created: 2026-07-08
status: complete
type: ho-document
project: palana
ho: 9.5
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-02-the-conduit
  - ho-03-the-field
  - ho-9.2-settings
agent-tasks:
  - Ho-9.5-AT-01.md
  - Ho-9.5-AT-02.md
---

# ho-9.5 — Host Onboarding

The one thing the field can't do yet is grow. pālana reads `~/.ssh/config`, curtains what the operator hides, probes what it names—but adding a host still means leaving the app for a text editor. ho-9.2 built the write machinery (backup required, atomic replace, reload) and left a button that says a guided add is coming and a note that hiding never truly removes. This ho makes both true: a guided flow that composes a `Host` block and writes it into the config, and a remove that strips one back out. The law the practitioner set holds throughout—"adding a server actually engage with .ssh, not some BS network picker with password. ssh or bust." The surface is over the file, never a parallel registry, and every write shows what it will do and backs up first.

Key setup is where onboarding stays thin. When a host is named but can't be reached because no key is installed, the flow says so plainly and hands the operator the exact `ssh-keygen` and `ssh-copy-id` commands, with a link to the companion guide ([[ssh-actually]]) for the understanding. pālana walks the mechanics; it does not reteach ssh.

**Out of scope:** a credential store, a password prompt, any trust ceremony that isn't `~/.ssh/config` (the sealed law). Editing an existing host's fields in place—v1 adds and removes whole blocks; editing is remove-then-add or the raw file, named as a follow-up if his hands want it. `Include`-file placement—new blocks land in the top-level config, not inside an included file. pālana running `ssh-copy-id` against a remote itself—v1 composes and shows the command; whether pālana executes it (confirm-gated, against the sshd fixture in test) is a Decision-4 question left to the hands session. Importing existing keys, managing `known_hosts`, agent configuration.

**Resolves deferred decisions:** the ho-9.2 debt—"ho-9.5 Think now owes: guided add + guided REMOVE + key setup walk"—lands here.

---

## Phase 1 — Think

### Decision 1 — A host block is a value, composed and validated in the core

`HostBlock` in `PalanaCore`: `alias: String`, `hostName: String`, `user: String?`, `port: Int?`, `identityFile: String?`. Validation is pure and total:

- `alias` is a single token—no whitespace, no `Host`-pattern metacharacters (`*`, `?`, `!`). A wildcard isn't a host, it's matching machinery (the `SSHConfigParser.isAlias` rule already knows this—reuse it).
- `hostName` is required and non-empty.
- `user`, `port`, `identityFile` are optional; a `port` outside 1–65535 is a refusal.

`compose()` renders the canonical block, emitting only the lines that carry a value:

```
Host <alias>
    HostName <hostname>
    User <user>
    Port <port>
    IdentityFile <path>
```

Four-space indent matching the config's own convention (`SSHConfigParser.blockIndent` reads the file's; a new block uses four). Validation errors are typed, one per broken rule, so the surface can name exactly what's wrong.

### Decision 2 — The parser grows add and remove, pure text transforms

`SSHConfigParser` already finds block boundaries (`findBlock`, `findBlockEnd`) for the hide/show transforms. Two more, same shape—text in, text out, nil on no-op:

- `adding(_ block: HostBlock, to text: String) -> String?`—appends the composed block at top level, after a blank-line separator. Returns nil if the alias already exists (adding a duplicate is a refusal, not a silent second block—the surface routes the operator to remove-first or picks a different alias).
- `removing(alias: String, from text: String) -> String?`—strips the alias's block via the existing boundary finders. Returns nil if the alias isn't present. This is the "truly remove" the 9.2 footer promised, the counterpart to `hiding`, which only curtains.

Both preserve `Include` directives and everything they don't touch. Tested against the config shapes the parser battery already covers—indented blocks, blocks at EOF, blocks followed by others, the hide-comment lines.

### Decision 3 — The write rides ho-9.2's backup law, unchanged

`SettingsModel` already backs up before it writes (`.palana-backup`), replaces atomically, and reloads the host list through `onConfigChanged`. Add and remove go through that exact path—no backup, no write, no exception. The only new thing is the transform feeding it (`adding`/`removing` instead of `hiding`/`showing`). The operator sees the composed `Host` block before it's written; a config mutation is never silent (the plan-panel law, applied to the file).

### Decision 4 — Key setup is detect, guide, and link—not a wizard

When a newly added host is reached and the connection fails on authentication, ho-9.2 already maps it to "no usable ssh key — key setup needed." Onboarding builds on that, thin:

- **Detect**—the first-reach probe (Decision 5) surfaces the auth failure as the named refusal, not a raw error.
- **Guide**—show the exact commands, composed against the new alias and copyable: `ssh-keygen -t ed25519` when no local key exists, then `ssh-copy-id <alias>` to install it. The alias is already valid ssh vocabulary by the time this shows, so the command is real, not a template.
- **Link**—the "what and why" goes to [[ssh-actually]]; onboarding does not reteach ssh. The companion's node on key setup is the destination.

**The open feel question for the hands session:** whether pālana *runs* `ssh-copy-id` itself—confirm-gated, echoed live, tested against the sshd fixture—or only shows the command for the operator to run. The hard rule stands either way: no mutating a real remote during the build; the fixture is the only target until the practitioner drives. v1 composes and shows; running-it is his call to add.

### Decision 5 — After the add, offer the first reach

Adding a host that can't be reached is a silent half-success. On write, offer to probe the new alias through the existing discovery path—the same `Field` probe the host menu's reload triggers. Success confirms the block is right; an auth failure routes into Decision 4's guidance; an unreachable host says so. The probe is offered, not forced (the operator may be adding a host that isn't up yet).

### Decision 6 — The surface extends the settings hosts footer

The guided flow lives where ho-9.2 stubbed it—the settings card's hosts footer, the "add a host" button. The button opens a form (alias, hostname, user, port, identity file); submit composes and shows the block, confirm writes it (backup first), then offers the reach. Remove surfaces per host in the same area—a remove affordance that shows the block it will strip, confirm, backup, write, reload. The exact form shape—inline in the card, a sheet, a popped panel—is the hands session's to settle; the honest default is inline in the settings card beside the existing hosts list.

---

## Phase 2 — Execute

Implementation on `claude-sonnet-4-6`, review and verification with the session. AT-02 depends on AT-01.

### Ho-9.5-AT-01 — The engine: HostBlock, validation, add and remove

`HostBlock` value + validation + `compose()`, `SSHConfigParser.adding`/`removing`, full unit battery against the parser's existing config fixtures. → `ho-process/agent-tasks/Ho-9.5-AT-01.md`

### Ho-9.5-AT-02 — The Surface: the guided add-and-remove flow

The add-a-host form, the show-and-confirm write through `SettingsModel`'s backup path, remove per host, the first-reach probe, the key-setup guidance and its [[ssh-actually]] link. → `ho-process/agent-tasks/Ho-9.5-AT-02.md`

### Done means

- The add-a-host form composes a valid `Host` block, shows it, and writes it only after confirmation and a backup; the host list reloads with the new alias
- A duplicate alias is refused with a plain reason; validation errors name the broken field
- Remove strips a host's block after showing it and backing up; hiding still exists separately and is not touched
- A newly added host can be probed; an auth failure surfaces as "no usable ssh key" with the exact `ssh-keygen`/`ssh-copy-id` commands and the guide link
- No real remote is mutated in any test; the composes and writes are proven against fixtures and the parser battery
- Verification rhythm green, PalanaCore coverage floor holds

---

## Phase 3 — Reflect

_Pending execution and the practitioner's hands._

---

_Authored: 2026-07-08 (Think phase, Opus). Full Think because the ho mutates the operator's ssh surface. To execute: two agent tasks on claude-sonnet-4-6, reviewed by the session, then a hands session—key-setup depth (show vs run) and the form's shape are his to settle._
