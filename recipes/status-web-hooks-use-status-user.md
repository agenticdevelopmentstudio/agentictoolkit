---
id: 5c202bb7-c4b6-4da9-a9b0-9d58f664461f
title: useStatusUser
domain: agentictoolkit://recipes/status-web-hooks-use-status-user
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook returning the signed-in StatusUser or null, a thin shape adapter
  over header-auth's shared status-auth-me session query.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-api
references: []
approved-by: ''
approved-date: ''
---

# useStatusUser

## Overview

`useStatusUser` is a client-only React hook in the status web app (`packages/web/packages/status-web/src/hooks/useStatusUser.ts`). It returns the current authenticated `StatusUser`, or `null` when the user is "unauthenticated / unknown" (its doc comment). It is a "thin shape adapter over header-auth's useStatusUser": it calls the session hook exported from `src/header-auth.ts` (imported under the alias `useStatusSession`) and returns only that hook's `user` field, dropping `isPending`.

The adapter exists so that "ONE queryFn owns the /api/auth/me semantics ... so consumers can't drift". All fetch, caching and retry behavior therefore comes from the session hook and its `fetchStatusUser` query function in `header-auth.ts`. This recipe specifies that inherited contract as seen through the adapter, because a port has to reproduce it for the adapter to behave the same.

Callers that need only the user object use this hook. `BoardShell` and `FleetView` read the result for role gating (`user?.role`), and `UnconfiguredProjectsBanner` derives `isAdmin` from `useStatusUser()?.role === "admin"`. Callers that also need the loading flag, such as `HomeGate` and `useStatusHeaderAuth`, import the session hook from `header-auth` directly instead.

## Behavioral Requirements

- **signature**: The hook MUST take no arguments and MUST return either a `StatusUser` or `null`.
- **status-user-shape**: A `StatusUser` MUST have `email: string`, an optional `displayName` that may be a `string` or `null`, and `role` with exactly one of the values `"pending"`, `"viewer"` or `"admin"`.
- **user-projection**: The hook MUST return the session hook's `user` field unchanged and nothing else. The session hook's `isPending` flag MUST NOT be part of the return value.
- **null-when-unknown**: The hook MUST return `null` in each of these cases: the first session load is still in flight, the backend reported a definitive signed-out session, or the first load failed with nothing cached. Callers cannot tell these cases apart through this hook.
- **single-query-owner**: The hook MUST NOT define its own fetch or query. It MUST read the session through the one shared session hook so every consumer uses the same query function.
- **shared-cache-key**: The session MUST be cached under the single query key `["status-auth-me"]` (`STATUS_AUTH_QUERY_KEY`). Every consumer, whether it uses this adapter or the session hook directly, MUST read the same cache entry, and concurrent consumers MUST be served by one in-flight request.
- **session-request**: Loading the session MUST send one `GET` to the `/auth/me` path, resolved to an absolute URL by the injected `StatusApiClient` (the default base is `/api`, so the default URL is `/api/auth/me`). The request MUST carry no body and no custom headers.
- **cookie-session**: The client MUST learn the session only by asking `/auth/me`. The session itself is the `status_auth` httpOnly cookie, which the browser attaches to the same-origin request; the client never reads or stores the cookie. The status backend owns setting and clearing it.
- **ok-user-response**: When the response is OK (status 200 to 299), the hook MUST resolve to the `user` field of the JSON body.
- **ok-null-response**: When an OK response body has `user: null` or no `user` field, the hook MUST resolve to `null`.
- **non-ok-throws**: When the response is not OK, the query function MUST throw an `Error` whose message is `auth/me unavailable (HTTP <status>)`. It MUST NOT treat a non-OK response as signed out. The doc comment gives the reason: the backend never answers this route with a 401, so a non-OK status means infrastructure trouble.
- **network-error-propagates**: When the underlying `fetch` rejects, the query function MUST let that rejection propagate unchanged. It MUST NOT convert it to `null`.
- **keep-last-known-session**: When a refetch fails after a user has already been cached, the hook MUST keep returning the cached user. The signed-in session MUST change to `null` only after an OK response with `user: null`.
- **retry-count**: A failed session load MUST be retried up to 3 times (4 attempts in total) before the query enters its error state. Retries use the query library's default backoff (in React Query v5, 1 s doubling per attempt, capped at 30 s).
- **stale-time**: A successfully loaded session MUST be treated as fresh for 60,000 ms. During that window, mounting another consumer MUST NOT trigger a new request.
- **refetch-triggers**: After the 60,000 ms fresh window, the session MUST be refetched on the query library's default triggers: a new consumer mounting, the window regaining focus, or the network reconnecting. It MUST NOT refetch on a timer, because the source sets no refetch interval.
- **login-invalidation-contract**: Code that signs a user in (the login and signup flows) MUST invalidate `["status-auth-me"]` after the cookie is set. The key's doc comment explains why: otherwise the cached `{ user: null }` stays in place for the whole stale time.
- **body-not-validated**: The query function MUST cast the JSON body to `{ user: StatusUser | null }` without checking its fields at runtime. The shape of `user`, including the `role` value, is trusted as the backend sent it.
- **no-error-exposure**: The hook MUST NOT expose the query error, a retry count or a status flag. A failed load is visible to callers only as the value it returns (a kept cached user, or `null`).
- **query-provider-precondition**: The calling component MUST be rendered under a React Query `QueryClientProvider`. The underlying `useQuery` call throws when no client is provided.
- **api-client-injection**: The hook MUST resolve URLs through the `StatusApiClient` from `useStatusApi()`. That is the client from the nearest `StatusApiProvider`, or the same-origin default client when there is no provider.
- **client-only-module**: The module MUST be marked as client code (the `"use client"` directive), because it depends on React hooks and the browser `fetch`.
- **concurrency**: All work MUST run on the single JavaScript thread. Deduplication of simultaneous requests and ordering of cache updates are handled by the query client's single cache entry for the key, so no cross-thread access exists.
- **no-other-side-effects**: Apart from the `/auth/me` request and the query cache entry, the hook MUST NOT write storage, log, emit analytics or navigate.

## Appearance

Not applicable — this is a React session-lookup hook, not a visual component.

## States

Not applicable — this is a React session-lookup hook, not a visual component.

## Accessibility

Not applicable — this is a React session-lookup hook, not a visual component.

## Conformance Test Vectors

`src/header-auth.test.ts` tests `fetchStatusUser`, the shared query function, with an injected `fetch`. Vectors 001 to 004 come from its assertions. The remaining vectors are derived from the source and assume a test `QueryClient` and an injected `StatusApiClient`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-status-user-001 | ok-user-response, status-user-shape | `/auth/me` responds 200 `{ user: { email: "a@b.c", displayName: "A", role: "admin" } }` | Resolves to exactly that user object (test: "resolves the user from a definitive 200") |
| use-status-user-002 | ok-null-response | `/auth/me` responds 200 `{ user: null }` | Resolves to `null` (test: "resolves null from a definitive signed-out 200") |
| use-status-user-003 | non-ok-throws | `/auth/me` responds 500 `{}` | Query function rejects with an error matching `HTTP 500`; the result is not `null` (test: "THROWS on a 5xx") |
| use-status-user-004 | network-error-propagates | `fetch` rejects with `TypeError("fetch failed")` | Query function rejects with an error matching `fetch failed` (test: "propagates a network failure") |
| use-status-user-005 | session-request, api-client-injection | Default client (base `/api`); render the hook | Exactly one `GET` to `/api/auth/me` with no body |
| use-status-user-006 | user-projection, null-when-unknown | Render the hook while the first request is still pending | Returns `null`; the return value has no `isPending` property |
| use-status-user-007 | keep-last-known-session | Cache holds user U; invalidate the key and make every retry answer 503 | Hook keeps returning U through all 4 attempts and after the query enters its error state |
| use-status-user-008 | retry-count, null-when-unknown, no-error-exposure | Empty cache; every `/auth/me` call answers 502 | 4 requests in total; hook then returns `null` with no error exposed |
| use-status-user-009 | shared-cache-key, single-query-owner | Mount this hook and `useStatusHeaderAuth` together with an empty cache | One request; both read the same user from key `["status-auth-me"]` |
| use-status-user-010 | stale-time | Session loaded at t=0; mount a second consumer at t=30,000 ms, then a third at t=61,000 ms | No request at 30,000 ms; one background refetch at 61,000 ms |
| use-status-user-011 | ok-null-response | `/auth/me` responds 200 `{}` | Resolves to `null` |
| use-status-user-012 | query-provider-precondition | Render the hook with no `QueryClientProvider` | Render throws the query library's missing-client error |
| use-status-user-013 | body-not-validated | 200 `{ user: { email: "x@y.z", role: "superuser" } }` | Returns the object as sent, with `role` `"superuser"`; no error |

## Edge Cases

- **First load in flight**: The hook MUST return `null`, the same value as signed out (use-status-user-006). Callers that must not flash signed-out UI MUST use the session hook's `isPending` instead, as `HomeGate` and `useStatusHeaderAuth` do.
- **First load fails with nothing cached**: After 4 failed attempts the hook MUST return `null`. The doc comment covers this as "unknown", and a later refetch trigger (focus, reconnect or remount) retries the load (use-status-user-008).
- **Transient failure while signed in**: The hook MUST keep returning the cached user (use-status-user-007). A 5xx from the proxy, a deploy restart or a network blip MUST NOT sign the user out.
- **Backend returns 401 or 403**: This is treated like any other non-OK status. The query function MUST throw, and the cached session MUST be kept. The source relies on the backend never sending 401 on this route, so this client has no path that turns an auth error into a sign-out.
- **OK response with a non-JSON body**: `res.json()` rejects, and the query MUST treat the rejection as a failure: it is retried and the cached session is kept.
- **OK response missing `user`**: The hook MUST resolve to `null` (use-status-user-011).
- **Unexpected `role` or missing `email`**: The hook MUST pass the value through unchanged (use-status-user-013). Role-gated callers then compare against the known values, so an unknown role matches neither `"admin"` nor `"viewer"`.
- **Sign-in without invalidation**: If a login flow sets the cookie but does not invalidate `["status-auth-me"]`, the hook MUST keep returning the cached `null` until the 60,000 ms fresh window ends and a refetch trigger fires.
- **Sign-out**: The logout action in `useStatusHeaderAuth` POSTs `/auth/logout` and then does a full page navigation to `/`. That reload discards the cache, so the next load MUST return `null`. This hook itself never clears the cache.
- **Concurrent consumers**: Several components mounting at the same moment MUST share one request through the single key (use-status-user-009).
- **Offline**: While disconnected, a failed fetch is retried and the cached session is kept. After reconnecting, the query library's reconnect trigger MUST refetch a stale session.
- **No timeout or cancellation**: The query function passes no abort signal and sets no timeout. A hung request stays pending until the browser gives up, and the hook keeps returning its current value meanwhile.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiProvider` `basePath` | `string` | `"/api"` (`DEFAULT_API_BASE`) | Base the `/auth/me` path is joined to. Supplied by the host, or by a test double through the provider. |
| `QueryClientProvider` client | `QueryClient` | none (required) | Owns the `["status-auth-me"]` cache entry. The host supplies it. |
| `staleTime` | `number` (ms) | `60_000` | Fixed in the session hook. Not caller-configurable. |
| `retry` | `number` | `3` | Fixed in the session hook. Not caller-configurable. |

The hook takes no parameters and reads no environment variables or settings keys.

## Deep Linking

Not applicable: the hook resolves a session and exposes no route or URL surface.

## Localization

Not applicable: the hook returns data and shows no user-facing strings. The thrown `auth/me unavailable (HTTP <status>)` message is never displayed, because this hook does not expose query errors.

## Accessibility Options

Not applicable: the hook renders nothing.

## Feature Flags

Not applicable: the source reads no flag, and the hook is always active when called.

## Analytics

Not applicable: the source emits no events.

## Privacy

- **Data collected**: The signed-in account's `email`, optional `displayName` and `role`, as returned by `/auth/me`.
- **Storage**: Held only in memory in the React Query cache under `["status-auth-me"]`. It is never written to `localStorage`, `sessionStorage` or cookies by this code. The session credential is the httpOnly `status_auth` cookie, which client script cannot read.
- **Transmission**: One same-origin `GET /auth/me` (through the host's `/api` proxy by default). The browser attaches the session cookie, and the client adds no credential of its own.
- **Retention**: For the life of the page's query client. A full page load, such as the logout redirect to `/`, discards it. Cookie lifetime and revocation are owned by the status backend.

## Logging

Not applicable: the source contains no log calls. Failures show up only as thrown query errors, which this adapter does not expose.

## Platform Notes

- **SwiftUI**: Start from an `@Observable` (or `ObservableObject`) session store, shared through `.environment`, that holds `user: StatusUser?` and loads with `URLSession.shared.data(from:)` plus `JSONDecoder` into a `Codable` `StatusUser` with a `Role` enum. Views read `store.user` to mirror this adapter. Reproduce the semantics by hand: a non-2xx status throws and leaves the cached user in place, retry 3 times with backoff, and treat the value as fresh for 60 s. `HTTPCookieStorage` attaches the session cookie automatically. A `Codable` enum rejects unknown roles, unlike the unvalidated cast in the source.
- **Compose**: Use a `ViewModel` exposing `StateFlow<StatusUser?>`, collected with `collectAsStateWithLifecycle()`, and load with Ktor or Retrofit plus `kotlinx.serialization`. A single repository-level `MutableStateFlow` gives the shared-cache behavior. Implement retry with `retryWhen` and exponential delay, and throw on non-2xx without clearing the cached value. Cookies need a `CookieJar` (OkHttp) or `HttpCookies` (Ktor).
- **React/Web**: Source platform. `src/hooks/useStatusUser.ts` is a one-line projection, `useStatusSession().user`. The contract lives in `src/header-auth.ts`: `STATUS_AUTH_QUERY_KEY`, `fetchStatusUser` (throws on non-OK) and the session hook's `useQuery` options `{ staleTime: 60_000, retry: 3 }`. React Query v5 keeps `data` when a refetch errors, and that is what `keep-last-known-session` relies on.
- **AppKit / UIKit**: Use a singleton session service holding `user: StatusUser?` and publishing changes through Combine `@Published` or `NotificationCenter`, with `URLSession` and `JSONDecoder` for the request. View controllers subscribe in `viewDidLoad`. Deduplicate simultaneous loads by storing one in-flight `Task` and awaiting it.
- **WinUI 3**: Start from a singleton `SessionService` view model implementing `INotifyPropertyChanged` with a `StatusUser? User` property. Pages bind it with `{x:Bind Session.User, Mode=OneWay}` and derive role gates such as `IsAdmin => User?.Role == Role.Admin`. Load with a shared `HttpClient` created over an `HttpClientHandler` whose `CookieContainer` holds `status_auth` (a browser attaches the cookie for you; .NET needs the handler). Deserialize with `System.Text.Json` (`JsonSerializer.Deserialize<AuthMeResponse>` with `JsonStringEnumConverter` for `role`). Call `EnsureSuccessStatusCode()` or check `IsSuccessStatusCode` and throw, so a non-2xx never sets `User = null`. Wrap the load in a `Task`-returning method that caches one in-flight `Task<StatusUser?>` to deduplicate concurrent callers, retries 3 times with `Task.Delay` backoff (1 s, 2 s, 4 s), and skips the request if the last success was under 60 s ago. Marshal the `User` assignment to the UI thread with `DispatcherQueue.TryEnqueue`. There is no React Query equivalent, so refetch on focus and reconnect has to be wired explicitly (`Window.Activated`, `NetworkInformation.NetworkStatusChanged`).

## Design Decisions

**Decision**: Keep a separate adapter that returns only `user`, rather than having every consumer call the session hook.
**Rationale**: The doc comment says one query function owns the `/api/auth/me` semantics, so role-gating consumers "can't drift". Consumers that need only the user get the simpler `StatusUser | null` shape, and those that need the loading flag use the session hook.
**Approved**: pending

**Decision**: Treat any non-OK `/auth/me` response as a thrown error, never as signed out.
**Rationale**: The `fetchStatusUser` doc comment says the backend never 401s this route, so a non-OK status means infrastructure trouble. Throwing lets React Query keep the last-known session and retry, which fixes "the 'visited the site and I was suddenly logged out' bug".
**Approved**: pending

**Decision**: Drop `isPending`, so loading, unknown and signed-out all return `null`.
**Rationale**: This is a deliberate lossy projection for role gates, which should hide admin affordances until a user is known. Callers that must not flash signed-out UI use the session hook's `isPending` instead.
**Approved**: pending

**Decision**: Use a 60 s stale time and 3 retries.
**Rationale**: Set in the session hook. The stale time limits `/auth/me` traffic across the many consumers. The retries ride out short backend restarts, and because a query error does not clear cached data, the header keeps showing the signed-in user in the meantime.
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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
