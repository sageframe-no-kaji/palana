# Palana Agent Instructions

## Process Record

- The canonical Ho process is the nested private repository at
  `ho-process-private/`.
- When `ho-process-private/` is present, read its Kamae 6 first when resuming
  work, then the relevant Kamae and ho documents there. A public-only clone has
  the documentary export, not the operational handoff.
- Preserve exact operational facts in the private record when they are needed
  for reasoning or reproduction, but never store credentials in Git.
- Treat public `ho-process/` as generated output. Never edit it directly.
- Publish process changes only through
  `ho-process-private/scripts/publish-public --apply`, then review, commit, and
  push the public diff before pushing the private repository.

## Safety

- Never run mutating operations against live infrastructure hosts. Use fixtures
  unless the practitioner is actively driving and explicitly authorizes the
  target operation.
- Verify behavior by command and report blocked or skipped checks explicitly.
- Do not add AI attribution trailers to commits or pull requests.
