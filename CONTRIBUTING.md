# Contributing to pālana

The short version: **bug reports are the most valuable contribution**, small
patches are welcome, and features start as conversations—this is an authored
project with a public design record, and architecture flows from that record,
not from pull requests.

## Bug reports

A good pālana bug report is easy to write because the app leaves artifacts.
Include what you have of:

- pālana version (About panel) and macOS version
- the host's OS and userland if a host is involved (the field view's
  capability tokens—GNU, BSD, BusyBox—are exactly this)
- **what the plan showed** and what actually ran—the plan panel text, and
  the matching entry from `~/Library/Application Support/palana/operations.log`
- for connection problems: the probe verdict from the field view (`f`, then
  `r` on the host's row), and whether `ssh <alias>` works in your terminal

File at [issues](https://github.com/sageframe-no-kaji/palana/issues).
**Security issues**: report privately via
[GitHub Security Advisories](https://github.com/sageframe-no-kaji/palana/security/advisories)
rather than a public issue.

## The beta deal

File a real issue during the v0.x beta—a bug, a refusal on a host pālana
hasn't met, a plan that said something untrue—and your 1.0 license is free.
"Real" means reproducible or informative, not a typo report; judged by the
author, generously.

## Patches

Keep them small and scoped—one change per PR. Before opening one, the
verification rhythm must pass clean:

```sh
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

PalanaCore holds a **≥90% line-coverage floor** (`swift test
--enable-code-coverage`). A patch that adds behavior adds the tests that
specify it; a patch that drops coverage below the floor isn't mergeable yet.

## Features and design

The design record governs. Before proposing a feature, read in this order:
`README.md`, `ho-process/kamae-2-palana-system-design.md`, then
`ho-process/kamae-4-palana-ho-overview.md`—many "why doesn't it…" questions
are answered there as decisions with reasoning (SSH-only, no daemon, no
embedded SSH stack, plans before mutations). Open an issue describing the
problem before writing code; feature PRs that skip that conversation will
usually be redirected to one.

## Licensing of contributions

GPL-3.0 in, GPL-3.0 out. You keep your copyright; your contribution is
accepted under the project license. **There is no CLA and there never will
be**—which means once your code is in, nobody (the author included) can
relicense pālana closed. The full policy: [The license,
plainly](https://palana.sageframe.net/licensing/).
