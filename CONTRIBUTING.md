# Contributing to pālana

Bug reports and small patches are welcome. For a new feature, open an issue describing the problem before writing code so the maintainer can consider it alongside the project’s design decisions.

## Bug reports

Describe what you did, what you expected, and what happened. Include the following details when available.

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
scripts/ci-test.sh
scripts/coverage-floor.sh 90 35
```

CI requires 90 percent line coverage for PalanaCore and 35 percent for the application logic measured by the coverage script. Include tests for new behavior. A full CI run also checks the public process export and sets up an isolated SSH server.

Use recorded SSH sessions for unit tests. For integration tests, use the disposable [SSH fixture](scripts/sshd-fixture.sh) or the [ZFS fixture](scripts/zfs-fixture.sh). Run mutating tests only against these fixtures.

## Features and design

The [README](README.md) describes the current app. The [system design](ho-process/kamae-2-palana-system-design.md) explains decisions such as using the system SSH client and showing a plan before file changes. The [build overview](ho-process/kamae-4-palana-ho-overview.md) traces those decisions through implementation.

## Licensing of contributions

You retain copyright in your contribution and license it under the project’s [GPL-3.0 license](LICENSE). The project will not ask contributors to sign a separate contributor license agreement.
