---
id: 4aad9d0a-4984-4021-ad1f-d8aa6a15b066
title: Status Server Monitor Provider Conn
domain: agentictoolkit://recipes/status-server-monitor-provider-conn
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Assembles a ProviderConn from active storage integrations and StatusConfig
  secrets, then enumerates deploy projects from it — the storage/config-port replacement
  for deploy-platform's DB-based helpers.
platforms:
- typescript
- web
tags:
- monitor
- deploy
- secrets
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
- agenticdevelopercookbook://guidelines/implementing/security/secure-storage
related:
- agentictoolkit://recipes/status-server-config
- agentictoolkit://recipes/status-server-monitor-enrich-deploy-errors
- agentictoolkit://recipes/status-server-monitor-fetch-vercel-projects
references:
- packages/web/packages/status-server/src/monitor/provider-conn.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/conn/index.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/enumerate/index.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/sync.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/refresh-project-meta.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/deploy-logs.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Provider Conn

## Overview

`provider-conn.ts` (`packages/web/packages/status-server/src/monitor/provider-conn.ts`) exports two async functions, `providerConn` and `enumerateDeployProjects`, that assemble a deploy-provider connection and a deploy-project enumeration from the `Storage` and `StatusConfig` ports instead of a live database handle. Per the module's own authoring comment, the pair are "the storage-boundary replacements for `providerConnFromConfig(db)` and `enumerateDeployProjectsVerified(db)`" — two DB-based helpers `@agentic-toolkit/deploy-platform/conn` and `/enumerate` still ship for their own `Db`-holding consumers, but which `status-server` "may no longer call" now that `db` "does not leave `src/libsql/`." `providerConn` reads the storage port's `deploy_integrations` rows, keeps only the active ones, and resolves each one's token by name through `config.secrets` rather than `process.env` — the module's comment states plainly "this package never reads the environment" — then hands both to `providerConnFromIntegrations` (`@agentic-toolkit/deploy-platform/conn`) to build the returned `ProviderConn`. `enumerateDeployProjects` layers on top of it: it resolves a `providerConn`, reads `storage.deploy.listProjectMeta()`, and passes both to `enumerateDeployProjectsFrom` (`@agentic-toolkit/deploy-platform/enumerate`) to produce a `DeployEnumeration`. Four files in `status-server` depend on this module: `monitor/sync.ts` and `monitor/refresh-project-meta.ts` call `providerConn` directly; `routes/reads.ts` and `routes/deploy-logs.ts` also call `providerConn`; `monitor/sync.ts` and `routes/reads.ts` additionally call `enumerateDeployProjects`.

## Behavioral Requirements

### `providerConn`

- **provider-conn-signature**: `providerConn(storage, config)` MUST accept a `Storage` port and a `StatusConfig` port and MUST return a `Promise<ProviderConn>`.
- **active-integration-filter**: `providerConn` MUST call `storage.config.listIntegrations()` and MUST filter the resolved `IntegrationRow[]` to only the rows whose `isActive` field is `true` before passing them onward; an inactive row's `tokenEnvVar`/`config` MUST NOT be read at all.
- **token-lookup-via-secrets**: For each active row whose `tokenEnvVar` is non-`null`, `providerConn` MUST resolve its token by looking that name up in `config.secrets`; for a row whose `tokenEnvVar` is `null`, `providerConn` MUST leave that provider's token `undefined` without performing any `config.secrets` lookup for it.
- **no-direct-env-read**: `providerConn` MUST NOT read `process.env` or any other environment-variable source directly; every credential value MUST originate from `config.secrets`.
- **provider-conn-field-mapping-delegation**: `providerConn` MUST derive the returned `ProviderConn`'s per-provider fields (`vercel.teamId`, `cloudflare.accountId`/`workerScripts`, `railway.projects`) entirely by passing the filtered active-integration array and the `config.secrets`-backed lookup function to `providerConnFromIntegrations`; it MUST NOT reimplement that per-provider mapping itself. A row's extra fields (`id`, `label`, `secretRef`, `createdAt`, `updatedAt`) are never read by that mapping — only `platform`, `config`, and `tokenEnvVar` are.
- **provider-conn-no-caching**: `providerConn` MUST call `storage.config.listIntegrations()` afresh on every invocation; it MUST NOT cache, memoize, or otherwise reuse a previous invocation's `IntegrationRow[]` or resolved `ProviderConn` — each call reflects the storage and `config.secrets` state at the moment it is called.
- **provider-conn-shape**: The `ProviderConn` `providerConn` resolves to MUST carry exactly the four provider keys `vercel: { token?, teamId? }`, `cloudflare: { token?, accountId?, workerScripts? }`, `railway: { token?, projects? }`, and `crunchy: { token? }`, with every field present on the object but `undefined` whenever the corresponding integration is missing, inactive, or lacks that `config` key.

### `enumerateDeployProjects`

- **enumerate-deploy-projects-signature**: `enumerateDeployProjects(storage, config)` MUST accept the same `Storage`/`StatusConfig` pair and MUST return a `Promise<DeployEnumeration>`.
- **enumerate-inputs-from-storage**: `enumerateDeployProjects` MUST build a `DeployEnumerationInputs` value whose `conn` field is the result of `providerConn(storage, config)` and whose `projectMeta` field is the result of `storage.deploy.listProjectMeta()`, and MUST pass that value to `enumerateDeployProjectsFrom` unmodified.
- **enumerate-sequential-not-concurrent**: `enumerateDeployProjects` MUST resolve `conn` (awaiting `providerConn`) before evaluating `storage.deploy.listProjectMeta()` — the two calls are sequential object-literal property evaluations, not a `Promise.all` — in contrast to `enumerateDeployProjectsVerified(db)` (`@agentic-toolkit/deploy-platform/enumerate`, external), whose analogous pair (`providerConnFromConfig(db)` and the project-meta table read) resolves concurrently via `Promise.all`.
- **enumerate-delegation-only**: `enumerateDeployProjects` MUST return exactly the `DeployEnumeration` value `enumerateDeployProjectsFrom` resolves to, performing no further filtering, transformation, sorting, or caching of that result itself.
- **enumerate-no-own-network-calls**: Neither `providerConn` nor `enumerateDeployProjects` MUST issue an HTTP request, open a socket, or otherwise contact a deploy provider directly; every provider-facing network call (Vercel domain lookups, Railway project/domain queries, Cloudflare account and worker-script calls) happens inside `enumerateDeployProjectsFrom`, or, for a caller that uses `providerConn` alone, inside whichever function receives the returned `ProviderConn`.

### Data Shape Contracts

- **deploy-enumeration-shape**: The `DeployEnumeration` `enumerateDeployProjects` resolves to MUST carry `projects: EnumeratedProject[]`, `verifiedPlatforms: string[]`, and `verifiedDomains: string[]`, exactly as `enumerateDeployProjectsFrom` defines them — this module adds no field to, and removes no field from, that shape.
- **project-meta-row-shape-matches-project-meta-like**: `Storage.deploy.listProjectMeta()`'s resolved `ProjectMetaRow[]` (`platform`, `projectName`, `domain`, `gitRepo`, `gitBranch`, `rootDirectory`, `framework`) MUST line up field-for-field with the `ProjectMetaLike` shape `enumerateDeployProjectsFrom` expects for its `projectMeta` input, since `ProjectMetaRow` is defined as an alias of `ProjectMetaInput`, whose fields are the same seven names.
- **integration-row-shape-satisfies-integration-like**: `Storage.config.listIntegrations()`'s resolved `IntegrationRow[]` MUST carry at least the `platform`, `config`, and `tokenEnvVar` fields `IntegrationLike` (the shape `providerConnFromIntegrations` reads) requires; `IntegrationRow`'s additional fields (`id`, `label`, `secretRef`, `isActive`, `createdAt`, `updatedAt`) are accepted on the array elements but never read by that mapping.

## Appearance

Not applicable — this is a storage/config-port connection-and-enumeration assembler, not a visual component.

## States

Not applicable — this is a storage/config-port connection-and-enumeration assembler, not a visual component; it holds no state machine of its own (see provider-conn-no-caching), so there is no runtime state to place here either.

## Accessibility

Not applicable — this is a storage/config-port connection-and-enumeration assembler, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-provider-conn-001 | active-integration-filter, provider-conn-field-mapping-delegation, integration-row-shape-satisfies-integration-like | `storage.config.listIntegrations()` resolves two rows: `{ id: 'i1', platform: 'vercel', label: 'v', config: { teamId: 'team_1' }, tokenEnvVar: 'VERCEL_API_TOKEN', secretRef: null, isActive: true, createdAt, updatedAt }` and `{ id: 'i2', platform: 'railway', label: 'r', config: {}, tokenEnvVar: 'RAILWAY_API_TOKEN', secretRef: null, isActive: false, createdAt, updatedAt }`; `config.secrets = { VERCEL_API_TOKEN: 'tok_v', RAILWAY_API_TOKEN: 'tok_r' }` | `providerConn` resolves `conn.vercel` equal to `{ token: 'tok_v', teamId: 'team_1' }` and `conn.railway` equal to `{ token: undefined, projects: undefined }` — the inactive row is filtered out before `providerConnFromIntegrations` ever runs, so `RAILWAY_API_TOKEN` is never looked up in `config.secrets` |
| status-server-monitor-provider-conn-002 | no-direct-env-read, token-lookup-via-secrets | One active row `{ platform: 'crunchy', config: {}, tokenEnvVar: 'CRUNCHY_API_TOKEN', isActive: true, ... }`; `config.secrets = { CRUNCHY_API_TOKEN: 'tok_c' }`; `process.env.CRUNCHY_API_TOKEN` set to a different value `'env_tok_c'` | `conn.crunchy.token === 'tok_c'` — resolved from `config.secrets`, never from `process.env`, which is never consulted |
| status-server-monitor-provider-conn-003 | enumerate-inputs-from-storage, deploy-enumeration-shape | `storage.deploy.listProjectMeta()` resolves `[{ platform: 'vercel', projectName: 'site-a', domain: 'a.example.com', gitRepo: null, gitBranch: null, rootDirectory: null, framework: null }]`; `storage.config.listIntegrations()` resolves `[]` | `enumerateDeployProjects` resolves a `DeployEnumeration` whose `projects` contains one `vercel`/`site-a` entry with `domain: 'a.example.com'` (the meta-derived pair surfaces regardless of `conn.vercel.token`) and whose `verifiedPlatforms` is `[]` (no live Railway/Cloudflare read occurred and no Vercel token means `vercelDomainsLive` is `false`) |
| status-server-monitor-provider-conn-004 | enumerate-sequential-not-concurrent | `storage.config.listIntegrations()` rejects with `Error('integrations unavailable')`; `storage.deploy.listProjectMeta` is a spy | `enumerateDeployProjects`'s returned promise rejects with that same `Error`, and the `storage.deploy.listProjectMeta` spy records zero calls — the sequential `await providerConn(...)` throws before the next object-literal property is ever evaluated |
| status-server-monitor-provider-conn-005 | enumerate-sequential-not-concurrent, enumerate-inputs-from-storage | `storage.config.listIntegrations()` resolves `[]` (so `providerConn` resolves normally); `storage.deploy.listProjectMeta()` rejects with `Error('meta unavailable')` | `enumerateDeployProjects`'s returned promise rejects with that same `Error`, after `providerConn`'s own work already completed once |
| status-server-monitor-provider-conn-006 | enumerate-delegation-only, deploy-enumeration-shape | `storage.config.listIntegrations()` resolves `[]`; `storage.deploy.listProjectMeta()` resolves `[]` | `enumerateDeployProjects` resolves `{ projects: [], verifiedPlatforms: [], verifiedDomains: [] }` — every provider is tokenless and every meta list is empty, so `enumerateDeployProjectsFrom`'s own fallbacks degrade to empty on every branch |
| status-server-monitor-provider-conn-007 | token-lookup-via-secrets | One active row `{ platform: 'vercel', config: {}, tokenEnvVar: null, isActive: true, ... }`; `config.secrets = { VERCEL_API_TOKEN: 'tok_v' }` | `conn.vercel.token === undefined` — a `null` `tokenEnvVar` short-circuits before any `config.secrets` lookup, so the presence of `VERCEL_API_TOKEN` in `config.secrets` has no effect |
| status-server-monitor-provider-conn-008 | provider-conn-no-caching, provider-conn-shape | `providerConn(storage, config)` is called twice in sequence; between the two calls the test mutates the stub's next `storage.config.listIntegrations()` resolution from `[]` to one active Vercel row with a token | The first call resolves `conn.vercel.token === undefined`; the second call resolves `conn.vercel.token === 'tok_v'` — proving no memoized result from the first call is reused |
| status-server-monitor-provider-conn-009 | enumerate-no-own-network-calls, provider-conn-field-mapping-delegation | Global `fetch` stubbed to throw immediately if called at all; `storage.config.listIntegrations()` resolves one active, fully-configured row; `config.secrets` populated | `providerConn` resolves the correct `ProviderConn` and the stubbed `fetch` records zero calls — `providerConn` and `providerConnFromIntegrations` perform no I/O of their own |
| status-server-monitor-provider-conn-010 | project-meta-row-shape-matches-project-meta-like | `storage.deploy.listProjectMeta()` resolves one row `{ platform: 'vercel', projectName: 'site-b', domain: 'b.example.com', gitRepo: 'org/repo-b', gitBranch: 'main', rootDirectory: null, framework: 'next' }`; `conn.vercel.token` unset | The resulting `DeployEnumeration.projects` entry for `site-b` carries `gitRepo === 'org/repo-b'`, `gitBranch === 'main'`, `framework === 'next'` unchanged — the seven `ProjectMetaRow` field names flow through `enumerateDeployProjectsFrom`'s `metaByKey`/`vercelCf` mapping only because they line up 1:1 with `ProjectMetaLike` |

## Edge Cases

- **Null and empty input**: `storage.config.listIntegrations()` resolving `[]` MUST leave every provider's token and config fields `undefined` with no throw (status-server-monitor-provider-conn-006). An active row's `tokenEnvVar` being `null` MUST leave that provider's token `undefined` without a `config.secrets` lookup (status-server-monitor-provider-conn-007). `storage.deploy.listProjectMeta()` resolving `[]` MUST leave `enumerateDeployProjects`'s Vercel/Cloudflare project pairs empty, since those pairs are seeded only from `metas` (plus live Cloudflare worker scripts) inside `enumerateDeployProjectsFrom` — MUST.
- **Boundary values**: This module defines no numeric or size-bounded input of its own — no page size, timeout constant, or retry count appears in `provider-conn.ts`. The only bounded value it touches is the boolean `isActive` filter, whose two values (`true`/`false`) are both exercised by active-integration-filter — MUST filter correctly on both. The numeric boundaries governing the deploy-project enumeration itself (Railway's 6,000ms per-project domain timeout, its 2-attempt retry cap, its 4-way concurrency limit) belong to `enumerateDeployProjectsFrom` (`@agentic-toolkit/deploy-platform/enumerate`), which this module calls but does not define, per enumerate-delegation-only.
- **Concurrent access**: `provider-conn.ts` holds no module-level variable, cache, or singleton of any kind — every field it reads comes from the `storage`/`config` arguments passed to that specific call. Two overlapping invocations (e.g. a monitor cycle's `sync.ts` call racing a concurrent `/deployments/:id/log` request's `deploy-logs.ts` call) are therefore fully independent: each performs its own storage reads and its own downstream calls with no shared mutable data between them, so nothing in this file itself can race — a fact of the module holding no state, not a claim about `enumerateDeployProjectsFrom`'s own internal fan-out (documented, and out of scope, in that file) — MUST.
- **Error states**: A rejection from `storage.config.listIntegrations()` MUST propagate as `providerConn`'s own rejection, uncaught — neither function contains a `try`/`catch` (status-server-monitor-provider-conn-004). A rejection from `storage.deploy.listProjectMeta()` MUST propagate as `enumerateDeployProjects`'s own rejection the same way (status-server-monitor-provider-conn-005). A rejection from `enumerateDeployProjectsFrom` itself MUST propagate unmodified; recovery is entirely the caller's responsibility — `monitor/sync.ts` (external) wraps its own call to `enumerateDeployProjects` in a `.catch` that falls back to an empty enumeration, while `routes/reads.ts` (external) lets a rejection propagate further — provider-conn.ts performs no recovery for either caller — MUST.
- **Offline / disconnected state**: Neither `providerConn` nor `enumerateDeployProjects` is itself a network client (enumerate-no-own-network-calls); whichever provider's HTTP call fails inside `enumerateDeployProjectsFrom` because that provider is unreachable is caught and degraded entirely inside that file's own per-provider timeouts and fallback lists, never inside `provider-conn.ts` — this file implements none of that resilience itself and MUST NOT be read as doing so.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | required, caller-supplied | `providerConn` reads `storage.config.listIntegrations()`; `enumerateDeployProjects` additionally reads `storage.deploy.listProjectMeta()`. |
| `config` (parameter) | `StatusConfig` | required, caller-supplied | Only `config.secrets` is read, by the `tokenEnvVar` name each active integration row supplies; `config.credentials` is never read by this file. |
| Integration row `tokenEnvVar` | `string \| null` (`IntegrationRow`) | `null` — that provider's token stays `undefined` | The credential NAME `providerConn` looks up in `config.secrets`; never a literal token value itself. |
| Integration row `isActive` | `boolean` (`IntegrationRow`) | — | Only rows with `isActive === true` are passed into `providerConnFromIntegrations`; inactive rows are filtered out before this module hands anything to `deploy-platform`. |
| Integration row `config` | `Record<string, unknown>` (`IntegrationRow`) | `{}` | Non-secret per-provider settings (`teamId`, `accountId`, `workerScripts`, `projects`) `providerConnFromIntegrations` reads, keyed by provider platform name. |

## Deep Linking

Not applicable: `provider-conn.ts` defines no URL scheme, route, or navigation target of its own; the `ProviderConn`/`DeployEnumeration` values it returns are internal data consumed by other `status-server` modules and routes, never a deep-link destination.

## Localization

Not applicable: `provider-conn.ts` contains no string literal used as user-facing copy — every value it produces is a typed connection field or a caller-supplied domain value (`platform`, `projectName`, `domain`) passed through unchanged, never a message rendered to an end user.

## Accessibility Options

Not applicable: this is a server-side data-assembly module with no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: neither `providerConn` nor `enumerateDeployProjects` consults a feature-flag system; whether a given provider is configured is gated entirely by that provider's integration row being active and carrying a resolvable token (active-integration-filter, token-lookup-via-secrets), never a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only output is the `ProviderConn` or `DeployEnumeration` value it returns to its caller.

## Privacy

- **Data collected**: this module reads and forwards the operator's own provider credentials — whichever of `VERCEL_API_TOKEN`, `CLOUDFLARE_API_TOKEN`, `RAILWAY_API_TOKEN`, `CRUNCHY_API_TOKEN`, or any other `tokenEnvVar` name an integration row supplies — resolved through `config.secrets`, plus each provider's own non-secret settings (`teamId`, `accountId`, `workerScripts`, `projects`) and the persisted project metadata (`platform`, `projectName`, `domain`, `gitRepo`, `gitBranch`, `rootDirectory`, `framework`) from `storage.deploy.listProjectMeta()`. It collects nothing from, or about, an end user of the monitored product.
- **Storage**: neither function persists anything; both return a freshly assembled in-memory value on every call (provider-conn-no-caching) with no cache and no write-back to storage.
- **Transmission**: this file itself never makes an HTTP call (enumerate-no-own-network-calls), so it never transmits a credential anywhere directly; it hands the resolved `ProviderConn` — including token values — to its caller (`enumerateDeployProjectsFrom`, or a `status-server` route/monitor function), which is what eventually sends a Bearer token over HTTPS to that one provider's own API host.
- **Retention**: none — the resolved `ProviderConn`/`DeployEnumeration` lives only in the calling function's local variable for the duration of one request or one monitor cycle; nothing in this file writes it anywhere durable.

## Logging

Neither `providerConn` nor `enumerateDeployProjects` calls `console.*` or any other logger at any point in the given source. A failure from either surfaces only as a rejected `Promise` to the caller (see Edge Cases: Error states) — there is no log line emitted by this file itself, in contrast to `enumerateDeployProjectsFrom` (external), which does log via `console.error` on a Railway domain-lookup timeout that fires with its box already aborted.

## Platform Notes

- **SwiftUI**: not a view concern (no UI). An Apple companion backend embedding this pattern models `providerConn`/`enumerateDeployProjects` as two `async throws` functions on a stateless type (a plain `struct` or an `actor` only if the storage/config ports themselves need actor isolation), taking a `StorageProtocol`-conforming value and a `Sendable` `StatusConfig` struct and returning a `ProviderConn` struct with four optional-field sub-structs; `[String: String?]` stands in for `Record<string, string | undefined>` as the `secrets` lookup, and `Dictionary` subscript access mirrors the JS bracket lookup's "missing key returns nil" behavior exactly.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the pair as two `suspend fun`s on a stateless class or top-level functions, `Map<String, String?>` for `config.secrets`, and a `data class ProviderConn(val vercel: VercelConn, val cloudflare: CloudflareConn, val railway: RailwayConn, val crunchy: CrunchyConn)` with each sub-type's fields nullable rather than optional, mirroring the JS `?`-typed fields.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/provider-conn.ts`, two plain exported `async` functions on the Node status backend; it depends on the in-repo `Storage`/`StatusConfig` port types (`../storage/ports`, `../config/port`) and two exports of the vendored `@agentic-toolkit/deploy-platform` package (`conn`'s `providerConnFromIntegrations`/`ProviderConn`, `enumerate`'s `enumerateDeployProjectsFrom`/`DeployEnumeration`) — none of it is client-side React.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — no App Kit or UIKit concern, since nothing here renders a view; a macOS/iOS agent process embedding this pattern has no additional consideration beyond the SwiftUI bullet above.
- **WinUI 3**: a .NET port models the pair as `Task<ProviderConn> ProviderConnAsync(IStorage storage, StatusConfig config)` and `Task<DeployEnumeration> EnumerateDeployProjectsAsync(IStorage storage, StatusConfig config)`, with `config.secrets` typed as `IReadOnlyDictionary<string, string?>` and looked up via `TryGetValue` (the `TryGetValue`-returns-false-on-miss shape is the direct analogue of the JS bracket lookup returning `undefined`). `ProviderConn` becomes a `record ProviderConn(VercelConn Vercel, CloudflareConn Cloudflare, RailwayConn Railway, CrunchyConn Crunchy)` of small nested records with nullable properties; unlike TypeScript's structural typing, `IntegrationRow` must explicitly implement (or be projected onto) an `IIntegrationLike` interface exposing `Platform`, `Config`, and `TokenEnvVar` for the analogue of `providerConnFromIntegrations` to accept it, since C# has no implicit structural subtyping across separately-declared types — the equivalent of project-meta-row-shape-matches-project-meta-like and integration-row-shape-satisfies-integration-like must be enforced by an explicit interface or mapping method rather than relying on the compiler to accept a wider object shape. `EnumerateDeployProjectsAsync` should preserve `enumerate-sequential-not-concurrent`'s ordering unless the port deliberately chooses to parallelize with `Task.WhenAll`, in which case that divergence from this recipe's traced source behavior belongs in that port's own Design Decisions. Neither this recipe's source nor a WinUI port needs `Windows.Storage`, `HttpClient`, or `System.Text.Json` directly in this specific file — those belong to whichever downstream function consumes the returned `ProviderConn`/`DeployEnumeration` (the by-id log fetch, the deploy-provider poll) — and no `ObservableCollection`/`INotifyPropertyChanged` applies, since nothing here is bound to a UI surface.

## Design Decisions

- **Decision**: read provider connections and project metadata through the `Storage`/`StatusConfig` ports instead of calling the deploy-platform package's own DB-based helpers (`providerConnFromConfig(db)`, `enumerateDeployProjectsVerified(db)`) directly.
  **Rationale**: stated directly in the source's own module comment — these are "the storage-boundary replacements" for those two helpers, which the deploy-platform package "still ships for its OWN Db-holding consumers, but which status-server may no longer call now that `db` does not leave `src/libsql/`." Every remaining `status-server` site that needs a provider connection or a live enumeration goes through `providerConn`/`enumerateDeployProjects` instead, per that same comment.
  **Approved**: pending
- **Decision**: resolve each integration row's token through `config.secrets`, keyed by the row's own `tokenEnvVar` name, rather than reading `process.env` directly inside this file.
  **Rationale**: stated directly in the source's own doc comment on `providerConn` — "the host decides what a credential name means; this package never reads the environment." This keeps the credential source pluggable per host (an env-var host, or a future secrets-manager host) without changing this file.
  **Approved**: pending
- **Decision**: resolve `conn` and read `storage.deploy.listProjectMeta()` sequentially (two ordinary `await`s inside one object literal) rather than concurrently via `Promise.all`, unlike the DB-based `enumerateDeployProjectsVerified(db)` it replaces.
  **Rationale**: not stated as a deliberate tradeoff in an inline comment; demonstrated as a fact of the code, per enumerate-sequential-not-concurrent. Recorded here per source-fidelity as fact, not endorsement — a reader who assumes this replacement preserved the DB-based helper's concurrency would be wrong, and a port that wants the faster concurrent shape should note that divergence explicitly rather than silently matching this file's sequential order.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | failed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` fails: no test file in `packages/web/packages/status-server/test/` exercises `providerConn` or `enumerateDeployProjects` directly — a repo-wide search finds only a comment mentioning `providerConnFromConfig` in `issues.test.ts`, not an assertion against this file's own two exports; the ten vectors above are derived directly from reading the source, not from an existing test suite, per this recipe's own authoring rules. `separation-of-concerns` passes: this file owns exactly one concern — translating the storage/config ports into the shapes `deploy-platform`'s pure `providerConnFromIntegrations` and `enumerateDeployProjectsFrom` expect — and delegates all per-provider field mapping, network access, and project enumeration to that vendored package, reimplementing none of it. `explicit-error-handling` passes on its narrow "MUST NOT silently swallow" bar: neither function contains a `try`/`catch` of any kind, so nothing here catches-and-discards an error; every rejection from `storage` or from `enumerateDeployProjectsFrom` surfaces intact to the caller, which is exactly the fail-fast, caller-decides pattern `monitor/sync.ts`'s own explicit `.catch` around `enumerateDeployProjects` (external) depends on. `graceful-degradation` fails as written: this file itself has no fallback for an unavailable `storage` or a rejecting `enumerateDeployProjectsFrom` — every dependency failure propagates as an unhandled rejection, and any degradation (an empty-enumeration fallback, for instance) is implemented entirely by the caller, not here — a deliberate design choice recorded above in Design Decisions, not a defended pass. `fault-tolerance` passes: `providerConn`'s own composition tolerates malformed-but-well-typed input without crashing — a missing integration row, a `null` `tokenEnvVar`, or an absent `config` key each resolve to `undefined` fields via optional chaining and nullish coalescing in `providerConnFromIntegrations`, never a thrown `TypeError`, per provider-conn-shape and the null/empty-input edge cases above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
