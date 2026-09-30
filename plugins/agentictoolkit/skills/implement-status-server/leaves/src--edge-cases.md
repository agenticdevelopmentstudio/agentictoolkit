<!-- leaf: implement-status-server/src--edge-cases · source: status-server-src.md -->

# Status Server

**Rules** (cite as `implement-status-server/src--edge-cases#<slug>`):

- `no-scheduler-provided` MUST — When opts.scheduler is undefined, /health MUST return 200 {status: 'ok', lastCycleAt: null} (no staleness signal), …
- `concurrent-status-summary-builds-during-cache-miss` MUST — When two or more simultaneous requests arrive after cache expiry, cachedSingleFlight MUST ensure only one …
- `origin-parsing-failure` MUST — When an origin is not in the list verbatim and cannot be parsed as a URL, isAllowedOrigin MUST catch the parse error …
- `manual-run-during-interval-tick` MUST — When runNow() is called during a scheduled interval tick, MUST coalesce: return false if a cycle was already in flight …
- `cycle-error-on-boot` MUST — When the initial cycle on start() throws an error, the error MUST be caught and logged; the scheduler MUST continue and …

## Edge Cases

- **Empty service list**: When storage contains zero services (snapshot.services.length === 0), buildStatusSummary counts total as 0 and all sub-counts as 0; the all-unknown override does not apply (it requires `total > 0`), so status is the snapshot's `overall` — with no services and no open issues that is `'healthy'` with `operational: true` and empty `downSites`.
- **No scheduler provided**: When `opts.scheduler` is undefined, `/health` MUST return 200 `{status: 'ok', lastCycleAt: null}` (no staleness signal), `cronRoutes` is not mounted, and `streamRoutes` receives `undefined` (its schedule frame reports a null next cycle and `POST /live/check` answers 503 `no scheduler`).
- **Concurrent status-summary builds during cache miss**: When two or more simultaneous requests arrive after cache expiry, `cachedSingleFlight` MUST ensure only one `buildStatusSummary` call runs; all requests MUST wait and share the result.
- **Origin parsing failure**: When an origin is not in the list verbatim and cannot be parsed as a URL, isAllowedOrigin MUST catch the parse error and return false, so no `Access-Control-Allow-Origin` is sent.
- **Cycle runs past watchdog timeout**: When a cycle is still running at watchdog expiry, the watchdog releases the single-flight lock WITHOUT waiting for the cycle to complete; a new tick can then start even though the first cycle is still in flight. When the abandoned cycle settles, its `release` is a no-op because `cycleSeq` has moved on, so it cannot free the newer cycle's lock; if it resolves, it does set `lastCycleAt` (see the open question on abandoned-cycle-last-cycle-at).
- **Manual run during interval tick**: When `runNow()` is called during a scheduled interval tick, MUST coalesce: return false if a cycle was already in flight (whether from the interval or a previous manual call), else run a manual cycle and return true; in both cases a started scheduler re-anchors the grid when `runNow()` resolves.
- **Cycle error on boot**: When the initial cycle on `start()` throws an error, the error MUST be caught and logged; the scheduler MUST continue and not crash; `lastCycleAt()` remains null until a cycle completes successfully.
- **Very long cycle followed by rapid runNow**: If a cycle takes 4 minutes and finishes, then `runNow()` is called immediately, re-anchoring happens and the next automatic tick is a full interval from the runNow completion, not from the original boot anchor.
