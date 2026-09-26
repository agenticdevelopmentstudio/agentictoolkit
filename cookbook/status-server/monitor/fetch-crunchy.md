---
id: f236e0ab-2623-4543-a3d9-9ffb4ba3f147
title: Status Server Monitor Fetch Crunchy
domain: agentictoolkit://cookbook/status-server/monitor/fetch-crunchy
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Monitor-cycle poller that lists every Crunchy Bridge cluster and maps each to a deploy row whose phase is the cluster's health; token-gated, cooldown-aware, single bounded attempt."
platforms:
- typescript
- web
tags:
- monitor
- crunchy
- deploy
- fetcher
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
related: []
references:
- packages/web/packages/status-server/src/monitor/fetch-crunchy.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/status-server/test/crunchy-deployments.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a monitor-cycle provider poller, not a visual component.

## States

Not applicable — this is a monitor-cycle provider poller, not a visual component; its runtime branches (dormant/no token, cooling down, succeeded, HTTP error, thrown error) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a monitor-cycle provider poller, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| crunchy-001 | token-gate | `fetchCrunchyClusters({})` | Resolves `{ ok: true, deploys: [] }`; the stubbed `fetch` global is never called — `crunchy-deployments.test.ts` › "is a no-op (ok) when no token is configured" |
| crunchy-002 | cluster-mapping, phase-mapping | `fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" })` against a stubbed 3-cluster response (`ready`/`ready`/`suspended`) | Resolves `ok: true`; `deploys.map(d => [d.projectName, d.deployPhase])` equals `[["adh-production","deployed"],["adh-staging","deployed"],["adh-testing","failed"]]`; `deploys[0]` matches `{ id: "cr_fq2z", platform: "crunchy", buildPhase: null, environment: "production" }` — `crunchy-deployments.test.ts` › "maps each cluster to a deploy row; ready then deployed, suspended then failed" |
| crunchy-003 | request-shape, https-transport | Same call, inspecting the stubbed `fetch`'s first call arguments | The requested URL string contains `api.crunchybridge.com/clusters`; the request `init.headers` matches `{ Authorization: "Bearer cbkey_x" }` — `crunchy-deployments.test.ts` › "sends the token as a Bearer header to /clusters" |
| crunchy-004 | http-error-fails-poll | Stubbed `fetch` resolves `{ ok: false, status: 500, json: async () => ({}) }` | Resolves `{ ok: false, deploys: [] }` — `crunchy-deployments.test.ts` › "returns ok:false with no deploys when the API errors" |
| crunchy-005 | thrown-fetch-fails-poll | Stubbed `fetch` throws `Error("network")` | Resolves `{ ok: false, deploys: [] }` — `crunchy-deployments.test.ts` › "returns ok:false when fetch throws" |
| crunchy-006 | environment-default | A cluster body entry with no `environment` field | The mapped deploy has `{ environment: "production", deployPhase: "deployed" }` — `crunchy-deployments.test.ts` › "defaults a cluster with no environment to production" |
| crunchy-007 | missing-clusters-empty | Stubbed `fetch` resolves a body of `{}` (no `clusters` key) | Resolves `{ ok: true, deploys: [] }` — `crunchy-deployments.test.ts` › "returns no deploys (ok) when the body has no clusters array" |
| crunchy-008 | phase-mapping | A cluster body entry with no `state` field | The mapped deploy has `deployPhase: "deployed"` — `crunchy-deployments.test.ts` › "treats a cluster missing its state as healthy (quieter: unknown is not a problem)" |
| crunchy-009 | rate-limit-recorded, http-error-fails-poll | Stubbed `fetch` resolves `{ ok: false, status: 429, headers: { get: () => "30" } }` | `fetchCrunchyClusters` resolves `{ ok: false, deploys: [] }`, and a subsequent `rateLimitedUntil("crunchy")` call returns a non-null expiry roughly 30 seconds out — traced directly to the source's `res.status === 429` branch calling `noteRateLimited`; not exercised by a dedicated case in `crunchy-deployments.test.ts`, whose given error test uses status 500 |
| crunchy-010 | cooldown-gate | `rateLimitedUntil("crunchy")` stubbed to return a future timestamp, then `fetchCrunchyClusters({ CRUNCHY_API_TOKEN: "cbkey_x" })` | The stubbed `fetch` global is never called; resolves `{ ok: false, deploys: [] }` — traced directly to the source's `if (rateLimitedUntil("crunchy")) return { ok: false, deploys: [] }` guard; not exercised by a dedicated case in `crunchy-deployments.test.ts` |
| crunchy-011 | request-timeout | Stubbed `fetch` returns a `Promise` that never settles | The request's `AbortController.signal.aborted` becomes `true` at 6,000ms and `fetchCrunchyClusters` resolves `{ ok: false, deploys: [] }` shortly after — traced directly to the source's `setTimeout(() => controller.abort(), 6_000)`; not exercised by a dedicated case in `crunchy-deployments.test.ts` |
| crunchy-012 | created-at-fallback | A cluster body entry with `created_at: "not-a-date"` | The mapped deploy's `createdAt` is a valid `Date` approximately equal to the call's execution time, never an Invalid Date — traced directly to `toValidDate(c.created_at) ?? new Date()`; not exercised by a dedicated case in `crunchy-deployments.test.ts`, whose fixtures use only valid ISO timestamps |
| crunchy-013 | static-fields | Any successful mapping (e.g. the crunchy-002 fixture) | Every mapped deploy has `commitHash: null`, `commitMessage: null`, `branch: null`, `commitRepo: null`, `url: null` — traced directly to the literal `null` assignments in the mapper; `crunchy-deployments.test.ts` asserts a subset of these fields via `toMatchObject` |
| crunchy-014 | no-retry | Same stubbed `fetch` spy as crunchy-003, after one call to `fetchCrunchyClusters` resolves | `spy.mock.calls.length === 1` — the source contains no loop or repeated call construct around the single `fetch` invocation — `crunchy-deployments.test.ts` › "sends the token as a Bearer header to /clusters" (inspects `spy.mock.calls[0]`, implying a single call) |

## Edge Cases

- **Null and empty input**: `env.CRUNCHY_API_TOKEN` absent, `undefined`, or an empty string all trigger the same dormant `{ ok: true, deploys: [] }` no-op (**token-gate**) — MUST. A response body of `{}` (no `clusters` key at all) resolves the same `{ ok: true, deploys: [] }` as a body of `{ clusters: [] }` (**missing-clusters-empty**) — MUST. A cluster entry with `environment: null` is indistinguishable from one with `environment` absent; both default to `"production"` (**environment-default**) — MUST.
- **Boundary values**: unlike the sibling GlitchTip fetcher's fixed `PAGE_LIMIT`, this file never inspects `clusters.length` for a size cutoff — a response of one cluster and a response of hundreds are mapped identically, in one pass, with no truncation and no pagination/cursor handling of any kind. The 6,000ms request timeout is the only numeric boundary this file defines; a response that lands at or just past that instant races the `AbortController`'s abort against the in-flight `fetch`, and the abort MUST win per **request-timeout**.
- **Concurrent access**: `fetchCrunchyClusters` itself holds no module-level mutable state — every call constructs its own local `AbortController` and `setTimeout` timer, so two overlapping calls on the same thread never interfere with each other's request or timeout state (each simply issues its own independent `GET`, and nothing in this file deduplicates them). The one piece of state this file reads and writes indirectly — the `crunchy` slot in `provider-cooldown.ts`'s registry — IS shared across threads (the monitor cycle's worker thread and the API thread's `/deploy-projects`/`/integrations` routes, external to this file) via a `SharedArrayBuffer`; that module's own `noteRateLimited`/`rateLimitedUntil` use `Atomics.load`/`Atomics.store` and never shorten an existing cooldown, so two concurrent 429s recorded from different threads converge on the furthest expiry rather than one clobbering the other — a guarantee this file relies on but does not itself implement.
- **Error states**: a non-429 HTTP error, a 429, and a thrown/aborted `fetch` or JSON-parse failure each produce the identical `{ ok: false, deploys: [] }` return shape; only the accompanying `console.error` line and, for a 429, the recorded cooldown, distinguish them (**http-error-fails-poll**, **thrown-fetch-fails-poll**, **rate-limit-recorded**) — MUST for all three. A caller reading only the return value cannot tell "provider unreachable" from "rate limited" from "malformed JSON body" apart from the log output.
- **Offline / disconnected state**: an unreachable host (DNS failure, connection refused) causes the `fetch` call itself to reject, which is caught by the same `catch` block as any other thrown error and resolves `{ ok: false, deploys: [] }` (**thrown-fetch-fails-poll**) — MUST. A host that accepts the connection but never responds is bounded by the 6,000ms `AbortController` rather than left hanging indefinitely (**request-timeout**) — MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `env.CRUNCHY_API_TOKEN` | `string \| undefined` (`env` parameter field, `fetch-crunchy.ts`) | caller-supplied | Crunchy Bridge Bearer token, used directly with no exchange. Absent or empty MUST trigger the dormant no-op per **token-gate**. |
| Request timeout | `number` (inline literal `6_000`, `fetch-crunchy.ts`) | `6_000` ms | Deadline for the single `/clusters` request, via `AbortController`. Not exported; not caller-configurable. |
| `crunchy` cooldown slot | registry entry (external, `provider-cooldown.ts`) | `0` (not cooling down) | Consulted via `rateLimitedUntil("crunchy")` before every request and written via `noteRateLimited("crunchy", ...)` on a 429; owned by `provider-cooldown.ts`, not by this file. `DEFAULT_COOLDOWN_MS` (`60_000`) and `MAX_COOLDOWN_MS` (`900_000`) bound how long a cooldown can last, also owned by that external module. |

## Deep Linking

Not applicable: this file constructs no application deep link or universal link; its only URL is the fixed Crunchy Bridge API origin (`https://api.crunchybridge.com/clusters`), a provider endpoint, never a link into this application.

## Localization

Not applicable: this file emits no user-facing string. Its two `console.error` calls are developer-facing diagnostics (an HTTP status, a caught error), never text shown to an end user.

## Accessibility Options

Not applicable: this file renders no UI, so Reduce Motion, Increase Contrast, and Differentiate Without Color have nothing to apply to.

## Feature Flags

Not applicable: this file consults no feature-flag system; whether it runs is decided entirely by the presence of `env.CRUNCHY_API_TOKEN`, per **token-gate**.

## Analytics

Not applicable: this file emits no self-referential analytics/telemetry event about its own invocation; producing the `ProviderDeploy` deploy rows is the module's whole purpose, and that is fully specified under Behavioral Requirements, not a side-channel instrumentation event.

## Privacy

- **Data collected**: cluster identity and health metadata — `id`, `name`, `state`, `is_suspended`, `environment`, and `created_at` — read from Crunchy Bridge's `/clusters` response. This is infrastructure metadata about the team's own database clusters, not end-user personal data.
- **Storage**: this file writes nothing to persistent storage; it only fetches and maps. Persisting the resulting deploy rows is a job external to this file.
- **Transmission**: `env.CRUNCHY_API_TOKEN` is sent only as an `Authorization: Bearer` header on the outbound request, never in a query string or request body. The transport origin is hardcoded to `https://`, per **https-transport** — this file, unlike its sibling Cloudflare/GlitchTip/PostHog fetchers, never accepts a caller-supplied host and so cannot be misconfigured onto a non-TLS origin.
- **Retention**: this file holds the token and every fetched cluster field only for the duration of one `fetchCrunchyClusters` call; there is no in-memory cache of any kind.

## Logging

Subsystem: process `console` | Category: monitor

| Event | Level | Message |
|-------|-------|---------|
| The `/clusters` response's `ok` is `false` | error | `` Crunchy /clusters <status> `` |
| The `fetch` call, the abort, or the JSON parse threw | error | `` Crunchy /clusters fetch <err> `` |

## Platform Notes

- **React/Web** (source platform): `fetch-crunchy.ts` lives under `packages/web/packages/status-server/src/monitor/`, on Node's global `fetch`, `AbortController`, and `setTimeout`/`clearTimeout`. It imports `crunchyPhases` from the sibling local module `./deploy-status`, `toValidDate`/`ProviderDeploy` from the sibling local module `./provider-deploy`, and `noteRateLimited`/`rateLimitedUntil` from the separate workspace package `@agentic-toolkit/deploy-platform/cooldown`, whose registry is backed by a cross-thread `SharedArrayBuffer`.
- **SwiftUI**: model `ProviderDeploy` as a `Sendable` struct mirroring the TypeScript interface's fields (optional fields as `String?`/`Date?`); use `URLSession` with `URLRequest.timeoutInterval = 6` (or a `Task` racing `Task.sleep` for cancellation) in place of `AbortController`; port `crunchyPhases`/`toValidDate` as pure, `Sendable` free functions; the cross-thread cooldown registry maps to an `actor` (Swift's idiomatic serialized-access analogue of the source's `Atomics`-guarded `SharedArrayBuffer`) shared between the polling task and any concurrent caller.
- **Compose**: the same structural mapping as SwiftUI — a Kotlin `data class ProviderDeploy`, a coroutine `withTimeout(6_000)` block in place of `AbortController`, `crunchyPhases`/`toValidDate` as pure Kotlin functions, and the shared cooldown registry as a `Mutex`-guarded singleton (or an `AtomicLong` array) shared across coroutine dispatchers.
- **AppKit/UIKit**: identical mapping to SwiftUI's; `URLSession`'s `dataTask`/`data(for:)` with a 6-second `timeoutIntervalForRequest` is the direct analogue of this file's single bounded, non-retried attempt.
- **WinUI 3**: a .NET port uses `HttpClient` with a per-call `CancellationTokenSource` timed via `CancelAfter(TimeSpan.FromSeconds(6))` as the `AbortController` analogue; `System.Text.Json` replaces `res.json()` for the `ClustersBody`/`CrunchyCluster` shapes, modeled as `record` types with nullable properties matching the TypeScript interfaces' optional fields; `crunchyPhases`/`toValidDate` port as static methods on a small helper class; and the cross-thread cooldown registry maps to a `lock`-guarded `Dictionary<string, DateTimeOffset>` (or a `System.Threading.Channels`-fed singleton) shared across the app's background poll `Task` and any UI-thread caller, standing in for the source's `SharedArrayBuffer`/`Atomics` pair. No `Windows.Storage` or `ObservableCollection`/`INotifyPropertyChanged` counterpart applies — this function returns a plain list from one call, not a bound collection or persisted state.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/fetch-crunchy.ts` |

## Design Decisions

- **Decision**: an unrecognized or absent cluster `state` is treated as healthy (`deployPhase: "deployed"`), never as unknown or failed.
  **Rationale**: stated directly in `crunchyPhases`'s doc comment in `deploy-status.ts` — "routine maintenance must not page, and an unrecognised state is not assumed bad."
  **Approved**: pending
- **Decision**: a missing or empty-string `CRUNCHY_API_TOKEN` resolves a successful, empty result rather than an error.
  **Rationale**: stated directly in the file's own header comment — "missing token then dormant" — mirroring `fetchCloudflareDeployments`'s identical gate, so a team that has not adopted the Crunchy Bridge integration reads as healthy-silent rather than raising a platform-health incident for a provider it never configured.
  **Approved**: pending
- **Decision**: every failure path (a non-`ok` HTTP response, a 429, or a thrown/aborted request) collapses to the identical `{ ok: false, deploys: [] }` return shape.
  **Rationale**: stated directly in the file's own header comment — "any failure then ok:false so the platform-health path opens a 'can't reach Crunchy' blind-spot issue" — the caller only needs to know the poll produced nothing trustworthy, not why; the distinction between failure kinds lives only in the `console.error` line.
  **Approved**: pending
- **Decision**: `fetchCrunchyClusters` makes exactly one bounded attempt per call and never retries.
  **Rationale**: not explained with its own reasoning in this file's comment beyond "poll-only, mirroring fetch-cloudflare" — the shared assumption across this monitor's provider pollers is that a failed poll is simply picked up by the next scheduled monitor cycle (external to this file), so an in-call retry is redundant with that outer cadence.
  **Approved**: pending
- **Decision**: the request timeout is a fixed 6,000ms, not exposed as a caller-configurable option (unlike the sibling Cloudflare fetcher's `overallBudgetMs`).
  **Rationale**: not stated with a numeric justification in this file's own comment; the value matches the Cloudflare fetcher's own per-script timeout, but this file gives no explicit reasoning for choosing that figure rather than another.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | passed | Security |

`separation-of-concerns` passes: `fetchCrunchyClusters` only fetches and maps; `crunchyPhases` and `toValidDate` are pure, network-free functions it delegates to, and persisting the resulting deploy rows is a job external to this file. `unit-test-coverage` passes: `crunchy-deployments.test.ts` is a dedicated suite exercising the no-token no-op, successful mapping for all three phase outcomes, the Bearer header, both failure paths (HTTP error and thrown), the environment default, the absent-`clusters` case, and the absent-`state` default. `explicit-error-handling` passes: every failure path (HTTP error, 429, thrown/aborted request) is caught, logged, and resolved as an explicit `{ ok: false, deploys: [] }` — nothing is silently swallowed. `timeout-configuration` passes: the single request is bounded by an `AbortController` cleared in a `finally` block. `retry-with-backoff` fails as written: this file makes exactly one attempt and never retries, a deliberate choice recorded in Design Decisions, not an oversight. `rate-limit-handling` passes: a 429 is recorded via `noteRateLimited` honoring the `retry-after` header, and every subsequent call checks `rateLimitedUntil` before issuing a request, per **cooldown-gate** and **rate-limit-recorded**. `error-response-handling` passes: a non-`ok` HTTP response, a 429, and a thrown/aborted request are each handled by name in the source, even though they converge on the same return shape. `graceful-degradation` passes: an unconfigured integration and every failure mode resolve cleanly rather than throwing past this file's own boundary. `data-integrity` passes: `createdAt` is gated through `toValidDate` with a safe fallback, per **created-at-fallback**, so this file can never construct an Invalid Date. `no-pii-in-logs` passes: both `console.error` lines name only an HTTP status or a caught error, never the token or a response body. `secure-transport` passes: unlike its sibling GlitchTip/PostHog/Cloudflare fetchers, this file hardcodes its request origin to `https://api.crunchybridge.com` rather than accepting a caller-supplied host, so the transport scheme cannot be misconfigured to a non-TLS origin.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation, documenting `fetchCrunchyClusters`'s token/cooldown gating, single bounded request, cluster-to-deploy-row mapping (including the healthy-by-default state handling and the environment/createdAt fallbacks), and the collapsed failure shape shared across HTTP-error, rate-limit, and thrown-exception paths. |
