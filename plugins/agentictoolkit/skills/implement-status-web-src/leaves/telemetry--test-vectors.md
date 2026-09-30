<!-- leaf: implement-status-web-src/telemetry--test-vectors · source: status-web-src-telemetry.md -->

# Status Web Telemetry

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| telemetry-001 | empty-snapshot | `emptySnapshot()` called twice | Each call returns `{ generatedAt: "", errors: [], analytics: [] }`, and the two results are different objects |
| telemetry-002 | cache-save-format, parse-projection | `parseSnapshot(JSON.stringify(snap))` where `snap` has `generatedAt` `2026-06-13T12:00:00.000Z`, one `ErrorDTO` (`id` "1", `project` "hub", `title` "boom", `count` 3) and one `pageviews`/`24h`/`all` metric of value 10 | A value deep-equal to `snap` (from `local-cache.test.ts` "round-trips a stored snapshot") |
| telemetry-003 | parse-empty | `parseSnapshot(null)` and `parseSnapshot("")` | Both return `null` |
| telemetry-004 | parse-malformed-json | `parseSnapshot("{not json")` | `null` |
| telemetry-005 | parse-shape-gate | `parseSnapshot` of the JSON for `null`, `{ generatedAt: "x" }`, `{ generatedAt: 1, errors: [], analytics: [] }`, and `{ generatedAt: "x", errors: "nope", analytics: [] }` | Each returns `null` |
| telemetry-006 | parse-projection | `parseSnapshot('{"generatedAt":"x","errors":[],"analytics":[],"extra":1}')` | `{ generatedAt: "x", errors: [], analytics: [] }` with no `extra` key |
| telemetry-007 | cache-ssr-guard | `localCache.load()` with `window` undefined | Returns `null` and does not touch storage |
| telemetry-008 | cache-save-best-effort | `localCache.save(snap)` when `localStorage.setItem` throws a quota error | Returns normally with no exception |
| telemetry-009 | live-request, live-body | `liveSource.get(api)` where `api.fetch("/telemetry")` answers 200 with a snapshot body | Exactly one fetch to `/telemetry`, and the promise resolves with the body unchanged |
| telemetry-010 | live-http-error | `api.fetch("/telemetry")` answers 503 | The promise rejects with an `Error` whose message is `telemetry 503` |
| telemetry-011 | turso-parallel-requests, turso-projection | `/errors` answers 200 `{ errors: [e] }` and `/analytics` answers 200 `{ metrics: [m] }` | Both fetches are issued before either resolves. The result is `{ errors: [e], analytics: [m] }` with `generatedAt` set to the client's ISO time at assembly |
| telemetry-012 | turso-errors-http-error | `/errors` answers 500 and `/analytics` answers 500 | Rejects with `errors 500` (the `/errors` check runs first) |
| telemetry-013 | turso-analytics-http-error | `/errors` answers 200 and `/analytics` answers 502 | Rejects with `analytics 502` |
| telemetry-014 | cache-binding, source-binding | Import `cache` and `source` from `telemetry/client` | `cache === localCache` and `source === liveSource` |
| telemetry-015 | fetch-result-not-ok | A store consumer receives `{ ok: false, items: [] }` | The consumer leaves its store unchanged, with no save and no clear |
