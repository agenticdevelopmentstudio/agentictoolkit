<!-- leaf: implement-status-server-monitor-fetch/vercel--part-5 · source: status-server-monitor-fetch-vercel.md -->

# Status Server Monitor Fetch Vercel — continued (part 5)

## Design Decisions

- **Decision**: default `overallBudgetMs` to 12,000ms and compute the deadline once, before the pagination loop's first iteration, rather than per-page.
  **Rationale**: stated directly in the source comment — "self-bound like the projects poll: sync's `guard` abandons a provider at 20s WITHOUT cancelling it, so an unbounded loop keeps paginating behind the next cycle. Observed cost is ~0.75s for 3 pages," meaning the 12-second figure is deliberately well under the caller's 20-second `guard` timeout so this function's own partial-result path fires first.
  **Approved**: pending
- **Decision**: set the lookback window to 30 minutes (`DEPLOYS_LOOKBACK_MS`) as the stopping condition for pagination, rather than stopping after a fixed number of pages or a fixed count of deployments.
  **Rationale**: stated directly in the source comment — one page is only the newest 100 deployments team-wide, and a measured 225-deployment burst (135 projects, a push touching a shared path rebuilding ~90 sites at once) had its newest 100 span just 74 seconds; every older deploy in that burst was then permanently invisible to the poll, leaving rows stuck reading `building` for roughly 9 minutes until the by-id reconcile caught them at 10 per 60-second tick. 30 minutes was chosen because it "spans any burst this repo can produce."
  **Approved**: pending
- **Decision**: cap pagination at exactly 5 pages (`MAX_PAGES`, 500 deployments) regardless of budget or lookback state.
  **Rationale**: stated directly in the source comment — "so a pathological history can't spin." This is a hard ceiling layered on top of, not instead of, the budget and lookback stopping conditions.
  **Approved**: pending
- **Decision**: on a page-0 failure (non-ok response or thrown fetch), return `{ ok: false, deploys: [] }` immediately, while a page-1-or-later failure instead keeps every already-mapped row and reports `ok: false`.
  **Rationale**: stated directly in the source comment — "Page 0 failing is definitive (nothing fetched). A later page failing must NOT wipe the pages already fetched — keep them and hand back a partial." The same `ok:false`-with-partial-`deploys` contract is stated to be shared with `fetchVercelProductionStates` and the Railway/Cloudflare fetchers (all external).
  **Approved**: pending
- **Decision**: check `rateLimitedUntil("vercel")` at the top of `fetchVercelDeployments`, `fetchVercelDeployError`, and `fetchVercelBuildLog` themselves, even though the poll's caller (`sync.ts`'s `guard` wrapper, external) already performs the identical check before invoking `fetchVercelDeployments` during the normal poll cycle.
  **Rationale**: not spelled out in an inline comment on these specific checks, but demonstrated as deliberate by the test suite — `provider-cooldown.test.ts`'s "vercel: a 429 poll opens the cooldown; the next poll never touches the network" test calls `fetchVercelDeployments` directly, twice, with no `guard` wrapper in between, and asserts the second call makes no additional request. `fetchVercelDeployError` and `fetchVercelBuildLog` are never wrapped by `guard` at all (their callers, `enrich-deploy-errors.ts` and `routes/deploy-logs.ts`, call them directly), so the cooldown check inside each function is these two functions' only protection against hammering an already-throttled account.
  **Approved**: pending
- **Decision**: give `fetchVercelBuildLog` a longer default abort timeout (20,000ms) than the 8,000ms used for the poll's page fetches and for `fetchVercelDeployError`.
  **Rationale**: stated directly in the source comment on `BUILD_LOG_CALL_TIMEOUT_MS` — "a full build log is far bigger than the single-field reads, and is fetched on demand by a human waiting on the answer — give it more room than the 8s poll timeout without letting it hang."
  **Approved**: pending
- **Decision**: `composeVercelBuildLog` keeps every qualifying line with no truncation, unlike a bounded tail.
  **Rationale**: stated directly in the source comment — "deliberately NOT truncated (unlike the Railway tail used for enrichment): this feeds an on-demand read, and a build failure's cause is often hundreds of lines above the final 'exited with 1' — the reason the one-line `error_text` is not enough to diagnose a failure from."
  **Approved**: pending
- **Decision**: implement no retry of any kind for a failed page fetch, a failed on-demand detail fetch, a failed build-log fetch, or a 429 — each failure is logged (or, for a 429, cooled down) once and the call moves on or returns.
  **Rationale**: not stated in an inline comment as a deliberate tradeoff, but demonstrated as a fact of the code: no fetch call in this file is wrapped in any retry loop. Recorded here per this recipe's authoring rules as a fact to state, not a gap to excuse — the poll relies entirely on its next cycle (external, `sync.ts`'s cadence) as its retry mechanism, `fetchVercelDeployError` relies on `enrich-deploy-errors.ts` re-attempting an un-enriched row on a later cycle per its own doc comment ("enrichment simply retries next cycle"), and `fetchVercelBuildLog` relies on the human simply asking again.
  **Approved**: pending
