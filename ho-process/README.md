# The Palana Ho Process

This directory is Palana's public build record. It shows how the project moved
from premise to architecture, from architecture to bounded work, and from work
to tested software. The record includes decisions that were later revised,
failed approaches, practitioner feedback, and the repair work that followed a
full-codebase review.

Palana was designed and built with the
[Ho System](https://github.com/sageframe-no-kaji/ho-system), a method for
AI-assisted building in which the practitioner retains judgment and an agent
executes against explicit boundaries. A **ho** is one bounded unit of work. Its
document establishes the problem, decisions, limits, verification, and handoff
before implementation begins; its Reflect section records what actually
happened.

## How the Record Works

1. The [original seed](pre-seed-1-palana-original-seed.md) and
   [design language](pre-seed-2-palana-design-language.md) preserve the first
   formulation of the project.
2. [Kamae 1](kamae-1-palana-seed.md) defines the problem, identity, audience,
   boundaries, and evidence required to proceed.
3. [Kamae 2](kamae-2-palana-system-design.md) fixes the system boundaries and
   architecture before feature work begins.
4. The repository [README](../README.md) is Kamae 3: the public account of the
   product as it exists.
5. [Kamae 4](kamae-4-palana-ho-overview.md) turns the architecture into an
   ordered program of bounded hos.
6. The [per-ho documents](hos/) authorize and record each unit of work, while
   the [agent tasks](agent-tasks/) divide larger hos into independently
   executable assignments.
7. [Kamae 6](kamae-6-palana-state-memory.md) carries forward only the state a
   later session needs to continue the build.

The chain is directional, but it is not a fiction of perfect foresight. New
evidence can create a new ho, split an existing one, or change the order. Closed
hos remain historical records rather than being rewritten to make the build
look cleaner than it was.

## Suggested Routes

- To understand the method in this repository, start with
  [ho-00: Orientation](hos/ho-00-orientation.md), then compare the
  [Ho overview](kamae-4-palana-ho-overview.md) with the completed per-ho record.
- To follow the product architecture, read the
  [system design](kamae-2-palana-system-design.md), then the engine hos from
  [the Conduit](hos/ho-02-the-conduit.md) through
  [the transports](hos/ho-06.1-the-transports-rsync-and-proxy.md).
- To follow the interface through practitioner use, begin with
  [the panes](hos/ho-07-the-surface-panes.md),
  [plan and enact](hos/ho-08-the-surface-plan-and-enact.md), and
  [the field view](hos/ho-09-the-surface-field-view.md).
- To inspect delegation, open an agent task such as
  [the Workbench surface task](agent-tasks/Ho-10-AT-02.md) beside the ho that
  authorized it, [the Workbench](hos/ho-10-the-workbench.md).
- To inspect review and repair, read the
  [full codebase review](reviews/2026-09-06-full-code-review.md), its
  [repair dispatch](reviews/2026-09-06-repair-dispatch.md), and the resulting
  [residual-safety task](agent-tasks/agent-task-2026-09-08-close-residual-safety-gaps.md).
- To inspect release work, read [ho-12: The Ship](hos/ho-12-the-ship.md) beside
  the repository's [release procedure](../RELEASING.md).

## Reading the Evidence

The product code and current repository documentation are authoritative for
Palana's present behavior. These files are authoritative for what was proposed,
decided, attempted, observed, and handed forward at each point in the build.
Commit identifiers connect process claims to the corresponding code, while test
counts and hands-on verdicts record the evidence available at that time rather
than the state of the current branch.

The process record contains no credentials or authentication material. Private
machine names, filesystem paths, account identifiers, network details, and
exact fleet counts have been generalized. Names such as `source-host`,
`storage-host`, `service-host`, and `appliance-host` belong to the synthetic
public topology, while operational values remain outside the repository.
