---
id: 5935b39d-9451-48c1-8b99-bd510d66d1a0
title: Status Web Src
domain: agentictoolkit://recipes/status-web-src
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The status dashboard's session client (auth/me fetch, shared React-Query
  session, host header auth seam) and its backend wire DTO types.
platforms:
- typescript
- web
tags:
- status
- web
- auth
- api-client
- monitoring
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
related:
- agentictoolkit://recipes/status-web-api
- agentictoolkit://recipes/status-server-auth
- agentictoolkit://recipes/status-server-monitor-types
references:
- packages/web/packages/status-web/src/header-auth.ts (agentictoolkit)
- packages/web/packages/status-web/src/header-auth.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/types.ts (agentictoolkit)
- packages/web/packages/status-web/src/api/client.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Web Src

## Overview

The two top-level modules of the `status-web` package's `src/` root.

`header-auth.ts` is the dashboard's client-side view of the status backend's
**local** session (the `status_auth` httpOnly cookie set by `/api/auth/login`,
not adh SSO). Because the cookie is httpOnly, the client learns the session only
by asking `GET {base}/auth/me`. The module exports `fetchStatusUser` (one
request, strict "non-OK is infrastructure trouble, not sign-out" semantics),
`useStatusUser` (the one shared React-Query cache entry under
`STATUS_AUTH_QUERY_KEY`, read by the header seam, the board gate and the
landing page), and `useStatusHeaderAuth` (the injectable auth source a host
passes to its own header component). It declares its own
`StatusHeaderAuthState` shape so the package carries no dependency on any
site's header package. It is published as the `./header-auth` subpath and
re-exported from the package barrel.

`types.ts` is type-only: the wire DTOs the dashboard reads from the status
backend (`StatusResponse`, `UptimeResponse`, `DeploymentDTO`,
`HistoryResponse`, `IntegrationsResponse` and their element types). It has no
runtime code and is imported by the package's own components and hooks; it is
not re-exported from the barrel.

## Behavioral Requirements

### Session data shapes (`header-auth.ts`)

- **status-user-shape**: `StatusUser` MUST carry `email: string`, an optional `displayName` that MAY be `string`, `null`, or absent, and `role` restricted to exactly `"pending"`, `"viewer"`, or `"admin"`.
- **header-auth-state-shape**: `StatusHeaderAuthState` MUST carry `user: { name: string } | null` plus the optional fields `authLoading?: boolean`, `loginHref?: string`, `signupHref?: string`, and `onLogout?: () => void` — the common subset a host header's auth slot takes, declared locally rather than imported.
- **header-auth-source-type**: `StatusHeaderAuthSource` MUST be a zero-argument hook type returning `StatusHeaderAuthState`; `useStatusHeaderAuth` MUST be a stable module-level constant of that type so a host can pass it to its header unchanged.
- **session-query-key**: `STATUS_AUTH_QUERY_KEY` MUST be the readonly tuple `["status-auth-me"]`, and it MUST be the only query key under which the session is cached.
- **session-key-invalidation-precondition**: A login or signup flow that sets the session cookie MUST invalidate `STATUS_AUTH_QUERY_KEY` afterwards; the doc comment on the constant documents this as a caller obligation because the login page caches a fresh `{ user: null }` and the post-login navigation is client-side. This module does not perform the invalidation itself.

### `fetchStatusUser(api, fetchImpl = fetch)`

- **auth-me-url**: `fetchStatusUser` MUST request the URL `api.url("/auth/me")` — the path resolved through the caller's `StatusApiClient` (with the default base `"/api"` this is `"/api/auth/me"`).
- **auth-me-transport**: `fetchStatusUser` MUST issue the request through its `fetchImpl` argument (defaulting to the global `fetch`) with no `init` object — a plain `GET` with no custom headers, no explicit `credentials` option and no abort signal — and MUST NOT route it through `api.fetch`.
- **auth-me-single-request**: Each call to `fetchStatusUser` MUST issue exactly one request; it MUST NOT retry on its own (retry belongs to `useStatusUser`).
- **auth-me-non-ok-throws**: When the response's `ok` is false, `fetchStatusUser` MUST reject with an `Error` whose message is `auth/me unavailable (HTTP <status>)`, and it MUST NOT resolve `null` for any non-OK status (the backend never answers this route with a 401, so any non-OK is infrastructure trouble, not sign-out).
- **auth-me-user-resolves**: When the response is OK and its JSON body's `user` is an object, `fetchStatusUser` MUST resolve that object unchanged.
- **auth-me-signed-out-resolves-null**: When the response is OK and its JSON body's `user` is `null` or absent, `fetchStatusUser` MUST resolve `null`.
- **auth-me-network-failure-propagates**: When `fetchImpl` rejects (connection failure, DNS failure), `fetchStatusUser` MUST reject with that same error, unwrapped.
- **auth-me-body-parse-failure-propagates**: When an OK response's body is not valid JSON, `fetchStatusUser` MUST reject with the error `res.json()` raises.
- **auth-me-no-shape-validation**: `fetchStatusUser` MUST NOT validate the fields of a returned `user` object at runtime; the body is cast to `{ user: StatusUser | null }` and a `user` missing `email` or carrying an unlisted `role` is returned as-is.

### `useStatusUser()`

- **session-query-config**: `useStatusUser` MUST read the session through one React-Query query with key `STATUS_AUTH_QUERY_KEY`, query function `fetchStatusUser(api)` (where `api` is `useStatusApi()`), `staleTime` of 60,000 ms, and `retry` of 3 (up to four attempts per fetch, with React Query's default exponential backoff).
- **session-query-dedupe**: Every concurrent consumer of `useStatusUser` MUST share the single cache entry for `STATUS_AUTH_QUERY_KEY`, so simultaneous mounts issue one `/auth/me` request, not one per consumer.
- **session-return-shape**: `useStatusUser` MUST return `{ user, isPending }`, where `user` is the cached data or `null` when no data exists, and `isPending` is true only while the first load is in flight with no data yet.
- **session-kept-across-errors**: When a refetch fails after data has been cached, `useStatusUser` MUST keep returning the last cached user; a failed refetch MUST NOT change `user` to `null`. Sign-out is observed only when a fetch resolves a definitive `null`.
- **session-error-not-exposed**: `useStatusUser` MUST NOT expose the query's error or error state to its caller; only `user` and `isPending` are returned.
- **first-load-failure-projection**: NEEDS REVIEW: Not implemented in source. When the very first `/auth/me` load fails all four attempts, `isPending` becomes false with no cached data, so `useStatusUser` returns `user: null` — indistinguishable from a definitive signed-out answer — and the header shows login/signup links; this contradicts the doc comment that "sign-out only ever comes from a definitive `{ user: null }`", and the hook exposes no error signal to tell the two apart. Settling this needs a decision from the package owner on whether a cold-load failure should surface an error state (e.g. by returning `isError`) or remain projected to signed-out.
- **session-query-defaults-inherited**: `useStatusUser` MUST NOT override any other React-Query option; refetch-on-focus, refetch-on-reconnect and cache garbage-collection timing are whatever the host's `QueryClient` defaults are.
- **session-client-resolution**: `useStatusUser` MUST resolve its `StatusApiClient` through `useStatusApi()` — the nearest `StatusApiProvider`'s client, or the same-origin default client when none is mounted.

### `useStatusHeaderAuth()`

- **header-signed-out-state**: When `useStatusUser` returns `user: null`, `useStatusHeaderAuth` MUST return exactly `{ user: null, authLoading: isPending, loginHref: "/login", signupHref: "/signup" }`.
- **header-loading-spinner**: While the first session load is in flight, `useStatusHeaderAuth` MUST return `authLoading: true` together with `user: null`, so the host shows a spinner rather than flashing login links.
- **header-signed-in-name**: When a user is present, `useStatusHeaderAuth` MUST return `user.name` equal to `displayName` when it is a non-empty string, and otherwise (`null`, absent, or `""`) equal to `email`.
- **header-signed-in-fields**: When a user is present, `useStatusHeaderAuth` MUST return only `user` and `onLogout`; `authLoading`, `loginHref` and `signupHref` MUST be absent.
- **header-role-not-projected**: `useStatusHeaderAuth` MUST NOT include the user's `role` or `email` (other than as the name fallback) in the returned state.
- **logout-request**: Invoking `onLogout` MUST send one `POST` to `/auth/logout` through `api.fetch` (with the default base, `"/api/auth/logout"`), with no body and no idempotency key; clearing the cookie is the backend's responsibility (see status-server-auth).
- **logout-navigation**: After the logout request settles — fulfilled with any status, including non-OK, or rejected — `onLogout` MUST set `window.location.href` to `"/"`, a full-page navigation to the public landing page.
- **logout-outcome-ignored**: `onLogout` MUST NOT inspect the logout response's status and MUST NOT invalidate `STATUS_AUTH_QUERY_KEY`; the full-page navigation reloads the session from `/auth/me`, so a logout the backend did not honour shows the user still signed in after the reload.
- **logout-rejection-unhandled**: When the logout request rejects, the rejection MUST propagate out of the discarded `.finally(...)` promise as an unhandled promise rejection; `onLogout` does not catch it.
- **no-switch-href**: `useStatusHeaderAuth` MUST NOT supply a `resolveSwitchHref` (or any site-switch resolver), so a host's site switcher navigates straight to sibling sites instead of through an adh-SSO redirect.

### Wire DTOs (`types.ts`)

- **types-module-type-only**: `types.ts` MUST contain only type declarations and type re-exports; it MUST NOT emit runtime code or perform runtime validation of any payload.
- **types-reexports**: `types.ts` MUST re-export the `HealthStatus`, `OverallStatus` and `DeployStatus` types from `lib/health`, `lib/overall` and `lib/deploy-status`.
- **health-status-values**: `HealthStatus` MUST be exactly `"healthy" | "degraded" | "down"`; `ServiceStatusDTO.status` and `HistoryCheck.status` MUST additionally admit `"unknown"`, while `UptimeDay.status` MUST NOT.
- **overall-status-values**: `OverallStatus` (the type of `StatusResponse.overall`) MUST be exactly `"operational" | "degraded" | "major_outage" | "unknown"`.
- **deploy-status-values**: `DeploymentDTO.status` MUST be a `DeployStatus` (`"success" | "failed" | "building" | "queued" | "canceled" | "unknown"`), derived server-side by `combinedStatus`; `buildPhase` MUST be a `BuildPhase` (`"queued" | "building" | "built" | "failed" | "canceled" | "unknown"`) or `null` when the platform reports no build lifecycle; `deployPhase` MUST be a `DeployPhase` (`"none" | "deploying" | "deployed" | "failed" | "unknown"`) and is never null.
- **service-status-dto**: `ServiceStatusDTO` MUST carry `slug`, `group`, `name`, `url` and `environment` as non-null strings, and `platform`, `deployProject`, `responseTimeMs`, `statusCode`, `error` and `lastCheckedAt` as nullable fields (`platform` is the explicit deploy target used as a correlation key).
- **status-response**: `StatusResponse` MUST carry `overall`, a `services` array of `ServiceStatusDTO`, and a `checkedAt` string.
- **uptime-shapes**: `UptimeResponse` MUST carry `services: UptimeService[]` and `days: number`; `UptimeService` MUST carry `slug`, `name`, a nullable `uptimePercent`, `totalChecks: number` and `daily: UptimeDay[]`; `UptimeDay` MUST carry `day`, `status` and a nullable `uptimePercent`.
- **deployment-tier-rendering**: A consumer MUST render `DeploymentDTO.tier` (the logical tier derived server-side by `deployEnv`, `null` for a row that deploys no tier such as a Vercel preview) as the deployment's tier, and MUST NOT render `environment` in its place, because `environment` is the provider's promotion target and reads `"production"` for every Vercel project; the client owns no copy of the tier derivation.
- **deployment-nullable-fields**: `DeploymentDTO` MUST carry `id`, `platform`, `projectName` and `createdAt` as non-null strings, and `environment`, `tier`, `commitHash`, `commitMessage`, `branch`, `commitRepo` (`"owner/name"`), `url`, `errorText` and `liveHost` as nullable strings.
- **deployment-error-text**: `DeploymentDTO.errorText` MUST be the provider's failure reason for a failed deploy (Vercel `errorMessage` or Railway build-log tail) and `null` otherwise, and consumers MUST render it verbatim.
- **deployment-phase-confirmed-at**: `DeploymentDTO.phaseConfirmedAt` MUST be an optional ISO timestamp of when the phases were last confirmed against provider truth; when it is absent (older backend or persisted pre-upgrade rows), consumers MUST treat `createdAt` as its floor.
- **history-shapes**: `HistoryResponse` MUST carry `service: string`, `hours: number` and `checks: HistoryCheck[]`; `HistoryCheck` MUST carry `status`, nullable `responseTimeMs`, `statusCode` and `error`, and a non-null `checkedAt` string.
- **check-state-values**: `CheckState` MUST be exactly `"ok" | "warn" | "error"`, and it MUST type both `IntegrationCheck.state` and `IntegrationsResponse.overall`.
- **integration-check-shape**: `IntegrationCheck` MUST carry `id`, `label`, `configured: boolean`, `ok: boolean`, `state` and `detail`, plus the optional `missingEnv?: string[]` (expected env vars found unset, named exactly; omitted or empty when nothing is missing), `unreachable?: boolean` (no HTTP response at all, debounced backend-side) and `correlated?: boolean` (unreachable together with other providers in the same run, judged monitor-side connectivity).
- **integrations-response**: `IntegrationsResponse` MUST carry `generatedAt: string`, `overall` and `checks: IntegrationCheck[]`.

### Concurrency and side effects

- **single-threaded-ordering**: All of this module's code MUST run on the browser's single JavaScript thread inside React client components (`header-auth.ts` declares `"use client"`; `types.ts` has no runtime code); there is no parallel mutation to order.
- **side-effects**: The only side effects in these sources MUST be the `GET /auth/me` request, the `POST /auth/logout` request, and the `window.location.href` assignment; nothing is written to storage, cookies or logs by this module.

## Appearance

Not applicable — this is a headless session client and DTO type module, not a visual component.

## States

Not applicable — this is a headless session client and DTO type module, not a visual component.

## Accessibility

Not applicable — this is a headless session client and DTO type module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-src-001 | auth-me-user-resolves (traced to `header-auth.test.ts`) | `fetchStatusUser(createStatusApiClient(), fetchImpl)` where `fetchImpl` resolves HTTP 200 `{"user":{"email":"a@b.c","displayName":"A","role":"admin"}}` | resolves `{ email: "a@b.c", displayName: "A", role: "admin" }` |
| status-web-src-002 | auth-me-signed-out-resolves-null (traced to `header-auth.test.ts`) | same call; `fetchImpl` resolves HTTP 200 `{"user":null}` | resolves `null` |
| status-web-src-003 | auth-me-non-ok-throws (traced to `header-auth.test.ts`) | same call; `fetchImpl` resolves HTTP 500 `{}` | rejects with an `Error` whose message matches `HTTP 500` (exactly `auth/me unavailable (HTTP 500)`) |
| status-web-src-004 | auth-me-network-failure-propagates (traced to `header-auth.test.ts`) | same call; `fetchImpl` rejects with `TypeError("fetch failed")` | rejects with that `TypeError` (message `fetch failed`) |
| status-web-src-005 | auth-me-signed-out-resolves-null | same call; `fetchImpl` resolves HTTP 200 `{}` | resolves `null` (`user` absent reads as signed-out) |
| status-web-src-006 | auth-me-non-ok-throws | same call; `fetchImpl` resolves HTTP 401 `{"user":null}` | rejects with `auth/me unavailable (HTTP 401)`; never resolves `null` |
| status-web-src-007 | auth-me-url, auth-me-transport | `createStatusApiClient({ basePath: "/proxy" })`; recording `fetchImpl` | `fetchImpl` called once with the single argument `"/proxy/auth/me"` and no `init` |
| status-web-src-008 | auth-me-body-parse-failure-propagates | `fetchImpl` resolves HTTP 200 with body `not json` | rejects with the JSON parse error from `res.json()` |
| status-web-src-009 | session-query-key | read `STATUS_AUTH_QUERY_KEY` | deep-equals `["status-auth-me"]` |
| status-web-src-010 | header-signed-out-state, header-loading-spinner | `useStatusUser` yields `{ user: null, isPending: true }` | `useStatusHeaderAuth()` returns `{ user: null, authLoading: true, loginHref: "/login", signupHref: "/signup" }` |
| status-web-src-011 | header-signed-out-state | `useStatusUser` yields `{ user: null, isPending: false }` | returns `{ user: null, authLoading: false, loginHref: "/login", signupHref: "/signup" }` |
| status-web-src-012 | header-signed-in-name, header-signed-in-fields | user `{ email: "a@b.c", displayName: "Ann", role: "viewer" }` | returns `user: { name: "Ann" }`, a function `onLogout`, and no `authLoading`/`loginHref`/`signupHref` keys |
| status-web-src-013 | header-signed-in-name | user `{ email: "a@b.c", displayName: "", role: "viewer" }` | `user.name === "a@b.c"` |
| status-web-src-014 | header-signed-in-name | user `{ email: "a@b.c", displayName: null, role: "admin" }` | `user.name === "a@b.c"` |
| status-web-src-015 | logout-request, logout-navigation | signed-in state, default client; call `onLogout()`; `api.fetch` resolves HTTP 200 | one `fetch("/api/auth/logout", { method: "POST" })`; afterwards `window.location.href === "/"` |
| status-web-src-016 | logout-navigation, logout-outcome-ignored | as 015 but `api.fetch` resolves HTTP 500 | `window.location.href === "/"`; no error thrown synchronously; the query key is not invalidated |
| status-web-src-017 | logout-navigation, logout-rejection-unhandled | as 015 but `api.fetch` rejects | `window.location.href === "/"`; an unhandled promise rejection carrying the fetch error is raised |
| status-web-src-018 | session-kept-across-errors | cache holds user `U`; next refetch (all four attempts) rejects with HTTP 503 | `useStatusUser()` still returns `{ user: U, isPending: false }` |
| status-web-src-019 | session-query-dedupe | two components calling `useStatusUser` mount in the same render with an empty cache | exactly one `/auth/me` request is issued |
| status-web-src-020 | session-query-config | first load; `fetchImpl` rejects every time | `/auth/me` is attempted 4 times (1 + `retry: 3`) before the query settles into error |

The `types.ts` requirements are compile-time shapes with no runtime behavior; a port verifies them with type-level assertions (e.g. assigning `"unknown"` to `UptimeDay["status"]` MUST fail to compile, and assigning it to `ServiceStatusDTO["status"]` MUST compile) rather than runtime vectors.

## Edge Cases

- **Signed-out answer vs. failure**: HTTP 200 `{ user: null }` → `fetchStatusUser` resolves `null` (MUST); any non-OK status, including 401 and 403 → rejects (MUST). Signed-out is never inferred from a status code.
- **Empty or missing body field**: HTTP 200 `{}` → resolves `null`, read as signed-out (MUST, per `body.user ?? null`).
- **Malformed body**: HTTP 200 with non-JSON body → rejects with the parse error; React Query retries (MUST).
- **Partial user object**: HTTP 200 `{ user: { role: "viewer" } }` (no `email`, no `displayName`) → resolved unchanged (MUST, per auth-me-no-shape-validation); `useStatusHeaderAuth` then returns `user.name` as `undefined` despite the `string` type.
- **Empty display name**: `displayName: ""` → header name falls back to `email` (MUST; `||` rather than `??`).
- **Transient failure with cached session**: backend restart, proxy 500, or network blip after a successful load → cached user is kept and the fetch retried up to 3 times (MUST); the header never flashes signed-out.
- **Cold-load failure**: backend unreachable on the very first load → after four failed attempts the hook returns `user: null, isPending: false`, and the header shows login/signup links; see the open question on first-load-failure-projection.
- **Offline / disconnected**: `fetch` rejects → treated like any failure above (error kept out of `user`, retried); no offline detection of its own.
- **Timeout**: no request timeout or abort signal is set on `/auth/me` or `/auth/logout` (MUST NOT be assumed); a hung request stays pending until the browser gives up, and on first load `isPending` stays true (header spinner) for that whole time.
- **Cancellation**: `fetchStatusUser` accepts no abort signal; React Query's query-function signal is not forwarded, so an unmounted query's in-flight request is not aborted.
- **Logout failure**: logout POST returns non-OK or rejects → navigation to `/` happens anyway (MUST); on reload the session is re-read, so an un-cleared cookie shows the user still signed in. A rejection surfaces as an unhandled promise rejection.
- **Logout double-invoke**: calling `onLogout` twice issues two POSTs; each navigates to `/` when it settles. No guard exists.
- **Concurrent consumers**: header, board gate and landing page mounting at once share one query and one request (MUST).
- **Login without invalidation**: a login flow that sets the cookie but does not invalidate `STATUS_AUTH_QUERY_KEY` leaves the cached `{ user: null }` in place for up to the 60,000 ms `staleTime` (documented caller obligation).
- **Injected client fetch**: a `StatusApiClient` built with a custom `fetch` is honoured by `onLogout` (via `api.fetch`) but not by `useStatusUser`, whose `fetchStatusUser(api)` call uses the global `fetch` with only `api.url`.
- **Optional DTO fields**: `phaseConfirmedAt` absent → consumers use `createdAt`; `missingEnv`, `unreachable`, `correlated` absent → treated as empty/false by consumers.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api` (`fetchStatusUser`) | `StatusApiClient` | none — required | Resolves the `/auth/me` URL via `api.url`. |
| `fetchImpl` (`fetchStatusUser`) | `typeof fetch` | global `fetch` | Injectable transport for tests. |
| `StatusApiProvider` client / `basePath` | `StatusApiClient` / `string` | same-origin default client, base `"/api"` | Supplies the client both hooks obtain from `useStatusApi()` (see status-web-api). |
| `staleTime` | number (ms) | `60_000` | Hard-coded in `useStatusUser`; not caller-configurable. |
| `retry` | number | `3` | Hard-coded in `useStatusUser`; not caller-configurable. |
| `QueryClient` | React Query client | host-provided | Must be mounted by the host; supplies all React-Query defaults the query does not override. |
| `loginHref` / `signupHref` | `string` | `"/login"` / `"/signup"` | Hard-coded in `useStatusHeaderAuth`. |
| Post-logout destination | `string` | `"/"` | Hard-coded in `onLogout`. |

## Deep Linking

Not applicable: these modules construct no deep links; the only paths they name are the fixed `"/login"`, `"/signup"` and `"/"` hrefs a host header renders, which are site routes owned by the host, not deep-link patterns.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not an i18n key) | `auth/me unavailable (HTTP <status>)` | `fetchStatusUser`'s thrown `Error` message on a non-OK response; English-only, never sourced from a localization resource. It is not rendered by this module (`useStatusUser` does not expose query errors). |

## Accessibility Options

Not applicable — this is a headless session client and DTO type module, not a visual component; it renders nothing and reads no motion, contrast or color setting.

## Feature Flags

Not applicable: neither `header-auth.ts` nor `types.ts` reads a feature-flag key; every path always executes.

## Analytics

Not applicable: neither file calls the package's telemetry client (`src/telemetry/`) or any analytics API.

## Privacy

- **Data collected**: the signed-in user's `email`, optional `displayName`, and `role`, returned by `/auth/me`.
- **Storage**: held only in the host's in-memory React-Query cache under `STATUS_AUTH_QUERY_KEY`; nothing is written to `localStorage`, cookies or disk by this module. The session credential itself is the `status_auth` httpOnly cookie, which client code cannot read — this module never touches it.
- **Transmission**: the browser attaches the cookie to the same-origin `/auth/me` and `/auth/logout` requests; this module sends no credential or personal data in a URL or body. The header seam exposes only a display name (`displayName` or, failing that, `email`).
- **Retention**: in memory until the page unloads or React Query garbage-collects the entry; `onLogout`'s full-page navigation discards the cache.

## Logging

Not applicable: neither file calls `console.*` or any logger; `fetchStatusUser`'s thrown `Error` is the only signal, and it is held by React Query rather than logged here.

## Platform Notes

- **SwiftUI**: model `fetchStatusUser` as an `async throws` function over `URLSession.data(from:)` that throws on any non-2xx `HTTPURLResponse` and decodes `{ user: StatusUser? }` with `JSONDecoder`; `HTTPCookieStorage` attaches the session cookie. Replace React Query with an `@Observable @MainActor` session store holding `user` and `isPending`, a 60-second staleness timestamp, and an explicit retry loop (3 retries with exponential backoff) that keeps the last user on failure. Expose the header state as a computed property; `onLogout` becomes an `async` method that POSTs then resets navigation regardless of outcome. DTOs become `Codable`, `Sendable` structs with `String` enums for the unions.
- **Compose**: Ktor or Retrofit call returning `StatusUser?`, throwing on non-2xx; a `ViewModel` exposing `StateFlow<SessionState>` shared app-wide (Hilt singleton) replaces the shared query key, with `retry(3)` plus delay backoff on the `Flow` and `stateIn` retaining the last value on error. DTOs become `@Serializable data class`es with `enum class` for the unions (`@SerialName("major_outage")`).
- **React/Web**: the source. `header-auth.ts` uses `@tanstack/react-query`'s `useQuery` and the package's `useStatusApi` context hook, carries `"use client"`, and is tested with Vitest in `header-auth.test.ts` by injecting `fetchImpl`. `types.ts` is compile-time TypeScript only.
- **AppKit / UIKit**: the same `URLSession` fetch and a shared session-store singleton (`ObservableObject` or Combine `CurrentValueSubject`) the header view controller observes; logout resets the window's root to the landing screen instead of assigning `window.location`.
- **WinUI 3**: implement `FetchStatusUserAsync` over a shared `HttpClient` (with an `HttpClientHandler` whose `CookieContainer` carries the session cookie), calling `EnsureSuccessStatusCode()` semantics manually to throw on any non-2xx and `System.Text.Json` (`JsonSerializer.DeserializeAsync<AuthMeBody>`) for the body. Replace React Query with a singleton `SessionService : INotifyPropertyChanged` exposing `User` and `IsPending`, a `DateTimeOffset` staleness check for the 60-second window, and a retry loop (`for` 4 attempts with `Task.Delay` exponential backoff) that leaves `User` untouched on failure; concurrent callers share one in-flight `Task<StatusUser?>` to reproduce the query dedupe. The header binds to a `HeaderAuthState` view-model (`x:Bind` to `User.Name`, a `ProgressRing` bound to `AuthLoading`, `HyperlinkButton`s for login/signup, a `RelayCommand` for logout). Logout POSTs via `HttpClient.PostAsync` inside `try/finally` and then navigates the root `Frame` to the landing page; unlike the source, .NET surfaces an unobserved faulted `Task` only via `TaskScheduler.UnobservedTaskException`. DTOs become `record`s with `[JsonPropertyName]` and string-valued enums via `JsonStringEnumConverter`; lists surface as `ObservableCollection<T>` only where bound. `Windows.Storage` has no role — nothing is persisted.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
