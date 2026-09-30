<!-- leaf: implement-status-server-monitor-1/live-types--edge-cases · source: status-server-monitor-live-types.md -->

# Status Server Monitor Live Types

**Rules** (cite as `implement-status-server-monitor-1/live-types--edge-cases#<slug>`):

- `null-and-empty-input` MUST — an endpoint that has never been probed MUST report lastCheckedAt: null (inherited from ServiceStatusDTO) and — per …
- `null-and-empty-input-2` MUST — a monitor process running outside Railway MUST report monitorVersion: null, per …
- `null-and-empty-input-3` MUST — a fresh database with no persisted probe ever written MUST report LiveSnapshot.lastCycleAt: null, per …
- `boundary-values` MUST — ProviderKey admits exactly four literal values; a fifth provider key is not a valid ProviderKey and …
- `error-states` MUST — not applicable to a producer failure in the sense of this file raising one — this file declares no function that can …

## Edge Cases

- **Null and empty input**: an endpoint that has never been probed MUST report `lastCheckedAt: null` (inherited from `ServiceStatusDTO`) and — per **down-since-is-server-truth** — `downSince: null`, since there is no open issue to have a `since`. (MUST)
- **Null and empty input**: a monitor process running outside Railway MUST report `monitorVersion: null`, per **monitor-version-is-railway-commit-or-null**. (MUST)
- **Null and empty input**: a fresh database with no persisted probe ever written MUST report `LiveSnapshot.lastCycleAt: null`, per **last-cycle-at-is-data-freshness-clock** — traced to `reads.int.test.ts`'s `toHaveProperty('lastCycleAt', null)` assertion. (MUST)
- **Boundary values**: `ProviderKey` admits exactly four literal values; a fifth provider key is not a valid `ProviderKey` and `LiveSnapshot.providers` MUST NOT carry an entry for one, per **provider-key-closed-set** and **providers-map-is-total**. (MUST)
- **Concurrent access**: not applicable to this file — it declares no mutable state and no function; the module's only property is the shape it declares, which cannot be entered concurrently. The concurrency of the process that builds a `LiveSnapshot` value (`buildLiveSnapshot` in `routes/reads.ts`) is outside this file's contract.
- **Error states**: not applicable to a producer failure in the sense of this file raising one — this file declares no function that can throw. **config-degraded-flag** is this contract's error-state signal: a producer that could not reach the database MUST still return a fully-shaped `LiveSnapshot` with `configDegraded: true`, rather than omit fields or fail the read outright, so every field declared in this file remains present per **all-fields-required** even in the degraded case.
- **Offline or disconnected state**: not applicable — this file makes no network call of its own; it only declares the shape of a value that is already the RESULT of the monitor's own network probing, described from the client's perspective by `generatedAt`/`lastCycleAt`/`probeIntervalMs` (per **generated-at-is-read-time**, **last-cycle-at-is-data-freshness-clock**, **probe-interval-ms-scales-staleness**), which exist specifically so a consumer can detect that the underlying poller has gone quiet without this file needing any network awareness itself.
