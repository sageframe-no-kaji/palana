---
created: 2026-07-16
status: ready
type: ho-document
project: palana
ho: 18
kamae: 5
shape: ha
phase: post-v0.6
builds-on:
  - ho-16-the-preview-pane
---

# ho-18 — Remote binary preview

ho-16 shipped the preview pane local-only, then the review added remote *text*
(a bounded `head -c` read). This closes the last gap it named: **remote images
and PDFs** — fetched to a local cache and shown via QuickLook, bounded so a
multi-GB remote file is never pulled. The info card and the local-only line
stay the honest fallback for everything too big or not previewable.

**Out of scope:** remote video/audio/archives (never fetched — too big, and
QuickLook streaming doesn't reach over the wire); a persistent on-disk cache
(the cache is ephemeral, one file, evicted as the cursor moves); previewing
remote binaries the size cap rejects (info card + a plain line, never a fetch).

---

## Phase 1 — Think

### Decision 1 — Size-gate before fetching, on facts we already hold
The listing already knows each entry's `size`. Route on it **before** any wire
read: a previewable-binary extension (image/PDF) whose `size` is under the cap
is fetched; anything larger, or any non-previewable binary (video, archive,
unknown), stays the info card + local-only line. No fetch is ever started that
we'd have to abort for size. The routing is pure and tested (`PreviewRouter`).

### Decision 2 — The previewable set and the cap
Previewable-binary extensions: the common images plus PDF and SVG
(`png/jpg/jpeg/gif/heic/heif/tiff/tif/bmp/webp/ico/pdf/svg`). The cap is **25 MB**
— catches virtually every photo and PDF, skips videos and disk images. Both live
as pinned constants; tune in Reflect if his hands want a different ceiling.

### Decision 3 — Fetch whole, to an ephemeral cache, then QuickLook
A binary must arrive whole to render (a truncated image is useless), so the
fetch is `Listing.readFile` (the existing one-round-trip read) — bounded by the
size gate, not by truncation. The bytes are written to a single temp cache file
carrying the entry's extension (so QuickLook infers the type), and the existing
`QLPreviewView` is pointed at it. Exactly one cache file exists at a time: each
new fetch (and every exit/clear) evicts the previous. The debounce and the
load-task cancellation from ho-16 already prevent thrash and stale fetches.

### Decision 4 — The honest fallback, reworded
The remote info-only state (too big, not previewable, or a failed fetch) keeps
the info card and a plain line — reworded from "binary preview is local-only"
(no longer true for images/PDFs) to name the real reason without alarm.

---

## Phase 2 — Execute (ho-18-AT-01)

- `PreviewRouter.remotePlan(entry:)` → `.text` / `.fetchBinary` / `.infoOnly`,
  with the previewable-binary set and the cap (pure, tested).
- `PreviewController`: a full-file remote reader (injected from the session,
  `Listing.readFile`); the `.fetchBinary` branch — fetch, cache, `.quickLook`;
  single-file cache eviction on load and clear.
- The remote info-only wording.

### Done means
- A remote image/PDF under the cap shows via QuickLook, debounced, with the info
  card; the cache holds one file and is evicted as the cursor moves.
- A remote binary over the cap (or a video/archive) shows the info card + the
  honest line — never a fetch, never a hang.
- Remote text still works (unchanged).
- The routing/cap/set are covered in core; verification rhythm green; coverage
  floor held.

---

## Phase 3 — Reflect
_Waits on his hands (does the fetch feel quick enough over a real link; is 25 MB
the right ceiling; does the cache stay invisible). Remote video/preview-of-more
is a deliberate non-goal — the local-only line is the answer there._
