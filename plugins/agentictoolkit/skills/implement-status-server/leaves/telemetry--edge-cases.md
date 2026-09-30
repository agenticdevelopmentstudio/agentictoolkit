<!-- leaf: implement-status-server/telemetry--edge-cases · source: status-server-telemetry.md -->

# Status Server Telemetry

**Rules** (cite as `implement-status-server/telemetry--edge-cases#<slug>`):

- `empty-items-array` MUST — When a fetcher returns ok: true with an empty items array, collect MUST call store.save([], { complete }) and return { …
- `null-and-undefined-complete-flag` MUST — If a fetcher omits complete, collect MUST default it to true before passing to store.save().
- `unconfigured-provider` MUST — If any of a provider's three credentials is unset or empty, collectTelemetry MUST skip calling collect() for that …
- `observation-recording-failure` MUST — If recordObservations() throws, collectTelemetry MUST catch it, log it, and MUST NOT abort the overall cycle; the …

## Edge Cases

- **Empty items array**: When a fetcher returns `ok: true` with an empty `items` array, `collect` MUST call `store.save([], { complete })` and return `{ ok: true, count: 0 }`, allowing stores to interpret emptiness as "no current issues" (if complete) or "no data this page" (if incomplete).
- **Null and undefined complete flag**: If a fetcher omits `complete`, `collect` MUST default it to `true` before passing to `store.save()`.
- **Fetcher network timeout**: The GlitchTip and PostHog fetchers catch their own timeouts and HTTP failures, log them with `console.warn`, and return `ok: false`. Any rejection that still escapes `collect()` is caught by the `.catch` on that stream's promise in `collectTelemetry`, logged, and not re-thrown; the other stream continues.
- **Store persistence failure**: If `store.save()` rejects, `collect()` rejects with that error and never returns a count. In `collectTelemetry` the stream's `.catch` logs it; for the errors stream this also records GlitchTip `reachable: false`, even though the provider answered.
- **Unconfigured provider**: If any of a provider's three credentials is unset or empty, `collectTelemetry` MUST skip calling `collect()` for that stream. For GlitchTip it still records `{ source: "glitchtip", configured: false, reachable: true }` (unconfigured is not unreachable); an unconfigured PostHog records nothing.
- **Concurrent provider outages**: If both streams fail concurrently, each failure is handled independently; `collectTelemetry` still records its one GlitchTip observation with `reachable: false`, and no observation for PostHog.
- **Observation recording failure**: If `recordObservations()` throws, `collectTelemetry` MUST catch it, log it, and MUST NOT abort the overall cycle; the platform-health row is not recorded for this cycle; telemetry collection has already finished by then and `collectTelemetry` resolves normally.
