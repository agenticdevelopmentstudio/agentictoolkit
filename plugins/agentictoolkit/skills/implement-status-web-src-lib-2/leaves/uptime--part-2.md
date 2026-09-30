<!-- leaf: implement-status-web-src-lib-2/uptime--part-2 · source: status-web-src-lib-uptime.md -->

# Uptime Math — continued (part 2)

## Design Decisions

**Decision**: Portfolio-wide uptime is the unweighted mean of each service's own uptime percent.
**Rationale**: The source's doc comment on `overallUptimePercent` states that volume-weighting "was misleading: a service checked more often, or simply monitored for longer, would dominate the number even though it's just one of the things we watch." Each service counts equally.
**Approved**: pending

**Decision**: Degraded checks count as up in `uptimePercent`.
**Rationale**: A degraded check answered successfully but slowly (see the `DEGRADED_THRESHOLD_MS` rule in `health.ts`); the service was reachable, so the numerator is `healthy + degraded`.
**Approved**: pending

**Decision**: A day is `"down"` only when more than half its checks were down; any down check below that makes it `"degraded"`.
**Rationale**: `dayStatus` checks `down > 0` first and then compares `down / total > 0.5`, so a single failed check cannot mark a whole day as an outage, yet any failure still keeps the day from showing `"healthy"`.
**Approved**: pending

**Decision**: Percentages are rounded to two decimals inside the module, not at display time.
**Rationale**: Both functions apply the multiply-round-divide step, and the status-server copy is documented as keeping "numbers match the old route exactly"; rounding in one shared place keeps the server's per-day values and the client's overall value consistent.
**Approved**: pending

**Decision**: No input validation and no zero-total guard in `dayStatus`.
**Rationale**: The module is pure arithmetic over counts the status server produces from its own check records; it trusts them. The observable consequences — values above 100 from inconsistent counts, `"down"` for a zero-total day with down checks, `"healthy"` for an empty day — are recorded as requirements and edge cases so ports reproduce them.
**Approved**: pending

**Decision**: The client keeps a duplicate of the server's uptime module.
**Rationale**: `status-server/src/monitor/uptime.ts` and this file are identical apart from comments and wrapping; the client needs `overallUptimePercent` to aggregate the per-service values it receives. Any change to the rounding or rules must land in both copies.
**Approved**: pending
