<!-- leaf: implement-hub-domain-1/hooks--part-3 · source: hub-domain-hooks.md -->

# Hub Domain Messaging Hooks — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/hooks--part-3#<slug>`):

- `auth-delegated-to-shared-client` MUST
- `session-refresh-waterfall` MUST
- `errors-carry-status-and-code` MUST
- `sse-token-rides-the-query-string` MUST
- `sse-token-read-fresh-per-attempt` MUST
- `no-stream-without-a-token` MUST
- `poll-fallback-uses-the-bearer-header` MUST
- `swiftui` MUST — model DmMessage, DmChatSummary, PresenceView, DmConversation, and Notification as Codable, Hashable, Sendable structs; …

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

