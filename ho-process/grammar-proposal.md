---
created: 2026-07-10
status: ratified 2026-07-10 — executed by ho-9.11
type: design-proposal
project: palana
---

# The Grammar, Reconsidered

His ask, verbatim: "can we think of a clear grammar. i think we landed TOO loosey goosey.. please give it a thought. not neckbeard mysticism but not dumb kid either."

The audit found 119 bindings across nine surfaces. Almost every key is sensible alone. The problem is there's no rule system underneath — you cannot predict a key you haven't learned. A clear grammar is a small set of rules that generate the keys, so learning the rules teaches keys you've never pressed.

## The five rules

**Rule 1 — a lowercase letter is a verb on files, and the panel is always the gate.** One keystroke states an intention; nothing runs until the plan is read and ⏎ pressed (or auto-send is on and there's no conflict). This already holds. It becomes law.

**Rule 2 — verbs that need a name open the name field, and ⏎ there does the whole job.** rename and create ask, then act on one Enter. No second confirmation, no case-trickery encoding "asks for a name."

**Rule 3 — six summons open surfaces, and that's the whole set:** `f` field · `F` host map (the field's big sibling — same domain, wider view) · `*` favorites · `` ` `` terminal · `?` the keys · `⌘,` settings. Esc closes any of them. The set is closed — a new surface must argue its way in.

**Rule 4 — ⌘ belongs to the app, never to files.** ⌘R refresh, ⌘← / ⌘→ history, ⌘+/−/0 zoom, ⌘K clear terminal, ⌘⇧G go to, ⌘⇧L the log, ⌘A select all. If a chord touches a *file*, the rule is broken.

**Rule 5 — esc retreats one step and never destroys work.** Prefix → selection → overlay → panel. Running work is only ever stopped by ⌃C. Already true; stated as law.

## What the rules force us to change

**1. The verbs return to yazi where they drifted.** Today `r` = remove and `R` = rename — which betrays yazi (`r` is rename there), puts the most destructive verb on the easiest key, and makes a shift-slip the difference between renaming and deleting. Proposed:

| key | verb | was |
|---|---|---|
| `y` | copy | unchanged |
| `m` | move | unchanged |
| `d` | **delete** | was `r` — yazi's own letter |
| `r` | **rename** | was `R` — yazi restored |
| `a` | create (trailing `/` = directory) | unchanged — already yazi |
| `t` | touch | unchanged |

`R` and `T` free up (T's touch-new duplicates what `a` already does with a bare name — folded, unless the label difference earned its keep with you). One caveat named honestly: `d` in the *terminal-engaged* mode fires `df` — different mode, visibly indicated, no key conflict, but the adjacency exists.

**2. The star family lands on one physical key.** Today it's scattered across three planes: `8` stars the current directory, `⇧⌘8` stars the highlighted entry (a ⌘-chord doing file work — breaks Rule 4), `*` opens the panel. Proposed, all on the 8 key:

- `8` — star the **highlighted** entry (the thing your cursor is on — the more natural read)
- `⌘8` — star the **current directory** (where the app stands — app plane, per Rule 4)
- `*` (shift-8) — the favorites panel (a surface, per Rule 3)

**3. Everything else stands.** Vim/yazi navigation (`j k h l`, `gg G`, `⌃d ⌃u`, space, `.`), the sequence families (`c…` clipboard, `,…` sort — both yazi-shaped), tab switching panes everywhere, the terminal-engaged tool letters. The audit found these already coherent.

**4. The keys card teaches the rules, not just the list.** `?` reorganizes into the five groups above — verbs / names / surfaces / app / families — so the card *is* the grammar lesson.

## The cost

`r` and `d` are retrained muscle for anyone who learned the current beta — that's you and nobody else yet, which is exactly why now is the moment. The rename lands as one ho: bindings, help card, context menus, chips, docs, in a single commit so there's never a half-translated state.

## Not proposed

Modal editing beyond what exists (the panel and terminal-engage are already the only modes). Leader keys. Configurable keymaps (a future settings question, not a grammar one). Touching the mouse verbs — they already mirror the keys.

---

_Marks wanted: the verb table (especially d/r), the 8-family, whether T survives, and anything in the closed surface set you'd trade._
