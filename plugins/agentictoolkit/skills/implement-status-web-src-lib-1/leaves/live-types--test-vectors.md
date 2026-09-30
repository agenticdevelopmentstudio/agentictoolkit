<!-- leaf: implement-status-web-src-lib-1/live-types--test-vectors · source: status-web-src-lib-live-types.md -->

# Live Snapshot Wire Types

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| live-types-001 | snapshot-required-fields, providers-complete, snapshot-optional-fields | `liveSnapshot()` from the fixture: `generatedAt: "2026-06-30T00:00:00.000Z"`, empty `services`/`deployments`/`staleProd`, all four providers `{ configured: true, ok: true }`, `configDegraded: false`, `configReason: null`, no `lastCycleAt`/`probeIntervalMs`/`monitorVersion` | Typechecks as `LiveSnapshot`; removing any provider key or any required field fails to typecheck |
| live-types-002 | provider-key-members | Assign `"cloudflare"` as a `ProviderKey` | Fails to typecheck; `"cloudflare-pages"` typechecks |
| live-types-003 | generated-at-identity | `isSameSnapshot(a, b)` where `a` and `b` are distinct objects with `generatedAt: "2026-06-30T00:00:00.000Z"`; then with `b.generatedAt: "2026-06-30T00:01:00.000Z"`; then `isSameSnapshot(null, b)` | `true`, then `false`, then `false` |
| live-types-004 | down-since-field, down-since-server-truth, dns-ok-field | `selectStaleMonitors([svc({ status: "down", downSince: 30 days ago, statusCode: 500, error: null, dnsOk: true })], NOW)` | One row with `slug: "ep1"`, `dnsOk: true`, `detail: "HTTP 500"`, `ageMs: 2592000000` |
| live-types-005 | down-since-null | `selectStaleMonitors` over a `down` service with `downSince: null` and over `healthy`/`degraded` services | `[]` |
| live-types-006 | dns-ok-source-meaning | The same down-for-a-week services with `dnsOk: true` and with `dnsOk: false` | Same selected slugs either way; each row's `dnsOk` echoes the input |
| live-types-007 | last-cycle-at-absent | `snapshotFreshness(undefined, "2026-06-30T00:00:00.000Z", 60000)` and `snapshotFreshness(null, ...)` | `"fresh"` both times |
| live-types-008 | probe-interval-absent, probe-interval-meaning | `snapshotStaleMs(undefined)`; `snapshotStaleMs(120000)` | `300000`; `600000` |
| live-types-009 | live-service-extends, live-service-status-values | A `LiveServiceDTO` literal with every `ServiceStatusDTO` field, `status: "unknown"`, `dnsOk: true`, `downSince: null` | Typechecks; omitting `dnsOk` or `downSince`, or setting `status: "offline"`, fails |
| live-types-010 | stale-prod-fields | A `StaleProdDTO` with `projectName: "site"`, `environment: "production"`, and `detail`, `sourceUrl`, `liveUrl` all `null` | Typechecks; `environment: null` fails |
| live-types-011 | type-only-module, no-side-effects, no-db-imports | Import the module and inspect its runtime exports | No runtime values are exported |
