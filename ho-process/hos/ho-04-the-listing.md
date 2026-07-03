---
created: 2026-07-03
status: draft
type: ho-document
project: palana
ho: 04
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - kamae-4-palana-ho-overview
  - ho-03-the-field
---

# ho-04 — The Listing

Remote directory reading. One SSH command per directory read, emitting a parseable listing—GNU `find -printf` as the primary path, a BSD fallback selected by ho-03's capability probe. The FileEntry model and the pane state model are the contract the Surface will render against, so they are committed here, three hos before any pane exists.

**Out of scope:** writing, classifying, composing. The Listing reads. No caching—a pane refresh is a fresh read, and staleness is the Field cache's vocabulary, not the Listing's.

**Resolves deferred decisions** (from the ho-overview):

- Listing command exact format (deferred decision 4)

**Carries from ho-03:** the flavor fact selects the command path. The container fixture answers GNU—the BSD battery leans on Darwin (CI's runner sshd, locally recorded transcripts), not the container. Integration suites against one fixture are `.serialized`. Public declarations get DocC at writing time.

---

## Phase 1 — Think

### Decision 1 — FileEntry: bytes are the truth, String is the face

Linux filenames are bytes with no promised encoding, and the done-means says weird names survive byte for byte. So `FileEntry` carries `nameData: Data` as the truth and `name: String` as the face—lossy-UTF-8 decoded for display and sorting. Command composition (ho-05) works from the bytes, the Surface renders the String, and nothing pretends a filename was ever text. The rest of the shape: `kind` (file, directory, symlink, other), `size`, `modified`, `permissions` (octal string), `owner`, `group`, `symlinkTarget: Data?`. Identity is the name bytes—one directory cannot hold two of them.

### Decision 2 — The GNU path: one `find -printf`, NUL everywhere (deferred decision 4 resolved)

```
cd <dir> && find . -mindepth 1 -maxdepth 1 -printf '%f\0%y\0%s\0%T@\0%m\0%u\0%g\0%l\0'
```

Eight NUL-terminated fields per entry, flat parse chunked by eight. NUL is the one byte a filename cannot contain, so names—and symlink targets—survive byte for byte by construction. Verified live against the pool VM: newlines, spaces, and UTF-8 in names arrive intact. `%T@` carries fractional seconds. One process on the remote regardless of entry count—this is the fast path and the fleet's path.

### Decision 3 — The BSD path: self-aligned records, targets as a keyed map

BSD `stat` cannot emit NUL from its format string—`\0` truncates the format (verified on Darwin). So the BSD path gets a different record shape, same single round trip:

```
cd <dir> && find . -mindepth 1 -maxdepth 1 -exec stat -f '<type><TAB>%z<TAB>%m<TAB>%Lp<TAB>%Su<TAB>%Sg' {} \; -print0 \
  ; printf 'PALANA-LINKS\0' ; <per-link name\0target\0 pairs>
```

find evaluates per entry, left to right: the stat line (no filename in it—every field delimiter-safe), then `-print0` writes `./name\0`. Line-then-NUL-name records self-align in one traversal—no cross-section ordering assumption. Symlink targets arrive in a third section as `name\0target\0` pairs keyed by name, race-safe by construction. The section marker cannot collide: `-print0` names always carry the `./` prefix. Cost, named: one `stat` fork per entry on the remote. BSD flavor means a Mac target in practice, and Mac directories are modest—correctness buys the forks. The GNU path carries the big directories.

### Decision 4 — Flavor is a parameter, not a dependency

`list(on:path:flavor:)` takes the userland flavor as an argument. The caller reads it from the Field's facts—the Listing does not hold a Field, does not discover, and stays testable with two transcripts and no topology. The probe's flavor fact selects the command path exactly as ho-03 designed, but the coupling lives at the call site.

### Decision 5 — Listing failures are typed at the Listing

A nonzero exit from the listing command classifies on stderr before anything above interprets noise: `directoryNotFound`, `permissionDenied`, `notADirectory`, and `listingFailed(exit:stderr:)` for the remainder—typed, never swallowed. Same discipline as the Conduit taxonomy, one layer up: the Conduit types door failures, the Listing types read failures.

### Decision 6 — The pane state model: a value the Surface renders

`PaneState` is a value: `host`, `path`, `entries`, `selection` (a set of entry identities), `cursor`, `sort`. Sort orders: name (default, `localizedStandardCompare`—Finder muscle memory), size, modified, each with direction. The model lives in PalanaCore and decides nothing about presentation—ho-07 renders it and forwards intent back. Committing it here means ho-05 composes plans against selections and ho-07 binds a table to a shape that already exists.

### Discovery (deferred to execution) — the BSD record's exact escapes and the hostile-name battery

The BSD `stat` format's tab escape, the link-section loop's exact sh, and the `%HT`-vs-`%LT` type mapping harden against real Darwin. Hostile-name fixtures—real newlines, control bytes, UTF-8, names that look like the section marker—get created on both fixtures, listed live, and recorded as transcripts for the unit battery.

---

## Phase 2 — Execute

One bounded conversation—no agent-task decomposition. Model: `claude-fable-5`.

Order of work:

1. `FileEntry` + `PaneState` models with their unit battery.
2. GNU command + parser—synthetic battery first, then hostile-name fixtures on the container and pool VM, recorded into transcripts.
3. BSD command + parser—hardened against Darwin locally, recorded into transcripts, exercised end to end on CI's runner sshd.
4. The Listing component: flavor dispatch, error classification, integration against both fixtures, `.serialized`.
5. Full verification rhythm; floor holds; CI green.

### Done means

- `list(host, path) → [FileEntry]` is correct on GNU and BSD userlands against fixtures, and weird filenames survive byte for byte.
- One round trip per directory—a pane refresh is one command.
- The FileEntry and PaneState shapes are committed and ho-05/ho-07 can build against them.

---

## Phase 3 — Reflect

*To be filled in after execution. Prompts:*

- **Did both parsers hold against the hostile battery?** What did real filenames do that synthetic ones didn't?
- **The BSD fork cost.** Measured against a plausible Mac directory—acceptable, or does the optimization arrive early?
- **Model review.** Did FileEntry/PaneState survive contact with ho-05's and ho-07's needs as far as they can be seen from here?
- **Followups for ho-05.**

---

_Authored: 2026-07-03 (Think phase)._
