---
created: 2026-07-10
status: open
type: ho-document
project: palana
ho: 9.11
kamae: 5
shape: ha
builds-on:
  - kamae-2-palana-system-design
  - grammar-proposal
agent-tasks:
  - Ho-9.11-AT-01.md
---

# ho-9.11 — The Grammar

The keys grew one at a time across five hands sessions and the practitioner named the result: "TOO loosey goosey." The proposal (`ho-process/grammar-proposal.md`) audited all 119 bindings, found five rules hiding in them, and named the two places the rules force a change. He ratified it — "in general, I think you are fine" — with marks: keep `t`, fold `T`, `y` stays copy (the `c` family and thirty years of yank own the alternatives), `d` delete and `r` rename restore yazi's letters. This ho executes the ratified proposal in one atomic commit — never a half-translated state.

**The changes:**

1. **Verbs**: `d` = delete (was `r`), `r` = rename (was `R`), `T` folded away (`a` already creates a file from a bare name). `R` and `T` unbind. `y m a t` unchanged.
2. **The 8-family collects**: `8` stars the highlighted entry (was `⇧⌘8`), `⌘8` stars the current directory (was `8`), `*` keeps the panel. `⇧⌘8` dies, and with it the `cmd-shift-*` token workaround.
3. **The `?` card teaches the rules**: reorganized into the five groups — verbs · names · surfaces · app · families — so the card is the grammar lesson.
4. **The README gets a keybindings table**, same five groups.
5. Every surface that names a key follows in the same commit: context menus, chips, hint lines, the floating keys panel, operations-log lines.

**Out of scope:** configurable keymaps (a settings question for later), any new verb, any change to navigation, sequences, or the surface summons — the audit found them coherent.

---

## Phase 3 — Reflect

**The audit made the proposal cheap and the ratification fast.** One read-only sweep produced the 119-binding inventory, the five rules fell out of it in an afternoon, and the practitioner's marks arrived the same day — because the proposal asked specific questions (d/r, the 8-family, T's survival) instead of presenting a fait accompli. His c-for-copy and r-for-rm instincts were answered with the structural reasons, not taste, and he took the answers.

**The atomic-commit law earned its keep at execution.** Bindings, chips, context menus, the card, the README — five surfaces naming keys, one diff. No test pinned the binding table (a gap worth noting: the grammar is now the app's most operator-facing contract and nothing asserts it — a bindings-table snapshot test is cheap insurance for the next rename).

**Hands verdict pending:** the retrained r/d muscle over a few real sessions, and whether the reorganized card actually teaches.

---

_Authored: 2026-07-10. The Think phase is the proposal document, ratified by the practitioner's marks the same day._
