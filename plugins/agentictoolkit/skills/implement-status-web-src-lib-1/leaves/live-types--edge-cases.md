<!-- leaf: implement-status-web-src-lib-1/live-types--edge-cases · source: status-web-src-lib-live-types.md -->

# Live Snapshot Wire Types

**Rules** (cite as `implement-status-web-src-lib-1/live-types--edge-cases#<slug>`):

- `older-backend` MUST — A payload with no lastCycleAt, probeIntervalMs or monitorVersion MUST typecheck; the client MUST then show no staleness …
- `first-probe-not-yet-run` MUST — lastCycleAt: null MUST mean no probe has run, and MUST NOT trigger a warning. MUST.
- `empty-snapshot` MUST — services, deployments and staleProd MAY each be empty arrays (the fixture default). MUST.
- `endpoint-down-with-no-onset` MUST — A down service with downSince: null MUST NOT be treated as long-down; selectStaleMonitors skips it. MUST.
- `malformed-downsince` MUST — A string that does not parse to a date yields a non-finite age, and selectStaleMonitors MUST skip that service rather …
- `malformed-generatedat-or-lastcycleat` MUST — An unparseable date makes the age NaN, and snapshotFreshness MUST return "fresh" rather than warn. MUST.
- `unknown-union-member-at-runtime` MUST — A status or provider key outside the declared unions is not rejected (no runtime validation); it reaches consumers …
- `re-delivered-frame` MUST — A frame whose generatedAt equals the last ingested one MUST be treated as the same delivery. MUST.
- `config-fallback` MUST — configDegraded MUST be true only on the static-list fallback; the server's successful-read path always sends …

## Edge Cases

- **Older backend**: A payload with no `lastCycleAt`, `probeIntervalMs` or `monitorVersion` MUST typecheck; the client MUST then show no staleness warning, use the 300000 ms floor, and show no version. MUST.
- **First probe not yet run**: `lastCycleAt: null` MUST mean no probe has run, and MUST NOT trigger a warning. MUST.
- **Empty snapshot**: `services`, `deployments` and `staleProd` MAY each be empty arrays (the fixture default). MUST.
- **Endpoint down with no onset**: A `down` service with `downSince: null` MUST NOT be treated as long-down; `selectStaleMonitors` skips it. MUST.
- **Malformed `downSince`**: A string that does not parse to a date yields a non-finite age, and `selectStaleMonitors` MUST skip that service rather than surface it. MUST.
- **Malformed `generatedAt` or `lastCycleAt`**: An unparseable date makes the age `NaN`, and `snapshotFreshness` MUST return `"fresh"` rather than warn. MUST.
- **Unknown union member at runtime**: A `status` or provider key outside the declared unions is not rejected (no runtime validation); it reaches consumers unchecked. MUST (fact of the contract).
- **Re-delivered frame**: A frame whose `generatedAt` equals the last ingested one MUST be treated as the same delivery. MUST.
- **Client and server copies drift**: A field renamed in only one copy compiles in both packages; see server-parity. No parity test exists to catch it.
- **Config fallback**: `configDegraded` MUST be `true` only on the static-list fallback; the server's successful-read path always sends `configDegraded: false` and `configReason: null`. MUST.
- **Concurrency, network, offline, cancellation, timeouts**: Not applicable; the module has no runtime behavior. Transport failures are owned by `use-live-snapshot.ts`.
