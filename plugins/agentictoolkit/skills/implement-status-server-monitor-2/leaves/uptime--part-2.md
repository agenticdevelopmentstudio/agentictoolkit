<!-- leaf: implement-status-server-monitor-2/uptime--part-2 · source: status-server-monitor-uptime.md -->

# Status Server Monitor Uptime — continued (part 2)

## Design Decisions

- **Decision**: count a `degraded` check together with a `healthy` check as up-time in `uptimePercent`, so only a `down` check reduces the returned percentage.
  **Rationale**: not explained beyond the file's own framing as ported arithmetic kept deliberately identical to "the old route"; recorded here as a fact of the ported formula — a slow-but-responding endpoint still counts as available time, and only a definite outage removes uptime credit.
  **Approved**: pending
- **Decision**: leave a zero-total day falling through `dayStatus`'s default branch to `"healthy"`, rather than adding an early return for `c.total <= 0` the way `uptimePercent` has.
  **Rationale**: not stated inline; recorded here as a fact of the code's structure — `dayStatus` has no zero-total guard, so a day with no checks at all reports the same `"healthy"` value as a day that was checked and found fully healthy. A consumer must read that same day's `uptimePercent` (`null`) to learn "no data," not `dayStatus`.
  **Approved**: pending
- **Decision**: compute portfolio-wide uptime in `overallUptimePercent` as the simple, unweighted mean of each service's OWN uptime percentage, rather than summing raw check counts across every service first.
  **Rationale**: stated directly in the source's own doc comment — "so every service counts equally" — a service checked far more often than another, or monitored for longer, must not dominate the headline number. The `status-web` duplicate's own comment on this same formula adds: "Volume-weighting was misleading: a service checked more often, or simply monitored for longer, would dominate the number even though it's just one of the things we watch."
  **Approved**: pending
- **Decision**: maintain an independent, byte-for-byte-identical copy of `Counts`, `uptimePercent`, `dayStatus`, and `overallUptimePercent` in the browser-bundled `status-web` package instead of importing this server-side file directly.
  **Rationale**: not stated inline in either file; recorded here as a fact of the repo's structure — `status-web` runs in the browser and cannot import a Node-only server package, so the same arithmetic contract is maintained as two separately authored and separately tested source files. Nothing in either file enforces that a future change to the rounding or threshold logic is mirrored in the other.
  **Approved**: pending
- **Decision**: export `overallUptimePercent` from this server-side module even though no route or caller inside `status-server` itself currently invokes it (`uptimePercent` and `dayStatus` are the two consumed by `buildUptime` in `../routes/reads.ts`).
  **Rationale**: not stated inline; recorded here as a fact — the function's only live caller is the separate `status-web` package's own copy of this file, consumed by `OverviewTab.tsx`. Within `status-server` itself, `overallUptimePercent` is currently unused.
  **Approved**: pending
- **Decision**: keep this recipe's Behavioral Requirements list much shorter than sibling monitor recipes such as Status Server Monitor Fetch Vercel Projects.
  **Rationale**: warranted by a genuine complexity difference, not under-authoring — `uptime.ts` is three pure, synchronous, side-effect-free functions with no I/O, network calls, retries, caching, or concurrency-sensitive shared state, against a paginating network fetcher with budgets, retries, and multiple TTL caches. Per the cross-recipe-consistency guideline, comparable depth applies to comparable complexity, and this component's complexity is genuinely smaller.
  **Approved**: pending
