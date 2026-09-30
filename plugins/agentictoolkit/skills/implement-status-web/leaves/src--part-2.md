<!-- leaf: implement-status-web/src--part-2 · source: status-web-src.md -->

# Status Web Src — continued (part 2)

**Rules** (cite as `implement-status-web/src--part-2#<slug>`):

- `types-module-type-only` MUST
- `types-reexports` MUST
- `health-status-values` MUST
- `overall-status-values` MUST
- `deploy-status-values` MUST
- `service-status-dto` MUST
- `status-response` MUST
- `uptime-shapes` MUST
- `deployment-tier-rendering` MUST
- `deployment-nullable-fields` MUST
- `deployment-error-text` MUST
- `deployment-phase-confirmed-at` MUST
- `history-shapes` MUST
- `check-state-values` MUST
- `integration-check-shape` MUST
- `integrations-response` MUST
- `single-threaded-ordering` MUST
- `side-effects` MUST

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

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not an i18n key) | `auth/me unavailable (HTTP <status>)` | `fetchStatusUser`'s thrown `Error` message on a non-OK response; English-only, never sourced from a localization resource. It is not rendered by this module (`useStatusUser` does not expose query errors). |

## Privacy

- **Data collected**: the signed-in user's `email`, optional `displayName`, and `role`, returned by `/auth/me`.
- **Storage**: held only in the host's in-memory React-Query cache under `STATUS_AUTH_QUERY_KEY`; nothing is written to `localStorage`, cookies or disk by this module. The session credential itself is the `status_auth` httpOnly cookie, which client code cannot read — this module never touches it.
- **Transmission**: the browser attaches the cookie to the same-origin `/auth/me` and `/auth/logout` requests; this module sends no credential or personal data in a URL or body. The header seam exposes only a display name (`displayName` or, failing that, `email`).
- **Retention**: in memory until the page unloads or React Query garbage-collects the entry; `onLogout`'s full-page navigation discards the cache.

## Platform Notes

- **SwiftUI**: model `fetchStatusUser` as an `async throws` function over `URLSession.data(from:)` that throws on any non-2xx `HTTPURLResponse` and decodes `{ user: StatusUser? }` with `JSONDecoder`; `HTTPCookieStorage` attaches the session cookie. Replace React Query with an `@Observable @MainActor` session store holding `user` and `isPending`, a 60-second staleness timestamp, and an explicit retry loop (3 retries with exponential backoff) that keeps the last user on failure. Expose the header state as a computed property; `onLogout` becomes an `async` method that POSTs then resets navigation regardless of outcome. DTOs become `Codable`, `Sendable` structs with `String` enums for the unions.
- **Compose**: Ktor or Retrofit call returning `StatusUser?`, throwing on non-2xx; a `ViewModel` exposing `StateFlow<SessionState>` shared app-wide (Hilt singleton) replaces the shared query key, with `retry(3)` plus delay backoff on the `Flow` and `stateIn` retaining the last value on error. DTOs become `@Serializable data class`es with `enum class` for the unions (`@SerialName("major_outage")`).
- **React/Web**: the source. `header-auth.ts` uses `@tanstack/react-query`'s `useQuery` and the package's `useStatusApi` context hook, carries `"use client"`, and is tested with Vitest in `header-auth.test.ts` by injecting `fetchImpl`. `types.ts` is compile-time TypeScript only.
- **AppKit / UIKit**: the same `URLSession` fetch and a shared session-store singleton (`ObservableObject` or Combine `CurrentValueSubject`) the header view controller observes; logout resets the window's root to the landing screen instead of assigning `window.location`.
- **WinUI 3**: implement `FetchStatusUserAsync` over a shared `HttpClient` (with an `HttpClientHandler` whose `CookieContainer` carries the session cookie), calling `EnsureSuccessStatusCode()` semantics manually to throw on any non-2xx and `System.Text.Json` (`JsonSerializer.DeserializeAsync<AuthMeBody>`) for the body. Replace React Query with a singleton `SessionService : INotifyPropertyChanged` exposing `User` and `IsPending`, a `DateTimeOffset` staleness check for the 60-second window, and a retry loop (`for` 4 attempts with `Task.Delay` exponential backoff) that leaves `User` untouched on failure; concurrent callers share one in-flight `Task<StatusUser?>` to reproduce the query dedupe. The header binds to a `HeaderAuthState` view-model (`x:Bind` to `User.Name`, a `ProgressRing` bound to `AuthLoading`, `HyperlinkButton`s for login/signup, a `RelayCommand` for logout). Logout POSTs via `HttpClient.PostAsync` inside `try/finally` and then navigates the root `Frame` to the landing page; unlike the source, .NET surfaces an unobserved faulted `Task` only via `TaskScheduler.UnobservedTaskException`. DTOs become `record`s with `[JsonPropertyName]` and string-valued enums via `JsonStringEnumConverter`; lists surface as `ObservableCollection<T>` only where bound. `Windows.Storage` has no role — nothing is persisted.

