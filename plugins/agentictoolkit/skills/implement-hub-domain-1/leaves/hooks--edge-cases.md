<!-- leaf: implement-hub-domain-1/hooks--edge-cases · source: hub-domain-hooks.md -->

# Hub Domain Messaging Hooks

**Rules** (cite as `implement-hub-domain-1/hooks--edge-cases#<slug>`):

- `null-and-empty-input-chatid` MUST — dm-thread-null-chatid-clears-state above; a null and an empty-string chatId are treated identically (both fail the …
- `null-and-empty-input-send-body` MUST — dm-thread-send-noop-on-empty-or-missing-chat above; a body that is empty or all whitespace after trim() MUST NOT be …
- `null-and-empty-input-presence-ids` MUST — fetchPresenceMap MUST return an empty Map without issuing any request when its deduplicated, falsy-filtered id list is …
- `null-and-empty-input-inbox-categories` MUST — an absent or empty categories array MUST produce no category= query parameters at all, per inbox-query-serialization.

## Edge Cases

- **Null and empty input — `chatId`**: `dm-thread-null-chatid-clears-state` above; a `null` and an
  empty-string `chatId` are treated identically (both fail the `!chatId` check) — MUST.
- **Null and empty input — `send` body**: `dm-thread-send-noop-on-empty-or-missing-chat` above; a
  body that is empty or all whitespace after `trim()` MUST NOT be sent.
- **Null and empty input — presence ids**: `fetchPresenceMap` MUST return an empty `Map` without
  issuing any request when its deduplicated, falsy-filtered id list is empty.
- **Null and empty input — inbox categories**: an absent or empty `categories` array MUST produce
  no `category=` query parameters at all, per `inbox-query-serialization`.
- **Boundary values — DM window ceiling**: `dm-inbox-window-growth-and-ceiling` and
  `dm-inbox-has-more-computation` above; the window never exceeds 500 rows and `hasMore` reports
  `false` once it does, even if more rows exist server-side, per the source's own comment that 500
  is "the ceiling the backend also caps at."
- **Boundary values — DM thread window**: neither the initial load nor the poll fallback in
  `useDmThread` requests more than `pageSize=200`, and the hook exposes no further-back pagination
  for thread history (unlike the conversation list's `loadMore`); a thread with more history than
  the current window simply never surfaces it through this hook — a fact, not a gap, since no
  history-paging method exists to fail.
- **Concurrent access — DM conversation list**: `dm-inbox-stale-response-discarded` above; the
  generation counter guarantees only the most recently issued load's result is ever applied.
  Concurrent JavaScript execution is single-threaded, so the check-and-increment on `generation`
  cannot itself race.
- **Concurrent access — DM thread history vs. live stream**: the SSE stream is opened only after
  the history load resolves, cursored at the last loaded `seq`; the stream is a cursor-based replay
  (`after=<seq>`), not a from-now push, so a message sent by another participant during the gap
  between the history response and the stream opening is still delivered once the stream connects.
- **Concurrent access — send during a thread switch**: see the
  `thread-message-isolation-on-chatid-switch` edge case below.
- **Error states — plain HTTP failure**: any `authedJson`/`authedRequest` rejection propagates as a
  thrown `AuthHttpError` (or a plain `Error` for a non-HTTP failure); each hook that exposes an
  `error` field sets it from `err.message`, and each hook whose failing operation is a direct
  caller action (`send`, `markRead`, mutations, `startDm`) lets the rejection propagate to the
  caller instead.
- **Error states — malformed SSE frame**: `dm-thread-malformed-frame-ignored` above.
- **Error states — presence fetch failure**: `dm-inbox-presence-failure-is-silent` above.
- **Offline or disconnected state**: `connectSse`'s poll fallback (interval + window-focus) is the
  only reconnection behavior either file relies on; neither file checks `navigator.onLine` or
  queues a `send`/mutation for retry once connectivity returns — a `send` issued while offline
  simply rejects with a network-level failure and is not retried or queued by this recipe.
- **No timeout**: no call in either file sets a deadline or `AbortSignal`; a reachable-but-
  unresponsive backend leaves that call pending indefinitely.
- **No cancellation**: no exposed function (`send`, `markRead`, mutations, `loadMore`, `startDm`)
  accepts an `AbortSignal`; a caller cannot cancel an in-flight call through these hooks.
- **No retry beyond the 401 waterfall**: every plain HTTP call issues exactly one request (plus,
  on a `401`, the single inherited refresh-and-retry); nothing in either file retries a network
  failure or a non-401 error status, and no exponential backoff exists anywhere in this recipe —
  `connectSse`'s poll fallback is a fixed interval, not a backoff schedule.
- **thread-message-isolation-on-chatid-switch**: NEEDS REVIEW: Not implemented in source. If `send` (or its returned promise) is still pending when `chatId` changes, `useDmThread`'s `messages` state is a single array not partitioned by chat id, and neither `send` nor `markRead` carries a generation guard analogous to the load effect's own `cancelled` flag or `useDmConversations`' generation counter; the resolved message can merge into whatever thread is displayed when it settles rather than the one it was sent for. Evidence that would settle it: whether product intent tolerates this cross-thread bleed-through during a fast thread switch, or a guard was expected and is simply absent from this checkout.
