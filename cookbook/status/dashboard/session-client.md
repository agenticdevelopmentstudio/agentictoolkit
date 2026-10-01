---
id: 5935b39d-9451-48c1-8b99-bd510d66d1a0
title: Session Client
domain: agentictoolkit://cookbook/status/dashboard/session-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status dashboard's session client (auth/me fetch, a shared cached session,
  host header auth seam) and its backend wire DTO types.
platforms:
- typescript
- web
tags:
- status
- auth
- api-client
- monitoring
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
related:
- agentictoolkit://cookbook/status/dashboard/api
- agentictoolkit://cookbook/status/service/auth
- agentictoolkit://cookbook/status/service/monitor/types
references:
- packages/web/packages/status-web/src/header-auth.ts (agentictoolkit)
- packages/web/packages/status-web/src/header-auth.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/types.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Session Client

## Overview

Two top-level pieces of logic: the session-and-header-auth logic and the wire-types module.

The session-and-header-auth logic is the dashboard's client-side view of the status backend's
**local** session (the `status_auth` httpOnly cookie set by `/api/auth/login`,
not adh SSO). Because the cookie is httpOnly, the client learns the session only
by asking `GET {base}/auth/me`. It exports the session-fetch function (one
request, strict "non-OK is infrastructure trouble, not sign-out" semantics),
the session hook (the one shared cache entry under
the session query key, read by the header seam, the board gate and the
landing page), and the header-auth hook (the injectable auth source a host
passes to its own header component). It declares its own
header-auth state shape so the package carries no dependency on any
site's header package. It is published as its own subpath and
re-exported from the package barrel.

The wire-types module is type-only: the wire DTOs the dashboard reads from the status
backend (the status response, the uptime response, a deployment record,
the history response, the integrations report and their element types). It has no
runtime code and is imported by the package's own components and hooks; it is
not re-exported from the barrel.

## Behavioral Requirements

### Session data shapes

- **status-user-shape**: A session user MUST carry `email` (a string), an optional `displayName` that MAY be a string, `null`, or absent, and `role` restricted to exactly `"pending"`, `"viewer"`, or `"admin"`.
- **header-auth-state-shape**: The header-auth state shape MUST carry `user` (an object with `name`, a string) or `null`, plus the optional fields `authLoading` (boolean), `loginHref` (string), `signupHref` (string), and `onLogout` (a zero-argument callback) — the common subset a host header's auth slot takes, declared locally rather than imported.
- **header-auth-source-type**: The header-auth source type MUST be a zero-argument hook type returning the header-auth state shape; the header-auth hook MUST be a stable module-level constant of that type so a host can pass it to its header unchanged.
- **session-query-key**: The session query key MUST be the fixed, order-preserving pair `["status-auth-me"]`, and it MUST be the only key under which the session is cached.
- **session-key-invalidation-precondition**: A login or signup flow that sets the session cookie MUST invalidate the session query key afterwards; this is documented as a caller obligation because the login page caches a fresh signed-out result and the post-login navigation is client-side. This logic does not perform the invalidation itself.

### The session-fetch function

- **auth-me-url**: The session-fetch function MUST request the URL the API client resolves for `/auth/me` (with the default base `"/api"` this is `"/api/auth/me"`).
- **auth-me-transport**: The session-fetch function MUST issue the request through its injectable transport argument (defaulting to the platform's fetch) with no request-options object — a plain `GET` with no custom headers, no explicit credentials option and no abort signal — and MUST NOT route it through the API client's own request method.
- **auth-me-single-request**: Each call to the session-fetch function MUST issue exactly one request; it MUST NOT retry on its own (retry belongs to the session hook).
- **auth-me-non-ok-throws**: When the response's `ok` is false, the session-fetch function MUST reject with an error whose message is `auth/me unavailable (HTTP <status>)`, and it MUST NOT resolve `null` for any non-OK status (the backend never answers this route with a 401, so any non-OK is infrastructure trouble, not sign-out).
- **auth-me-user-resolves**: When the response is OK and its JSON body's `user` field is an object, the session-fetch function MUST resolve that object unchanged.
- **auth-me-signed-out-resolves-null**: When the response is OK and its JSON body's `user` field is `null` or absent, the session-fetch function MUST resolve `null`.
- **auth-me-network-failure-propagates**: When the transport rejects (connection failure, DNS failure), the session-fetch function MUST reject with that same error, unwrapped.
- **auth-me-body-parse-failure-propagates**: When an OK response's body is not valid JSON, the session-fetch function MUST reject with the error the body-parsing step raises.
- **auth-me-no-shape-validation**: The session-fetch function MUST NOT validate the fields of a returned `user` object at runtime; the body is trusted as given, and a `user` missing `email` or carrying an unlisted `role` is returned as-is.

### The session hook

- **session-query-config**: The session hook MUST read the session through one cached query keyed by the session query key, whose query function is the session-fetch function (given the current API-client instance), a staleness window of 60,000 ms, and up to 3 retries (up to four attempts per fetch, with the default exponential backoff).
- **session-query-dedupe**: Every concurrent consumer of the session hook MUST share the single cache entry for the session query key, so simultaneous mounts issue one `/auth/me` request, not one per consumer.
- **session-return-shape**: The session hook MUST return `user` and `isPending`, where `user` is the cached data or `null` when no data exists, and `isPending` is true only while the first load is in flight with no data yet.
- **session-kept-across-errors**: When a refetch fails after data has been cached, the session hook MUST keep returning the last cached user; a failed refetch MUST NOT change `user` to `null`. Sign-out is observed only when a fetch resolves a definitive `null`.
- **session-error-not-exposed**: The session hook MUST NOT expose the query's error or error state to its caller; only `user` and `isPending` are returned.
- **first-load-failure-projection**: NEEDS REVIEW: Not implemented in source. When the very first `/auth/me` load fails all four attempts, `isPending` becomes false with no cached data, so the session hook returns `user: null` — indistinguishable from a definitive signed-out answer — and the header shows login/signup links; this contradicts the documented rule that "sign-out only ever comes from a definitive null user", and the hook exposes no error signal to tell the two apart. Settling this needs a decision from the package owner on whether a cold-load failure should surface an error state (for example, an explicit error flag) or remain projected to signed-out.
- **session-query-defaults-inherited**: The session hook MUST NOT override any caching option beyond those named above; refetch-on-focus, refetch-on-reconnect and cache garbage-collection timing are whatever the host's shared query client defaults are.
- **session-client-resolution**: The session hook MUST resolve its API client through the nearest provider's client, or the same-origin default client when none is mounted.

### The header-auth hook

- **header-signed-out-state**: When the session hook returns a `null` user, the header-auth hook MUST return exactly `user: null`, `authLoading` equal to the session hook's `isPending`, `loginHref: "/login"`, `signupHref: "/signup"`.
- **header-loading-spinner**: While the first session load is in flight, the header-auth hook MUST return `authLoading: true` together with `user: null`, so the host shows a spinner rather than flashing login links.
- **header-signed-in-name**: When a user is present, the header-auth hook MUST return `user.name` equal to `displayName` when it is a non-empty string, and otherwise (`null`, absent, or `""`) equal to `email`.
- **header-signed-in-fields**: When a user is present, the header-auth hook MUST return only `user` and `onLogout`; `authLoading`, `loginHref` and `signupHref` MUST be absent.
- **header-role-not-projected**: The header-auth hook MUST NOT include the user's `role` or `email` (other than as the name fallback) in the returned state.
- **logout-request**: Invoking `onLogout` MUST send one `POST` to `/auth/logout` through the API client's own request method (with the default base, `"/api/auth/logout"`), with no body and no idempotency key; clearing the cookie is the backend's responsibility (see the status server's auth component).
- **logout-navigation**: After the logout request settles — fulfilled with any status, including non-OK, or rejected — `onLogout` MUST navigate the whole page to `"/"`, the public landing page.
- **logout-outcome-ignored**: `onLogout` MUST NOT inspect the logout response's status and MUST NOT invalidate the session query key; the full-page navigation reloads the session from `/auth/me`, so a logout the backend did not honour shows the user still signed in after the reload.
- **logout-rejection-unhandled**: When the logout request rejects, the rejection MUST propagate as an unhandled rejection rather than being caught by `onLogout`.
- **no-switch-href**: The header-auth hook MUST NOT supply a site-switch resolver, so a host's site switcher navigates straight to sibling sites instead of through an adh-SSO redirect.

### Wire DTOs

- **types-module-type-only**: The wire-types module MUST contain only type declarations and type re-exports; it MUST NOT emit runtime code or perform runtime validation of any payload.
- **types-reexports**: The wire-types module MUST re-export a health status, an overall status and a deploy status from the health-classification, overall-status and deploy-status logic, respectively.
- **health-status-values**: A health status MUST be exactly one of `"healthy"`, `"degraded"` or `"down"`; a service status record's `status` and a history check's `status` MUST additionally admit `"unknown"`, while a day's uptime record's `status` MUST NOT.
- **overall-status-values**: An overall status (the type of the status response's `overall` field) MUST be exactly one of `"operational"`, `"degraded"`, `"major_outage"` or `"unknown"`.
- **deploy-status-values**: A deployment record's `status` MUST be a deploy status — one of `"success"`, `"failed"`, `"building"`, `"queued"`, `"canceled"` or `"unknown"` — derived server-side by the status-combining logic; its `buildPhase` MUST be a build phase — one of `"queued"`, `"building"`, `"built"`, `"failed"`, `"canceled"` or `"unknown"` — or `null` when the platform reports no build lifecycle; its `deployPhase` MUST be a deploy phase — one of `"none"`, `"deploying"`, `"deployed"`, `"failed"` or `"unknown"` — and is never null.
- **service-status-dto**: A service status record MUST carry `slug`, `group`, `name`, `url` and `environment` as non-null strings, and `platform`, `deployProject`, `responseTimeMs`, `statusCode`, `error` and `lastCheckedAt` as nullable fields (`platform` here is the explicit deploy target used as a correlation key, not a UI or OS platform).
- **status-response**: The status response MUST carry `overall`, a `services` list of service status records, and a `checkedAt` string.
- **uptime-shapes**: The uptime response MUST carry a `services` list of per-service uptime summaries and a `days` count; each service's uptime summary MUST carry `slug`, `name`, a nullable `uptimePercent`, a `totalChecks` count and a `daily` list of per-day uptime records; each day's uptime record MUST carry `day`, `status` and a nullable `uptimePercent`.
- **deployment-tier-rendering**: A consumer MUST render a deployment record's `tier` field (the logical tier derived server-side by the deploy-environment logic; `null` for a row that deploys no tier, such as a preview) as the deployment's tier, and MUST NOT render `environment` in its place, because `environment` is the provider's promotion target and reads `"production"` for every Vercel project; the client owns no copy of the tier derivation.
- **deployment-nullable-fields**: A deployment record MUST carry `id`, `platform`, `projectName` and `createdAt` as non-null strings, and `environment`, `tier`, `commitHash`, `commitMessage`, `branch`, `commitRepo` (`"owner/name"`), `url`, `errorText` and `liveHost` as nullable strings.
- **deployment-error-text**: A deployment record's `errorText` MUST be the provider's failure reason for a failed deploy (Vercel's `errorMessage` field or a Railway build-log tail) and `null` otherwise, and consumers MUST render it verbatim.
- **deployment-phase-confirmed-at**: A deployment record's `phaseConfirmedAt` MUST be an optional ISO timestamp of when the phases were last confirmed against provider truth; when it is absent (older backend or persisted pre-upgrade rows), consumers MUST treat `createdAt` as its floor.
- **history-shapes**: The history response MUST carry `service` (a string), `hours` (a number) and a `checks` list of history check records; each history check record MUST carry `status`, nullable `responseTimeMs`, `statusCode` and `error`, and a non-null `checkedAt` string.
- **check-state-values**: A check state MUST be exactly one of `"ok"`, `"warn"` or `"error"`, and it MUST be the type of both a check's `state` field and the integrations report's `overall` field.
- **integration-check-shape**: A check MUST carry `id`, `label`, `configured` (boolean), `ok` (boolean), `state` and `detail`, plus the optional `missingEnv` (a list of strings — expected env vars found unset, named exactly; omitted or empty when nothing is missing), `unreachable` (boolean — no HTTP response at all, debounced backend-side) and `correlated` (boolean — unreachable together with other providers in the same run, judged monitor-side connectivity).
- **integrations-response**: The integrations report MUST carry `generatedAt` (a string), `overall` and a `checks` list of checks.

### Concurrency and side effects

- **single-threaded-ordering**: All of this logic's runtime code MUST run without concurrent execution (see Platform Notes for what guarantees this); there is no parallel mutation to order.
- **side-effects**: The only side effects in this logic MUST be the `GET /auth/me` request, the `POST /auth/logout` request, and the full-page navigation to `/`; nothing is written to storage, cookies or logs by this logic.

## Appearance

Not applicable — this is headless session logic and a wire-types module, not a visual component.

## States

Not applicable — this is headless session logic and a wire-types module, not a visual component.

## Accessibility

Not applicable — this is headless session logic and a wire-types module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-src-001 | auth-me-user-resolves (see Platform Notes) | the session-fetch function called with a default API client and a transport that resolves HTTP 200 with body `{"user":{"email":"a@b.c","displayName":"A","role":"admin"}}` | resolves to a user with `email: "a@b.c"`, `displayName: "A"`, `role: "admin"` |
| status-web-src-002 | auth-me-signed-out-resolves-null (see Platform Notes) | the session-fetch function called with a transport that resolves HTTP 200 with body `{"user":null}` | resolves `null` |
| status-web-src-003 | auth-me-non-ok-throws (see Platform Notes) | the session-fetch function called with a transport that resolves HTTP 500 with body `{}` | rejects with an error whose message is exactly `auth/me unavailable (HTTP 500)` |
| status-web-src-004 | auth-me-network-failure-propagates (see Platform Notes) | the session-fetch function called with a transport that rejects with a runtime error whose message is `fetch failed` | rejects with that same error (message `fetch failed`) |
| status-web-src-005 | auth-me-signed-out-resolves-null | the session-fetch function called with a transport that resolves HTTP 200 with body `{}` | resolves `null` (`user` absent reads as signed-out) |
| status-web-src-006 | auth-me-non-ok-throws | the session-fetch function called with a transport that resolves HTTP 401 with body `{"user":null}` | rejects with `auth/me unavailable (HTTP 401)`; never resolves `null` |
| status-web-src-007 | auth-me-url, auth-me-transport | the session-fetch function called with an API client configured with base path `/proxy`, and a recording transport | the transport is called once with the single argument `"/proxy/auth/me"` and no request-options object |
| status-web-src-008 | auth-me-body-parse-failure-propagates | the session-fetch function called with a transport that resolves HTTP 200 with a body that is not valid JSON | rejects with the body-parsing error |
| status-web-src-009 | session-query-key | reading the session query key | deep-equals the pair `["status-auth-me"]` |
| status-web-src-010 | header-signed-out-state, header-loading-spinner | the header-auth hook, when the session hook yields `user: null` and `isPending: true` | returns `user: null`, `authLoading: true`, `loginHref: "/login"`, `signupHref: "/signup"` |
| status-web-src-011 | header-signed-out-state | the header-auth hook, when the session hook yields `user: null` and `isPending: false` | returns `user: null`, `authLoading: false`, `loginHref: "/login"`, `signupHref: "/signup"` |
| status-web-src-012 | header-signed-in-name, header-signed-in-fields | the header-auth hook, when the session hook yields a user with `email: "a@b.c"`, `displayName: "Ann"`, `role: "viewer"` | returns `user: { name: "Ann" }`, an `onLogout` callback, and no `authLoading`/`loginHref`/`signupHref` keys |
| status-web-src-013 | header-signed-in-name | the header-auth hook, when the session hook yields a user with `email: "a@b.c"`, `displayName: ""`, `role: "viewer"` | `user.name` equals `"a@b.c"` |
| status-web-src-014 | header-signed-in-name | the header-auth hook, when the session hook yields a user with `email: "a@b.c"`, `displayName: null`, `role: "admin"` | `user.name` equals `"a@b.c"` |
| status-web-src-015 | logout-request, logout-navigation | invoking `onLogout` in a signed-in state with the default client, when the request resolves HTTP 200 | one `POST` request to `/api/auth/logout`; afterwards the page navigates to `/` |
| status-web-src-016 | logout-navigation, logout-outcome-ignored | invoking `onLogout` as above, when the request resolves HTTP 500 | the page still navigates to `/`; no error thrown synchronously; the session query key is not invalidated |
| status-web-src-017 | logout-navigation, logout-rejection-unhandled | invoking `onLogout` as above, when the request rejects | the page still navigates to `/`; an unhandled rejection carrying that error is raised |
| status-web-src-018 | session-kept-across-errors | the session hook, with a cached user and a refetch whose four attempts all reject with HTTP 503 | still returns that cached user with `isPending: false` |
| status-web-src-019 | session-query-dedupe | two consumers of the session hook mounting together in the same render with an empty cache | exactly one `/auth/me` request is issued |
| status-web-src-020 | session-query-config | the session hook on first load, when every attempt rejects | `/auth/me` is attempted 4 times (the initial attempt plus 3 retries) before the query settles into an error state |

The wire-DTO requirements above are compile-time shapes with no runtime behavior; a port verifies them with type-level assertions (for example, assigning `"unknown"` to a day's uptime record's `status` field MUST fail to compile, while assigning it to a service status record's `status` field MUST compile) rather than runtime vectors.

## Edge Cases

- **Signed-out answer vs. failure**: HTTP 200 with a `null` user → the session-fetch function resolves `null` (MUST); any non-OK status, including 401 and 403 → rejects (MUST). Signed-out is never inferred from a status code.
- **Empty or missing body field**: HTTP 200 with an empty body → resolves `null`, read as signed-out (MUST; an absent `user` field is treated the same as an explicit `null`).
- **Malformed body**: HTTP 200 with non-JSON body → rejects with the parse error; the session hook's retry behavior still applies (MUST).
- **Partial user object**: HTTP 200 with a user object carrying only `role` (no `email`, no `displayName`) → resolved unchanged (MUST, per auth-me-no-shape-validation); the header-auth hook then returns `user.name` as absent despite the shape declaring it a required string.
- **Empty display name**: `displayName: ""` → header name falls back to `email` (MUST; an empty string, not just an absent or null value, triggers the fallback).
- **Transient failure with cached session**: backend restart, proxy 500, or network blip after a successful load → cached user is kept and the fetch retried up to 3 times (MUST); the header never flashes signed-out.
- **Cold-load failure**: backend unreachable on the very first load → after four failed attempts the hook returns a `null` user with `isPending: false`, and the header shows login/signup links; see the open question on first-load-failure-projection.
- **Offline / disconnected**: the transport rejects → treated like any failure above (error kept out of `user`, retried); no offline detection of its own.
- **Timeout**: no request timeout or abort signal is set on `/auth/me` or `/auth/logout` (MUST NOT be assumed); a hung request stays pending until the platform gives up, and on first load `isPending` stays true (header spinner) for that whole time.
- **Cancellation**: the session-fetch function accepts no abort signal; the session hook's own cancellation signal is not forwarded, so an unmounted query's in-flight request is not aborted.
- **Logout failure**: logout POST returns non-OK or rejects → navigation to `/` happens anyway (MUST); on reload the session is re-read, so an un-cleared cookie shows the user still signed in. A rejection surfaces as an unhandled rejection.
- **Logout double-invoke**: calling `onLogout` twice issues two POSTs; each navigates to `/` when it settles. No guard exists.
- **Concurrent consumers**: header, board gate and landing page mounting at once share one query and one request (MUST).
- **Login without invalidation**: a login flow that sets the cookie but does not invalidate the session query key leaves the cached signed-out result in place for up to the 60,000 ms staleness window (documented caller obligation).
- **Injected client transport**: an API client built with a custom transport is honoured by `onLogout` (via the client's own request method) but not by the session hook, whose call to the session-fetch function uses the platform's default transport with only the client's URL resolution.
- **Optional DTO fields**: `phaseConfirmedAt` absent → consumers use `createdAt`; `missingEnv`, `unreachable`, `correlated` absent → treated as empty/false by consumers.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| the API-client argument (to the session-fetch function) | the API client | none — required | Resolves the `/auth/me` URL. |
| the transport argument (to the session-fetch function) | a fetch-like function | the platform's default fetch | Injectable transport for tests. |
| the API-client provider's client / base path | the API client / a string | same-origin default client, base `"/api"` | Supplies the client both hooks obtain from the API-client hook (see the dashboard's API client component). |
| the staleness window | a number of milliseconds | `60,000` | Hard-coded in the session hook; not caller-configurable. |
| the retry count | a number | `3` | Hard-coded in the session hook; not caller-configurable. |
| the shared query client | the caching client this logic relies on | host-provided | Must be mounted by the host; supplies all caching defaults the query does not override. |
| `loginHref` / `signupHref` | strings | `"/login"` / `"/signup"` | Hard-coded in the header-auth hook. |
| Post-logout destination | a string | `"/"` | Hard-coded in the logout callback. |

## Deep Linking

Not applicable: this logic constructs no deep links; the only paths it names are the fixed `"/login"`, `"/signup"` and `"/"` hrefs a host header renders, which are site routes owned by the host, not deep-link patterns.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not an i18n key) | `auth/me unavailable (HTTP <status>)` | The session-fetch function's thrown error message on a non-OK response; English-only, never sourced from a localization resource. It is not rendered by this logic (the session hook does not expose query errors). |

## Accessibility Options

Not applicable — this is headless session logic and a wire-types module, not a visual component; it renders nothing and reads no motion, contrast or color setting.

## Feature Flags

Not applicable: neither piece of this logic reads a feature-flag key; every path always executes.

## Analytics

Not applicable: neither piece of this logic calls the package's telemetry client or any analytics API.

## Privacy

- **Data collected**: the signed-in user's `email`, optional `displayName`, and `role`, returned by `/auth/me`.
- **Storage**: held only in the host's in-memory cache under the session query key; nothing is written to persistent browser storage, cookies or disk by this logic. The session credential itself is the `status_auth` httpOnly cookie, which client code cannot read — this logic never touches it.
- **Transmission**: the browser attaches the cookie to the same-origin `/auth/me` and `/auth/logout` requests; this logic sends no credential or personal data in a URL or body. The header seam exposes only a display name (`displayName` or, failing that, `email`).
- **Retention**: in memory until the page unloads or the cache garbage-collects the entry; `onLogout`'s full-page navigation discards the cache.

## Logging

Not applicable: neither piece of this logic calls a console or logging API; the session-fetch function's thrown error is the only signal, and it is held by the session hook rather than logged here.

## Platform Notes

- **SwiftUI**: model `fetchStatusUser` as an `async throws` function over `URLSession.data(from:)` that throws on any non-2xx `HTTPURLResponse` and decodes `{ user: StatusUser? }` with `JSONDecoder`; `HTTPCookieStorage` attaches the session cookie. Replace React Query with an `@Observable @MainActor` session store holding `user` and `isPending`, a 60-second staleness timestamp, and an explicit retry loop (3 retries with exponential backoff) that keeps the last user on failure. Expose the header state as a computed property; `onLogout` becomes an `async` method that POSTs then resets navigation regardless of outcome. DTOs become `Codable`, `Sendable` structs with `String` enums for the unions.
- **Compose**: Ktor or Retrofit call returning `StatusUser?`, throwing on non-2xx; a `ViewModel` exposing `StateFlow<SessionState>` shared app-wide (Hilt singleton) replaces the shared query key, with `retry(3)` plus delay backoff on the `Flow` and `stateIn` retaining the last value on error. DTOs become `@Serializable data class`es with `enum class` for the unions (`@SerialName("major_outage")`).
- **React/Web**: the source. `header-auth.ts` uses `@tanstack/react-query`'s `useQuery` and the package's `useStatusApi` context hook, carries `"use client"` (so it runs only inside a React client component, never during server rendering), and is tested with Vitest in `header-auth.test.ts` by injecting `fetchImpl` — vectors 001–004 above are traced to that suite. `types.ts` is compile-time TypeScript only. The single-threaded JavaScript runtime is what backs the single-threaded-ordering requirement above; nothing here needs an explicit lock or actor. Neither file calls the package's telemetry client (`src/telemetry/`).
- **AppKit / UIKit**: the same `URLSession` fetch and a shared session-store singleton (`ObservableObject` or Combine `CurrentValueSubject`) the header view controller observes; logout resets the window's root to the landing screen instead of assigning `window.location`.
- **WinUI 3**: implement `FetchStatusUserAsync` over a shared `HttpClient` (with an `HttpClientHandler` whose `CookieContainer` carries the session cookie), calling `EnsureSuccessStatusCode()` semantics manually to throw on any non-2xx and `System.Text.Json` (`JsonSerializer.DeserializeAsync<AuthMeBody>`) for the body. Replace React Query with a singleton `SessionService : INotifyPropertyChanged` exposing `User` and `IsPending`, a `DateTimeOffset` staleness check for the 60-second window, and a retry loop (`for` 4 attempts with `Task.Delay` exponential backoff) that leaves `User` untouched on failure; concurrent callers share one in-flight `Task<StatusUser?>` to reproduce the query dedupe. The header binds to a `HeaderAuthState` view-model (`x:Bind` to `User.Name`, a `ProgressRing` bound to `AuthLoading`, `HyperlinkButton`s for login/signup, a `RelayCommand` for logout). Logout POSTs via `HttpClient.PostAsync` inside `try/finally` and then navigates the root `Frame` to the landing page; unlike the source, .NET surfaces an unobserved faulted `Task` only via `TaskScheduler.UnobservedTaskException`. DTOs become `record`s with `[JsonPropertyName]` and string-valued enums via `JsonStringEnumConverter`; lists surface as `ObservableCollection<T>` only where bound. `Windows.Storage` has no role — nothing is persisted.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/header-auth.ts` |
| web | `packages/web/packages/status-web/src/types.ts` |

## Design Decisions

**Decision**: `fetchStatusUser` throws on every non-OK response instead of mapping 401/403 to signed-out.
**Rationale**: the doc comment states the backend never answers `/auth/me` with a 401 — signed-out is a definitive 200 `{ user: null }` — so a non-OK is infrastructure trouble; throwing lets React Query keep the last-known session and retry instead of flashing the signed-out header at a logged-in user (the "suddenly logged out" bug).
**Approved**: pending

**Decision**: one React-Query key, `["status-auth-me"]`, is the only session cache, shared by header, board gate and landing page.
**Rationale**: the doc comment on `useStatusUser` states the single key dedupes across every consumer; the doc comment on `STATUS_AUTH_QUERY_KEY` makes login/signup responsible for invalidating it.
**Approved**: pending

**Decision**: `fetchStatusUser` resolves its URL through `api.url` but sends through its own `fetchImpl` (default global `fetch`), not `api.fetch`.
**Rationale**: the doc comment says `fetchImpl` stays injectable for tests while "the URL itself is always resolved through the caller's `StatusApiClient`". The consequence is that a client-level `fetch` override does not reach the session read, while `onLogout` does use `api.fetch`.
**Approved**: pending

**Decision**: `StatusHeaderAuthState` is declared in this package rather than imported from a header package.
**Rationale**: the doc comment states the package carries no dependency on any site's chrome; the shape is the common subset every header auth slot takes.
**Approved**: pending

**Decision**: logout navigates with a full-page `window.location.href = "/"` in `.finally`, without checking the response or invalidating the query.
**Rationale**: a full reload discards the React-Query cache and re-reads `/auth/me`, so the post-logout state always reflects the backend's truth; the source accepts an unhandled rejection when the POST itself fails.
**Approved**: pending

**Decision**: no `resolveSwitchHref` is supplied to the host header.
**Rationale**: the doc comment states a silent adh-SSO redirect is wrong for this non-adh local session, so the site switcher navigates straight to siblings.
**Approved**: pending

**Decision**: `DeploymentDTO.tier` is computed server-side and the client holds no copy of the derivation.
**Rationale**: the field's doc comment says to render `tier`, never `environment` (which reads "production" for every Vercel project), and that the client deliberately owns no copy of `deployEnv`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | passed | Access Patterns |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | Reliability |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [secure-data-storage](agenticdevelopercookbook://compliance/privacy-and-data#secure-data-storage) | passed | Privacy and Data |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | partial | Internationalization |

`separation-of-concerns` passes: the session fetch is a pure async function over an injected client and transport, the caching policy lives in one hook, the header projection in another, and the DTOs are a type-only module; neither file renders anything. `unit-test-coverage` is `partial`: `header-auth.test.ts` covers `fetchStatusUser`'s four outcomes (user, signed-out, 5xx, network failure), but `useStatusUser`, `useStatusHeaderAuth` and `onLogout` have no tests. `explicit-error-handling` is `partial`: non-OK `/auth/me` responses become an explicit `Error`, but `useStatusUser` drops the query's error state, so a cold-load failure reads as signed-out (the open question on first-load-failure-projection), and a rejected logout POST escapes as an unhandled rejection. `error-response-handling` passes: every non-OK `/auth/me` status is treated uniformly as a failure carrying the status code, never misread as sign-out. `retry-with-backoff` passes: the session query retries 3 times with React Query's default exponential backoff. `timeout-configuration` fails: neither request sets a timeout or abort signal. `graceful-degradation` is `partial`: a cached session survives backend blips unchanged, but a failure on the first load degrades to a signed-out header with no error indication. `secure-storage` passes: the credential is an httpOnly cookie the client never reads or stores. `secure-data-storage` passes: the user record lives only in in-memory cache, never in persistent storage. `data-minimization` passes: the header seam receives only a display name, not the role or (unless it is the fallback) the email. `no-hardcoded-strings` is `partial`: the thrown error message is English-only, though this module never displays it.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
