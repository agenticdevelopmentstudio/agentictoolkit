<!-- leaf: implement-status-server-monitor-2/provider-deploy · source: status-server-monitor-provider-deploy.md -->

**Rules** (cite as `implement-status-server-monitor-2/provider-deploy#<slug>`):

- `provider-deploy-required-fields` MUST
- `provider-deploy-optional-fields` MAY
- `provider-project-id-identity-key` MUST
- `error-text-out-of-band-only` MUST
- `confirmed-at-fetcher-omission` MUST
- `to-valid-date-nullish-rejection` MUST
- `to-valid-date-type-rejection` MUST
- `to-valid-date-construction` MUST
- `dto-passthrough-fields` MUST
- `dto-provider-project-id-coalesce` MUST
- `dto-error-text-coalesce` MUST
- `dto-status-derivation` MUST
- `dto-tier-gate` MUST
- `dto-live-host-passthrough` MUST
- `iso-serialize-valid-date` MUST
- `iso-serialize-invalid-date-fail-soft` MUST
- `dto-created-at-via-iso-serialize` MUST
- `dto-phase-confirmed-at-fallback` MUST

# Status Server Monitor Provider Deploy

## Overview

`provider-deploy.ts` (`packages/web/packages/status-server/src/monitor/provider-deploy.ts`) is a pure, synchronous logic module in the status backend. It exports the `ProviderDeploy` interface — a deployment exactly as a provider fetcher or webhook mapper reports it, described by the file's own header comment as "structurally the old deployments-table row minus the storage-only columns" (a `liveHost` is stamped from config at serve time; a `fetchedAt` was a storage artifact) — the trust-boundary timestamp parser `toValidDate`, and `providerDeployToDTO`, which shapes a `ProviderDeploy` plus a resolved `liveHost` into the wire `DeploymentDTO` (`types.ts`) that the client renders. `providerDeployToDTO` composes two other pure modules external to this file: `combinedStatus` from `deploy-status.ts` (agentictoolkit://recipes/status-server-monitor-deploy-status) derives the single `status` field, and `deployEnv` plus `isRealEnvDeployRow` from `deploy-view.ts` (agentictoolkit://recipes/status-server-monitor-deploy-view) derive the `tier` field. Every provider fetcher (`fetch-vercel.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, `fetch-vercel-projects.ts`) and the webhook mapper (`webhook-events.ts`) import `toValidDate` and the `ProviderDeploy` type to construct rows at the trust boundary; `routes/reads.ts` is `providerDeployToDTO`'s only caller, once for a persisted row (via its own `rowToProviderDeploy`, which stamps `confirmedAt` from the row's `fetched_at`) and once for a live-buffer overlay row (whose `confirmedAt` is stamped from the webhook's own receipt time). This file performs no network call, no database read or write, and holds no state between calls; its one side effect is a single `console.error` call inside the module-private `isoOf` helper, reached only when a legacy row's `createdAt` is already an Invalid Date.

## Behavioral Requirements

### `ProviderDeploy` Data Shape

- **provider-deploy-required-fields**: A `ProviderDeploy` value MUST carry `id: string`, `platform: string`, `projectName: string`, `buildPhase: BuildPhase | null`, `deployPhase: DeployPhase`, `environment: string | null`, `commitHash: string | null`, `commitMessage: string | null`, `branch: string | null`, `commitRepo: string | null`, `url: string | null`, and `createdAt: Date`; per the interface's own inline comments, `id` MUST be one of the four provider-prefixed shapes `'vc_<uid>'`, `'cf_<id>'`, `'ry_<id>'`, `'cr_<id>'`, `platform` MUST be one of `'vercel'`, `'cloudflare-pages'`, `'railway'`, `'crunchy'`, and `commitRepo` MUST be an `'owner/name'` pair when present, used to build a GitHub commit link.
- **provider-deploy-optional-fields**: A `ProviderDeploy` value MAY omit `providerProjectId` (`string | null`), `errorText` (`string | null`), and `confirmedAt` (`Date`) entirely; these three fields carry no default and their absence is a distinct, meaningful state from a present `null` (only `providerProjectId` and `errorText` accept an explicit `null`; `confirmedAt` accepts only presence or absence).
- **provider-project-id-identity-key**: A consumer resolving a `ProviderDeploy`'s identity against a board target MUST key on `providerProjectId ?? projectName`, per the field's own doc comment; `providerProjectId` MUST be left absent for any platform whose fetcher has not adopted provider-issued project ids, so that platform keeps working unchanged and id adoption remains a per-platform change rather than a flag day.
- **error-text-out-of-band-only**: No provider fetcher and no webhook mapper in this codebase MUST set `errorText` when constructing a `ProviderDeploy`; per the field's own comment, `errorText` MUST be populated only out-of-band, by `enrich-deploy-errors.ts` (external to this file), and is otherwise read back unchanged off the persisted row.
- **confirmed-at-fetcher-omission**: A `ProviderDeploy` constructed directly from freshly fetched or freshly received provider truth (a poll fetcher or a webhook mapper) MUST leave `confirmedAt` absent, because, per the field's own comment, that construction's own confirmation time is "now" and the row is persisted before it is served; a caller reconstructing a `ProviderDeploy` from a persisted row or a live-buffer overlay MUST supply `confirmedAt` from that row's own confirmation timestamp (the persisted `fetched_at`, or a webhook overlay's receipt time) rather than leaving it absent.

### `toValidDate`

- **to-valid-date-nullish-rejection**: `toValidDate(raw)` MUST return `null` when `raw` is `null` or `undefined`, without constructing a `Date`.
- **to-valid-date-type-rejection**: `toValidDate(raw)` MUST return `null` when `raw` is neither a `string`, a `number`, nor a `Date` instance, without constructing a `Date`.
- **to-valid-date-construction**: For a `raw` value that is a `string`, a `number`, or a `Date`, `toValidDate` MUST use `raw` itself when it is already a `Date` instance, and MUST otherwise construct `new Date(raw)`; it MUST return that `Date` when `Number.isFinite(d.getTime())` is `true`, and MUST return `null` in every other case — an unparseable string, `Number.NaN`, a numeric value outside `Date`'s representable range, or a `Date` already constructed from unparseable input.

### `providerDeployToDTO`

- **dto-passthrough-fields**: `providerDeployToDTO(d, liveHost)` MUST copy `id`, `platform`, `projectName`, `buildPhase`, `deployPhase`, `environment`, `commitHash`, `commitMessage`, `branch`, `commitRepo`, and `url` from `d` to the returned `DeploymentDTO` unchanged.
- **dto-provider-project-id-coalesce**: `providerDeployToDTO` MUST set the result's `providerProjectId` to `d.providerProjectId ?? null`; per the mapper's own comment, this converts an absent field to an explicit wire `null` (rather than an absent JSON key) so a consumer can distinguish "this row has no provider-issued id" from "this DTO predates the field."
- **dto-error-text-coalesce**: `providerDeployToDTO` MUST set the result's `errorText` to `d.errorText ?? null`.
- **dto-status-derivation**: `providerDeployToDTO` MUST set the result's `status` to `combinedStatus({ buildPhase: d.buildPhase, deployPhase: d.deployPhase })` (agentictoolkit://recipes/status-server-monitor-deploy-status, external to this file).
- **dto-tier-gate**: `providerDeployToDTO` MUST set the result's `tier` to `null` when `isRealEnvDeployRow(d.platform, d.environment)` returns `false`, and MUST otherwise set `tier` to `deployEnv(d.platform, d.projectName, d.environment, d.branch ?? null)` (both agentictoolkit://recipes/status-server-monitor-deploy-view, external to this file). Per the mapper's own comment, this gate MUST be evaluated and applied before `deployEnv` is called, because `deployEnv` itself has no "not a deployment of any tier" answer to give — a Vercel preview reports no `environment` yet its `branch` names a feature ref and its `projectName` is the production project's, so both of `deployEnv`'s own fallback signals would otherwise badge it with a tier it does not have.
- **dto-live-host-passthrough**: `providerDeployToDTO` MUST set the result's `liveHost` to its own `liveHost` parameter unchanged; it MUST NOT derive `liveHost` from any field of `d`.
- **iso-serialize-valid-date**: The module-private `isoOf(id, d)` helper MUST return `d.toISOString()` when `Number.isFinite(d.getTime())` is `true`.
- **iso-serialize-invalid-date-fail-soft**: `isoOf(id, d)` MUST NOT throw when `d` is an Invalid Date; it MUST instead log an error identifying `id` and the fact that the value being serialized is an invalid `createdAt` (via `console.error`), and MUST return `new Date(0).toISOString()` — the Unix epoch, ISO-encoded.
- **dto-created-at-via-iso-serialize**: `providerDeployToDTO` MUST set the result's `createdAt` to `isoOf(d.id, d.createdAt)`.
- **dto-phase-confirmed-at-fallback**: `providerDeployToDTO` MUST set the result's `phaseConfirmedAt` to `isoOf(d.id, d.confirmedAt ?? d.createdAt)` — using `d.confirmedAt` when present, and falling back to `d.createdAt` when `d.confirmedAt` is absent.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `raw` (parameter to `toValidDate`) | `unknown` | none — caller-supplied | The provider- or webhook-supplied timestamp value to validate: an ISO string, an epoch number, or a `Date`. |
| `d`, `liveHost` (parameters to `providerDeployToDTO`) | `ProviderDeploy`, `string \| null` | none — caller-supplied | `d` is the in-memory deployment to shape; `liveHost` is the config-resolved live custom-domain host (external to this file, e.g. `ownerHostFor` in `routes/reads.ts`) stamped onto the result's `liveHost` field unchanged. |
| `id`, `d` (parameters to the module-private `isoOf`) | `string`, `Date` | none — caller-supplied only from within this file | `id` identifies the deploy in the logged error message when `d` is an Invalid Date; `isoOf` is not exported and has no caller outside `providerDeployToDTO`. |

## Privacy

- **Data collected**: none of this file's own. It receives an already-fetched or already-received `ProviderDeploy` (provider status strings, commit metadata, a source URL) and a resolved `liveHost` string as plain function arguments from callers external to this file; it collects nothing itself.
- **Storage**: none. This file holds no state between calls and writes nothing to disk, memory cache, or database; persistence of the data it shapes is owned by the storage layer and `routes/reads.ts`, both external to this file.
- **Transmission**: none performed by this file itself. `providerDeployToDTO`'s return value is handed back to its caller (`routes/reads.ts`), which decides whether and how to serialize it onto the wire.
- **Retention**: not applicable — this file holds no data across calls.

