<!-- leaf: implement-status-web-hooks/use-media-query--edge-cases · source: status-web-hooks-use-media-query.md -->

# useMediaQuery

**Rules** (cite as `implement-status-web-hooks/use-media-query--edge-cases#<slug>`):

- `empty-query-string` MUST — useMediaQuery("") MUST pass "" to the platform API unchanged; the returned value is whatever matches the platform …
- `malformed-query` MUST — A syntactically invalid query MUST be passed through unchanged; the platform reports it as not all, so the hook returns …
- `missing-media-query-api` MUST — In an environment without the API (jsdom, some test runners), the effect MUST throw; callers or tests are responsible …
- `query-changes-every-render` MUST — A caller that builds a new query string on every render with different content MUST cause a teardown and resubscribe on …
- `change-event-after-unmount` MUST — Because cleanup removes the listener, no state update MUST occur from change events that fire after unmount.
- `rapid-consecutive-change-events` MUST — Each event MUST set state to that event's matches; the final returned value is the last delivered event's value.
- `concurrent-calls` MUST — Multiple components calling the hook with the same query each MUST create an independent subscription and state; there …

## Edge Cases

- **Empty query string**: `useMediaQuery("")` MUST pass `""` to the platform API unchanged; the returned value is whatever `matches` the platform reports for it (browsers treat an empty media query as matching all).
- **Malformed query**: A syntactically invalid query MUST be passed through unchanged; the platform reports it as `not all`, so the hook returns `false` and no change event is expected to fire.
- **Missing media-query API**: In an environment without the API (jsdom, some test runners), the effect MUST throw; callers or tests are responsible for stubbing it.
- **Query changes every render**: A caller that builds a new query string on every render with different content MUST cause a teardown and resubscribe on every such render; a caller passing an identical string MUST NOT.
- **Unmount before effect runs**: If the component unmounts before its effect runs, no subscription is created and no cleanup runs.
- **Change event after unmount**: Because cleanup removes the listener, no state update MUST occur from change events that fire after unmount.
- **Rapid consecutive change events**: Each event MUST set state to that event's `matches`; the final returned value is the last delivered event's value.
- **Concurrent calls**: Multiple components calling the hook with the same query each MUST create an independent subscription and state; there is no shared cache.
- **Cancellation, timeout, network**: Not applicable — the hook makes no asynchronous request and has nothing to cancel or time out beyond listener removal.
