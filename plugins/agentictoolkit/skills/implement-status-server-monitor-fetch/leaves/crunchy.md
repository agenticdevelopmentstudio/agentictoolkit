<!-- leaf: implement-status-server-monitor-fetch/crunchy · source: status-server-monitor-fetch-crunchy.md -->

**Rules** (cite as `implement-status-server-monitor-fetch/crunchy#<slug>`):

- `token-gate` MUST
- `cooldown-gate` MUST
- `request-shape` MUST
- `https-transport` MUST
- `request-timeout` MUST
- `no-retry` MUST
- `rate-limit-recorded` MUST
- `http-error-fails-poll` MUST
- `thrown-fetch-fails-poll` MUST
- `missing-clusters-empty` MUST
- `cluster-mapping` MUST
- `phase-mapping` MUST
- `environment-default` MUST
- `created-at-fallback` MUST
- `static-fields` MUST

# Status Server Monitor Fetch Crunchy

## Overview

`fetch-crunchy.ts` (`packages/web/packages/status-server/src/monitor/fetch-crunchy.ts`) is one of the status server's monitor-cycle provider pollers; its own header comment states it is "poll-only, mirroring fetch-cloudflare". Its single export, `fetchCrunchyClusters`, lists every Crunchy Bridge cluster in the configured team (testing, staging, production, and any future cluster or replica) and maps each one to a `ProviderDeploy` deploy row whose `deployPhase` IS the cluster's health, via `crunchyPhases` (`./deploy-status`, external to this file but directly invoked). A missing token means the integration was never configured, which this file treats as a dormant success rather than an error; any request failure — a non-`ok` HTTP response, a 429, or a thrown/aborted fetch — resolves `ok: false` so the platform-health path (external to this file) can open a "can't reach Crunchy" blind-spot issue, per the file's own header comment. The raw `CRUNCHY_API_TOKEN` is used directly as a Bearer token, with no OAuth exchange.

## Behavioral Requirements

### Gating (token and cooldown)

- **token-gate**: `fetchCrunchyClusters` MUST resolve `{ ok: true, deploys: [] }` immediately, without issuing any network request, when `env.CRUNCHY_API_TOKEN` is absent, `undefined`, or an empty string.
- **cooldown-gate**: When the `crunchy` provider slot is currently cooling down per `rateLimitedUntil("crunchy")`, `fetchCrunchyClusters` MUST resolve `{ ok: false, deploys: [] }` immediately, without issuing any network request.

### Request and Timeout

- **request-shape**: When neither gate above applies, `fetchCrunchyClusters` MUST issue exactly one `GET` request to the fixed URL `https://api.crunchybridge.com/clusters`, carrying header `Authorization: Bearer` followed by the value of `env.CRUNCHY_API_TOKEN`.
- **https-transport**: The request's origin MUST be the hardcoded literal `https://api.crunchybridge.com`; the transport scheme and host are never caller-configurable through `env`.
- **request-timeout**: The request MUST be bounded by an `AbortController` whose signal aborts after 6,000ms, driven by `setTimeout`, with the timer cleared in a `finally` block regardless of outcome.
- **no-retry**: `fetchCrunchyClusters` MUST make exactly one request attempt per call; it MUST NOT retry a failed, timed-out, or aborted attempt within the same call.

### Response and Error Handling

- **rate-limit-recorded**: When the response status is 429, `fetchCrunchyClusters` MUST call `noteRateLimited("crunchy", ...)` with the response's `retry-after` header value before resolving, so the cooldown slot is set for subsequent calls (including calls from the other thread that shares the cooldown registry).
- **http-error-fails-poll**: When the response's `ok` is `false` (including the 429 case), `fetchCrunchyClusters` MUST log a `console.error` line naming the HTTP status and MUST resolve `{ ok: false, deploys: [] }`.
- **thrown-fetch-fails-poll**: When the `fetch` call throws, the abort fires, or parsing the response body as JSON throws, `fetchCrunchyClusters` MUST catch it, log a `console.error` line naming the caught error, and resolve `{ ok: false, deploys: [] }`.
- **missing-clusters-empty**: When the parsed body's `clusters` field is absent (`undefined`), `fetchCrunchyClusters` MUST resolve `{ ok: true, deploys: [] }`, treating an absent `clusters` field identically to an empty `clusters` array rather than as an error.

### Cluster Mapping

- **cluster-mapping**: For each entry in `clusters`, `fetchCrunchyClusters` MUST produce a `ProviderDeploy` whose `id` is `cr_` followed by the cluster's `id`, whose `platform` is the literal `"crunchy"`, and whose `projectName` is the cluster's `name`.
- **phase-mapping**: Each deploy's `buildPhase` MUST be `null`, and its `deployPhase` MUST be `"failed"` when the cluster's `is_suspended` is `true` or its `state` is one of `failed`, `creation_failed`, or `suspended`; every other `state` value — including `ready`, any routine/transient operation state, and a `state` that is absent or not among the documented set — MUST map `deployPhase` to `"deployed"`.
- **environment-default**: Each deploy's `environment` MUST be the cluster's own `environment` value when present and non-null, and MUST default to the literal `"production"` when the cluster's `environment` is `null` or absent.
- **created-at-fallback**: Each deploy's `createdAt` MUST be the `Date` produced by `toValidDate(c.created_at)` when that call returns a valid `Date`, and MUST fall back to the current time at the moment of mapping (the poll's own execution time) whenever `toValidDate` returns `null` — never an Invalid Date.
- **static-fields**: Each deploy's `commitHash`, `commitMessage`, `branch`, `commitRepo`, and `url` MUST all be `null`, since a Crunchy Bridge cluster record carries no VCS commit or deployment-URL metadata.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `env.CRUNCHY_API_TOKEN` | `string \| undefined` (`env` parameter field, `fetch-crunchy.ts`) | caller-supplied | Crunchy Bridge Bearer token, used directly with no exchange. Absent or empty MUST trigger the dormant no-op per **token-gate**. |
| Request timeout | `number` (inline literal `6_000`, `fetch-crunchy.ts`) | `6_000` ms | Deadline for the single `/clusters` request, via `AbortController`. Not exported; not caller-configurable. |
| `crunchy` cooldown slot | registry entry (external, `provider-cooldown.ts`) | `0` (not cooling down) | Consulted via `rateLimitedUntil("crunchy")` before every request and written via `noteRateLimited("crunchy", ...)` on a 429; owned by `provider-cooldown.ts`, not by this file. `DEFAULT_COOLDOWN_MS` (`60_000`) and `MAX_COOLDOWN_MS` (`900_000`) bound how long a cooldown can last, also owned by that external module. |

## Privacy

- **Data collected**: cluster identity and health metadata — `id`, `name`, `state`, `is_suspended`, `environment`, and `created_at` — read from Crunchy Bridge's `/clusters` response. This is infrastructure metadata about the team's own database clusters, not end-user personal data.
- **Storage**: this file writes nothing to persistent storage; it only fetches and maps. Persisting the resulting deploy rows is a job external to this file.
- **Transmission**: `env.CRUNCHY_API_TOKEN` is sent only as an `Authorization: Bearer` header on the outbound request, never in a query string or request body. The transport origin is hardcoded to `https://`, per **https-transport** — this file, unlike its sibling Cloudflare/GlitchTip/PostHog fetchers, never accepts a caller-supplied host and so cannot be misconfigured onto a non-TLS origin.
- **Retention**: this file holds the token and every fetched cluster field only for the duration of one `fetchCrunchyClusters` call; there is no in-memory cache of any kind.

## Platform Notes

- **React/Web** (source platform): `fetch-crunchy.ts` lives under `packages/web/packages/status-server/src/monitor/`, on Node's global `fetch`, `AbortController`, and `setTimeout`/`clearTimeout`. It imports `crunchyPhases` from the sibling local module `./deploy-status`, `toValidDate`/`ProviderDeploy` from the sibling local module `./provider-deploy`, and `noteRateLimited`/`rateLimitedUntil` from the separate workspace package `@agentic-toolkit/deploy-platform/cooldown`, whose registry is backed by a cross-thread `SharedArrayBuffer`.
- **SwiftUI**: model `ProviderDeploy` as a `Sendable` struct mirroring the TypeScript interface's fields (optional fields as `String?`/`Date?`); use `URLSession` with `URLRequest.timeoutInterval = 6` (or a `Task` racing `Task.sleep` for cancellation) in place of `AbortController`; port `crunchyPhases`/`toValidDate` as pure, `Sendable` free functions; the cross-thread cooldown registry maps to an `actor` (Swift's idiomatic serialized-access analogue of the source's `Atomics`-guarded `SharedArrayBuffer`) shared between the polling task and any concurrent caller.
- **Compose**: the same structural mapping as SwiftUI — a Kotlin `data class ProviderDeploy`, a coroutine `withTimeout(6_000)` block in place of `AbortController`, `crunchyPhases`/`toValidDate` as pure Kotlin functions, and the shared cooldown registry as a `Mutex`-guarded singleton (or an `AtomicLong` array) shared across coroutine dispatchers.
- **AppKit/UIKit**: identical mapping to SwiftUI's; `URLSession`'s `dataTask`/`data(for:)` with a 6-second `timeoutIntervalForRequest` is the direct analogue of this file's single bounded, non-retried attempt.
- **WinUI 3**: a .NET port uses `HttpClient` with a per-call `CancellationTokenSource` timed via `CancelAfter(TimeSpan.FromSeconds(6))` as the `AbortController` analogue; `System.Text.Json` replaces `res.json()` for the `ClustersBody`/`CrunchyCluster` shapes, modeled as `record` types with nullable properties matching the TypeScript interfaces' optional fields; `crunchyPhases`/`toValidDate` port as static methods on a small helper class; and the cross-thread cooldown registry maps to a `lock`-guarded `Dictionary<string, DateTimeOffset>` (or a `System.Threading.Channels`-fed singleton) shared across the app's background poll `Task` and any UI-thread caller, standing in for the source's `SharedArrayBuffer`/`Atomics` pair. No `Windows.Storage` or `ObservableCollection`/`INotifyPropertyChanged` counterpart applies — this function returns a plain list from one call, not a bound collection or persisted state.

