# Session: a library cookbook for agentictoolkit, regrouped by concept and made platform-neutral

- **Date:** 2026-10-01
- **Session:** `f86b41ce-963c-4e0c-bcf6-23bb78552ce7`
- **Branch:** `feature/cookbook`, `docs-update-donnism`

## Orientation

This session did two things. First, it extended the cookr project format in
agenticcookbook so that a *library* can carry a cookbook of its own specs,
each linked to its code through Reference Implementations. Second, it applied
that format to this repo. The loose root `recipes/` became `cookbook/`, and
the user then asked for the following, verbatim:

> "I don't want loose recipes at the root… General to specific. There
> shouldn't be platform specific directories… platform specifics are part of
> the recipes design for platform specific implementation details."

The specs were regrouped into eight concept groups and their normative text
was rewritten to be platform-neutral. A `/code-review max` of the branch
found 15 defects. These were reported to the user, who chose to ship anyway.
`/ship` landed the branch on main as `52e0776b` (PR #53). The cookbook
defects are still open.

## Decisions

- **Group by concept, from general to specific, with no platform
  directories.** The project is platform-agnostic, so a window such as the AI
  chat window is described once, and per-platform detail goes in that spec's
  Platform Notes. This was the user's direct requirement.
- **Normative sections are neutral, and Platform Notes holds the rest.**
  Overview, Behavioral Requirements, Appearance, States, Accessibility, Edge
  Cases, Configuration and Test Vectors are neutral. External protocols such
  as the VS Code API, LSP, AppleScript and SQL stay normative, because they
  are what the spec implements rather than platform terms.
- **Version bumps follow the kind of change.** A rewritten spec gets a minor
  bump and a moved-only spec gets a patch bump. Both get a Change History row,
  so consumers can tell a behavioral restatement from a relocation.
- **cookr `arrangement` judges by group, not by mirrored directories.** A spec
  is aligned when it sits inside the `recipes` group of the code root that its
  Reference Implementations fall under. Mirroring code directories was what
  produced platform folders in the first place. This lives on the
  agenticcookbook `cookr` branch (`c65f3d5`), which was not shipped this
  session.
- **One subagent at a time.** An earlier attempt fanned out to about 20 agents
  and burned usage, and the user said: "just start again, but use one agent at
  a time… I can't chew through my usage like that". The rewrite was redone
  sequentially, in batches.
- **The disclosure-card rebase conflict was merged by hand.** Main's 1.2.0
  change (title status symbol) was folded into the neutral spec. A scripted set
  of exact single-match replacements restated it in neutral terms, and the
  result became 1.3.0. Taking either side wholesale would have lost the other
  side's work.

## Considered and rejected

- **Parallel fan-out of the rewrite across about 20 agents.** Rejected for its
  usage cost; see the "One subagent at a time" decision.
- **Platform directories (`macos/`, `web/`) under `cookbook/`.** Rejected
  because the project is platform-agnostic.

## Open threads

- **The 15 code-review defects** are listed in priority order in
  [cookbook-organization](../project/cookbook-organization.md#known-defects-from-a-code-review-max-of-the-branch-2026-09-29).
  The most serious is "MUST NOT" turned into "Neither … MUST" in
  `authentication-client` and four other specs, which drops prohibitions.
- **The agenticcookbook `cookr` branch** (`c65f3d5`, the arrangement-by-group
  change) is still unmerged in that repo.
- **The installed `cookr` shim is stale.** It has no `arrangement` command.
  Reinstalling was not requested.

## Pointers

- Design and rules: [docs/project/cookbook-organization.md](../project/cookbook-organization.md)
- PR #53 / `52e0776b` on main
- `cookbook/cookbook.json`: the groups and code roots
- `tools/classify_recipes.py`: the classifier used for the regroup. It has a
  known basename-keying bug.
