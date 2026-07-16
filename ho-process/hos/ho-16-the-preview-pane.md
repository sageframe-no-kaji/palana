---
created: 2026-07-15
status: ready
type: ho-document
project: palana
ho: 16
kamae: 5
shape: ha
phase: 6 — the v1 polish
builds-on:
  - ho-10.3-the-zfs-pane-mode
  - ho-9.8-columns
---

# ho-16 — The preview pane (local)

A third pane mode: **preview**. One pane stops browsing and instead shows the file
the *other* pane's cursor is on — text you can scroll, an image, a PDF, plus an
info card from facts already gathered. This is the eighth-block "life-changing"
seed, scoped to **local files only** for v1.

**Scope (v1):** LOCAL files only — text (`.md`, configs, code, logs, all text),
images/PDF/quick-lookable types, and the info card. **Out of scope (follow-up
ho):** remote preview — remote *text* (`.md`, configs, all that jazz, via a
`Listing.readFile` head-read) is the immediate fast-follow; remote *binary/image*
(fetch-to-cache on ho-9.10's machinery, with size caps / eviction) is a later
Think. When the source cursor is on a remote file, show the info card + a plain
"content preview is local-only for now" line — never block or fetch.

---

## Phase 1 — Think

### Decision 1 — A third `PaneMode`, mirroring the other pane
`PaneModel.Mode` grows `.preview` (alongside `.files`, `.zfs`). A pane in `.preview`
renders no listing; it **follows the opposite pane's cursor** — the file that pane's
selection is on drives what preview shows. Toggle in/out with a key (mirror the zfs
mode's grammar: a single letter — propose `v` for "view/preview"; Esc restores
`.files`), with a plugin-hued boundary badge like the zfs mode's so the mode is
unmistakable (design system §7).

### Decision 2 — Local routing: text vs quick-look
For a LOCAL file under the source cursor:
- **Text** (detected by extension across the text families — `.md`, `.txt`,
  `.conf/.cfg/.yaml/.toml/.json/.ini`, code extensions, dotfiles, logs — *and* a
  content sniff for the extensionless case: valid UTF-8, no NUL bytes in the head):
  read the file (capped — see Decision 4) and show it **scrollable, monospace**
  (design system §3 — a file's literal content is "data truth"). No syntax
  highlighting in v1.
- **Everything else** (images, PDF, and any quick-lookable type): a
  `QLPreviewView` wrapped in `NSViewRepresentable`, pointed at the file URL.

### Decision 3 — The info card, always
Above/beside the content, an info card assembled from facts pālana already holds
on the `FileEntry` — name, kind, size, created/modified/changed dates, and the
recursive size ◆ if present (ho-06.5). The card renders even when content can't
(remote, or an unreadable type), so the pane is never blank.

### Decision 4 — Follow with a debounce; cap the read
The preview tracks the source pane's cursor, but arrow-spam must not thrash it:
debounce cursor motion by the design system's micro-interaction window
(`~0.10–0.12s`) before loading. Local text reads are capped (first **256 KB**;
show a "… (truncated)" footer past the cap) so a multi-GB log never hangs the UI.
QuickLook handles its own large-file streaming.

### Decision 5 — Local-only boundary, honestly stated
When the source cursor sits on a **remote** file, render the info card + the plain
line "content preview is local-only for now" — no fetch, no spinner, no error. The
remote-text follow-up (its own ho) fills this in.

---

## Phase 2 — Execute (ho-16-AT-01)

- `PaneModel.Mode.preview`; enter/exit grammar (`v` / Esc), boundary badge.
- The opposite-pane-cursor follow wiring, debounced.
- Local text path (extension families + UTF-8/NUL sniff, capped read, scrollable
  mono view) and the `QLPreviewView` `NSViewRepresentable` for the rest.
- The info card from `FileEntry` facts.
- Remote source → info card + local-only line.

### Done means
- `v` puts a pane into preview; it shows what the *other* pane's cursor is on;
  Esc restores files.
- Local text (incl. `.md`, configs, code) shows scrollable; local images/PDF show
  via QuickLook; the info card always renders.
- Fast cursor movement doesn't thrash the preview (debounced); huge text files cap
  cleanly.
- A remote cursor shows the info card + the local-only line, never a fetch or hang.
- Tests: the mode toggle; text-vs-quicklook routing (extension + sniff);
  the debounce/cap logic; the remote → local-only branch. Cover the routing and
  facts logic in core/model; the `QLPreviewView` representable is app-target.
- Verification rhythm green; PalanaCore coverage floor held.

---

## Phase 3 — Reflect
_Waits on execution and his hands (does the follow feel live but calm; is `v` the
right key; is 256 KB the right cap; does the info card carry enough). The remote-text
preview is the named next ho — it should cover `.md`, configs, all text._
