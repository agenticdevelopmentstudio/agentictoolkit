---
id: b3e2495c-5478-411c-80d7-9eefc2f2e297
title: Status Server Monitor Fetch Cloudflare
domain: agentictoolkit://cookbook/status-server/monitor/fetch-cloudflare
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Polls every Cloudflare Worker script's deployments with bounded fan-out and
  an 18s budget, mapping metadata into ProviderDeploy rows; a no-op absent a token,
  and cools down after a 429.
platforms:
- typescript
- web
tags:
- monitor
- cloudflare
- deploy
- fetcher
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
related:
- agentictoolkit://cookbook/status-server/monitor/alerts
references:
- packages/web/packages/status-server/src/monitor/fetch-cloudflare.ts (agentictoolkit)
- packages/web/packages/status-server/test/cloudflare-deployments.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/provider-cooldown.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Fetch Cloudflare

## Overview

`fetch-cloudflare.ts` (`packages/web/packages/status-server/src/monitor/fetch-cloudflare.ts`) exports one function, `fetchCloudflareDeployments`, the Cloudflare Workers provider adapter behind the status server's deploy-monitor poll cycle (`sync.ts`, external). Given a Cloudflare API token and account id, it lists every Worker script the token can see (falling back to a caller-configured list when the listing fails), fetches each script's deployment history with bounded concurrency, and maps the results into `ProviderDeploy` rows (`./provider-deploy`, external) that the caller upserts into the deploy store. It shares its overall-budget-then-bounded-fan-out shape, its rate-limit cooldown gate, and its blind-spot-vs-healthy-empty-account distinction with the sibling Railway fetcher (`fetch-railway.ts`, external) — several of its own comments say so directly, citing the Railway fetcher as the precedent the identical bug or fix was already solved for.

## Behavioral Requirements

### Signature and No-Op Preconditions

- **env-shape**: `fetchCloudflareDeployments` MUST accept one `env` object with optional fields `CLOUDFLARE_API_TOKEN?: string`, `CLOUDFLARE_ACCOUNT_ID?: string`, `workerScripts?: readonly string[]`, and `overallBudgetMs?: number`, and MUST return a `Promise` resolving to `{ ok: boolean; deploys: ProviderDeploy[] }`.
- **noop-missing-credentials**: When `env.CLOUDFLARE_API_TOKEN` or `env.CLOUDFLARE_ACCOUNT_ID` is falsy (absent, empty string, or otherwise falsy), `fetchCloudflareDeployments` MUST return `{ ok: true, deploys: [] }` immediately, performing no network call.
- **cooldown-gate-on-entry**: Before any network call, `fetchCloudflareDeployments` MUST check `rateLimitedUntil("cloudflare")` (`@agentic-toolkit/deploy-platform/cooldown`, external) and, when it returns a truthy cooldown expiry, MUST return `{ ok: false, deploys: [] }` immediately, performing no network call. This precondition is checked on every call and is independent of the caller-side `guard()` wrapper in `sync.ts` (external), which checks the identical shared registry before invoking this function at all — the check inside this file is a self-contained precondition, not a workaround for `guard` occasionally being bypassed (unit tests, and the second call in the `provider-cooldown.test.ts` cooldown assertions, invoke this function directly without `guard`).

### Budget

- **overall-budget-default**: `fetchCloudflareDeployments` MUST default `overallBudgetMs` to 18,000 (18 seconds) when `env.overallBudgetMs` is not supplied.
- **deadline-starts-before-listing**: The overall deadline (`Date.now() + overallBudgetMs`) MUST be computed before the Worker-script listing call, so the listing's own elapsed time counts against the budget. Per the source's own comment, this mirrors "the same off-by-a-listing fix as the Railway fetcher" — computing the deadline after the listing let the real worst case run past the caller's 20-second `guard` timeout (`PROVIDER_POLL_TIMEOUT_MS` in `sync.ts`, external), causing the whole poll to be discarded as unreachable rather than returning the partial result it had already fetched.
- **listing-timeout**: The Worker-script listing call MUST be aborted after `Math.min(6_000, overallBudgetMs)` milliseconds via an `AbortController`.
- **per-script-timeout**: Each per-script deployments fetch MUST be aborted after `Math.min(6_000, remaining)` milliseconds, where `remaining` is the deadline minus the current time evaluated immediately before that script's fetch starts inside the `mapLimit` worker.
- **budget-exhaustion-stops-new-fetches**: Once the overall deadline has passed (`remaining <= 0`) or any earlier script set the module-local `skipped` flag, `fetchCloudflareDeployments` MUST NOT start a fetch for any further script in the `mapLimit` iteration; it MUST set `skipped = true` and return for that script without incrementing the error count.

### Script Listing and Fallback

- **prefer-live-listing**: `fetchCloudflareDeployments` MUST call `listWorkerScripts(accountId, token, signal)` (`@agentic-toolkit/deploy-platform/providers`, external) to enumerate every Worker script the account exposes, preferring it over any caller-supplied list.
- **fallback-to-configured-scripts**: When the result of `listWorkerScripts` does not carry a `scripts` field (its `WorkerScriptsResult` union's error branch), `fetchCloudflareDeployments` MUST fall back to `(env.workerScripts ?? []).slice()`.
- **blind-spot-vs-empty-account**: When the resulting `scripts` array has length zero, `fetchCloudflareDeployments` MUST return `deploys: []` and MUST set `ok` to `false` when the listing result carried an `error` field, or `true` when the listing genuinely succeeded with zero scripts (`{ scripts: [] }`) and no fallback was needed. Per the source's own comment, a failed listing with no configured fallback is "a BLIND SPOT (we hold a token yet can see nothing), not a healthy empty account," so it MUST surface as `ok: false` to fire the platform-health issue the same way the Railway fetcher's identical case does; a genuine authorized zero-Worker account MUST stay `ok: true`.

### Bounded Concurrent Fan-Out

- **bounded-concurrency-five**: `fetchCloudflareDeployments` MUST fetch each script's deployments through `mapLimit` (`@agentic-toolkit/deploy-platform/util`, external) with a concurrency limit of 5 (`CF_SCRIPT_CONCURRENCY`), never serially and never fully unbounded. Per the source's own comment, a prior serial `for`-loop made total time N scripts times up to 6 seconds, which "chronically blew the budget and returned partials every cycle" on a many-worker account — the same shape the Railway fetcher already fixed with `mapLimit`.
- **429-stops-remaining-queue**: When a per-script fetch receives an HTTP 429 response, `fetchCloudflareDeployments` MUST call `noteRateLimited("cloudflare", res.headers.get("retry-after"))` and MUST set the module-local `skipped` flag to `true`, so that every script not yet started in the `mapLimit` fan-out is also skipped for the remainder of this call. Per the source's own comment, cooling down "means not hammering the rest of the account this cycle either," not only refusing new calls on the NEXT cycle.

### Per-Script Response Handling

- **non-ok-response-is-error**: When a per-script deployments fetch resolves with `res.ok === false` (for any status, including 429), `fetchCloudflareDeployments` MUST log `` Cloudflare Workers <script> <status> `` via `console.error` and MUST set the module-local `anyError` flag to `true`, contributing no rows for that script and continuing to the next script rather than aborting the whole call.
- **thrown-error-is-error**: When a per-script fetch call throws (including the per-script `AbortController` firing), `fetchCloudflareDeployments` MUST catch it, log `` Cloudflare Workers fetch <script> `` plus the error via `console.error`, and set `anyError` to `true`, contributing no rows for that script.
- **deployments-slice-five**: On a successful per-script response, `fetchCloudflareDeployments` MUST read `body.result?.deployments ?? []` and MUST take only the first 5 entries (`.slice(0, 5)`) as the candidate rows for that script.

### Row Mapping

- **row-id-prefix**: Each mapped `ProviderDeploy.id` MUST be the literal string `` cf_ `` concatenated with the Cloudflare deployment's `id` field.
- **row-platform-literal**: Each mapped row's `platform` field MUST be the literal string `cloudflare-pages`, per the source's own comment, "kept as 'cloudflare-pages' — type/glyph/summary maps key on this value" (i.e. this is a deliberate cross-module key, not a mislabeling of a Cloudflare Worker as a Cloudflare Pages deployment).
- **row-project-name-is-script-id**: Each mapped row's `projectName` field MUST be the Worker script id being polled, not any value read from the deployment or its metadata.
- **row-build-phase-null**: Each mapped row's `buildPhase` field MUST be `null`, per the source's own comment, because "Workers deployments are live; no failed-build concept" exists for this provider.
- **row-deploy-phase-deployed**: Each mapped row's `deployPhase` field MUST be the literal `"deployed"`, unconditionally, because every deployment `listWorkerScripts`'s companion deployments endpoint returns is already live.
- **row-environment-production**: Each mapped row's `environment` field MUST be the literal string `"production"`, unconditionally; Cloudflare's Worker deployments endpoint carries no per-deployment environment signal this function reads.
- **row-created-at-validated**: Each mapped row's `createdAt` field MUST be the result of `toValidDate(dep.created_on)` (`./provider-deploy`, external); when that call returns `null` (an unparseable or missing `created_on`), `fetchCloudflareDeployments` MUST log `` Cloudflare deployment <id> has unparseable created_on <value> — skipping `` via `console.error` and MUST exclude that one deployment from the returned rows entirely (via `flatMap` returning `[]` for it), without dropping any other deployment from the same script or failing the script's fetch.
- **row-commit-hash-shortened**: When `dep.metadata?.commit_hash` is a `string`, the mapped row's `commitHash` field MUST be `shortSha(meta.commit_hash)` (`./format`, external, a 7-character truncation); otherwise it MUST be `null`.
- **row-commit-message-full**: When `dep.metadata?.commit_message` is a `string`, the mapped row's `commitMessage` field MUST be `commitFullMessage(meta.commit_message)` (`./format`, external, the whole message capped at 4,000 characters, whitespace-trimmed); otherwise it MUST be `null`.
- **row-branch-passthrough**: When `dep.metadata?.branch` is a `string`, the mapped row's `branch` field MUST be that string unchanged; otherwise it MUST be `null`.
- **row-commit-repo-always-null**: Each mapped row's `commitRepo` field MUST be `null`, unconditionally, per the source's own comment, because "Workers deployment metadata doesn't carry the repo."
- **row-url-always-null**: Each mapped row's `url` field MUST be `null`, unconditionally; unlike the Railway fetcher (external), this function supplies no dashboard-link fallback for `url`.

### Return Value

- **deploys-array-always-populated**: `fetchCloudflareDeployments` MUST return every successfully mapped row from every script's fetch in the `deploys` array, regardless of whether `ok` is `true` or `false` — a partial poll's already-fetched rows MUST NOT be discarded.
- **ok-composition**: The returned `ok` field, for the branch where at least one script was listed and polled, MUST be `!anyError && !skipped` — `true` only when every polled script's fetch succeeded, no 429 was received, and no script was left unpolled for lack of remaining budget.

## Appearance

Not applicable — this is a server-side Cloudflare Workers deployment-polling function, not a visual component.

## States

Not applicable — this is a server-side Cloudflare Workers deployment-polling function, not a visual component; its runtime state (no-op, cooling down, listing, per-script fan-out, budget-exhausted) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side Cloudflare Workers deployment-polling function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-fetch-cloudflare-001 | noop-missing-credentials, env-shape | `fetchCloudflareDeployments({})`; `fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't' })` (no account id) | Both resolve `{ ok: true, deploys: [] }` with no `fetch` call made — both calls type-check with every `env` field except none required, demonstrating the all-optional shape — `cloudflare-deployments.test.ts` › "is a no-op (ok) when the token or account id is not configured" |
| status-server-monitor-fetch-cloudflare-002 | prefer-live-listing, overall-budget-default, row-id-prefix, row-platform-literal, row-project-name-is-script-id, row-build-phase-null, row-deploy-phase-deployed, row-environment-production, row-created-at-validated, row-commit-hash-shortened, row-commit-message-full, row-branch-passthrough, row-commit-repo-always-null, row-url-always-null, deploys-array-always-populated, ok-composition | `listWorkerScripts` mocked to return `{ scripts: ['web'] }`; the script's deployments endpoint returns one deployment `{ id: 'd1', created_on: '2026-06-26T00:00:00.000Z', metadata: { commit_hash: 'abcdef123456', commit_message: 'fix: thing\n\nbody', branch: 'main' } }`; call with a valid token and account id and no `overallBudgetMs` (default applies) | `out.ok === true`; `out.deploys` has length 1; `out.deploys[0]` deep-equals `{ id: 'cf_d1', platform: 'cloudflare-pages', projectName: 'web', buildPhase: null, deployPhase: 'deployed', environment: 'production', commitHash: 'abcdef1', commitMessage: 'fix: thing\n\nbody', branch: 'main', commitRepo: null, url: null, createdAt: new Date('2026-06-26T00:00:00.000Z') }` — the `platform`/`projectName`/`environment` fields are asserted by `cloudflare-deployments.test.ts` › "lists the account workers then fetches each one's deployments"; the remaining fields are fixed by the unmodified row-mapping `flatMap` and are not individually asserted by that test |
| status-server-monitor-fetch-cloudflare-003 | non-ok-response-is-error, deploys-array-always-populated, ok-composition | Two scripts listed (`web`, `broken`); `web`'s deployments call succeeds with one deployment; `broken`'s deployments call returns HTTP 500 | `out.ok === false`; `out.deploys` has length 1 (only `web`'s deploy landed; `broken`'s failure did not discard it) — `cloudflare-deployments.test.ts` › "marks the poll not-ok when a script fetch errors, but keeps the others' deploys" |
| status-server-monitor-fetch-cloudflare-004 | budget-exhaustion-stops-new-fetches, ok-composition | Three scripts listed (`web`, `admin`, `landing`), each would otherwise succeed; called with `overallBudgetMs: 0` | `out.ok === false`; `out.deploys` is an empty array — every script is skipped for budget with no throw — `cloudflare-deployments.test.ts` › "returns a partial (ok:false) instead of discarding the whole poll when the overall budget is spent" |
| status-server-monitor-fetch-cloudflare-005 | deadline-starts-before-listing, listing-timeout | `listWorkerScripts`'s underlying listing fetch is delayed 250ms; called with `overallBudgetMs: 150` | `out.ok === false`; `out.deploys` is `[]`; no `fetch` call to any `/deployments` URL is ever made — the listing alone exhausted the budget before any per-script fetch could start, and the listing's own abort fires at `Math.min(6_000, 150) = 150`ms — `cloudflare-deployments.test.ts` › "spends the listing time against the overall budget (no per-script fetches once spent)" |
| status-server-monitor-fetch-cloudflare-006 | fallback-to-configured-scripts | `listWorkerScripts`'s underlying listing fetch throws `Error('network down')`; `env.workerScripts` is `['web']`; `web`'s deployments call (mocked directly, bypassing the listing) succeeds with one deployment | `out.ok === true`; `out.deploys` has length 1 — the failed live listing falls back to the configured `['web']` list and the poll proceeds normally on it, per fallback-to-configured-scripts |
| status-server-monitor-fetch-cloudflare-007 | blind-spot-vs-empty-account | The underlying `fetch` throws `Error('network down')` on every call (the listing fails and no `env.workerScripts` fallback is supplied) | `out.ok === false`; `out.deploys` is `[]` — a token that cannot list workers with no configured fallback is a blind spot, not a healthy empty account — `cloudflare-deployments.test.ts` › "reports ok:false when the listing fails AND no fallback scripts are configured" |
| status-server-monitor-fetch-cloudflare-008 | bounded-concurrency-five | Three scripts listed (`w1`, `w2`, `w3`); each script's deployments fetch is delayed 120ms | `out.ok === true`; `out.deploys` has length 3; elapsed wall-clock time is under 2.5 × 120ms, i.e. well under the ≈360ms a strictly serial fetch of the three scripts would take — `cloudflare-deployments.test.ts` › "fetches script deployments concurrently, not serially" |
| status-server-monitor-fetch-cloudflare-009 | cooldown-gate-on-entry | The listing fetch itself returns HTTP 429; `fetchCloudflareDeployments` is called once, then called again immediately with the same token and account id | The first call resolves `ok: false`; the second call makes NO additional `fetch` call of any kind (the entry-point cooldown gate short-circuits it before any listing or per-script call) — `provider-cooldown.test.ts` › "cloudflare: a 429 on the script listing cools the provider down" |
| status-server-monitor-fetch-cloudflare-010 | row-created-at-validated | A script lists one deployment whose `created_on` is not a parseable date (e.g. an empty string or garbage value) | That deployment is excluded from `out.deploys` (mapped via `flatMap` to `[]`), and `console.error` is called with a message containing `has unparseable created_on` and the deployment's `id` — traced to the `toValidDate` boundary-validation branch in the row-mapping `flatMap` |
| status-server-monitor-fetch-cloudflare-011 | 429-stops-remaining-queue, deploys-array-always-populated | Six scripts listed (`s1`…`s6`, concurrency limit 5); `s1`'s deployments call resolves immediately with HTTP 429; `s2`–`s5`'s deployments calls each resolve slightly slower with one valid deployment; `s6` is never given a mocked response at all | `out.ok === false`; `out.deploys` has length 4 (`s2`–`s5`'s rows); `fetch` is never called with a URL containing `s6` — the worker that finishes `s1` sets `skipped = true` before it loops to claim `s6`, so `s6`'s callback returns without fetching, per 429-stops-remaining-queue |
| status-server-monitor-fetch-cloudflare-012 | deployments-slice-five | One script (`web`) lists 6 deployments in its `result.deployments` array, each with a valid distinct `id` and `created_on` | `out.deploys` has length 5, containing exactly the first 5 array entries in their original order; the 6th entry's `id` does not appear anywhere in `out.deploys`, per deployments-slice-five's `.slice(0, 5)` |
| status-server-monitor-fetch-cloudflare-013 | per-script-timeout, thrown-error-is-error | One script (`web`) listed; its deployments `fetch` call is mocked to never resolve or reject; called with the default `overallBudgetMs` (18,000) under fake timers advanced past 6,000ms | The per-script `AbortController` fires at `Math.min(6_000, remaining) = 6_000`ms, causing the `fetch` promise to reject with an abort error; the catch block logs `` Cloudflare Workers fetch web `` and sets `anyError`; `out.ok === false` and `out.deploys` is `[]`, resolved within the timeout window rather than hanging indefinitely |

## Edge Cases

- **Null and empty input**: `env.CLOUDFLARE_API_TOKEN` or `env.CLOUDFLARE_ACCOUNT_ID` absent, `undefined`, or an empty string all satisfy the same falsy check and MUST produce the `{ ok: true, deploys: [] }` no-op (noop-missing-credentials) — MUST. `env.workerScripts` absent MUST be treated as an empty array (`env.workerScripts ?? []`) when a fallback is needed — MUST. A script listing that succeeds with zero scripts and no fallback needed MUST return `deploys: []` with `ok: true` (blind-spot-vs-empty-account) — MUST.
- **Boundary values**: exactly 5 deployments or fewer from a script's `deployments` array are all kept; a 6th or later entry is dropped by `.slice(0, 5)` regardless of its own status or recency (deployments-slice-five) — MUST. The concurrency limit is exactly 5 simultaneous per-script fetches (bounded-concurrency-five); a 6th script's fetch does not start until one of the first 5 completes — MUST, per `mapLimit`'s own contract (`map-limit.ts`, external): "at most `limit` in flight."
- **Concurrent access**: this function has no internal mutable state shared across separate calls to `fetchCloudflareDeployments` — its own local variables (`deploys`, `anyError`, `skipped`) are function-scoped and freshly created on each invocation. The provider-cooldown registry it reads and writes (`rateLimitedUntil`, `noteRateLimited`, `@agentic-toolkit/deploy-platform/cooldown`, external) IS shared cross-thread by design — that module's own header comment states it uses a `SharedArrayBuffer` with `Atomics` reads/writes specifically because the monitor cycle and the API-thread's live enumeration are on different Node `Worker` threads and must agree on the same cooldown state. This file makes no attempt at additional synchronization of its own; a 429 noted by a concurrent call to `listWorkerScripts` from a different caller (e.g. live deploy-projects enumeration, external) is visible to this function's own `rateLimitedUntil("cloudflare")` check on its very next invocation, by construction of the shared registry — MUST.
- **Error states**: a non-2xx per-script deployments response is logged and counted as an error but does not abort the remaining scripts (non-ok-response-is-error) — MUST. A thrown fetch (network failure, or the per-script `AbortController` firing) is caught, logged, and counted as an error the same way (thrown-error-is-error) — MUST. A failed script listing with no configured `workerScripts` fallback is reported as `ok: false` (blind-spot-vs-empty-account) — MUST. A 429 anywhere in the per-script fan-out halts the REMAINING unstarted scripts in that same call via the `skipped` flag, but scripts already in flight when the 429 landed run to their own completion or timeout — MUST, per the `mapLimit` worker loop's structure (each worker checks `skipped` only before starting its NEXT item).
- **Offline / disconnected state**: every network call in this function — the listing and each per-script fetch — carries its own `AbortController` timeout bounded by the shared overall deadline (listing-timeout, per-script-timeout), so a fully offline or unresponsive Cloudflare API degrades to the same abort-then-log path as any other unreachable-host failure, contributing `anyError: true` for whichever calls were affected rather than hanging indefinitely — MUST. This function itself makes no retry attempt of any kind on any failure — see the retry-with-backoff Compliance result and the Design Decisions entry below — SHOULD NOT be assumed to recover an offline call within the same poll cycle; the next cycle (roughly 5 minutes later, per the caller's cadence, external) is the only retry.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `CLOUDFLARE_API_TOKEN` | `string \| undefined` (field of `env`) | none — required for a non-no-op poll | The Cloudflare API Bearer token. Absent or empty triggers the no-op branch (noop-missing-credentials). This file reads it only from the `env` object passed in; it does not read `process.env` itself. |
| `CLOUDFLARE_ACCOUNT_ID` | `string \| undefined` (field of `env`) | none — required for a non-no-op poll | The Cloudflare account id to enumerate Workers under. The caller (`sync.ts`, external) resolves this externally via `resolveCfAccountForConn` before calling this function; this file performs no account-id discovery of its own. |
| `workerScripts` | `readonly string[] \| undefined` (field of `env`) | `[]` (via `env.workerScripts ?? []`) | The configured fallback Worker-script id list, used only when `listWorkerScripts` fails to enumerate scripts live (fallback-to-configured-scripts). The caller passes `conn.cloudflare.workerScripts` (external, sourced from the DB integration config). |
| `overallBudgetMs` | `number \| undefined` (field of `env`) | `18_000` | The overall poll budget in milliseconds, counted from before the script listing starts (deadline-starts-before-listing). Per the source's own comment, "under sync's 20s `guard`" — deliberately shorter than the caller's `PROVIDER_POLL_TIMEOUT_MS` (20,000ms, `sync.ts`, external) so this function's own partial-result path fires before the caller's blunter all-or-nothing timeout would discard the whole poll. Overridable, per the source comment, "for tests/tuning." |
| `CF_SCRIPT_CONCURRENCY` (module constant) | `number` | `5` | Fixed fan-out limit for per-script fetches via `mapLimit`; not exposed on `env` and not configurable per call. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only issues outbound `fetch` calls to Cloudflare's REST API and returns in-memory `ProviderDeploy` rows.

## Localization

Not applicable: this file's only user-facing-adjacent strings are `console.error` diagnostic lines read by operators/developers in server logs, not end-user-facing text; none of them route through a localization mechanism, and none are shown to an end user of the monitored product.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; whether it runs at all is gated entirely by the presence of `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` (noop-missing-credentials) and the shared cooldown registry, both already documented under Behavioral Requirements and Configuration, not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only observability output is the `console.error` lines documented under Logging.

## Privacy

- **Data collected**: this file transmits the caller-supplied Cloudflare API token as a Bearer credential on every request it makes; it reads back deployment ids, timestamps, and commit metadata (`commit_hash`, `commit_message`, `branch`) that Cloudflare itself already recorded from the account's own deploys. It collects no data from, and about, an end user of the monitored product.
- **Storage**: none in this file — it holds the token and every fetched row only in local variables and the returned `deploys` array for the duration of one call; persistence is entirely the caller's responsibility (`storage.deploy.upsertDeployments`, `sync.ts`, external).
- **Transmission**: the token is sent as `Authorization: Bearer <token>` on every request to `api.cloudflare.com`, over HTTPS (the URL is a hardcoded `https://` literal); no other destination ever receives the token. Cloudflare's own response, including commit metadata, is received over the same HTTPS connection.
- **Retention**: not applicable to this file directly — it retains nothing after the call returns; how long the mapped rows persist once upserted is governed by the caller's storage layer, external to this file.

## Logging

This file uses plain `console.error` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Per-script deployments fetch returned non-2xx | error (`console.error`) | `` Cloudflare Workers <script> <status> `` |
| Per-script deployments fetch threw | error (`console.error`) | `` Cloudflare Workers fetch <script> `` (plus the caught error, as a second argument) |
| A deployment's `created_on` failed `toValidDate` | error (`console.error`) | `` Cloudflare deployment <id> has unparseable created_on <JSON-stringified value> — skipping `` |

A fully successful poll (every script fetched, no 429, budget not exhausted) produces no log output from this file at any level.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this polling pattern would model the return shape as a `Sendable` `struct { ok: Bool; deploys: [ProviderDeploy] }`, the per-script fan-out as a `TaskGroup` capped to 5 concurrent child tasks (Swift's structured concurrency has no direct `mapLimit` equivalent, so the cap has to be enforced by hand, e.g. releasing a `AsyncSemaphore`-style gate before adding the next child task), and each request's timeout via `URLRequest.timeoutInterval` or a `Task` wrapped in `withThrowingTaskGroup` racing a `Task.sleep` cancellation, mirroring this file's `AbortController`-per-call shape.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the fan-out with `kotlinx.coroutines`' `Semaphore(5)` guarding a `coroutineScope { scripts.map { async { ... } } }` (closer to `mapLimit`'s worker-pool shape than a raw `Dispatchers.IO.limitedParallelism`, which limits the dispatcher rather than one specific batch of work), and each request's timeout via `withTimeoutOrNull` composed with the shared overall deadline, since Ktor/OkHttp's own per-call timeout config is static per client rather than computed per call the way this file recomputes `remaining` before each script.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/fetch-cloudflare.ts` as a plain async function on the Node status backend, imported by `sync.ts`'s poll cycle and `routes/hooks.ts` (both external); it depends on two sibling in-repo modules (`./format`, `./provider-deploy`) and three exports of the vendored `@agentic-toolkit/deploy-platform` package (`util`'s `mapLimit`, `cooldown`'s `noteRateLimited`/`rateLimitedUntil`, `providers`'s `listWorkerScripts`) — none of it is client-side React.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no Node-`Worker`-per-thread module-duplication concern the way the cooldown registry's own design note (external, `provider-cooldown.ts`) worries about; a Swift `actor` wrapping the cooldown slots would be a single shared instance regardless of which thread calls into it, so the cross-thread `SharedArrayBuffer`/`Atomics` mechanism this file's dependency uses has no direct analogue to port — an `actor` already gives the same guarantee for free.
- **WinUI 3**: a .NET port models `ProviderDeploy` as a `record` with the same fields this file populates (`Id`, `Platform`, `ProjectName`, `BuildPhase` nullable, `DeployPhase`, `Environment`, `CommitHash`, `CommitMessage`, `Branch`, `CommitRepo`, `Url`, `CreatedAt`), the per-script fan-out as `Task.WhenAll` over a `SemaphoreSlim(5, 5)`-gated set of tasks (the direct `mapLimit` analogue: acquire before starting a script's `Task`, release in a `finally`), and each request via `HttpClient.GetAsync` with a `CancellationTokenSource` per call whose `CancelAfter` is computed from the same shared deadline this file recomputes as `remaining` before every script — not `HttpClient.Timeout`, which is static per client and cannot express "whatever time is left in the overall budget." Cloudflare's JSON bodies deserialize via `System.Text.Json` records shaped like `WorkerDeploymentMetadata`/`WorkerDeployment`/`WorkersDeploymentsBody`; the boundary-validation pattern in `toValidDate` (accept ISO string, epoch number, or `DateTime`, reject anything that fails to parse) is worth porting explicitly, since `DateTime.Parse` throws by default rather than returning a sentinel the way this file's `toValidDate` does with `null`. The shared cross-thread cooldown registry (`SharedArrayBuffer`/`Atomics` in the source) has no direct .NET analogue needed if the Windows App SDK host runs this poll on a single process without a Node-style per-`Worker` module duplication; a `static` field guarded by `Interlocked`/`lock` suffices for a single-process host, but a multi-process host would need an out-of-process store (e.g. a named memory-mapped file or a shared cache) to preserve the "every caller sees the same cooldown" guarantee this file's dependency provides.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/fetch-cloudflare.ts` |

## Design Decisions

- **Decision**: check `rateLimitedUntil("cloudflare")` at the top of `fetchCloudflareDeployments` itself, even though the caller (`sync.ts`'s `guard` wrapper, external) already performs the identical check before invoking this function during the normal poll cycle.
  **Rationale**: not spelled out in an inline comment on this specific check, but demonstrated as deliberate by the test suite: `provider-cooldown.test.ts`'s "cloudflare: a 429 on the script listing cools the provider down" test calls `fetchCloudflareDeployments` directly, twice, with no `guard` wrapper in between, and asserts the second call makes no additional request. A caller that bypasses `guard` (direct unit-test invocation, or any future caller external to `sync.ts`) still gets the cooldown protection, because the check is a property of this function's own precondition, not solely of the wrapper around it.
  **Approved**: pending
- **Decision**: fetch each script's deployments with a bounded concurrency of exactly 5 (`CF_SCRIPT_CONCURRENCY`), not serially and not fully unbounded.
  **Rationale**: stated directly in the source comment on the `mapLimit` call — a serial loop made total time "N scripts × up to 6s, so a many-worker account chronically blew the budget and returned partials every cycle," which is "the same shape Railway fixed with mapLimit." An unbounded fan-out is avoided per `map-limit.ts`'s own doc comment (external): it would make every script's wall-clock time include time spent queued behind the others, corrupting any per-script timing measurement — though this file does not itself measure per-script timing, the same contention risk (hammering Cloudflare's API with N simultaneous requests) applies.
  **Approved**: pending
- **Decision**: start the overall budget's deadline before the script listing call, not after it.
  **Rationale**: stated directly in the source comment — "the overall budget starts BEFORE the script listing — the listing is part of the poll, so its time counts against the deadline," explicitly citing this as "the same off-by-a-listing fix as the Railway fetcher" (a bug that once existed in that sibling file and was fixed there first).
  **Approved**: pending
- **Decision**: on a 429 from any per-script fetch, set `skipped = true` (which also halts the remaining unstarted scripts) rather than only recording the cooldown and continuing to poll the rest of the account.
  **Rationale**: stated directly in the source comment — "`skipped` also stops the remaining queue after a 429 — cooling down means not hammering the rest of the account this cycle either."
  **Approved**: pending
- **Decision**: treat a failed script listing with no configured `workerScripts` fallback as `ok: false` (a platform-health signal), while a listing that succeeds with genuinely zero scripts stays `ok: true`.
  **Rationale**: stated directly in the source comment — "a failed listing with no configured fallback is a BLIND SPOT (we hold a token yet can see nothing), not a healthy empty account," matching "the Railway fetcher's contract" for the identical situation.
  **Approved**: pending
- **Decision**: keep every successfully mapped deploy row in the returned `deploys` array even when `ok` is `false` for the overall call, rather than discarding everything on any error or partial condition.
  **Rationale**: stated directly in the source comment on the return statement — "the deploys we DID fetch are still upserted by the caller, so a deploy that was reached lands even when the account has too many Workers to poll within one budget."
  **Approved**: pending
- **Decision**: implement no retry of any kind for a failed per-script fetch, a failed listing, or a 429 — a failure is logged (or, for a 429, cooled down) once and the call moves on.
  **Rationale**: not stated in an inline comment as a deliberate tradeoff, but demonstrated as a fact of the code: neither the per-script fetch path nor the listing call is wrapped in any retry loop (contrast the Railway fetcher, external, which retries its listing call once specifically because it is "the FIRST call of the poll and therefore always the coldest"). Recorded here per this recipe's authoring rules as a fact to state, not a gap to excuse — this file relies entirely on the caller's next poll cycle (roughly every 5 minutes, external) as its retry mechanism, and on the shared cooldown registry to avoid retrying INTO an active 429.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` passes: `cloudflare-deployments.test.ts` exercises the no-op precondition, the happy-path listing-then-fetch, a partial failure that still keeps the healthy scripts' deploys, the budget-exhaustion partial, the listing-spends-the-budget contract, the blind-spot-vs-fallback distinction, and bounded concurrency; `provider-cooldown.test.ts` exercises the cross-call cooldown gate. `separation-of-concerns` passes: this file owns exactly one concern (fetching and mapping Cloudflare deploys); it delegates script enumeration to `listWorkerScripts`, bounded fan-out to `mapLimit`, cooldown state to the shared registry, and persistence entirely to its caller, none of which this file reimplements. `explicit-error-handling` passes: every failure path (non-2xx per-script response, a thrown fetch, an unparseable `created_on`) is caught and logged via `console.error` with a distinguishing message, and is reflected in the returned `ok`/`deploys` shape — nothing fails silently with no trace. `timeout-configuration` passes: both the listing call and every per-script call carry an `AbortController` deadline derived from the overall budget. `rate-limit-handling` passes: a 429 from either the listing call (inside `listWorkerScripts`, external) or a per-script call is recorded via `noteRateLimited` honoring `Retry-After`, and `rateLimitedUntil` is checked before this function does any work at all. `retry-with-backoff` fails as written: no failed call of any kind — a non-2xx response, a thrown error, or a 429 — is retried within this function; a failure is logged (or cooled down) once and the call moves on to the next script, relying entirely on the caller's next poll cycle to try again, a deliberate tradeoff recorded as fact in Design Decisions above, not a defended pass. `graceful-degradation` passes: a missing token/account id is a full no-op rather than an error, a partial failure keeps and returns whatever rows were successfully fetched rather than discarding them, and every failure mode resolves to a well-formed `{ ok, deploys }` value rather than throwing out of the function.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
