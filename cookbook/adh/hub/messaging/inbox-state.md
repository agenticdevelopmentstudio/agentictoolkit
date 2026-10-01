---
id: 8da824cf-e518-4cee-b897-3a8e17f9c32a
title: Inbox State
domain: agentictoolkit://cookbook/adh/hub/messaging/inbox-state
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'State and transport logic for the direct-message inbox/thread and the notification
  list: a live-update channel with a shared poll fallback, pagination, and message dedupe.'
platforms:
- typescript
- web
tags:
- hub
- messaging
- notifications
- direct-messages
- real-time
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

# Inbox State

## Overview

This is the state and transport logic for the direct-message inbox, a single direct-message
thread, starting a direct message, the unread-count badge, and the notification inbox list. The
DM logic and the notification logic carry the same shape — state backed by a shared authenticated
request client, kept live over a shared live-connection transport, which authenticates over a
token carried by the connection itself plus a self-healing interval-and-window-focus poll
fallback. The notification logic additionally owns ONE process-wide "wake" channel — a single
refcounted live connection to the notification stream endpoint and a broadcast/subscribe pair —
that the DM logic reuses rather than opening its own parallel signal. It is headless **logic**
with no visual surface, so this recipe marks Appearance, States, and Accessibility not applicable
and carries the entire runtime contract in Behavioral Requirements, per the non-UI component
guidance this recipe was authored under.

## Behavioral Requirements

**Shared wake channel**

- **shared-stream-refcounting**: subscribing to the wake channel MUST open the single shared live
  connection to the notification stream endpoint only on the transition from zero to one
  subscriber, and unsubscribing MUST close that connection only on the transition from one
  subscriber back to zero; a second, third, or later subscriber MUST NOT open an additional
  connection.
- **local-change-broadcast**: broadcasting a wake signal MUST invoke every function currently in
  the subscriber set, synchronously and with no arguments.
- **wake-signal-carries-no-payload**: the shared connection's event and poll handling MUST both
  reduce to the same wake broadcast; a `notification` server event's payload MUST NOT be parsed,
  inspected, or passed to subscribers — receipt of the event is the entire signal; the wake
  payload itself is ignored.

**Unread count**

- **unread-count-fetch-on-mount-and-wake**: the unread-count state MUST issue `GET
  {API_BASE}/unread-count` once on mount and once on every subsequent wake delivered through the
  wake channel, and MUST set `count` to the resolved `count` field each time.
- **unread-count-preserved-on-failure**: a rejected `GET {API_BASE}/unread-count` MUST leave the
  previously set `count` unchanged; the unread-count state MUST NOT reset `count` to `0` or to any
  other value on a failed fetch.

**Notification inbox**

- **inbox-query-serialization**: building the inbox query string MUST set `status`, `read`,
  `page`, and `pageSize` query parameters only when the corresponding query field is provided,
  and MUST append one repeated `category=<c>` parameter per entry of the categories list, in that
  list's order; a query with every field omitted MUST serialize to the empty string.
- **inbox-status-left-to-backend-default**: when the `status` query field is not provided,
  building the inbox query string MUST omit the `status` parameter entirely rather than
  substituting a client-side default; this "defaults to the caller's inbox" on the backend, not
  in this logic.
- **inbox-fetch-per-query-and-nonce**: the notification inbox state MUST re-issue `GET {API_BASE}`
  (with the built query string appended when non-empty) whenever the built query string changes or
  a refetch or a mutation increments the internal reload counter, and MUST set `items`/`total`
  from the resolved `{ items, total, page, pageSize }` body on success.
- **inbox-stale-response-ignored**: if the query or reload counter changes again — or the state is
  torn down — before an in-flight `GET {API_BASE}` request resolves, the notification inbox state
  MUST NOT apply that request's resolution (success or failure) to `items`, `total`, `loading`, or
  `error`.
- **inbox-refetch-on-wake**: the notification inbox state MUST re-issue its fetch on every wake
  delivered through the wake channel, in addition to the query/counter-driven refetch above.
- **inbox-mutation-then-broadcast**: the mark-read, mark-unread, archive, trash, and read-all
  actions MUST each `POST` to a distinct path built from `{API_BASE}` (`/<id>/read`, `/<id>/unread`,
  `/<id>/archive`, `/<id>/trash`, and `/read-all` respectively, with `id` percent-encoded) and, on
  success, MUST broadcast a wake signal exactly once — refetching both this state's own list and
  every other mounted messaging state, including the unread count.
- **inbox-mutation-failure-leaves-list-untouched**: if a mutation's `POST` rejects, the
  notification inbox state MUST NOT broadcast a wake signal and MUST NOT modify `items` itself;
  the affected row remains exactly as it was before the call — correct rather than optimistic.

**DM conversation list**

- **dm-inbox-initial-window**: on mount, the DM conversation list state MUST request `GET
  {DM_BASE}?pageSize=100` (`DM_PAGE_SIZE`).
- **dm-inbox-window-growth-and-ceiling**: each call to the load-more action MUST increase the
  requested window by `DM_PAGE_SIZE` (100) up to a ceiling of `DM_MAX_LIMIT` (500) — the new window
  size is `min(current + 100, 500)`; the load-more action MUST NOT issue an offset-based follow-up
  request — the next refresh re-requests the single, larger window from
  `{DM_BASE}?pageSize=<newLimit>`.
- **dm-inbox-presence-merge**: for every chat row returned, the DM conversation list state MUST
  merge that row's `online`/`lastSeenAt` from a single `GET {PRESENCE_BASE}` call keyed by
  `chat.otherUserId`, falling back to `online: false, lastSeenAt: null` when no presence record is
  returned for that user id.
- **dm-inbox-presence-query-encoding**: the presence fetch MUST request `GET {PRESENCE_BASE}
  ?userIds=<enc(ids)>` where `ids` is the deduplicated, falsy-filtered list of `otherUserId`
  values joined with `,` and the ENTIRE joined string is percent-encoded as one unit — a comma
  inside the joined list is itself percent-escaped, not left literal.
- **dm-inbox-presence-failure-is-silent**: if the presence fetch rejects, the DM conversation list
  state MUST proceed with every chat's `online`/`lastSeenAt` defaulted to `false`/`null` rather
  than failing the whole load or surfacing an `error`.
- **dm-inbox-stale-response-discarded**: the DM conversation list state MUST track a generation
  counter, incremented on every new load and on teardown, and MUST discard (apply neither the
  success nor the failure branch of) any load whose generation is no longer the current one when
  it settles.
- **dm-inbox-refetch-on-wake**: the DM conversation list state MUST re-request its current window
  on every wake delivered through the wake channel.
- **dm-inbox-load-failure-keeps-last-good-list**: a rejected load MUST set `error` to a message but
  MUST NOT clear or replace the previously loaded `chats` array.
- **dm-inbox-has-more-computation**: `hasMore` MUST be `true` only when the loaded `chats.length`
  is less than the server-reported `total` AND the current window `limit` is still below
  `DM_MAX_LIMIT`; reaching the 500-row ceiling MUST report `hasMore: false` even if `total` is
  larger, since no request is made past that ceiling.

**A single DM thread**

- **dm-thread-null-chatid-clears-state**: when `chatId` is `null` or the empty string, the DM
  thread state MUST set `messages` to `[]` and `loading` to `false`, and MUST NOT issue any
  request or open any connection.
- **dm-thread-history-load-and-sort**: for a non-empty `chatId`, the DM thread state MUST request
  `GET {DM_BASE}/<enc(chatId)>/messages?pageSize=200` and MUST merge the returned `items`, sorted
  ascending by `seq`, into `messages`.
- **dm-thread-message-merge-dedupe**: every point where a message enters `messages` — the initial
  history load, the live stream, and the poll fallback — MUST go through the same merge step,
  which MUST discard an incoming message whose `id` already exists in the list and otherwise MUST
  append it and re-sort the full list ascending by `seq`.
- **dm-thread-sse-cursor-from-last-loaded-seq**: after the history load resolves, the DM thread
  state MUST open a live connection at `GET {DM_BASE}/<enc(chatId)>/stream?after=<afterSeq>`,
  where `afterSeq` is the `seq` of the last (highest) loaded message, or `0` when no messages
  were loaded.
- **dm-thread-malformed-frame-ignored**: a live-stream event whose `data` fails to parse as JSON
  MUST be dropped without updating `messages` and MUST NOT throw out of the event handler.
- **dm-thread-teardown-on-change-or-unmount**: on `chatId` change or unmount, the DM thread state
  MUST mark itself cancelled and MUST close the stream/poll handle, so neither the pending history
  fetch nor the connection can update state afterward.
- **dm-thread-poll-fallback-refetch**: the poll fallback MUST re-request the same `GET
  {DM_BASE}/<enc(chatId)>/messages?pageSize=200` window and merge its `items` the same way as the
  initial load; a failed poll refetch MUST be swallowed, leaving `messages` unchanged.
- **dm-thread-send-noop-on-empty-or-missing-chat**: the send action MUST trim the message body
  and, when `chatId` is absent or the trimmed text is the empty string, MUST return without
  issuing any request.
- **dm-thread-send-client-message-id**: the send action MUST generate a `clientMessageId` using a
  random-UUID generator when one is available, and MUST otherwise generate one from the current
  timestamp and a random suffix, before `POST`-ing `{ body, clientMessageId }` to
  `{DM_BASE}/<enc(chatId)>/messages`.
- **dm-thread-send-merges-and-broadcasts**: on a successful send, the DM thread state MUST merge
  the server-returned message into `messages` via the same merge step and MUST broadcast a wake
  signal exactly once.
- **dm-thread-send-propagates-failure**: a rejected send request MUST propagate the rejection to
  the caller unchanged; the send action MUST NOT catch or convert it.
- **dm-thread-mark-read-request-shape**: the mark-read action MUST return without a request when
  `chatId` is absent, and otherwise MUST `POST` a literal `{}` JSON body to
  `{DM_BASE}/<enc(chatId)>/read` and then broadcast a wake signal exactly once.
- **dm-thread-ownership-comparison**: the ownership check MUST return `true` only when the
  caller's id (from the signed-in session) is non-null AND strictly equals `msg.senderUserId`; it
  MUST return `false` whenever the caller's id is `null`, regardless of `msg.senderUserId`.

**Starting a DM**

- **start-dm-request-shape**: the start-DM action MUST `POST { recipientId }` to `{DM_BASE}` and,
  on a successful response, MUST resolve to `{ chatId: res.id }`.
- **start-dm-forbidden-mapping**: the start-DM action MUST catch a typed HTTP error with status
  `403` and resolve to `{ forbidden: true }` instead of rejecting.
- **start-dm-other-errors-propagate**: any error other than a `403` typed HTTP error (including
  any other HTTP status or a network-level failure) MUST propagate out of the start-DM action as
  a rejection.

### Security

This is a security-relevant recipe: it transmits a bearer session credential, and the
live-connection path carries that credential in a URL rather than a header.

- **auth-delegated-to-shared-client**: every plain HTTP call in this recipe MUST go through the
  shared authenticated request client, which attaches `Authorization: Bearer <token>` from the
  stored access token; neither the DM logic nor the notification logic reads, stores, or attaches
  a token itself for its plain HTTP calls.
- **session-refresh-waterfall**: a `401` on any plain HTTP call in this recipe MUST trigger exactly
  one token refresh and one retried request, inherited unconditionally from the shared request
  client; a second `401` on the retry MUST propagate as a thrown typed HTTP error with `status:
  401`.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause
  the call to throw a typed HTTP error, carrying the response's HTTP status and, when the body
  supplies one, a machine-readable `code`.
- **sse-token-rides-the-query-string**: both the DM thread's live connection
  (`.../stream?after=...`) and the shared notification stream (`/api/notifications/stream`) MUST
  be opened with the live access token appended as an `access_token` query parameter, because the
  underlying live-connection transport cannot set a request header; this is a deliberate deviation
  from the header-based scheme every other call in this recipe uses.
- **sse-token-read-fresh-per-attempt**: the live-connection transport MUST read the stored access
  token on every connection attempt (the initial open and each retry after a hard close), not once
  at state-initialization time, so a token refreshed by the poll fallback's own requests is
  picked up on the next reconnect attempt.
- **no-stream-without-a-token**: the live-connection transport MUST NOT open a live connection when
  no access token is available; it MUST fall back to the interval-and-focus poll instead, which
  keeps retrying to open the connection on each tick.
- **poll-fallback-uses-the-bearer-header**: unlike the live-connection path, the poll fallback's
  own requests (the DM thread's refetch and the notification logic's wake-driven refetches) MUST
  carry the token via the `Authorization` header through the shared request client, not in the
  URL.
- **presence-visibility-is-server-gated**: the presence lookup's response is documented as
  reporting `{ online: false, lastSeenAt: null }` for a hidden or absent target; this recipe
  performs no visibility check of its own — the guarantee that real state never leaks is enforced
  entirely by the `/api/presence` backend.

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
| hub-domain-hooks-001 | shared-stream-refcounting | Two independent consumers each subscribe to the wake channel | Only one live connection (or poll timer) is created; unsubscribing one leaves the shared connection open — no dedicated test; derived directly from source |
| hub-domain-hooks-002 | shared-stream-refcounting | The last subscriber unsubscribes | The shared connection/poll handle is closed and the shared reference is cleared, so the next subscription reopens it — no dedicated test; derived directly from source |
| hub-domain-hooks-003 | local-change-broadcast | Two consumers each subscribe to the wake channel; a third piece of code broadcasts a wake signal | Both subscribed listeners are invoked with no arguments — no dedicated test; derived directly from source |
| hub-domain-hooks-004 | unread-count-fetch-on-mount-and-wake | The unread-count state initializes against a stub returning `{ count: 4 }` | `count` resolves to `4` after the initial fetch — no dedicated test; derived directly from source |
| hub-domain-hooks-005 | unread-count-preserved-on-failure | `count` is `4`; the next `GET /unread-count` rejects | `count` remains `4`; no reset to `0` — no dedicated test; derived directly from source |
| hub-domain-hooks-006 | inbox-query-serialization | Building the inbox query with categories `["a", "b"]` and `page: 2` | Serializes to `page=2&category=a&category=b` — no dedicated test; derived directly from source |
| hub-domain-hooks-007 | inbox-status-left-to-backend-default | Building the inbox query with every field omitted | Serializes to the empty string; no `status` key present — no dedicated test; derived directly from source |
| hub-domain-hooks-008 | inbox-stale-response-ignored | The notification inbox state is mounted; the query parameters change before the first `GET` resolves | The first request's resolution (success or failure) is never applied to `items`/`total`/`error` — no dedicated test; derived directly from source |
| hub-domain-hooks-009 | inbox-mutation-then-broadcast | The mark-read action resolves for notification `"n1"` | `POST /api/notifications/n1/read` is sent, then a wake signal fires exactly once — no dedicated test; derived directly from source |
| hub-domain-hooks-010 | inbox-mutation-failure-leaves-list-untouched | The archive action's `POST` rejects for notification `"n1"` | No wake signal is broadcast; `items` is unchanged — no dedicated test; derived directly from source |
| hub-domain-hooks-011 | dm-inbox-initial-window | The DM conversation list state mounts | `GET /api/chat/dms?pageSize=100` is the first request — no dedicated test; derived directly from source |
| hub-domain-hooks-012 | dm-inbox-window-growth-and-ceiling | The load-more action is called four times starting from `limit = 100` | Requested `pageSize` grows `200, 300, 400, 500` and stays at `500` on a fifth call — no dedicated test; derived directly from source |
| hub-domain-hooks-013 | dm-inbox-presence-merge | A chat row for `otherUserId: "u1"`; presence response has no `u1` entry | That row's `online` is `false` and `lastSeenAt` is `null` — no dedicated test; derived directly from source |
| hub-domain-hooks-014 | dm-inbox-presence-query-encoding | `otherUserId`s `["a,b", "c"]` | The presence request's `userIds` query value equals the percent-encoding of `"a,b,c"`, with the internal comma escaped — no dedicated test; derived directly from source |
| hub-domain-hooks-015 | dm-inbox-presence-failure-is-silent | The presence `GET` rejects while the chats `GET` succeeds | `chats` still resolves, every row defaulted to `online: false, lastSeenAt: null`; no `error` is set for this reason — no dedicated test; derived directly from source |
| hub-domain-hooks-016 | dm-inbox-stale-response-discarded | Two loads are in flight; the older one resolves after the newer one | The older resolution is discarded; `chats` reflects only the newer response — no dedicated test; derived directly from source |
| hub-domain-hooks-017 | dm-inbox-load-failure-keeps-last-good-list | `chats` already holds two rows; the next `GET` rejects | `chats` still holds the same two rows; `error` is set to a message — no dedicated test; derived directly from source |
| hub-domain-hooks-018 | dm-inbox-has-more-computation | `chats.length = 500`, `total = 800`, `limit = 500` | `hasMore` is `false` (ceiling reached) despite `total` exceeding `chats.length` — no dedicated test; derived directly from source |
| hub-domain-hooks-019 | dm-thread-null-chatid-clears-state | The DM thread state initializes with `chatId: null` | `messages` is `[]`, `loading` is `false`; no request is issued — no dedicated test; derived directly from source |
| hub-domain-hooks-020 | dm-thread-history-load-and-sort | History response `items` in seq order `[3, 1, 2]` | `messages` resolves sorted ascending as seq `[1, 2, 3]` — no dedicated test; derived directly from source |
| hub-domain-hooks-021 | dm-thread-message-merge-dedupe | A live-stream event delivers a message whose `id` matches one already in `messages` | `messages` length is unchanged; no duplicate row is added — no dedicated test; derived directly from source |
| hub-domain-hooks-022 | dm-thread-sse-cursor-from-last-loaded-seq | History load's last item has `seq: 42` | The live connection is opened with `after=42` — no dedicated test; derived directly from source |
| hub-domain-hooks-023 | dm-thread-malformed-frame-ignored | A live-stream event whose `data` is not valid JSON | `messages` is unchanged; no exception escapes the handler — no dedicated test; derived directly from source |
| hub-domain-hooks-024 | dm-thread-teardown-on-change-or-unmount | `chatId` changes from `"c1"` to `"c2"` while `"c1"`'s history fetch is still pending | The `"c1"` fetch's resolution, once it arrives, is ignored (cancellation was recorded); `"c1"`'s connection is closed — no dedicated test; derived directly from source |
| hub-domain-hooks-025 | dm-thread-send-noop-on-empty-or-missing-chat | The send action is called with `"   "` on an open thread | No `POST` is issued; the returned promise resolves with no side effect — no dedicated test; derived directly from source |
| hub-domain-hooks-026 | dm-thread-send-client-message-id | The send action is called with `"hi"` in an environment with no random-UUID generator available | The POST body's `clientMessageId` matches the timestamp-plus-random-suffix fallback shape, not a UUID — no dedicated test; derived directly from source |
| hub-domain-hooks-027 | dm-thread-mark-read-request-shape | The mark-read action is called on chat `"c1"` | `POST /api/chat/dms/c1/read` is sent with body `{}`; a wake signal fires once — no dedicated test; derived directly from source |
| hub-domain-hooks-028 | dm-thread-ownership-comparison | The caller's id is `null`; `msg.senderUserId` is `""` | The ownership check returns `false` — no dedicated test; derived directly from source |
| hub-domain-hooks-029 | start-dm-forbidden-mapping | `POST /api/chat/dms` responds `403` | The start-DM action resolves to `{ forbidden: true }`, not a rejection — no dedicated test; derived directly from source |
| hub-domain-hooks-030 | start-dm-other-errors-propagate | `POST /api/chat/dms` responds `500` | The start-DM action's returned promise rejects with a typed HTTP error, status `500` — no dedicated test; derived directly from source |
| hub-domain-hooks-031 | session-refresh-waterfall | Any plain HTTP call in this recipe first responds `401`; refresh succeeds | Exactly one retried request is sent with the new token; a `401` on that retry throws a typed HTTP error, status `401` — traced to the shared authenticated request client, exercised only indirectly through this state |
| hub-domain-hooks-032 | sse-token-rides-the-query-string | The live-connection transport opens the DM thread's live connection with a current access token `"tok"` | The constructed live-connection URL ends in `access_token=tok` — no dedicated test; derived directly from the shared live-connection transport |
| hub-domain-hooks-033 | thread-message-isolation-on-chatid-switch | The send action is called for `chatId = "c1"`; before the POST resolves, `chatId` changes to `"c2"` | See the `thread-message-isolation-on-chatid-switch` edge case below — the resolved message from `"c1"`'s send call merges into whatever `messages` array is current when it settles, with no chatId-generation guard preventing it from landing under `"c2"` |

## Edge Cases

- **Null and empty input — `chatId`**: `dm-thread-null-chatid-clears-state` above; a `null` and an
  empty-string `chatId` are treated identically — MUST.
- **Null and empty input — send body**: `dm-thread-send-noop-on-empty-or-missing-chat` above; a
  body that is empty or all whitespace after trimming MUST NOT be sent.
- **Null and empty input — presence ids**: the presence lookup MUST return an empty map without
  issuing any request when its deduplicated, falsy-filtered id list is empty.
- **Null and empty input — inbox categories**: an absent or empty categories list MUST produce
  no `category=` query parameters at all, per `inbox-query-serialization`.
- **Boundary values — DM window ceiling**: `dm-inbox-window-growth-and-ceiling` and
  `dm-inbox-has-more-computation` above; the window never exceeds 500 rows and `hasMore` reports
  `false` once it does, even if more rows exist server-side — 500 is the ceiling the backend also
  caps at.
- **Boundary values — DM thread window**: neither the initial load nor the poll fallback in the
  DM thread state requests more than `pageSize=200`, and the state exposes no further-back
  pagination for thread history (unlike the conversation list's load-more action); a thread with
  more history than the current window simply never surfaces it through this state — a fact, not
  a gap, since no history-paging action exists to fail.
- **Concurrent access — DM conversation list**: `dm-inbox-stale-response-discarded` above; the
  generation counter guarantees only the most recently issued load's result is ever applied.
  Concurrent execution here is single-threaded, so the check-and-increment on the generation
  counter cannot itself race.
- **Concurrent access — DM thread history vs. live stream**: the live connection is opened only
  after the history load resolves, cursored at the last loaded `seq`; the connection is a
  cursor-based replay (`after=<seq>`), not a from-now push, so a message sent by another
  participant during the gap between the history response and the connection opening is still
  delivered once the connection connects.
- **Concurrent access — send during a thread switch**: see the
  `thread-message-isolation-on-chatid-switch` edge case below.
- **Error states — plain HTTP failure**: any plain HTTP call's rejection propagates as a thrown
  typed HTTP error (or a plain error for a non-HTTP failure); each piece of state that exposes an
  `error` field sets it from the error's message, and each direct caller action (send, mark-read,
  the mutations, start-DM) lets the rejection propagate to the caller instead.
- **Error states — malformed live-stream frame**: `dm-thread-malformed-frame-ignored` above.
- **Error states — presence fetch failure**: `dm-inbox-presence-failure-is-silent` above.
- **Offline or disconnected state**: the poll fallback (interval + window-focus) is the only
  reconnection behavior this recipe relies on; nothing here checks a live network-connectivity
  signal or queues a send/mutation for retry once connectivity returns — a send issued while
  offline simply rejects with a network-level failure and is not retried or queued by this recipe.
- **No timeout**: no call in this recipe sets a deadline or cancellation signal; a
  reachable-but-unresponsive backend leaves that call pending indefinitely.
- **No cancellation**: no exposed action (send, mark-read, the mutations, load-more, start-DM)
  accepts a cancellation signal; a caller cannot cancel an in-flight call through this state.
- **No retry beyond the 401 waterfall**: every plain HTTP call issues exactly one request (plus,
  on a `401`, the single inherited refresh-and-retry); nothing in this recipe retries a network
  failure or a non-401 error status, and no exponential backoff exists anywhere in this recipe —
  the poll fallback is a fixed interval, not a backoff schedule.
- **thread-message-isolation-on-chatid-switch**: NEEDS REVIEW: Not implemented in source. If the
  send action (or its returned promise) is still pending when `chatId` changes, the DM thread
  state's `messages` is a single array not partitioned by chat id, and neither the send action nor
  the mark-read action carries a generation guard analogous to the history load's own cancellation
  flag or the DM conversation list's generation counter; the resolved message can merge into
  whatever thread is displayed when it settles rather than the one it was sent for. Evidence that
  would settle it: whether product intent tolerates this cross-thread bleed-through during a fast
  thread switch, or a guard was expected and is simply absent from this checkout.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DM_BASE` | module constant, `"/api/chat/dms"` | fixed | Not injectable; every DM request path is built as `${DM_BASE}/...`. |
| `PRESENCE_BASE` | module constant, `"/api/presence"` | fixed | Not injectable; the presence fetch's only base path. |
| `API_BASE` (notification logic) | module constant, `"/api/notifications"` | fixed | Not injectable; every notification request path is built from it. |
| `DM_PAGE_SIZE` | module constant, `100` | fixed | The initial DM conversation window and the increment the load-more action grows it by. |
| `DM_MAX_LIMIT` | module constant, `500` | fixed | The DM conversation window's hard ceiling; the load-more action clamps to it. |
| `chatId` (DM thread state) | `string \| null` (caller parameter) | none — required | The DM chat to load and stream; `null`/empty clears state and issues no request. |
| `recipientId` (start-DM action) | `string` (caller parameter) | none — required | The target user id; sent verbatim in the `POST` body. |
| query parameters (notification inbox state) | `status?`, `categories?`, `read?`, `page?`, `pageSize?` | `{}` | Serialized into the query string; an omitted field is left out of the query string entirely, not defaulted client-side. |
| `pollIntervalMs` (inherited from the shared live-connection transport) | number (ms) | `20 000` (shared transport default) | Neither the DM logic nor the notification logic passes its own value; both use the shared transport's fixed default. |

## Deep Linking

Not applicable: this logic registers no URL scheme, route, or navigation target of its own; it is
data-and-transport state consumed by a separate presentation layer that owns any deep-linking
concern.

## Localization

This logic reads from and writes to no localization catalog; every hardcoded string below is a
plain English literal authored directly in this recipe's source, stated here as fact rather than
as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Failed to load conversations` | The DM conversation list state's fallback `error` message when the rejected load's error has no message |
| — | `Failed to load messages` | The DM thread state's fallback `error` message when the history load rejects without an error instance |
| — | `Failed to load notifications` | The notification inbox state's fallback `error` message when the rejected fetch's error has no message |

Every other error message a caller can observe from this logic (a typed HTTP error's message, or
one produced by the shared request client's own `204`-body check) originates outside this recipe
and is not authored here.

## Accessibility Options

Not applicable: this logic renders no UI and responds to none of Reduce Motion, Increase Contrast,
or Differentiate Without Color.

## Feature Flags

Not applicable: this logic reads no feature-flag key and performs no flag-gated branch of any
kind.

## Analytics

Not applicable: this logic contains no analytics or event-emission call.

## Privacy

- **Data collected**: this recipe does not originate personal data of its own; it reads and writes
  message content (the message body field), notification records (including an arbitrary
  key-value payload and an optional actor id), and presence facts (`online`, `lastSeenAt`) for the
  ids the caller supplies.
- **Storage**: none held by this logic beyond in-memory state for the lifetime of the mounted
  component; nothing is written to persistent browser storage, a database, or a file by this
  logic.
- **Transmission**: yes, on every call. Plain HTTP calls carry the bearer credential in the
  `Authorization` header via the shared authenticated request client; the two live connections
  instead carry that same credential as an `access_token` URL query parameter, per
  `sse-token-rides-the-query-string` — a distinct exposure surface (URLs can reach server access
  logs, browser history, and intermediate proxies in ways a header does not) that this recipe
  records as a documented fact, not a change it makes.
- **Retention**: none retained by this logic after the response or event it produced is applied to
  state; whatever the backend itself retains is outside the scope of this recipe.

## Logging

Not applicable: this logic contains no logging call of any kind — every caught error here (the
presence fetch, the poll-fallback refetches, a malformed live-stream frame) is discarded silently,
with no diagnostic output anywhere in this recipe.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/messaging/src/hooks/use-dms.ts` and
  `use-notifications.ts` hold the hooks; both build on `authedJson`/`authedRequest`/`AuthHttpError`
  from `@agentic-toolkit/auth/client`, `useAuth` from `@agentic-toolkit/auth`, and the shared
  `connectSse`/`SseHandle` from `@agentic-toolkit/data/stream` — the one live-connection transport
  every real-time consumer in the web app now shares, per that package's own top-of-file comment.
  The live connection is a browser `EventSource`, which cannot set a request header — the reason
  its access token rides the URL query string instead; the client-generated message id uses
  `crypto.randomUUID()` when available, falling back to a `Date.now()`-based string.
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

**Decision**: the DM thread's live connection and the shared notification stream's connection both
carry their access token in the URL query string instead of a header, unlike every other request
in this recipe.
**Applies to**: Web — this is the browser `EventSource`'s own platform limitation (it cannot set
request headers); a live-connection client on another platform that can set a header need not
replicate this deviation.
**Rationale**: both source files say so directly; this recipe documents the resulting exposure
difference under Security and Privacy rather than treating it as an oversight to silently correct.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/messaging/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
