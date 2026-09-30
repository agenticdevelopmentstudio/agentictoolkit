<!-- leaf: implement-status-server-monitor-fetch/cloudflare--part-3 · source: status-server-monitor-fetch-cloudflare.md -->

# Status Server Monitor Fetch Cloudflare — continued (part 3)

## Design Decisions

- **Decision**: check `rateLimitedUntil("cloudflare")` at the top of `fetchCloudflareDeployments` itself, even though the caller (`sync.ts`'s `guard` wrapper, external) already performs the identical check before invoking this function during the normal poll cycle.
  **Rationale**: not spelled out in an inline comment on this specific check, but demonstrated as deliberate by the test suite: `provider-cooldown.test.ts`'s "cloudflare: a 429 on the script listing cools the provider down" test calls `fetchCloudflareDeployments` directly, twice, with no `guard` wrapper in between, and asserts the second call makes no additional request. A caller that bypasses `guard` (direct unit-test invocation, or any future caller external to `sync.ts`) still gets the cooldown protection, because the check is a property of this function's own precondition, not solely of the wrapper around it.
  **Approved**: pending
- **Decision**: fetch each script's deployments with a bounded concurrency of exactly 5 (`CF_SCRIPT_CONCURRENCY`), not serially and not fully unbounded.
  **Rationale**: stated directly in the source comment on the `mapLimit` call — a serial loop made total time "N scripts × up to 6s, so a many-worker account chronically blew the budget and returned partials every cycle," which is "the same shape Railway fixed with mapLimit." An unbounded fan-out is avoided per `map-limit.ts`'s own doc comment (external): it would make every script's wall-clock time include time spent queued behind the others, corrupting any per-script timing measurement — though this file does not itself measure per-script timing, the same contention risk (hammering Cloudflare's API with N simultaneous requests) applies.
  **Approved**: pending
- **Decision**: start the overall budget's deadline before the script listing call, not after it.
  **Rationale**: stated directly in the source comment — "the overall budget starts BEFORE the script listing — the listing is part of the poll, so its time counts against the deadline," explicitly citing this as "the same off-by-a-listing fix as the Railway fetcher" (a bug that once existed in that sibling file and was fixed there first).
  **Approved**: pending
- **Decision**: on a 429 from any per-script fetch, set `skipped = true` (which also halts the remaining unstarted scripts) rather than only recording the cooldown and continuing to poll the rest of the account.
  **Rationale**: stated directly in the source comment — "`skipped` also stops the remaining queue after a 429 — cooling down means not hammering the rest of the account this cycle either."
  **Approved**: pending
- **Decision**: treat a failed script listing with no configured `workerScripts` fallback as `ok: false` (a platform-health signal), while a listing that succeeds with genuinely zero scripts stays `ok: true`.
  **Rationale**: stated directly in the source comment — "a failed listing with no configured fallback is a BLIND SPOT (we hold a token yet can see nothing), not a healthy empty account," matching "the Railway fetcher's contract" for the identical situation.
  **Approved**: pending
- **Decision**: keep every successfully mapped deploy row in the returned `deploys` array even when `ok` is `false` for the overall call, rather than discarding everything on any error or partial condition.
  **Rationale**: stated directly in the source comment on the return statement — "the deploys we DID fetch are still upserted by the caller, so a deploy that was reached lands even when the account has too many Workers to poll within one budget."
  **Approved**: pending
- **Decision**: implement no retry of any kind for a failed per-script fetch, a failed listing, or a 429 — a failure is logged (or, for a 429, cooled down) once and the call moves on.
  **Rationale**: not stated in an inline comment as a deliberate tradeoff, but demonstrated as a fact of the code: neither the per-script fetch path nor the listing call is wrapped in any retry loop (contrast the Railway fetcher, external, which retries its listing call once specifically because it is "the FIRST call of the poll and therefore always the coldest"). Recorded here per this recipe's authoring rules as a fact to state, not a gap to excuse — this file relies entirely on the caller's next poll cycle (roughly every 5 minutes, external) as its retry mechanism, and on the shared cooldown registry to avoid retrying INTO an active 429.
  **Approved**: pending
