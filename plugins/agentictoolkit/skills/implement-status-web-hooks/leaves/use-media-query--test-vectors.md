<!-- leaf: implement-status-web-hooks/use-media-query--test-vectors · source: status-web-hooks-use-media-query.md -->

# useMediaQuery

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| media-query-001 | initial-value | Viewport matches `"(max-width: 760px)"`; inspect the value returned from the very first render, before effects run | `false` |
| media-query-002 | ssr-value | Server-render a component calling `useMediaQuery("(min-width: 761px)")` | Rendered output reflects `false` |
| media-query-003 | mount-sync | Stubbed media-query API returns `matches: true` for the query; render and flush effects | Returned value becomes `true` |
| media-query-004 | mount-sync | Stubbed media-query API returns `matches: false`; render and flush effects | Returned value stays `false` |
| media-query-005 | change-subscription | After mount with `matches: false`, dispatch a change event with `matches: true` | Returned value becomes `true`; a following event with `matches: false` returns it to `false` |
| media-query-006 | unsubscribe-on-unmount | Mount, then unmount the calling component | `removeEventListener` is called once with `"change"` and the same handler passed to `addEventListener` |
| media-query-007 | query-change-resubscribe | Re-render with `query` changed from `"(max-width: 760px)"` to `"(min-width: 761px)"` | Old listener removed, media-query API called with the new query, new listener added, value set to the new query's `matches` |
| media-query-008 | stable-query-no-resubscribe | Re-render with the same `query` string | Media-query API is not called again; `addEventListener` call count unchanged |
| media-query-009 | stale-value-on-query-change | Mounted with query A (matches `true`); re-render with query B (matches `false`) | The render with B first returns `true`, then `false` after the effect runs |
| media-query-010 | no-environment-guard | Media-query API is absent (jsdom without a stub); render and flush effects | The effect throws a TypeError; the hook does not return a fallback |
