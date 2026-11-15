# Contributing to pālana

Bug reports are the most useful contribution. Small patches are welcome.
Features start as a conversation in an issue, because pālana is an authored
project with a public design record, and its architecture follows that record
rather than individual pull requests.

## Bug reports

The app records most of what a good report needs. Include what you have of:

- the pālana version (from the About panel) and the macOS version
- the host's operating system and userland, if a host is involved (the field
  card shows the userland as GNU, BSD, or BusyBox)
- **what the plan showed and what actually ran**: the plan panel text, and the
  matching entry from `~/Library/Application Support/palana/operations.log`
- for connection problems: the probe result from the field card (`f`, then `r`
  on the host's row), and whether `ssh -o BatchMode=yes <alias> true` succeeds
  in Terminal

File reports in the [issue tracker](https://github.com/sageframe-no-kaji/palana/issues).
Report **security issues** privately through
[GitHub Security Advisories](https://github.com/sageframe-no-kaji/palana/security/advisories),
not in a public issue.

## Patches

Keep each pull request small and limited to one change. Before you open one,
these checks must pass:

```sh
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
```

PalanaCore has a **90 percent line-coverage floor** (`swift test
--enable-code-coverage`), and CI enforces it. A patch that adds behavior also
adds the tests that specify it. A patch that drops coverage below the floor
cannot be merged until it adds tests.

Tests never run mutating operations against live hosts. Use the recorded
Conduit transcripts for unit tests and the disposable sshd and ZFS fixtures
(`scripts/sshd-fixture.sh`, `scripts/zfs-fixture.sh`) for integration tests.

## Features and design

The design record governs the architecture. Before you propose a feature, read
`README.md`, then `ho-process/kamae-2-palana-system-design.md`, then
`ho-process/kamae-4-palana-ho-overview.md`. Many "why doesn't it…" questions
are answered there as decisions with reasons: SSH only, no daemon, no embedded
SSH stack, and a plan before every change. Open an issue that describes the
problem before you write code. A feature pull request without that
conversation will usually be redirected to one.

## Licensing of contributions

Contributions come in under GPL-3.0 and stay under GPL-3.0. You keep your
copyright, and your contribution is accepted under the project license.
**There is no contributor license agreement, and there never will be.** Once
your code is in, nobody, including the author, can relicense pālana as closed
source. The license is the ordinary, unmodified
[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html), and a copy is in
[LICENSE](LICENSE).

Building from source is free at every version. The $29 build sold at
[palana.sageframe.net](https://palana.sageframe.net) is the signed, notarized
app and its 1.x updates. It is never permission to run the software, because
GPL-3.0 already grants that.
