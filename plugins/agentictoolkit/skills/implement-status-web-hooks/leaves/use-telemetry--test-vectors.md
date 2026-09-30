<!-- leaf: implement-status-web-hooks/use-telemetry--test-vectors · source: status-web-hooks-use-telemetry.md -->

# useTelemetry

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| telemetry-001 | poll-interval-constant | Read the exported constant | `TELEMETRY_POLL_MS` is `60000` |
| telemetry-002 | first-render-empty, empty-fallback, hook-signature | Empty `localStorage`; source never resolves; render the hook once | Returned value deep-equals `{ generatedAt: "", errors: [], analytics: [] }` |
| telemetry-003 | hydrate-after-mount, cache-fallback | `localStorage["adh-telemetry-v1"]` holds a valid snapshot `S`; source never resolves | First render returns the empty snapshot; after effects flush, the hook returns a value deep-equal to `S` |
| telemetry-004 | live-wins, persist-on-data, cache-save-format | Cache holds snapshot `A`; source resolves snapshot `B` | Hook returns `B`; `localStorage["adh-telemetry-v1"]` equals `JSON.stringify(B)` |
| telemetry-005 | live-request, query-fn | `StatusApiProvider` with `basePath: "/x"` and a recording `fetch` | Exactly one request to `/x/telemetry` per query run, with no init options |
| telemetry-006 | live-http-error, single-retry, no-save-on-failure | Source `fetch` answers 502 every time; cache holds snapshot `A` | `fetch` is called twice (initial plus one retry); the query error message is `telemetry 502`; the hook returns `A`; `localStorage` still holds `A` |
| telemetry-007 | data-retained-on-error | First poll resolves `B`; next poll (and its retry) answer 500 | Hook still returns `B` after the failed poll |
| telemetry-008 | parse-gate | `parseSnapshot(null)` and `parseSnapshot("")` (from `local-cache.test.ts`) | Both return `null` |
| telemetry-009 | parse-gate | `parseSnapshot("{not json")` (from `local-cache.test.ts`) | Returns `null` |
| telemetry-010 | parse-gate | `parseSnapshot` of `JSON.stringify(null)`, `{ generatedAt: "x" }`, `{ generatedAt: 1, errors: [], analytics: [] }`, `{ generatedAt: "x", errors: "nope", analytics: [] }` (from `local-cache.test.ts`) | Each returns `null` |
| telemetry-011 | parse-projection, snapshot-shape | `parseSnapshot(JSON.stringify(snap))` for a snapshot with one error and one analytics metric (from `local-cache.test.ts`) | Result deep-equals `snap` |
| telemetry-012 | parse-projection | `parseSnapshot('{"generatedAt":"t","errors":[],"analytics":[],"extra":1}')` | Returns `{ generatedAt: "t", errors: [], analytics: [] }` with no `extra` key |
| telemetry-013 | cache-save-best-effort | `localStorage.setItem` throws (quota exceeded); source resolves `B` | No exception reaches the component; the hook returns `B` |
| telemetry-014 | cache-load-parse | `localStorage.getItem` throws; source never resolves | Hook returns the empty snapshot after mount |
| telemetry-015 | shared-poll, per-instance-cache-io | Two components call the hook under one `QueryClient`; source resolves `B` | One source fetch; both return `B`; `localStorage.setItem` is called twice with the same value |
| telemetry-016 | poll-cadence | Hook mounted, document visible, first fetch resolved; advance timers 60000 ms | A second source fetch occurs |
| telemetry-017 | empty-snapshot | Call `emptySnapshot()` twice | Two distinct objects, each deep-equal to `{ generatedAt: "", errors: [], analytics: [] }` |
