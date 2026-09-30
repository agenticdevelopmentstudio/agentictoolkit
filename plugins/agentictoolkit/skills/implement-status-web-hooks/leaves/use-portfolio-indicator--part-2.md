<!-- leaf: implement-status-web-hooks/use-portfolio-indicator--part-2 · source: status-web-hooks-use-portfolio-indicator.md -->

# usePortfolioIndicator — continued (part 2)

## Design Decisions

**Decision**: The "status unknown" rule lives in one shared hook used by every portfolio-wide sign.
**Rationale**: The doc comment states that sharing the derivation "keeps the 'when is status unknown' rule in ONE place so the two signs can never disagree".
**Approved**: pending

**Decision**: Snapshot staleness and board staleness are separate unknown conditions.
**Rationale**: The source comment states the live transport and the board poll "fail independently, and either one alone going stale is real information the other can't stand in for".
**Approved**: pending

**Decision**: The hook trusts `board === null` and computes no board-staleness term of its own.
**Rationale**: Fix Round 3 item 1 moved board staleness into `useBoard`, so "`board === null` already covers both 'never arrived' and 'gone stale' by construction, the same way every other consumer of `useBoard` now does"; a second check here would be a consumer re-deriving a rule its input already applies.
**Approved**: pending

**Decision**: A null snapshot counts as fresh, not unknown.
**Rationale**: The source comment states "null lastCycleAt (no probe yet) is fresh, so a healthy monitor is unaffected"; the board, not the snapshot, is the thing that must have come back before a colour is claimed.
**Approved**: pending

**Decision**: `count` is taken from the board even when `pillKey` is `"unknown"`.
**Rationale**: The expression `board?.problems.length ?? 0` is independent of the unknown test; callers decide whether to show a count beside an unknown glyph.
**Approved**: pending

**Decision**: Staleness compares two server timestamps rather than the client clock.
**Rationale**: `snapshotFreshness` documents that measuring `generatedAt - lastCycleAt` is "immune to client clock skew and to `setInterval`-based client timers being throttled while a tab sleeps".
**Approved**: pending
