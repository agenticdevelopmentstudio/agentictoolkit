<!-- leaf: implement-status-server/telemetry--test-vectors · source: status-server-telemetry.md -->

# Status Server Telemetry

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|----|----|----|
| telemetry-001 | collect-operation, collect-fetcher-call, collect-success-result | Fetcher returning `{ ok: true, items: [{id: '1', issueKey: 'GT-1', project: 'web', title: 'Error', culprit: null, level: 'error', count: 5, userCount: 2, firstSeen: '2026-09-24T00:00:00Z', lastSeen: '2026-09-24T12:00:00Z', permalink: 'https://sentry.io/...' }], complete: true }` and a Store that appends | Collect invokes fetcher and store; returns `{ ok: true, count: 1 }` |
| telemetry-002 | collect-fetch-failure-handling | Fetcher returning `{ ok: false, items: [], complete: true }` | Collect does not call store.save(); returns `{ ok: false, count: 0 }` |
| telemetry-003 | collect-fetch-success, collect-success-result | Fetcher returning `{ ok: true, items: [item1, item2], complete: false }` | Collect returns `{ ok: true, count: 2 }` and passes `{ complete: false }` to store.save() |
| telemetry-004 | collect-fetch-success | Fetcher returning `{ ok: true, items: [item1] }` with `complete` omitted | `store.save` receives `([item1], { complete: true })`; collect returns `{ ok: true, count: 1 }` |
| telemetry-005 | collect-telemetry-concurrent | Configuration with both GlitchTip and PostHog; both fetchers return `ok: true` with items | Both fetchers are invoked concurrently; both stores receive save() calls; collectTelemetry returns without error |
| telemetry-006 | collect-telemetry-guarded | Configuration with all three GlitchTip credentials set, `POSTHOG_API_KEY` empty | Errors collect runs; analytics collect is not called; only the errors store receives `save()` |
| telemetry-007 | collect-telemetry-fail-soft | Both providers configured; `storage.telemetry.errors.save` rejects; analytics poll succeeds | `"[telemetry] errors collection failed"` logged; analytics collection completes; recordObservations receives `{ source: 'glitchtip', configured: true, reachable: false }`; collectTelemetry resolves |
| telemetry-008 | telemetry-snapshot-structure | Call `emptySnapshot()` | Returns `{ generatedAt: "", errors: [], analytics: [] }` |
| telemetry-009 | complete-flag-semantics | Fetcher returns `{ ok: true, items: [item1], complete: false }` to a reconciling store | `store.save` receives `([item1], { complete: false })` unchanged; honoring it is the store's job |
| telemetry-010 | collect-telemetry-observations | collectTelemetry called with both providers configured and reachable | recordObservations is called with `{ source: 'glitchtip', configured: true, reachable: true }` |
