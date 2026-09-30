<!-- leaf: implement-status-server-monitor-2/provider-conn · source: status-server-monitor-provider-conn.md -->

**Rules** (cite as `implement-status-server-monitor-2/provider-conn#<slug>`):

- `provider-conn-signature` MUST
- `active-integration-filter` MUST
- `token-lookup-via-secrets` MUST
- `no-direct-env-read` MUST
- `provider-conn-field-mapping-delegation` MUST
- `provider-conn-no-caching` MUST
- `provider-conn-shape` MUST
- `enumerate-deploy-projects-signature` MUST
- `enumerate-inputs-from-storage` MUST
- `enumerate-sequential-not-concurrent` MUST
- `enumerate-delegation-only` MUST
- `enumerate-no-own-network-calls` MUST
- `deploy-enumeration-shape` MUST
- `project-meta-row-shape-matches-project-meta-like` MUST
- `integration-row-shape-satisfies-integration-like` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | required, caller-supplied | `providerConn` reads `storage.config.listIntegrations()`; `enumerateDeployProjects` additionally reads `storage.deploy.listProjectMeta()`. |
| `config` (parameter) | `StatusConfig` | required, caller-supplied | Only `config.secrets` is read, by the `tokenEnvVar` name each active integration row supplies; `config.credentials` is never read by this file. |
| Integration row `tokenEnvVar` | `string \| null` (`IntegrationRow`) | `null` — that provider's token stays `undefined` | The credential NAME `providerConn` looks up in `config.secrets`; never a literal token value itself. |
| Integration row `isActive` | `boolean` (`IntegrationRow`) | — | Only rows with `isActive === true` are passed into `providerConnFromIntegrations`; inactive rows are filtered out before this module hands anything to `deploy-platform`. |
| Integration row `config` | `Record<string, unknown>` (`IntegrationRow`) | `{}` | Non-secret per-provider settings (`teamId`, `accountId`, `workerScripts`, `projects`) `providerConnFromIntegrations` reads, keyed by provider platform name. |

## Privacy

- **Data collected**: this module reads and forwards the operator's own provider credentials — whichever of `VERCEL_API_TOKEN`, `CLOUDFLARE_API_TOKEN`, `RAILWAY_API_TOKEN`, `CRUNCHY_API_TOKEN`, or any other `tokenEnvVar` name an integration row supplies — resolved through `config.secrets`, plus each provider's own non-secret settings (`teamId`, `accountId`, `workerScripts`, `projects`) and the persisted project metadata (`platform`, `projectName`, `domain`, `gitRepo`, `gitBranch`, `rootDirectory`, `framework`) from `storage.deploy.listProjectMeta()`. It collects nothing from, or about, an end user of the monitored product.
- **Storage**: neither function persists anything; both return a freshly assembled in-memory value on every call (provider-conn-no-caching) with no cache and no write-back to storage.
- **Transmission**: this file itself never makes an HTTP call (enumerate-no-own-network-calls), so it never transmits a credential anywhere directly; it hands the resolved `ProviderConn` — including token values — to its caller (`enumerateDeployProjectsFrom`, or a `status-server` route/monitor function), which is what eventually sends a Bearer token over HTTPS to that one provider's own API host.
- **Retention**: none — the resolved `ProviderConn`/`DeployEnumeration` lives only in the calling function's local variable for the duration of one request or one monitor cycle; nothing in this file writes it anywhere durable.

