<!-- leaf: implement-status-server-monitor-1/format--part-2 · source: status-server-monitor-format.md -->

# Status Server Monitor Format — continued (part 2)

## Design Decisions

- **Decision**: consolidate sha-truncation and first-line/full-message extraction into one
  shared module instead of leaving the logic duplicated in each fetcher and row builder.
  **Rationale**: stated directly in the source's opening comment — this file is "the
  single source for the sha-truncation and first-line extraction that was otherwise
  copy-pasted across the fetchers and the row builders." A shared module removes the
  possibility of the several call sites drifting apart on truncation length or
  whitespace handling.
  **Approved**: pending
- **Decision**: give `commitFirstLine` and `commitFullMessage` different default caps (200
  vs. 4000 characters) and different whitespace rules (no trim vs. trailing-only trim).
  **Rationale**: stated in `commitFullMessage`'s doc comment — unlike `commitFirstLine`,
  it "KEEPS newlines so the details pane can show the whole 'git comment'; the row still
  derives the subject with `commitFirstLine`." A row showing only a one-line subject needs
  a short cap; a details pane showing the whole commit message needs a much larger one and
  must not have its internal structure (the blank line separating subject from body)
  collapsed.
  **Approved**: pending
- **Decision**: treat an empty string identically to `null`/`undefined` in all three
  functions, via a single truthiness check (`!hash`, `!message`), rather than checking
  `=== null || === undefined`.
  **Rationale**: not stated in source; recorded here as a fact of the code per this
  recipe's authoring rules, not a defended choice. The effect is that a caller-supplied
  empty-string hash or commit message is indistinguishable from a genuinely absent one —
  both formatters return `null` either way.
  **Approved**: pending
