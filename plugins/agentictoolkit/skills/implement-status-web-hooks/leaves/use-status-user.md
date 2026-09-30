<!-- leaf: implement-status-web-hooks/use-status-user · source: status-web-hooks-use-status-user.md -->

**Rules** (cite as `implement-status-web-hooks/use-status-user#<slug>`):

- `signature` MUST
- `status-user-shape` MUST
- `user-projection` MUST
- `null-when-unknown` MUST
- `single-query-owner` MUST
- `shared-cache-key` MUST
- `session-request` MUST
- `cookie-session` MUST
- `ok-user-response` MUST
- `ok-null-response` MUST
- `non-ok-throws` MUST
- `network-error-propagates` MUST
- `keep-last-known-session` MUST
- `retry-count` MUST
- `stale-time` MUST
- `refetch-triggers` MUST
- `login-invalidation-contract` MUST
- `body-not-validated` MUST
- `no-error-exposure` MUST
- `query-provider-precondition` MUST
- `api-client-injection` MUST
- `client-only-module` MUST
- `concurrency` MUST
- `no-other-side-effects` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiProvider` `basePath` | `string` | `"/api"` (`DEFAULT_API_BASE`) | Base the `/auth/me` path is joined to. Supplied by the host, or by a test double through the provider. |
| `QueryClientProvider` client | `QueryClient` | none (required) | Owns the `["status-auth-me"]` cache entry. The host supplies it. |
| `staleTime` | `number` (ms) | `60_000` | Fixed in the session hook. Not caller-configurable. |
| `retry` | `number` | `3` | Fixed in the session hook. Not caller-configurable. |

The hook takes no parameters and reads no environment variables or settings keys.

## Privacy

- **Data collected**: The signed-in account's `email`, optional `displayName` and `role`, as returned by `/auth/me`.
- **Storage**: Held only in memory in the React Query cache under `["status-auth-me"]`. It is never written to `localStorage`, `sessionStorage` or cookies by this code. The session credential is the httpOnly `status_auth` cookie, which client script cannot read.
- **Transmission**: One same-origin `GET /auth/me` (through the host's `/api` proxy by default). The browser attaches the session cookie, and the client adds no credential of its own.
- **Retention**: For the life of the page's query client. A full page load, such as the logout redirect to `/`, discards it. Cookie lifetime and revocation are owned by the status backend.

## Platform Notes

- **SwiftUI**: Start from an `@Observable` (or `ObservableObject`) session store, shared through `.environment`, that holds `user: StatusUser?` and loads with `URLSession.shared.data(from:)` plus `JSONDecoder` into a `Codable` `StatusUser` with a `Role` enum. Views read `store.user` to mirror this adapter. Reproduce the semantics by hand: a non-2xx status throws and leaves the cached user in place, retry 3 times with backoff, and treat the value as fresh for 60 s. `HTTPCookieStorage` attaches the session cookie automatically. A `Codable` enum rejects unknown roles, unlike the unvalidated cast in the source.
- **Compose**: Use a `ViewModel` exposing `StateFlow<StatusUser?>`, collected with `collectAsStateWithLifecycle()`, and load with Ktor or Retrofit plus `kotlinx.serialization`. A single repository-level `MutableStateFlow` gives the shared-cache behavior. Implement retry with `retryWhen` and exponential delay, and throw on non-2xx without clearing the cached value. Cookies need a `CookieJar` (OkHttp) or `HttpCookies` (Ktor).
- **React/Web**: Source platform. `src/hooks/useStatusUser.ts` is a one-line projection, `useStatusSession().user`. The contract lives in `src/header-auth.ts`: `STATUS_AUTH_QUERY_KEY`, `fetchStatusUser` (throws on non-OK) and the session hook's `useQuery` options `{ staleTime: 60_000, retry: 3 }`. React Query v5 keeps `data` when a refetch errors, and that is what `keep-last-known-session` relies on.
- **AppKit / UIKit**: Use a singleton session service holding `user: StatusUser?` and publishing changes through Combine `@Published` or `NotificationCenter`, with `URLSession` and `JSONDecoder` for the request. View controllers subscribe in `viewDidLoad`. Deduplicate simultaneous loads by storing one in-flight `Task` and awaiting it.
- **WinUI 3**: Start from a singleton `SessionService` view model implementing `INotifyPropertyChanged` with a `StatusUser? User` property. Pages bind it with `{x:Bind Session.User, Mode=OneWay}` and derive role gates such as `IsAdmin => User?.Role == Role.Admin`. Load with a shared `HttpClient` created over an `HttpClientHandler` whose `CookieContainer` holds `status_auth` (a browser attaches the cookie for you; .NET needs the handler). Deserialize with `System.Text.Json` (`JsonSerializer.Deserialize<AuthMeResponse>` with `JsonStringEnumConverter` for `role`). Call `EnsureSuccessStatusCode()` or check `IsSuccessStatusCode` and throw, so a non-2xx never sets `User = null`. Wrap the load in a `Task`-returning method that caches one in-flight `Task<StatusUser?>` to deduplicate concurrent callers, retries 3 times with `Task.Delay` backoff (1 s, 2 s, 4 s), and skips the request if the last success was under 60 s ago. Marshal the `User` assignment to the UI thread with `DispatcherQueue.TryEnqueue`. There is no React Query equivalent, so refetch on focus and reconnect has to be wired explicitly (`Window.Activated`, `NetworkInformation.NetworkStatusChanged`).

