<!-- leaf: implement-status-server/live--test-vectors · source: status-server-live.md -->

# Status Server Live

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-live-001 | subscription-registration, subscriber-count | `subscribeLive(cbA)`, then `subscribeLive(cbB)` | `liveSubscriberCount()` returns `2` — `live-events.test.ts` "fans one published snapshot out to every subscriber" |
| status-server-live-002 | subscription-registration, unsubscribe-idempotent | Call the function `subscribeLive(cb)` returned, then `publishSnapshot(s)` | `cb` is never invoked; `liveSubscriberCount()` returns `0` — `live-events.test.ts` "stops delivering after unsubscribe" |
| status-server-live-003 | publish-fanout-same-reference | `subscribeLive` twice (pushing to arrays `a` and `b`); `publishSnapshot(s)` | `a` and `b` both equal `[s]`; `a[0]` and `b[0]` are the same object reference as `s` — `live-events.test.ts` same test, `toBe` assertions |
| status-server-live-004 | publish-subscriber-isolation | One subscriber's callback throws synchronously; a second subscriber pushes to an array; `publishSnapshot(s)` | The second subscriber still receives `s`; no exception escapes `publishSnapshot` — `live-events.test.ts` "a throwing subscriber never blocks the fan-out to the others" |
| status-server-live-005 | publish-updates-cache-unconditionally | `publishSnapshot(s)` with zero subscribers currently registered | A subsequent `recentSnapshot` call with a large enough window returns `s`; traced to source: the cache write precedes and does not depend on the subscriber loop |
| status-server-live-006 | recent-snapshot-null-before-publish | Fake timers; `recentSnapshot(1000)` called before any publish | Returns `null` — `live-events.test.ts` "recentSnapshot serves the last published snapshot within the age window, else null", first assertion |
| status-server-live-007 | recent-snapshot-freshness-window | Publish `s`, then immediately call `recentSnapshot(1000)` | Returns `s`, the same object reference — same test, second assertion |
| status-server-live-008 | recent-snapshot-freshness-window | Publish `s`, advance fake time by 1500ms, then call `recentSnapshot(1000)` | Returns `null` (aged out) — same test, third assertion |
| status-server-live-009 | reset-clears-subscribers-and-cache | Two `subscribeLive` calls, then `resetLiveEvents()` | `liveSubscriberCount()` returns `0` immediately afterward; traced to source's `subscribers.clear()` |
| status-server-live-010 | emit-skips-when-idle | Zero subscribers registered; call `emitLiveUpdate(storage, config)` where `storage`'s methods throw if invoked | None of `storage`'s methods are called and no timer is scheduled; traced to source's `if (subscribers.size === 0) return;` guard, which runs before the coalesce check or the `setTimeout` call — not exercised by any test in `test/` |
| status-server-live-011 | emit-coalesces-concurrent-calls, emit-fixed-coalesce-window | One subscriber registered; call `emitLiveUpdate(storage, config)` three times synchronously in the same tick, then advance time by 150ms | The build runs exactly once, not three times, and the subscriber receives exactly one snapshot; traced to source's `if (pending) return;` guard — not exercised by any test in `test/` |
| status-server-live-012 | emit-build-failure-logged-not-thrown, emit-no-retry | One subscriber registered; the build's promise rejects; call `emitLiveUpdate(storage, config)`; advance time by 150ms | The rejection is caught and logged via `console.error`; the subscriber's callback is never invoked; the call to `emitLiveUpdate` itself does not throw — traced to source's `.catch` clause — not exercised by any test in `test/` |
| status-server-live-013 | reset-cancels-armed-timer | Call `emitLiveUpdate` to arm the debounce timer, then call `resetLiveEvents()` before 150ms elapses, then advance time past 150ms | The build is never invoked; traced to source's `clearTimeout(pending)` inside `resetLiveEvents` — not exercised by any test in `test/` |
