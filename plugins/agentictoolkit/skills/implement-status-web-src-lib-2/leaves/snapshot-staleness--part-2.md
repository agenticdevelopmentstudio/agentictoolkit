<!-- leaf: implement-status-web-src-lib-2/snapshot-staleness--part-2 · source: status-web-src-lib-snapshot-staleness.md -->

# Snapshot Staleness — continued (part 2)

## Design Decisions

**Decision**: Measure the lag server clock against server clock (`generatedAt` minus `lastCycleAt`), never against the client's `Date.now()`.
**Rationale**: Per the doc comment, comparing against the client clock would false-trip on client clock skew or on `setInterval` timers throttled while a tab sleeps. Because the client re-pulls `/live`, a wedged poller still shows a growing lag.
**Approved**: pending

**Decision**: Scale the window to five times the probe interval, floored at five minutes.
**Rationale**: It mirrors the backend scheduler's own `staleAfterMs`, so raising `PROBE_INTERVAL_SECONDS` does not make a single skipped cycle false-trip the banner. The floor also serves older backends that report no interval.
**Approved**: pending

**Decision**: Escalate to `"very-stale"` at three times the window.
**Rationale**: The doc comment states `very-stale` escalates the banner tone from amber to red, separating a briefly paused monitor from one that has been down for a long time.
**Approved**: pending

**Decision**: Missing or unparseable timestamps fail open to `"fresh"`.
**Rationale**: No probe yet (a zero-endpoint monitor) or no read clock means there is nothing to judge, and a garbage date must not raise a false "monitoring paused" banner. This is the opposite of `board-staleness.ts`, which fails closed because an unjudgeable board must not render as healthy.
**Approved**: pending

**Decision**: Keep one shared rule for the banner and the portfolio indicator.
**Rationale**: The doc comment names the goal: the banner and the header/home status sign "can never disagree", which would happen if each computed its own threshold.
**Approved**: pending
