<!-- leaf: implement-hub-domain-1/hooks--part-2 · source: hub-domain-hooks.md -->

# Hub Domain Messaging Hooks — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/hooks--part-2#<slug>`):

- `shared-stream-refcounting` MUST
- `local-change-broadcast` MUST
- `wake-signal-carries-no-payload` MUST
- `unread-count-fetch-on-mount-and-wake` MUST
- `unread-count-preserved-on-failure` MUST
- `inbox-query-serialization` MUST
- `inbox-status-left-to-backend-default` MUST
- `inbox-fetch-per-query-and-nonce` MUST
- `inbox-stale-response-ignored` MUST
- `inbox-refetch-on-wake` MUST
- `inbox-mutation-then-broadcast` MUST
- `inbox-mutation-failure-leaves-list-untouched` MUST
- `dm-inbox-initial-window` MUST
- `dm-inbox-window-growth-and-ceiling` MUST
- `dm-inbox-presence-merge` MUST
- `dm-inbox-presence-query-encoding` MUST
- `dm-inbox-presence-failure-is-silent` MUST
- `dm-inbox-stale-response-discarded` MUST
- `dm-inbox-refetch-on-wake` MUST
- `dm-inbox-load-failure-keeps-last-good-list` MUST
- `dm-inbox-has-more-computation` MUST
- `dm-thread-null-chatid-clears-state` MUST
- `dm-thread-history-load-and-sort` MUST
- `dm-thread-message-merge-dedupe` MUST
- `dm-thread-sse-cursor-from-last-loaded-seq` MUST
- `dm-thread-malformed-frame-ignored` MUST
- `dm-thread-teardown-on-change-or-unmount` MUST
- `dm-thread-poll-fallback-refetch` MUST
- `dm-thread-send-noop-on-empty-or-missing-chat` MUST
- `dm-thread-send-client-message-id` MUST
- `dm-thread-send-merges-and-broadcasts` MUST
- `dm-thread-send-propagates-failure` MUST
- `dm-thread-mark-read-request-shape` MUST
- `dm-thread-ownership-comparison` MUST
- `start-dm-request-shape` MUST
- `start-dm-forbidden-mapping` MUST
- `start-dm-other-errors-propagate` MUST

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

