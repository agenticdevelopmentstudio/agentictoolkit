<!-- leaf: implement-status-server/live--edge-cases · source: status-server-live.md -->

# Status Server Live

**Rules** (cite as `implement-status-server/live--edge-cases#<slug>`):

- `null-and-empty-input` MUST — publishSnapshot and emitLiveUpdate never inspect the contents of a LiveSnapshot — a degenerate snapshot (for example …
- `boundary-values` MUST — maxAgeMs of 0 passed to recentSnapshot MUST still return the cached snapshot when the elapsed time is exactly 0 (the …
- `concurrent-access` MUST — within one JavaScript task, mutation of the subscriber set, cache, and timer handle is single-threaded and MUST NOT …
- `error-states` MUST — a rejected buildLiveSnapshot promise is caught, logged, and dropped (emit-build-failure-logged-not-thrown); it MUST NOT …

## Edge Cases

- **Null and empty input**: `publishSnapshot` and `emitLiveUpdate` never
  inspect the contents of a `LiveSnapshot` — a degenerate snapshot (for
  example one with `configDegraded: true` and every array empty) flows
  through identically to a healthy one, because this module treats it as an
  opaque value. `recentSnapshot` before any publish and `liveSubscriberCount`
  before any subscription both return their empty-state values (`null` and
  `0`) rather than throwing (MUST, per recent-snapshot-null-before-publish).
- **Boundary values**: `maxAgeMs` of `0` passed to `recentSnapshot` MUST
  still return the cached snapshot when the elapsed time is exactly `0`
  (the comparison is `<=`, not `<`). A fourth `emitLiveUpdate` call arriving
  at the exact instant the 150ms timer's callback begins running observes
  `pending` already set to `null` (it is cleared as the very first statement
  in that callback), so it MUST be treated as the start of a brand-new burst
  with its own fresh 150ms window, not folded into the build that is already
  running.
- **Concurrent access**: within one JavaScript task, mutation of the
  subscriber set, cache, and timer handle is single-threaded and MUST NOT
  interleave (single-threaded-mutation). Across an `await` boundary this
  guarantee does not hold — see the open question on
  in-flight-build-cancellation, which is exactly a race between a build
  already in flight and a later `resetLiveEvents` or fresh burst.
- **Error states**: a rejected `buildLiveSnapshot` promise is caught, logged,
  and dropped (emit-build-failure-logged-not-thrown); it MUST NOT reach any
  subscriber as a partial or error snapshot, and no snapshot is delivered
  for that failed attempt. A throwing subscriber is isolated
  (publish-subscriber-isolation) and MUST NOT be removed from the subscriber
  set as a consequence of throwing — it stays registered and is retried on
  the next `publishSnapshot`.
- **Offline / disconnected state**: this module has no client-side
  connectivity of its own to lose. Its analogue of "disconnected" is a
  subscriber's returned unsubscribe function being called — by
  `routes/stream.ts`, external to this file, when the browser's `EventSource`
  disconnects — after which `publishSnapshot` simply no longer includes that
  callback (unsubscribe-idempotent). This module has no notion of
  reconnection; a reconnecting client calls `subscribeLive` again as a fresh
  registration, and `routes/stream.ts` decides whether to serve it a cached
  `recentSnapshot` or trigger a fresh build, both external to this file.
