---
created: 2026-07-03
status: complete
type: pre-seed
project: palana
feeds: kamae-1-palana-seed.md
---

# Pre-Seed 2: pālana design language

_Captured from the practitioner's redirect and design interview, July 3, 2026. This document records decisions and preferences in the practitioner's own words. It joins `pre-seed-1-palana-original-seed.md` as input to the Kamae 1 seed. Where the two conflict, this document wins — it is newer and it is the redirect._

---

## Sealed decisions

Four decisions, sealed in conversation on July 3, 2026. These are not opinions. The seed and everything downstream treat them as given.

**Swift, native macOS.** "Swift 100%." This supersedes the original seed's Tauri + Rust + Svelte direction and its rejection of Swift. The original rejection rested on a Linux path that served the tertiary audience — the primary audience runs a Mac, and the environment is paved for Swift (the language module is written, Sharibako shipped with the Core + CLI + App layout, the signing pipeline exists). The Linux path is the named cost, accepted.

**Forteller is not a dependency.** The original seed required Forteller built first and wired into core. Forteller is two commits — a seed and a README stub. The redirect: "We can add that later as a plugin. In many ways AI and my MCP have made that less needed anyway." Forteller integration moves to the plugin roster. The plugin API gets proven by a tool that exists at first release instead.

**Dual pane.** Two panes, not three. Source and destination is the grammar of the plan engine, and the grammar wants exactly two positions.

**Fully autonomous build.** The Kamae chain is authored and executed by the agent. The practitioner is interrupted for exactly one thing: UI/UX sessions — hands on the running app, feel feedback. Everything else runs without him.

---

## The interview

Four questions, asked July 3, 2026. His answers, verbatim, then what they commit the design to.

### Muscle memory

Asked which file-manager grammar his hands already know:

> "2+3 [ForkLift/Transmit Mac conventions + defining its own grammar]. I want it to be smooth though. I've been using yazi and like that. The fact that you can't do dual pane in Finder is brutal. Forklift is a little ratchet."

The original seed's F-key convention (F5 copy, F6 move) was aspiration, not muscle memory — nothing in his hands descends from Norton Commander. What his hands actually know: yazi's keyboard smoothness and Mac conventions. What he's escaping: Finder's missing dual pane and ForkLift's jank.

**Commitment:** pālana defines its own keyboard grammar, descended from yazi and macOS conventions — not from the F-key row. Smoothness is a requirement, not a nice-to-have. If a keystroke stutters, that is a defect.

### Visual voice

Asked what character the app should have on open:

> "2/3/4! Not Apple, but smooth like that. Not atm brand colors but that feel. Mostly 4 [calm garden register] I think. I really like Typora — clean and smooth. Calm vibe. NOT cluttered, 2-3 colors. NOT dense terminal. Consumer app but powerful."

**Commitment:** the calm garden register, executed with native-Mac smoothness. Typora is the reference artifact — an app that is quiet, spare, and does one thing with total clarity. Two to three colors. No terminal density, no operator-cockpit aesthetic, no Apple pastiche, no brand-palette transplant. The tending metaphor is carried by calm, not by decoration. A consumer app's surface over an operator's engine.

### Plan → enact

Asked how the signature interaction — seeing what an operation really is before it runs — should feel:

> "1 [plan panel + Enter]. But SMOOTH. It should be transparent, with monospace 'terminal' area that provides data, but the interaction SMOOTH."

**Commitment:** the plan appears in a panel, Enter enacts, Esc dismisses — low ceremony, rhythmic, fast. Inside the calm surface, one zone speaks monospace: the plan's data area, where the operation's truth lives — files, sizes, within-dataset or cross-dataset, transport. Monospace appears exactly where data truth is displayed and nowhere else. The transition into and out of the plan is fluid — the panel is part of the flow, not a modal interruption.

### Field view

Asked where the topology view lives relative to the panes:

> "Summonable overlay."

**Commitment:** the field view appears on a keystroke, command-palette style — the full topology (machines, datasets, services), navigable, and a selection points a pane there. Then it vanishes. The panes keep the whole window. The map is summoned, consulted, dismissed.

---

## The design identity, assembled

One paragraph, for the seed to inherit:

pālana looks and feels like Typora reads — calm, spare, two or three colors, nothing on screen that isn't working. It moves like yazi — keyboard-first, fluid, never a stutter. Its one monospace zone is the plan panel, where the operation's truth is displayed before Enter enacts it. The field view is summoned, consulted, dismissed. It is a consumer app in its manners and an operator's tool in its engine — the calm is the point, because the calm is what tending feels like when the tool isn't fighting you.

---

## Addendum, July 3, 2026 — second round of design signal

Given mid-run, while the System Design was drafting. His words, then the commitments.

> "QSpace Pro. Smooth and simple. Feels too MAC but the smoothness is good."

> "We should have a terminal built in, in fact, the pane that shows what is going to happen COULD echo in a real terminal."

> "I LOVE the keyboard shortcuts in yazi — cc to copy path, etc. All of that good stuff to copy and paste!"

> "Marta is nice as well. But Typora is much better. Basically, it should match my vision for Sutra (sorry the design isn't done yet!)"

**The Sutra register governs.** Sutra's System Design states the vision pālana now inherits: "The app should feel like a good notebook. Calm. Almost no chrome. Buttons that appear and recede. The writing is the foreground. Everything else is background until called." Warm ground, near-black ink, one interactive accent color, mono only where the record lives. pālana matches that register — the notebook calm, the single accent, the receding chrome — with its own palette values. Substitute "the files" for "the writing" and the sentence is pālana's.

**Too-Mac is a named failure mode.** QSpace Pro has the smoothness and overshoots the platform: it reads as Apple furniture. pālana takes the smoothness and keeps the notebook voice. Reference ladder, descending: Typora, Marta, QSpace Pro (smoothness only), yazi (keyboard only).

**The plan panel is a real terminal surface.** Not monospace styling — a terminal-grade view. The plan shows the exact commands before enactment, and when Enter fires, the enactment echoes there live: the real commands, the real output, streaming. The interface's claim that "these are the commands" becomes checkable by watching them run. An interactive terminal (type into it, per host) is a Workbench tool for later — the v1 commitment is the echo, not the shell.

**yazi's clipboard verbs come along.** cc-style copy-path, copy-name, copy-directory — the small keyboard vocabulary that makes a file manager useful between other tools. The keyboard-grammar ho inherits yazi's verb set as its starting point, pruned by the practitioner's hands in the first UI/UX session.
