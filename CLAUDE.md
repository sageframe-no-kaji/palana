# pālana

A native Mac file manager for the homelab operator — dual panes over SSH, a Plan Engine that composes readable transfer plans (rsync, proxy, `zfs send/receive`), and a field view of the hosts. PalanaCore is a headless library that carries all truth and logic; Palana is a thin SwiftUI surface over it.

## Languages

@~/.claude/modules/languages-swift.md

## Reading order for a fresh session

1. `README.md` — what the project is (Kamae 3)
2. `ho-process/kamae-2-palana-system-design.md` — committed architecture and stack (Kamae 2)
3. `ho-process/kamae-4-palana-ho-overview.md` — build sequence (Kamae 4)
4. The current ho in `ho-process/hos/` — the bounded scope for this session (Kamae 5)

## Verification rhythm

Run after every implementation, before every commit:

- `swift-format lint --recursive --strict Sources Tests`
- `swiftlint lint --strict`
- `swift build`
- `swift test`
- Coverage floor: **≥90% line coverage on PalanaCore** (`swift test --enable-code-coverage`; enforced in CI, checked on demand via `xcrun llvm-cov report`)

## Kokoroe

- **The spec is the authorization.** The ho document bounds the session; work outside it is not authorized by momentum.
- **Verify by command, not by assertion.** A claim that the build passes is a `swift build` transcript, not a sentence.
- **Halt on surprise.** Unexpected state, failing assumptions, or off-spec discoveries stop the work and surface to the practitioner.
- **Propose, don't decide.** Architectural questions the documents don't answer go back to the practitioner. The coding session does not silently make the call.

## Hard rules (pālana-specific)

- **NEVER run mutating operations against live homelab hosts. Fixtures only.** Unit tests use recorded Conduit transcripts; SSH integration runs against a local sshd container fixture; ZFS integration runs against a file-backed throwaway pool in a Linux VM (Lima/OrbStack). No exceptions. The practitioner's machines become targets only when the practitioner is driving.
- **Never sign commits or PRs with AI attribution tags.** No `Co-Authored-By: Claude`, no `Generated with Claude Code`, no contributor credits — anywhere. Strip any template that includes one.
- **The ntfy alert channel is recorded in `prompts/ntfy-topic.txt` (gitignored).** Ping it when the practitioner's hands are needed — a blocking decision, a halt-on-surprise, a session that can't proceed.

## Project structure

- Multi-product Swift package: `PalanaCore` (library — Conduit, Field, Listing, Plan Engine, Transports, Workbench arrive with their hos), `Palana` (SwiftUI app target — the Surface).
- Private prompts in `prompts/` (gitignored).
- `ho-process/` is tracked publicly — the build record is part of the methodology demonstration (Sharibako precedent).
- SwiftPM only. `xcode/` arrives at ho-11 if signing demands it.

## Ho process

Ho documents for this project live in `ho-process/` (publicly tracked):

- `ho-process/kamae-1-palana-seed.md` — Kamae 1 (parti)
- `ho-process/kamae-2-palana-system-design.md` — Kamae 2 (architecture)
- `README.md` (repo root) — Kamae 3 (canonical public document)
- `ho-process/kamae-4-palana-ho-overview.md` — Kamae 4 (build sequence)
- `ho-process/hos/` — per-ho documents (Kamae 5)
- `ho-process/agent-tasks/` — child agent task specs (dandori format)

## References

- Sibling project (layout lineage): https://github.com/sageframe-no-kaji/sharibako
- Ho System framework: https://github.com/sageframe-no-kaji/ho-system
