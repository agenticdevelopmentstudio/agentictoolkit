<!-- leaf: implement-status-server/src--part-3 · source: status-server-src.md -->

# Status Server — continued (part 3)

## Design Decisions

**Decision**: Single-flight caching on the public `/public/status-summary` endpoint.

**Rationale**: The public status endpoint is the only route anonymous traffic can reach. A cache miss triggers an expensive `buildStatusSummary` call (one full snapshot read + aggregation). Without single-flight, a burst of requests landing on an expired cache would start N concurrent expensive builds, causing a thundering herd. Single-flight ensures only one build per cache window, protecting the database from O(request rate) load spikes.

**Approved**: pending

---

**Decision**: Grid-based periodic scheduling with re-anchoring after manual runs.

**Rationale**: Periodic status checks should fire on a predictable cadence so client-side countdown timers are accurate. When a manual `runNow()` resolves (which may take much longer than the interval), re-anchoring the timer ensures the next automatic tick is a full interval away from the completion, rather than firing moments later and bunching cycles. This keeps the periodic grid stable even when manual runs are long.

**Approved**: pending

---

**Decision**: Watchdog timer with cycle abandonment rather than blocking.

**Rationale**: Monitoring loops must never wedge. A single un-timed-out async operation deep in a cycle can cause `inFlight` to remain true forever, causing all later ticks to no-op while the process continues serving ever-staler data. The watchdog hard-caps cycle duration (3× interval, minimum 2 minutes) and releases the lock, allowing the loop to continue. The abandoned cycle is left to settle asynchronously, but does not hold future ticks hostage. This was the design response to a 32-hour outage where a deployed loop remained wedged.

**Approved**: pending

---

**Decision**: No automatic retry or backoff on cycle failures.

**Rationale**: Each cycle is try/caught; errors are logged to the console but do not crash the process or block future ticks. Automatic retry with backoff is not implemented in the source — failed cycles simply mark the service as data-stale (`/health` returns 503 after staleness window), and the caller (a deployment platform) must decide whether to restart the process, page on-call, or wait for the next tick to succeed. This delegates retry policy to the operator, matching the code's philosophy of exposing problems rather than hiding them.

**Approved**: pending

---

**Decision**: Staleness is measured from boot timestamp before the first cycle completes.

**Rationale**: A monitoring loop that never completes a cycle should not appear healthy. If `lastCycleAt` is null (no completed cycle yet), staleness is measured from `startedAt` so the loop trips stale even with zero signal. Within the first staleness window after boot `/health` still reports `ok`; only a loop that has not completed a cycle by the end of that window reports `stale`.

**Approved**: pending

---

**Decision**: Status summary collapses to `'unknown'` (not `'healthy'`) when all services are unknown.

**Rationale**: A status page must never claim green when it can't tell. When there is at least one service and every monitored service has status `'unknown'` (e.g., before the first probe cycle), the 3-state rollup collapses to `'healthy'`. This is overridden to `'unknown'` explicitly so the public headline never shows green on zero signal. This is a deliberate contract: `operational: true` only when the overall rollup is healthy, never when it's unknown.

**Approved**: pending
