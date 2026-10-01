---
id: 5c202bb7-c4b6-4da9-a9b0-9d58f664461f
title: Status User State
domain: agentictoolkit://cookbook/status/dashboard/state/status-user
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State returning the signed-in user object or null, a thin shape adapter
  over the shared status-auth-me session read.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/api
references: []
approved-by: ''
approved-date: ''
---

# Status User State

## Overview

The status user state is a thin shape adapter over the shared session state. It returns the current authenticated user object, or `null` when the user is "unauthenticated / unknown". It calls the underlying shared session state and returns only that state's `user` field, dropping its loading flag.

The adapter exists so that one request function owns the `/auth/me` semantics, so consumers can't drift. All fetch, caching and retry behavior therefore comes from the session state and its request function. This recipe specifies that inherited contract as seen through the adapter, because a port has to reproduce it for the adapter to behave the same.

Callers that need only the user object use this state — for example, views that read the result for role gating by checking `user?.role`, or a banner that derives an `isAdmin` flag from `role === "admin"`. Callers that also need the loading flag use the shared session state directly instead.

## Behavioral Requirements

- **signature**: The state MUST take no arguments and MUST return either a user object or `null`.
- **status-user-shape**: The user object MUST have an `email` string, an optional `displayName` that may be a string or `null`, and a `role` that is exactly one of `"pending"`, `"viewer"` or `"admin"`.
- **user-projection**: The state MUST return the session state's `user` field unchanged and nothing else. The session state's loading flag MUST NOT be part of the return value.
- **null-when-unknown**: The state MUST return `null` in each of these cases: the first session load is still in flight, the backend reported a definitive signed-out session, or the first load failed with nothing cached. Callers cannot tell these cases apart through this state.
- **single-query-owner**: The state MUST NOT define its own request or read. It MUST read the session through the one shared session state so every consumer uses the same request function.
- **shared-cache-key**: The session MUST be cached under the single cache key `status-auth-me`. Every consumer, whether it uses this adapter or the session state directly, MUST read the same cache entry, and concurrent consumers MUST be served by one in-flight request.
- **session-request**: Loading the session MUST send one `GET` to the `/auth/me` path, resolved to an absolute URL by the injected API client (the default base is `/api`, so the default URL is `/api/auth/me`). The request MUST carry no body and no custom headers.
- **cookie-session**: The client MUST learn the session only by asking `/auth/me`. The session itself is the `status_auth` httpOnly cookie, which the browser attaches to the same-origin request; the client never reads or stores the cookie. The status backend owns setting and clearing it.
- **ok-user-response**: When the response is OK (status 200 to 299), the state MUST resolve to the `user` field of the JSON body.
- **ok-null-response**: When an OK response body has `user: null` or no `user` field, the state MUST resolve to `null`.
- **non-ok-throws**: When the response is not OK, the request function MUST throw, with a message of `auth/me unavailable (HTTP <status>)`. It MUST NOT treat a non-OK response as signed out. The reason: the backend never answers this route with a 401, so a non-OK status means infrastructure trouble.
- **network-error-propagates**: When the underlying request rejects, the request function MUST let that rejection propagate unchanged. It MUST NOT convert it to `null`.
- **keep-last-known-session**: When a refetch fails after a user has already been cached, the state MUST keep returning the cached user. The signed-in session MUST change to `null` only after an OK response with `user: null`.
- **retry-count**: A failed session load MUST be retried up to 3 times (4 attempts in total) before the read enters its error state. Retries use exponential backoff, starting at 1 s and doubling per attempt, capped at 30 s.
- **stale-time**: A successfully loaded session MUST be treated as fresh for 60,000 ms. During that window, mounting another consumer MUST NOT trigger a new request.
- **refetch-triggers**: After the 60,000 ms fresh window, the session MUST be refetched on the platform's default triggers: a new consumer mounting, the application regaining focus, or the network reconnecting. It MUST NOT refetch on a timer, because the source sets no refetch interval.
- **login-invalidation-contract**: Code that signs a user in (the login and signup flows) MUST invalidate the `status-auth-me` cache entry after the cookie is set. Otherwise the cached `{ user: null }` stays in place for the whole stale time.
- **body-not-validated**: The request function MUST treat the JSON body as containing a `user` field that is either the user object or `null`, without checking its fields at runtime. The shape of the user object, including the `role` value, is trusted as the backend sent it.
- **no-error-exposure**: The state MUST NOT expose the read's error, a retry count or a status flag. A failed load is visible to callers only as the value it returns (a kept cached user, or `null`).
- **query-provider-precondition**: The calling context MUST have a shared cache provider available. Attempting to read with no such provider throws a missing-client error.
- **api-client-injection**: The state MUST resolve URLs through an injected API client. That is the client from the nearest override provider, or the same-origin default client when there is no provider.
- **concurrency**: Simultaneous requests MUST be deduplicated and cache updates ordered through the single cache entry for the key, so no concurrent or interleaved access to the session occurs.
- **no-other-side-effects**: Apart from the `/auth/me` request and the cache entry, the state MUST NOT write storage, log, emit analytics or navigate.

## Appearance

Not applicable — this is a session-lookup state, not a visual component.

## States

Not applicable — this is a session-lookup state, not a visual component.

## Accessibility

Not applicable — this is a session-lookup state, not a visual component.

## Conformance Test Vectors

Vectors 001 to 004 come from the shared request function's own test assertions, exercised with an injected transport. The remaining vectors are derived from the source and assume a test cache and an injected API client.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-status-user-001 | ok-user-response, status-user-shape | `/auth/me` responds 200 `{ user: { email: "a@b.c", displayName: "A", role: "admin" } }` | Resolves to exactly that user object (test: "resolves the user from a definitive 200") |
| use-status-user-002 | ok-null-response | `/auth/me` responds 200 `{ user: null }` | Resolves to `null` (test: "resolves null from a definitive signed-out 200") |
| use-status-user-003 | non-ok-throws | `/auth/me` responds 500 `{}` | The request function rejects with an error matching `HTTP 500`; the result is not `null` (test: "THROWS on a 5xx") |
| use-status-user-004 | network-error-propagates | The transport rejects with a network-level error (`fetch failed`) | The request function rejects with an error matching `fetch failed` (test: "propagates a network failure") |
| use-status-user-005 | session-request, api-client-injection | Default client (base `/api`); render the state | Exactly one `GET` to `/api/auth/me` with no body |
| use-status-user-006 | user-projection, null-when-unknown | Render the state while the first request is still pending | Returns `null`; the return value has no loading-flag property |
| use-status-user-007 | keep-last-known-session | Cache holds user U; invalidate the key and make every retry answer 503 | The state keeps returning U through all 4 attempts and after the read enters its error state |
| use-status-user-008 | retry-count, null-when-unknown, no-error-exposure | Empty cache; every `/auth/me` call answers 502 | 4 requests in total; the state then returns `null` with no error exposed |
| use-status-user-009 | shared-cache-key, single-query-owner | Mount this state and the shared session state together with an empty cache | One request; both read the same user from the `status-auth-me` cache key |
| use-status-user-010 | stale-time | Session loaded at t=0; mount a second consumer at t=30,000 ms, then a third at t=61,000 ms | No request at 30,000 ms; one background refetch at 61,000 ms |
| use-status-user-011 | ok-null-response | `/auth/me` responds 200 `{}` | Resolves to `null` |
| use-status-user-012 | query-provider-precondition | Render the state with no shared cache provider available | Render throws a missing-client error |
| use-status-user-013 | body-not-validated | 200 `{ user: { email: "x@y.z", role: "superuser" } }` | Returns the object as sent, with `role` `"superuser"`; no error |

## Edge Cases

- **First load in flight**: The state MUST return `null`, the same value as signed out (use-status-user-006). Callers that must not flash signed-out UI MUST use the shared session state's loading flag instead.
- **First load fails with nothing cached**: After 4 failed attempts the state MUST return `null`. This is "unknown", and a later refetch trigger (focus, reconnect or remount) retries the load (use-status-user-008).
- **Transient failure while signed in**: The state MUST keep returning the cached user (use-status-user-007). A 5xx from the proxy, a deploy restart or a network blip MUST NOT sign the user out.
- **Backend returns 401 or 403**: This is treated like any other non-OK status. The request function MUST throw, and the cached session MUST be kept. The source relies on the backend never sending 401 on this route, so this client has no path that turns an auth error into a sign-out.
- **OK response with a non-JSON body**: Parsing the body as JSON rejects, and the read MUST treat the rejection as a failure: it is retried and the cached session is kept.
- **OK response missing `user`**: The state MUST resolve to `null` (use-status-user-011).
- **Unexpected `role` or missing `email`**: The state MUST pass the value through unchanged (use-status-user-013). Role-gated callers then compare against the known values, so an unknown role matches neither `"admin"` nor `"viewer"`.
- **Sign-in without invalidation**: If a login flow sets the cookie but does not invalidate the `status-auth-me` cache entry, the state MUST keep returning the cached `null` until the 60,000 ms fresh window ends and a refetch trigger fires.
- **Sign-out**: The logout action sends a `POST` to `/auth/logout` and then performs a full page navigation to `/`. That reload discards the cache, so the next load MUST return `null`. This state itself never clears the cache.
- **Concurrent consumers**: Several consumers mounting at the same moment MUST share one request through the single key (use-status-user-009).
- **Offline**: While disconnected, a failed request is retried and the cached session is kept. After reconnecting, the platform's reconnect trigger MUST refetch a stale session.
- **No timeout or cancellation**: The request function passes no cancellation signal and sets no timeout. A hung request stays pending until the platform's network stack gives up, and the state keeps returning its current value meanwhile.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Injected API client base path | string | `/api` | Base the `/auth/me` path is joined to. Supplied by the host, or by a test double through the client provider. |
| Shared cache (injected) | cache | none (required) | Owns the `status-auth-me` cache entry. The host supplies it. |
| Stale time | number (ms) | `60000` | Fixed in the shared session state. Not caller-configurable. |
| Retry count | number | `3` | Fixed in the shared session state. Not caller-configurable. |

The state takes no parameters and reads no environment variables or settings keys.

## Deep Linking

Not applicable: the state resolves a session and exposes no route or URL surface.

## Localization

Not applicable: the state returns data and shows no user-facing strings. The thrown `auth/me unavailable (HTTP <status>)` message is never displayed, because this state does not expose read errors.

## Accessibility Options

Not applicable: the state renders nothing.

## Feature Flags

Not applicable: the source reads no flag, and the state is always active when called.

## Analytics

Not applicable: the source emits no events.

## Privacy

- **Data collected**: The signed-in account's `email`, optional `displayName` and `role`, as returned by `/auth/me`.
- **Storage**: Held only in memory in the shared cache under the key `status-auth-me`. It is never written to local storage, session storage or cookies by this code. The session credential is the httpOnly `status_auth` cookie, which client script cannot read.
- **Transmission**: One same-origin `GET /auth/me` (through the host's `/api` proxy by default). The browser attaches the session cookie, and the client adds no credential of its own.
- **Retention**: For the life of the page's shared cache. A full page load, such as the logout redirect to `/`, discards it. Cookie lifetime and revocation are owned by the status backend.

## Logging

Not applicable: the source contains no log calls. Failures show up only as thrown read errors, which this adapter does not expose.

## Platform Notes

- **SwiftUI**: Start from an `@Observable` (or `ObservableObject`) session store, shared through `.environment`, that holds `user: StatusUser?` and loads with `URLSession.shared.data(from:)` plus `JSONDecoder` into a `Codable` `StatusUser` with a `Role` enum. Views read `store.user` to mirror this adapter. Reproduce the semantics by hand: a non-2xx status throws and leaves the cached user in place, retry 3 times with backoff, and treat the value as fresh for 60 s. `HTTPCookieStorage` attaches the session cookie automatically. A `Codable` enum rejects unknown roles, unlike the unvalidated cast in the source.
- **Compose**: Use a `ViewModel` exposing `StateFlow<StatusUser?>`, collected with `collectAsStateWithLifecycle()`, and load with Ktor or Retrofit plus `kotlinx.serialization`. A single repository-level `MutableStateFlow` gives the shared-cache behavior. Implement retry with `retryWhen` and exponential delay, and throw on non-2xx without clearing the cached value. Cookies need a `CookieJar` (OkHttp) or `HttpCookies` (Ktor).
- **React/Web**: Source platform. `src/hooks/useStatusUser.ts` is a one-line projection, `useStatusSession().user`. The contract lives in `src/header-auth.ts`: the cache key constant `STATUS_AUTH_QUERY_KEY` (`["status-auth-me"]`), the request function `fetchStatusUser` (throws on non-OK), and the session hook's `useQuery` options `{ staleTime: 60_000, retry: 3 }` — React Query v5's default backoff for those retries is 1 s doubling per attempt, capped at 30 s. React Query v5 keeps `data` when a refetch errors, and that is what `keep-last-known-session` relies on. The module must be marked `"use client"` because it depends on React hooks and the browser `fetch`. The calling component must be rendered under a `QueryClientProvider`; the underlying `useQuery` call throws when no client is provided. Concurrency is trivial because JavaScript runs on a single thread; deduplication and cache-update ordering are handled by the query client's single cache entry for the key. The injected transport comes from `useStatusApi()` — the client from the nearest `StatusApiProvider`, or the same-origin default `StatusApiClient` otherwise — and a network failure surfaces as whatever the browser `fetch` API rejects with (typically a `TypeError`, e.g. `fetch failed`).
- **AppKit / UIKit**: Use a singleton session service holding `user: StatusUser?` and publishing changes through Combine `@Published` or `NotificationCenter`, with `URLSession` and `JSONDecoder` for the request. View controllers subscribe in `viewDidLoad`. Deduplicate simultaneous loads by storing one in-flight `Task` and awaiting it.
- **WinUI 3**: Start from a singleton `SessionService` view model implementing `INotifyPropertyChanged` with a `StatusUser? User` property. Pages bind it with `{x:Bind Session.User, Mode=OneWay}` and derive role gates such as `IsAdmin => User?.Role == Role.Admin`. Load with a shared `HttpClient` created over an `HttpClientHandler` whose `CookieContainer` holds `status_auth` (a browser attaches the cookie for you; .NET needs the handler). Deserialize with `System.Text.Json` (`JsonSerializer.Deserialize<AuthMeResponse>` with `JsonStringEnumConverter` for `role`). Call `EnsureSuccessStatusCode()` or check `IsSuccessStatusCode` and throw, so a non-2xx never sets `User = null`. Wrap the load in a `Task`-returning method that caches one in-flight `Task<StatusUser?>` to deduplicate concurrent callers, retries 3 times with `Task.Delay` backoff (1 s, 2 s, 4 s), and skips the request if the last success was under 60 s ago. Marshal the `User` assignment to the UI thread with `DispatcherQueue.TryEnqueue`. There is no React Query equivalent, so refetch on focus and reconnect has to be wired explicitly (`Window.Activated`, `NetworkInformation.NetworkStatusChanged`).

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/useStatusUser.ts` |

## Design Decisions

**Decision**: Keep a separate adapter that returns only `user`, rather than having every consumer call the session state.
**Rationale**: One request function owns the `/api/auth/me` semantics, so role-gating consumers "can't drift". Consumers that need only the user get the simpler `StatusUser | null` shape, and those that need the loading flag use the session state.
**Approved**: pending

**Decision**: Treat any non-OK `/auth/me` response as a thrown error, never as signed out.
**Rationale**: The backend never 401s this route, so a non-OK status means infrastructure trouble. Throwing lets the shared cache (React Query, on the web implementation) keep the last-known session and retry, which fixes "the 'visited the site and I was suddenly logged out' bug".
**Approved**: pending

**Decision**: Drop the loading flag, so loading, unknown and signed-out all return `null`.
**Rationale**: This is a deliberate lossy projection for role gates, which should hide admin affordances until a user is known. Callers that must not flash signed-out UI use the session state's loading flag instead.
**Approved**: pending

**Decision**: Use a 60 s stale time and 3 retries.
**Rationale**: Set in the web implementation's session hook. The stale time limits `/auth/me` traffic across the many consumers. The retries ride out short backend restarts, and because a read error does not clear cached data, the header keeps showing the signed-in user in the meantime.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | failed | reliability |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | security |

**separation-of-concerns** passes. The adapter only reshapes the result, and fetch and cache semantics live in one query function in `header-auth.ts`.

**unit-test-coverage** is partial. `header-auth.test.ts` covers `fetchStatusUser` for 200 with a user, 200 with null, 500 and a network failure. Nothing tests the adapter itself or the query options (retry, stale time, keeping cached data).

**explicit-error-handling** passes. Non-OK responses throw with the HTTP status, and network errors propagate instead of turning into a sign-out. The adapter's choice not to expose the error is a documented projection, not a swallowed failure.

**error-recovery** and **graceful-degradation** pass. Transient failures retry 3 times with backoff while the last-known session keeps being shown.

**timeout-handling** fails. The request has no timeout or abort signal, so a hung `/auth/me` stays pending indefinitely.

**secure-storage** passes. The credential is an httpOnly cookie that the client never reads, and the user record is held only in memory.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
