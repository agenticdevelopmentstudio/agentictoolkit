---
id: 8da824cf-e518-4cee-b897-3a8e17f9c32a
title: Hub Domain Messaging Hooks
domain: agentictoolkit://cookbook/messaging/hooks
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'TypeScript hooks for the web DM inbox/thread and notification store: SSE-backed
  live updates with a shared poll fallback, pagination, and message dedupe.'
platforms:
- typescript
- web
tags:
- hub
- messaging
- notifications
- direct-messages
- real-time
- react-hooks
depends-on: []
related: []
references:
- packages/web/packages/messaging/src/hooks/use-dms.ts (agentictoolkit)
- packages/web/packages/messaging/src/hooks/use-notifications.ts (agentictoolkit)
- packages/web/packages/data/src/stream/index.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
- packages/web/packages/auth/src/tokens.ts (agentictoolkit)
- packages/web/packages/auth/src/context.tsx (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain Messaging Hooks

## Overview

`use-dms.ts` and `use-notifications.ts` are the client-side logic for the web messaging
surface: the DM inbox, a single DM thread, starting a DM, the header unread badge, and the
notification inbox list. Both files carry the same shape — a data hook backed by `authedJson`/
`authedRequest` from `@agentic-toolkit/auth/client`, kept live over the shared `connectSse`
transport (`@agentic-toolkit/data/stream`), which is SSE-with-token-in-query-string plus a
self-healing interval-and-window-focus poll fallback. `use-notifications.ts` additionally owns
ONE module-level "wake" channel — a single refcounted `/api/notifications/stream` connection and
an `emitLocalChange`/`subscribeToNotifications` pub-sub pair — that `use-dms.ts` reuses rather
than opening its own parallel signal, per both files' own top-of-file comments. It is a headless
**logic** module with no visual surface, so this recipe marks Appearance, States, and
Accessibility not applicable and carries the entire runtime contract in Behavioral Requirements,
per the non-UI component guidance this recipe was authored under.

## Behavioral Requirements

**Shared wake channel (`use-notifications.ts` module scope: `subscribeToNotifications`,
`emitLocalChange`)**

- **shared-stream-refcounting**: `subscribeToNotifications` MUST open the single module-level
  `/api/notifications/stream` `EventSource` connection (via `connectSse`) only on the transition
  from zero to one subscriber, and the unsubscribe function it returns MUST close that connection
  only on the transition from one subscriber back to zero; a second, third, or later subscriber
  MUST NOT open an additional connection.
- **local-change-broadcast**: `emitLocalChange` MUST invoke every function currently in the
  subscriber set, synchronously and with no arguments.
- **wake-signal-carries-no-payload**: the shared stream's `onEvent`/`onPoll` handlers MUST both
  be `notifyAll` itself; a `notification` server event's payload MUST NOT be parsed, inspected, or
  passed to subscribers — receipt of the event is the entire signal, per the source's own comment
  that "the wake payload is ignored."

**Unread count (`useUnreadCount`)**

- **unread-count-fetch-on-mount-and-wake**: `useUnreadCount` MUST issue `GET
  {API_BASE}/unread-count` once on mount and once on every subsequent wake delivered through
  `subscribeToNotifications`, and MUST set `count` to the resolved `count` field each time.
- **unread-count-preserved-on-failure**: a rejected `GET {API_BASE}/unread-count` MUST leave the
  previously set `count` unchanged; `useUnreadCount` MUST NOT reset `count` to `0` or to any other
  value on a failed fetch.

**Notification inbox (`useInbox`)**

- **inbox-query-serialization**: `buildInboxQuery` MUST set `status`, `read`, `page`, and
  `pageSize` query parameters only when the corresponding `InboxParams` field is provided, and
  MUST append one repeated `category=<c>` parameter per entry of `params.categories`, in that
  array's order; an `InboxParams` with every field omitted MUST serialize to the empty string.
- **inbox-status-left-to-backend-default**: when `params.status` is not provided,
  `buildInboxQuery` MUST omit the `status` parameter entirely rather than substituting a
  client-side default; the `useInbox` doc comment states this "defaults to the caller's inbox" on
  the backend, not in this file.
- **inbox-fetch-per-query-and-nonce**: `useInbox` MUST re-issue `GET {API_BASE}` (with the built
  query string appended when non-empty) whenever `buildInboxQuery(params)`'s result changes or
  `refetch`/a mutation increments the internal reload counter, and MUST set `items`/`total` from
  the resolved `{ items, total, page, pageSize }` body on success.
- **inbox-stale-response-ignored**: if the query or reload counter changes again — or the
  component unmounts — before an in-flight `GET {API_BASE}` request resolves, `useInbox` MUST NOT
  apply that request's resolution (success or failure) to `items`, `total`, `loading`, or `error`.
- **inbox-refetch-on-wake**: `useInbox` MUST re-issue its fetch on every wake delivered through
  `subscribeToNotifications`, in addition to the query/nonce-driven refetch above.
- **inbox-mutation-then-broadcast**: `markRead`, `markUnread`, `archive`, `trash`, and `readAll`
  MUST each `POST` to a distinct path built from `{API_BASE}` (`/<id>/read`, `/<id>/unread`,
  `/<id>/archive`, `/<id>/trash`, and `/read-all` respectively, with `id` percent-encoded via
  `encodeURIComponent`) and, on success, MUST call `emitLocalChange` exactly once — refetching both
  this hook's own list and every other mounted messaging hook, including `useUnreadCount`.
- **inbox-mutation-failure-leaves-list-untouched**: if a mutation's `POST` rejects, `useInbox` MUST
  NOT call `emitLocalChange` and MUST NOT modify `items` itself; the affected row remains exactly
  as it was before the call, per the source's own comment that this is "correct rather than
  optimistic."

**DM conversation list (`useDmConversations`)**

- **dm-inbox-initial-window**: on mount, `useDmConversations` MUST request `GET {DM_BASE}
  ?pageSize=100` (`DM_PAGE_SIZE`).
- **dm-inbox-window-growth-and-ceiling**: each call to `loadMore` MUST increase the requested
  window by `DM_PAGE_SIZE` (100) up to a ceiling of `DM_MAX_LIMIT` (500), via
  `Math.min(n + 100, 500)`; `loadMore` MUST NOT issue an offset-based follow-up request — the next
  render's effect re-requests the single, larger window from `{DM_BASE}?pageSize=<newLimit>`.
- **dm-inbox-presence-merge**: for every chat row returned, `useDmConversations` MUST merge that
  row's `online`/`lastSeenAt` from a single `GET {PRESENCE_BASE}` call keyed by
  `chat.otherUserId`, falling back to `online: false, lastSeenAt: null` when no presence view is
  returned for that user id.
- **dm-inbox-presence-query-encoding**: the presence fetch MUST request `GET {PRESENCE_BASE}
  ?userIds=<enc(ids)>` where `ids` is the deduplicated, falsy-filtered list of `otherUserId`
  values joined with `,` and the ENTIRE joined string is percent-encoded as one unit — a comma
  inside the joined list is itself percent-escaped, not left literal.
- **dm-inbox-presence-failure-is-silent**: if the presence fetch rejects, `useDmConversations`
  MUST proceed with every chat's `online`/`lastSeenAt` defaulted to `false`/`null` rather than
  failing the whole load or surfacing an `error`.
- **dm-inbox-stale-response-discarded**: `useDmConversations` MUST track a generation counter,
  incremented on every new load and on effect cleanup, and MUST discard (apply neither the success
  nor the failure branch of) any load whose generation is no longer the current one when it
  settles.
- **dm-inbox-refetch-on-wake**: `useDmConversations` MUST re-request its current window on every
  wake delivered through `subscribeToNotifications`.
- **dm-inbox-load-failure-keeps-last-good-list**: a rejected load MUST set `error` to a message but
  MUST NOT clear or replace the previously loaded `chats` array.
- **dm-inbox-has-more-computation**: `hasMore` MUST be `true` only when the loaded `chats.length`
  is less than the server-reported `total` AND the current window `limit` is still below
  `DM_MAX_LIMIT`; reaching the 500-row ceiling MUST report `hasMore: false` even if `total` is
  larger, since the client will not request past that ceiling.

**A single DM thread (`useDmThread`)**

- **dm-thread-null-chatid-clears-state**: when `chatId` is `null` or the empty string,
  `useDmThread` MUST set `messages` to `[]` and `loading` to `false`, and MUST NOT issue any
  request or open any connection.
- **dm-thread-history-load-and-sort**: for a non-empty `chatId`, `useDmThread` MUST request `GET
  {DM_BASE}/<enc(chatId)>/messages?pageSize=200` and MUST merge the returned `items`, sorted
  ascending by `seq`, into `messages`.
- **dm-thread-message-merge-dedupe**: every point where a message enters `messages` — the initial
  history load, the SSE stream, and the poll fallback — MUST go through `mergeMessage`, which MUST
  discard an incoming message whose `id` already exists in the list and otherwise MUST append it
  and re-sort the full list ascending by `seq`.
- **dm-thread-sse-cursor-from-last-loaded-seq**: after the history load resolves, `useDmThread`
  MUST open a stream at `GET {DM_BASE}/<enc(chatId)>/stream?after=<afterSeq>`, where `afterSeq` is
  the `seq` of the last (highest) loaded message, or `0` when no messages were loaded.
- **dm-thread-malformed-frame-ignored**: an SSE `message` event whose `data` fails `JSON.parse`
  MUST be dropped without updating `messages` and MUST NOT throw out of the event handler.
- **dm-thread-teardown-on-change-or-unmount**: on `chatId` change or unmount, `useDmThread` MUST
  set its internal `cancelled` flag and MUST close the stream/poll handle returned by
  `connectSse`, so neither the pending history fetch nor the connection can update state
  afterward.
- **dm-thread-poll-fallback-refetch**: the poll fallback action (`connectSse`'s `onPoll`) MUST
  re-request the same `GET {DM_BASE}/<enc(chatId)>/messages?pageSize=200` window and merge its
  `items` the same way as the initial load; a failed poll refetch MUST be swallowed, leaving
  `messages` unchanged.
- **dm-thread-send-noop-on-empty-or-missing-chat**: `send(body)` MUST trim `body` and, when
  `chatId` is falsy or the trimmed text is the empty string, MUST return without issuing any
  request.
- **dm-thread-send-client-message-id**: `send` MUST generate a `clientMessageId` via
  `crypto.randomUUID()` when `crypto` and `randomUUID` are both available, and MUST otherwise
  generate one from the current timestamp and a random suffix, before `POST`-ing `{ body, clientMessageId }`
  to `{DM_BASE}/<enc(chatId)>/messages`.
- **dm-thread-send-merges-and-broadcasts**: on a successful `send`, `useDmThread` MUST merge the
  server-returned message into `messages` via `mergeMessage` and MUST call `emitLocalChange`
  exactly once.
- **dm-thread-send-propagates-failure**: a rejected `send` POST MUST propagate the rejection to
  the caller unchanged; `send` MUST NOT catch or convert it.
- **dm-thread-mark-read-request-shape**: `markRead` MUST return without a request when `chatId` is
  falsy, and otherwise MUST `POST` a literal `{}` JSON body to `{DM_BASE}/<enc(chatId)>/read` and
  then call `emitLocalChange` exactly once.
- **dm-thread-ownership-comparison**: `isOwn(msg)` MUST return `true` only when `callerId` (the
  signed-in user's `id`, from `useAuth`) is non-null AND strictly equals `msg.senderUserId`; it
  MUST return `false` whenever `callerId` is `null`, regardless of `msg.senderUserId`.

**Starting a DM (`startDm`)**

- **start-dm-request-shape**: `startDm(recipientId)` MUST `POST { recipientId }` to `{DM_BASE}`
  and, on a successful response, MUST resolve to `{ chatId: res.id }`.
- **start-dm-forbidden-mapping**: `startDm` MUST catch an `AuthHttpError` with `status === 403` and
  resolve to `{ forbidden: true }` instead of rejecting.
- **start-dm-other-errors-propagate**: any error other than a `403` `AuthHttpError` (including any
  other HTTP status or a network-level failure) MUST propagate out of `startDm` as a rejection.

### Security

This is a security-relevant recipe: both files transmit a bearer session credential, and the
live-stream path carries that credential in a URL rather than a header.

- **auth-delegated-to-shared-client**: every `authedJson`/`authedRequest` call in both files MUST
  go through `@agentic-toolkit/auth/client`, which attaches `Authorization: Bearer <token>` from
  `readAccessToken()`; neither `use-dms.ts` nor `use-notifications.ts` reads, stores, or attaches a
  token itself for its plain HTTP calls.
- **session-refresh-waterfall**: a `401` on any plain HTTP call in either file MUST trigger exactly
  one token refresh and one retried request, inherited unconditionally from `authedFetch`; a
  second `401` on the retry MUST propagate as a thrown `AuthHttpError` with `status: 401`.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause
  the call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body
  supplies one, a machine-readable `code`.
- **sse-token-rides-the-query-string**: both the DM thread stream (`.../stream?after=...`) and the
  shared notifications stream (`/api/notifications/stream`) MUST be opened by `connectSse`, which
  appends the live access token as an `access_token` query parameter, because `EventSource` cannot
  set a request header; both files' own top-of-file comments state this explicitly as a deliberate
  deviation from the header-based scheme every other call in this recipe uses.
- **sse-token-read-fresh-per-attempt**: `connectSse` MUST call `readAccessToken()` on every
  connection attempt (the initial open and each retry after a hard close), not once at hook-mount
  time, so a token refreshed by the poll fallback's own `authedJson` calls is picked up on the next
  reconnect attempt.
- **no-stream-without-a-token**: `connectSse` MUST NOT construct an `EventSource` when
  `readAccessToken()` returns a falsy value; it MUST fall back to the interval-and-focus poll
  instead, which keeps retrying `openSse` on each tick.
- **poll-fallback-uses-the-bearer-header**: unlike the SSE path, the poll fallback's own requests
  (`authedJson` calls inside `use-dms.ts`'s `refetchThread` and `use-notifications.ts`'s
  `notifyAll`-driven refetches) MUST carry the token via the `Authorization` header through
  `authedFetch`, not in the URL.
- **presence-visibility-is-server-gated**: `PresenceView` is documented as reporting `{ online:
  false, lastSeenAt: null }` for a hidden or absent target; neither file performs any visibility
  check of its own — the guarantee that "real state never leaks" is enforced entirely by the
  `/api/presence` backend, per the `PresenceView` doc comment.

## Appearance

Not applicable — this is the DM and notification data-and-transport layer, not a visual component.

## States

Not applicable — this is the DM and notification data-and-transport layer, not a visual component;
any loading/error/empty visual state is owned by the presentation components that consume these
hooks.

## Accessibility

Not applicable — this is the DM and notification data-and-transport layer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-hooks-001 | shared-stream-refcounting | Two components mount, each calling `subscribeToNotifications` | Only one `EventSource` (or poll timer) is created; unsubscribing one leaves the shared stream open — no dedicated test; derived directly from source |
| hub-domain-hooks-002 | shared-stream-refcounting | The last subscriber unsubscribes | The shared stream/poll handle is closed and `sharedStream` is nulled, so the next `subscribeToNotifications` call reopens it — no dedicated test; derived directly from source |
| hub-domain-hooks-003 | local-change-broadcast | Two hooks call `subscribeToNotifications`; a third piece of code calls `emitLocalChange()` | Both subscribed listeners are invoked with no arguments — no dedicated test; derived directly from source |
| hub-domain-hooks-004 | unread-count-fetch-on-mount-and-wake | `useUnreadCount()` mounts against a stub returning `{ count: 4 }` | `count` resolves to `4` after the initial fetch — no dedicated test; derived directly from source |
| hub-domain-hooks-005 | unread-count-preserved-on-failure | `count` is `4`; the next `GET /unread-count` rejects | `count` remains `4`; no reset to `0` — no dedicated test; derived directly from source |
| hub-domain-hooks-006 | inbox-query-serialization | `buildInboxQuery({ categories: ["a", "b"], page: 2 })` | Serializes to `page=2&category=a&category=b` — no dedicated test; derived directly from source |
| hub-domain-hooks-007 | inbox-status-left-to-backend-default | `buildInboxQuery({})` | Serializes to the empty string; no `status` key present — no dedicated test; derived directly from source |
| hub-domain-hooks-008 | inbox-stale-response-ignored | `useInbox` is mounted; `params` changes before the first `GET` resolves | The first request's resolution (success or failure) is never applied to `items`/`total`/`error` — no dedicated test; derived directly from source |
| hub-domain-hooks-009 | inbox-mutation-then-broadcast | `markRead("n1")` resolves | `POST /api/notifications/n1/read` is sent, then `emitLocalChange` fires exactly once — no dedicated test; derived directly from source |
| hub-domain-hooks-010 | inbox-mutation-failure-leaves-list-untouched | `archive("n1")`'s `POST` rejects | `emitLocalChange` is not called; `items` is unchanged — no dedicated test; derived directly from source |
| hub-domain-hooks-011 | dm-inbox-initial-window | `useDmConversations()` mounts | `GET /api/chat/dms?pageSize=100` is the first request — no dedicated test; derived directly from source |
| hub-domain-hooks-012 | dm-inbox-window-growth-and-ceiling | `loadMore()` is called four times from `limit = 100` | Requested `pageSize` grows `200, 300, 400, 500` and stays at `500` on a fifth call — no dedicated test; derived directly from source |
| hub-domain-hooks-013 | dm-inbox-presence-merge | A chat row for `otherUserId: "u1"`; presence response has no `u1` entry | That row's `online` is `false` and `lastSeenAt` is `null` — no dedicated test; derived directly from source |
| hub-domain-hooks-014 | dm-inbox-presence-query-encoding | `otherUserId`s `["a,b", "c"]` | The presence request's `userIds` query value equals `encodeURIComponent("a,b,c")`, with the internal comma escaped — no dedicated test; derived directly from source |
| hub-domain-hooks-015 | dm-inbox-presence-failure-is-silent | The presence `GET` rejects while the chats `GET` succeeds | `chats` still resolves, every row defaulted to `online: false, lastSeenAt: null`; no `error` is set for this reason — no dedicated test; derived directly from source |
| hub-domain-hooks-016 | dm-inbox-stale-response-discarded | Two loads are in flight; the older one resolves after the newer one | The older resolution is discarded; `chats` reflects only the newer response — no dedicated test; derived directly from source |
| hub-domain-hooks-017 | dm-inbox-load-failure-keeps-last-good-list | `chats` already holds two rows; the next `GET` rejects | `chats` still holds the same two rows; `error` is set to a message — no dedicated test; derived directly from source |
| hub-domain-hooks-018 | dm-inbox-has-more-computation | `chats.length = 500`, `total = 800`, `limit = 500` | `hasMore` is `false` (ceiling reached) despite `total` exceeding `chats.length` — no dedicated test; derived directly from source |
| hub-domain-hooks-019 | dm-thread-null-chatid-clears-state | `useDmThread(null)` | `messages` is `[]`, `loading` is `false`; no request is issued — no dedicated test; derived directly from source |
| hub-domain-hooks-020 | dm-thread-history-load-and-sort | History response `items` in seq order `[3, 1, 2]` | `messages` resolves sorted ascending as seq `[1, 2, 3]` — no dedicated test; derived directly from source |
| hub-domain-hooks-021 | dm-thread-message-merge-dedupe | An SSE event delivers a message whose `id` matches one already in `messages` | `messages` length is unchanged; no duplicate row is added — no dedicated test; derived directly from source |
| hub-domain-hooks-022 | dm-thread-sse-cursor-from-last-loaded-seq | History load's last item has `seq: 42` | The stream URL is opened with `after=42` — no dedicated test; derived directly from source |
| hub-domain-hooks-023 | dm-thread-malformed-frame-ignored | An SSE `message` event whose `data` is not valid JSON | `messages` is unchanged; no exception escapes the handler — no dedicated test; derived directly from source |
| hub-domain-hooks-024 | dm-thread-teardown-on-change-or-unmount | `chatId` changes from `"c1"` to `"c2"` while `"c1"`'s history fetch is still pending | The `"c1"` fetch's resolution, once it arrives, is ignored (`cancelled` was set); `"c1"`'s stream is closed — no dedicated test; derived directly from source |
| hub-domain-hooks-025 | dm-thread-send-noop-on-empty-or-missing-chat | `send("   ")` on an open thread | No `POST` is issued; the returned promise resolves with no side effect — no dedicated test; derived directly from source |
| hub-domain-hooks-026 | dm-thread-send-client-message-id | `send("hi")` in an environment with no `crypto.randomUUID` | The POST body's `clientMessageId` matches the `` `${Date.now()}-${...}` `` fallback shape, not a UUID — no dedicated test; derived directly from source |
| hub-domain-hooks-027 | dm-thread-mark-read-request-shape | `markRead()` on chat `"c1"` | `POST /api/chat/dms/c1/read` is sent with body `{}`; `emitLocalChange` fires once — no dedicated test; derived directly from source |
| hub-domain-hooks-028 | dm-thread-ownership-comparison | `callerId` is `null`; `msg.senderUserId` is `""` | `isOwn(msg)` returns `false` — no dedicated test; derived directly from source |
| hub-domain-hooks-029 | start-dm-forbidden-mapping | `POST /api/chat/dms` responds `403` | `startDm` resolves to `{ forbidden: true }`, not a rejection — no dedicated test; derived directly from source |
| hub-domain-hooks-030 | start-dm-other-errors-propagate | `POST /api/chat/dms` responds `500` | `startDm`'s returned promise rejects with `AuthHttpError status: 500` — no dedicated test; derived directly from source |
| hub-domain-hooks-031 | session-refresh-waterfall | Any plain HTTP call in either file first responds `401`; refresh succeeds | Exactly one retried request is sent with the new token; a `401` on that retry throws `AuthHttpError status: 401` — traced to `authedFetch` in `auth/src/client.ts`, exercised only indirectly through these hooks |
| hub-domain-hooks-032 | sse-token-rides-the-query-string | `connectSse` opens the DM thread stream with a current access token `"tok"` | The constructed `EventSource` URL ends in `access_token=tok` — no dedicated test; derived directly from `stream/index.ts` |
| hub-domain-hooks-033 | thread-message-isolation-on-chatid-switch | `send("hello")` is called for `chatId = "c1"`; before the POST resolves, the hook's `chatId` prop changes to `"c2"` | See the `thread-message-isolation-on-chatid-switch` edge case below — the resolved message from `"c1"`'s `send` call merges into whatever `messages` array is current when it settles, with no chatId-generation guard preventing it from landing under `"c2"` |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DM_BASE` | module constant, `"/api/chat/dms"` | fixed | Not injectable; every DM request path is built as `${DM_BASE}/...`. |
| `PRESENCE_BASE` | module constant, `"/api/presence"` | fixed | Not injectable; the presence fetch's only base path. |
| `API_BASE` (`use-notifications.ts`) | module constant, `"/api/notifications"` | fixed | Not injectable; every notification request path is built from it. |
| `DM_PAGE_SIZE` | module constant, `100` | fixed | The initial DM conversation window and the increment `loadMore` grows it by. |
| `DM_MAX_LIMIT` | module constant, `500` | fixed | The DM conversation window's hard ceiling; `loadMore` clamps to it. |
| `chatId` (`useDmThread`) | `string \| null` (caller parameter) | none — required | The DM chat to load and stream; `null`/empty clears state and issues no request. |
| `recipientId` (`startDm`) | `string` (caller parameter) | none — required | The target user id; sent verbatim in the `POST` body. |
| `params` (`useInbox`) | `InboxParams` (`status?`, `categories?`, `read?`, `page?`, `pageSize?`) | `{}` | Serialized by `buildInboxQuery`; an omitted field is left out of the query string entirely, not defaulted client-side. |
| `pollIntervalMs` (`connectSse`, inherited) | number (ms) | `DEFAULT_SSE_POLL_INTERVAL_MS` (20 000) | Neither `use-dms.ts` nor `use-notifications.ts` passes its own value to `connectSse`; both use the shared transport's fixed default. |

## Deep Linking

Not applicable: neither `use-dms.ts` nor `use-notifications.ts` registers a URL scheme, route, or
navigation target of its own; both are data-and-transport hooks consumed by a separate
presentation layer that owns any deep-linking concern.

## Localization

Neither file reads from or writes to a localization catalog; every hardcoded string below is a
plain English literal authored directly in these two files, stated here as fact rather than as a
gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Failed to load conversations` | `useDmConversations`' fallback `error` message when the rejected load's `Error` has no `.message` |
| — | `Failed to load messages` | `useDmThread`'s fallback `error` message when the history load rejects without an `Error` instance |
| — | `Failed to load notifications` | `useInbox`'s fallback `error` message when the rejected fetch's error has no `.message` |

Every other error message a caller can observe from either file (an `AuthHttpError`'s message, or
one produced by `authedJson`'s own `204`-body check) originates outside these two files and is not
authored here.

## Accessibility Options

Not applicable: `use-dms.ts` and `use-notifications.ts` render no UI and respond to none of Reduce
Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: neither file reads a feature-flag key or performs any flag-gated branch of any
kind.

## Analytics

Not applicable: neither file contains an analytics or event-emission call.

## Privacy

- **Data collected**: this recipe does not originate personal data of its own; it reads and writes
  direct-message content (`DmMessage.body`), notification records (`Notification`, including an
  arbitrary `data: Record<string, unknown>` payload and an optional `actorId`), and presence facts
  (`online`, `lastSeenAt`) for the ids the caller supplies.
- **Storage**: none held by these two files beyond in-memory React state for the lifetime of the
  mounted component; nothing is written to `localStorage`, a database, or a file by either file.
- **Transmission**: yes, on every call. Plain HTTP calls carry the bearer credential in the
  `Authorization` header via `@agentic-toolkit/auth/client`; the two SSE connections instead carry
  that same credential as an `access_token` URL query parameter, per `sse-token-rides-the-query-string`
  — a distinct exposure surface (URLs can reach server access logs, browser history, and
  intermediate proxies in ways a header does not) that this recipe records as a documented fact of
  the source, not a change it makes.
- **Retention**: none retained by these files after the response or event they produced is applied
  to hook state; whatever the backend itself retains is outside the scope of these two files.

## Logging

Not applicable: neither `use-dms.ts` nor `use-notifications.ts` contains a logging call of any
kind — every caught error in both files (the presence fetch, the poll-fallback refetches, a
malformed SSE frame) is discarded silently, with no `console` call or other diagnostic output
anywhere in either file.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/messaging/src/hooks/use-dms.ts` and
  `use-notifications.ts` hold the hooks; both build on `authedJson`/`authedRequest`/`AuthHttpError`
  from `@agentic-toolkit/auth/client`, `useAuth` from `@agentic-toolkit/auth`, and the shared
  `connectSse`/`SseHandle` from `@agentic-toolkit/data/stream` — the one live-connection transport
  every real-time consumer in the web app now shares, per that package's own top-of-file comment.
- **SwiftUI**: model `DmMessage`, `DmChatSummary`, `PresenceView`, `DmConversation`, and
  `Notification` as `Codable, Hashable, Sendable` structs; port each hook to an `@Observable` (or
  `ObservableObject`) type whose `async` methods mirror `send`/`markRead`/`loadMore`/mutation calls,
  backed by `URLSession` for plain requests and `URLSession.bytes(for:)` (or a small SSE-framing
  helper over it) for the two live streams, since Foundation has no built-in `EventSource`
  equivalent; the token-in-query quirk MUST be preserved deliberately if parity with the web client
  is the goal, or flagged as a divergence if the port instead sends it as a header-equivalent the
  platform's stream transport supports.
- **AppKit / UIKit**: no direct UI dependency exists in either source file; a macOS/iOS messaging
  surface would consume the ported hooks through an injected data-source/view-model object exposing
  the same fields (`chats`, `messages`, `loading`, `error`, `hasMore`, …) rather than calling
  `URLSession` from a view controller directly.
- **Compose**: model the wire rows as `@Serializable` Kotlin `data class`es and each hook as a
  `ViewModel` exposing `StateFlow`s, backed by Ktor's or OkHttp's SSE support for the two live
  streams and coroutine `suspend fun`s for the plain calls; Ktor's client-side SSE plugin removes
  the need to hand-roll a poll fallback, though preserving this recipe's self-healing behavior
  exactly would still require one.
- **WinUI 3**: a .NET port would model the wire rows as `record`s attributed for
  `System.Text.Json`, and each hook as a class exposing `Task`-returning methods built on
  `HttpClient`, attaching `Authorization: Bearer <token>` the way `authedFetch` does and refreshing
  on a `401` the same one-retry way; `HttpClient` has no native SSE client, so the two live streams
  would need a package such as `LaunchDarkly.EventSource` or a hand-rolled reader over a streamed
  `HttpResponseMessage`, with an `ObservableCollection`/`INotifyPropertyChanged`-based
  view-model layer standing in for the `useState` calls this recipe's hooks use to hold `messages`
  and `chats` — this is the platform with the least existing prior art in this repo for both the
  refresh-and-retry contract and the token-in-query stream pattern, so a WinUI 3 port needs to
  build the equivalent of both `authedFetch` and `connectSse`, not just these two hooks.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/messaging/src/hooks/` |

## Design Decisions

**Decision**: the shared wake channel opens exactly one `/api/notifications/stream` connection,
refcounted across every mounted messaging hook, rather than each hook opening its own.
**Rationale**: the source's own comment in `use-notifications.ts` states this directly — a page
with the header bell, the DM list, and an open inbox previously held two to three duplicate wake
connections before this refactor; refcounting on a module-level `Set` keeps one connection alive
exactly as long as at least one hook needs it.
**Approved**: pending

**Decision**: the DM conversation list grows a single window (`loadMore` widening one `pageSize`
request) instead of accumulating separate offset pages.
**Rationale**: the source's own comment explains this keeps each fetch "one consistent snapshot" —
accumulating offset pages independently would let a chat that reorders between page fetches
(`updated_at`-sorted) produce a duplicate or dropped row across the page boundary.
**Approved**: pending

**Decision**: the presence fetch failing is treated as "assume everyone offline" rather than
failing the whole conversation-list load.
**Rationale**: the source's own comment on `fetchPresenceMap` calls this out explicitly as
best-effort, because a transient presence-service blip must not blank the entire DM inbox; this
recipe records that asymmetry (the chats list is essential, presence is decorative) as intentional.
**Approved**: pending

**Decision**: `send`'s access token for the DM thread's live stream, and the shared notifications
stream's token, both ride the URL query string instead of a header, unlike every other request in
this recipe.
**Rationale**: this is `EventSource`'s own platform limitation — it cannot set request headers —
and both source files say so directly; this recipe documents the resulting exposure difference
under Security and Privacy rather than treating it as an oversight to silently correct.
**Approved**: pending

**Decision**: `send` and `markRead` carry no chatId-generation guard, while the thread's own history
load and `useDmConversations`' window load both do.
**Rationale**: recorded as observed source behavior, not smoothed over — see the
`thread-message-isolation-on-chatid-switch` marker; a port MUST decide deliberately whether to add
a matching guard to these two callbacks or to preserve the current behavior, since the current
checkout does not settle which is intended.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | partial | Security |
| [reconnection-strategy](agenticdevelopercookbook://compliance/access-patterns#reconnection-strategy) | partial | Access Patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | partial | Access Patterns |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | partial | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | failed | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`separation-of-concerns` passes: both files contain zero JSX or DOM code — they export hooks and
plain functions consumed by a separate presentation layer. `unit-test-coverage` fails: this
checkout has no test file next to either `use-dms.ts` or `use-notifications.ts`, and the one
messaging-adjacent test found (`MessagingPane.test.tsx`, in a different package) exercises a
different component and neither imports nor mocks either file. `explicit-error-handling` is
`partial`: every plain HTTP failure either throws (`AuthHttpError`/`Error`) or lands in an exposed
`error` field, but several catches (`fetchPresenceMap`, the SSE malformed-frame handler, and both
poll-fallback refetches) discard the error with no signal at all beyond a silent fallback.
`server-side-authorization` passes: `startDm`'s `403`-to-`forbidden` mapping and every route's
participant-scoping are enforced entirely by the backend per the source's own "Backend contract"
comments; neither file performs a client-side permission check. `secure-transport` is `partial`:
neither file controls TLS itself (deployment-level, unverifiable from this checkout), and the
SSE-token-in-query-string design is a documented deviation from the header-based scheme the rest of
this recipe uses, per `sse-token-rides-the-query-string`. `reconnection-strategy` is `partial`:
`connectSse` defines explicit, self-healing reconnection (live retry plus interval-and-focus poll),
but with no exponential backoff or jitter — a fixed poll interval only. `pagination-support` is
`partial`: the DM conversation list and the notification inbox both support pagination
(`pageSize`/`page`, and the DM list's growing-window `loadMore`), but the DM thread exposes no
further-back paging for message history. `offline-behavior` is `partial`: the poll fallback
degrades gracefully across a connectivity blip, but neither file checks `navigator.onLine` or
queues a `send`/mutation issued while offline. `error-response-handling` passes: every documented
status this recipe's own backend-contract comments describe (`401`, `403`, `204` where relevant) is
handled explicitly, and every other non-2xx status surfaces as a typed `AuthHttpError`.
`retry-with-backoff` fails: no call in either file retries a failure with backoff of any kind
beyond the single inherited `401` refresh-and-retry. `timeout-configuration` fails: no call sets a
deadline or `AbortSignal`. `idempotent-operations` passes: `mergeMessage`'s id-based dedupe makes a
duplicate delivery (the SSE stream and a `send`'s own POST response both resolving the same row) a
no-op, and `send` generates a `clientMessageId` intended for server-side idempotency per the
source's own comment. `graceful-degradation` passes: a dead SSE stream downgrades to polling, a
failed presence fetch downgrades to "assume offline," and a failed list refresh keeps the last good
data — none of the three crashes the hook or blanks the UI.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
