<!-- leaf: implement-status-server-monitor-1/integrations--part-5 · source: status-server-monitor-integrations.md -->

# Status Server Monitor Integrations — continued (part 5)

## Design Decisions

- **Decision**: retry a failed probe exactly once, after a fixed 300ms pause, rather than with no retry at all or with exponential backoff and jitter.
  **Rationale**: stated directly in the source's own comments on `PROBE_RETRIES` and `RETRY_BACKOFF_MS` — retrying once tolerates "a single momentary stall (cron-burst event-loop pressure, a GC pause, a restart cold-start, a brief egress hiccup)" without flipping "the whole status page red," and the fixed pause exists "so the retry doesn't re-hit the same burst." Demonstrated by `integrations-retry.test.ts` › "recovers a provider that fails once then succeeds — no false red banner."
  **Approved**: pending
- **Decision**: distinguish a "no HTTP response at all" failure (tagged `unreachable: true`) from a definitive HTTP/API error, and debounce and correlate only the former.
  **Rationale**: stated directly in the source's own comment inside `checkCloudflare` — "Only a NO-RESPONSE failure is 'unreachable' (debounced as transient). A definitive HTTP/API error (401 revoked token, 403 missing scope) is an immediate, actionable error — not a network blip." Demonstrated by `integrations-retry.test.ts` › "does NOT retry a real HTTP response (401 token-invalid surfaces immediately)."
  **Approved**: pending
- **Decision**: give Cloudflare's account-id resolution its own timeout window, separate from the subsequent Worker-scripts probe's window.
  **Rationale**: stated directly in the source's own comment — "Discovery and the scripts probe each get their OWN window so a slow /accounts call can't eat the scripts call's budget and false-alarm 'unreachable.'"
  **Approved**: pending
- **Decision**: treat `listWorkerScripts`'s returned error-flagged VALUE, not only a thrown error, as retryable for Cloudflare's probe.
  **Rationale**: stated directly in the source's own comment — "listWorkerScripts swallows failures into an error result (not a throw), so retry on error — a transient blip recovers, a real outage stays failed and goes red."
  **Approved**: pending
- **Decision**: debounce a single unreachable provider for `CONFIRM_RUNS` runs spanning `CONFIRM_WINDOW_MS`, but once several providers are confirmed-unreachable in the same run, downgrade them to a correlated warning plus a synthetic Connectivity check rather than ever fully suppressing them.
  **Rationale**: stated directly in `self-check-stability.ts`'s own module doc comment — an unreachable failure "is reported as healthy-with-a-note until it has persisted CONFIRM_RUNS consecutive runs spanning CONFIRM_WINDOW_MS," and "when several providers are confirmed-unreachable in the SAME run, the outage is almost certainly ours, not theirs," so each is "downgraded to a correlated warn" with "a single synthetic Connectivity check" naming "the real suspect." Demonstrated by `integrations-retry.test.ts` › "confirms a persistent all-provider outage but correlates it as monitor-side — amber, not red" and its single-provider counterpart.
  **Approved**: pending
- **Decision**: have `checkStatsFreshness` compute staleness from its own internal `Date.now()` call rather than accepting the `nowMs` `runIntegrationsCheck` received, while `runIntegrationsCheck` forwards that same `nowMs` into the stabilizer.
  **Rationale**: not stated as a deliberate tradeoff in an inline comment; demonstrated as a fact of the code. `timeAgo`'s own doc comment states "nowMs is passed in for testability," yet `checkStatsFreshness` never receives an outer `nowMs` to pass to it, computing its own internally instead — a caller cannot control this specific check's staleness boundary through `runIntegrationsCheck`'s `nowMs` parameter the way it can control the stabilizer's debounce/correlation timing, per stats-freshness-uses-wall-clock-not-caller-nowms and stabilization-uses-callers-nowms above. Recorded here per source-fidelity as fact, not endorsement.
  **Approved**: pending
- **Decision**: identify a `Promise.allSettled` rejection's check by array POSITION against parallel `ids`/`labels` arrays, rather than by a name carried in the rejection itself.
  **Rationale**: stated directly in the source's own comment on the mapping — "Order must match the Promise.allSettled array above." Recorded here as a fact and an acknowledged invariant rather than a marker, per positional-fallback-on-unexpected-rejection: no test in the three given test files exercises an actual rejection from any of the seven check functions, since each already resolves to a well-formed error-state object from its own try/catch, so this fallback path protects against an unanticipated crash rather than a documented, tested contract.
  **Approved**: pending
