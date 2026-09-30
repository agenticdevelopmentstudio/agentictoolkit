<!-- leaf: implement-status-web-src-lib-1/deploy-view · source: status-web-src-lib-deploy-view.md -->

**Rules** (cite as `implement-status-web-src-lib-1/deploy-view#<slug>`):

- `platform-summary-shape` MUST
- `platform-summary-invariant` MUST
- `endpoint-like-shape` MUST
- `platform-order-value` MUST
- `platform-order-shared` MUST
- `summarize-signature` MUST
- `summarize-group-key` MUST
- `summarize-entry-creation` MUST
- `summarize-total` MUST
- `summarize-demotion` MUST
- `summarize-demotion-rule` MUST
- `summarize-ready` MUST
- `summarize-building` MUST
- `summarize-failed` MUST
- `summarize-total-only-statuses` MUST
- `summarize-order-known` MUST
- `summarize-order-unknown` MUST
- `summarize-empty` MUST
- `endpoint-deploys-signature` MUST
- `endpoint-key` MUST
- `endpoint-no-target` MUST
- `endpoint-match` MUST
- `target-key-format` MUST
- `platform-canon-rule` MUST
- `endpoint-railway-env` MUST
- `endpoint-non-railway-env` MUST
- `endpoint-cloudflare-alias` MUST
- `endpoint-project-case` MUST
- `endpoint-sort` MUST
- `endpoint-no-mutation` MUST
- `latest-terminal-signature` MUST
- `latest-terminal-pick` MUST
- `latest-terminal-skip` MUST
- `latest-terminal-none` MUST
- `latest-terminal-no-demotion` MUST
- `failures-signature` MUST
- `failures-count` MUST
- `failures-zero` MUST
- `pure-functions` MUST
- `no-throw` MUST

# Deploy View

## Overview

`deploy-view.ts` (`packages/web/packages/status-web/src/lib/deploy-view.ts`) is the status dashboard's view-side logic over raw `DeploymentDTO` rows. It has no state, no I/O and no side effects. It exports:

- `PlatformSummary`: a per-platform count record (`platform`, `ready`, `building`, `failed`, `total`).
- `PLATFORM_ORDER`: the shared stable ordering of known platforms, `["vercel", "cloudflare-pages", "railway", "crunchy"]`.
- `summarizeByPlatform(deploys, nowMs, probeIntervalMs?)`: buckets deploys by status per platform. It demotes a stale in-flight deploy to "total only", using the same rule as the activity list and `DeployList`. `Dashboard.tsx` calls it for the Build-pipeline pane and the KPI building pill.
- `EndpointLike`: the deploy-target fields of a monitored endpoint (`platform`, `deployProject`, `environment`).
- `deploysForEndpoint`, `latestTerminalForEndpoint` and `failuresForEndpoint`: correlate an endpoint to its deploys by the EXPLICIT (platform, project) wired on the endpoint in config, with "No host guessing." `DetailPanel.tsx` and `StatusMatrix.tsx` call them.
- `deployTargetKey` and `platformCanon`: re-exported unchanged from `@agentic-toolkit/deploy-platform/canon`. The source comment says they are "Re-exported (never restated) so the two sides can't key the same deploy differently" — the Hono server keys deploys with the same function.

The stale-in-flight test is `deployDtoUnconfirmed` from `./row-model`. The Board Staleness recipe shares its fail-closed clock rule.

## Behavioral Requirements

### Data shapes

- **platform-summary-shape**: `PlatformSummary` MUST have exactly the fields `platform: string`, `ready: number`, `building: number`, `failed: number` and `total: number`.
- **platform-summary-invariant**: For every `PlatformSummary` returned, `ready + building + failed` MUST be less than or equal to `total`. Every deploy increments `total`, and at most one of the other three.
- **endpoint-like-shape**: `EndpointLike` MUST have the optional nullable fields `platform?: string | null`, `deployProject?: string | null` and `environment?: string | null`. A structurally wider object (the host's endpoint roster entry) MUST be accepted.
- **platform-order-value**: `PLATFORM_ORDER` MUST equal `["vercel", "cloudflare-pages", "railway", "crunchy"]`, in that order.
- **platform-order-shared**: `PLATFORM_ORDER` MUST be exported, so that every platform-grouped surface (the deploy summary, and the Auto Configure review modal in `AutoConfigureReview.tsx`) orders sections from one list.

### summarizeByPlatform

- **summarize-signature**: `summarizeByPlatform` MUST take `deploys: DeploymentDTO[]`, `nowMs: number` (epoch ms) and an optional `probeIntervalMs?: number`, and MUST return `PlatformSummary[]`.
- **summarize-group-key**: `summarizeByPlatform` MUST group by the raw `d.platform` string, with no canonicalization. Deploys with `"cloudflare"` and `"cloudflare-pages"` MUST land in two separate summaries.
- **summarize-entry-creation**: The first deploy seen for a platform MUST create an entry with all four counts at 0 before that deploy is counted.
- **summarize-total**: Every deploy MUST increment its platform's `total` exactly once, whatever its status or staleness.
- **summarize-demotion**: A deploy for which `deployDtoUnconfirmed(d, nowMs, probeIntervalMs)` returns `true` MUST count in `total` only, and in none of `ready`, `building` or `failed`.
- **summarize-demotion-rule**: `deployDtoUnconfirmed` MUST return `false` for any status other than `"building"` or `"queued"` (`IN_FLIGHT_STATUSES`). For an in-flight status it MUST parse `phaseConfirmedAt`, falling back to `createdAt` when `phaseConfirmedAt` is absent. It MUST return `true` when the parsed value is not finite (fail closed), and otherwise return `true` only when `nowMs - confirmed` is strictly greater than `max(600000, (probeIntervalMs ?? 0) * 5)`.
- **summarize-ready**: A non-demoted deploy with status `"success"` MUST increment `ready`.
- **summarize-building**: A non-demoted deploy with status `"building"` or `"queued"` MUST increment `building`.
- **summarize-failed**: A deploy with status `"failed"` MUST increment `failed`.
- **summarize-total-only-statuses**: A deploy with status `"canceled"` or `"unknown"` MUST increment `total` only.
- **summarize-order-known**: The result MUST list the summaries for platforms in `PLATFORM_ORDER` first, in `PLATFORM_ORDER` order, including only the platforms present.
- **summarize-order-unknown**: Summaries for platforms not in `PLATFORM_ORDER` MUST follow the known ones, in the order each platform was first seen in `deploys`.
- **summarize-empty**: `summarizeByPlatform([], nowMs)` MUST return `[]`.

### deploysForEndpoint

- **endpoint-deploys-signature**: `deploysForEndpoint` MUST take `deploys: DeploymentDTO[]` and `ep: EndpointLike`, and MUST return a new `DeploymentDTO[]`.
- **endpoint-key**: `deploysForEndpoint` MUST compute the endpoint key as `deployTargetKey(ep.platform, ep.deployProject, ep.environment)`.
- **endpoint-no-target**: When the endpoint key is `null` (no platform, or no project, as for a health-only check), `deploysForEndpoint` MUST return `[]`.
- **endpoint-match**: A deploy MUST be included exactly when `deployTargetKey(d.platform, d.projectName, d.environment)` equals the endpoint key.
- **target-key-format**: `deployTargetKey` MUST return `null` when the canonical platform is empty or the project is falsy. Otherwise it MUST return `"<canonPlatform>|<project>|<env>"`, where `<env>` is the lowercased environment (or `""` when the environment is null) for `railway`, and `""` for every other platform.
- **platform-canon-rule**: `platformCanon` MUST map `"cloudflare-pages"` to `"cloudflare"`, `null` or `undefined` to `""`, and every other value to itself.
- **endpoint-railway-env**: For a `railway` endpoint, a deploy of the same project in a different environment MUST NOT match. The match on environment MUST be case-insensitive.
- **endpoint-non-railway-env**: For a non-railway endpoint, the environment MUST NOT affect the match, because Vercel and Cloudflare projects are environment-specific.
- **endpoint-cloudflare-alias**: An endpoint configured with platform `"cloudflare"` MUST match deploys whose platform is `"cloudflare-pages"`, and the reverse.
- **endpoint-project-case**: The project name comparison MUST be case-sensitive. Only the environment is lowercased.
- **endpoint-sort**: The result MUST be sorted newest first by `createdAt`, using `Date` parsing of the string.
- **endpoint-no-mutation**: `deploysForEndpoint` MUST NOT reorder or modify the caller's `deploys` array. It sorts the filtered copy.

### latestTerminalForEndpoint

- **latest-terminal-signature**: `latestTerminalForEndpoint` MUST take `deploys: DeploymentDTO[]` and `ep: EndpointLike`, and MUST return `DeploymentDTO | null`.
- **latest-terminal-pick**: `latestTerminalForEndpoint` MUST return the first deploy in `deploysForEndpoint(deploys, ep)` order (newest first) whose status is `"success"` or `"failed"`.
- **latest-terminal-skip**: `latestTerminalForEndpoint` MUST skip deploys with status `"canceled"`, `"building"`, `"queued"` or `"unknown"`, even when they are newer.
- **latest-terminal-none**: `latestTerminalForEndpoint` MUST return `null` when no correlated deploy is terminal, and when the endpoint correlates to nothing.
- **latest-terminal-no-demotion**: `latestTerminalForEndpoint` MUST NOT apply stale-in-flight demotion. It takes no clock argument.

### failuresForEndpoint

- **failures-signature**: `failuresForEndpoint` MUST take `deploys: DeploymentDTO[]` and `ep: EndpointLike`, and MUST return a `number`.
- **failures-count**: `failuresForEndpoint` MUST return the count of correlated deploys whose status is exactly `"failed"`, across the whole input with no time window.
- **failures-zero**: `failuresForEndpoint` MUST return 0 when nothing correlates.

### Purity and concurrency

- **pure-functions**: Every exported function MUST be synchronous and MUST NOT perform I/O, log, or mutate its arguments.
- **no-throw**: Every exported function MUST NOT throw on input of the declared types. An unparseable date yields `NaN` and is handled by comparison, not by an exception.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread. Concurrent calls cannot interleave, and no ordering rule is needed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deploys` | `DeploymentDTO[]` | none (required) | The deploy rows to summarize or correlate, supplied by the board. |
| `nowMs` | `number` | none (required) | Client clock in epoch ms, used by `summarizeByPlatform` for stale-in-flight demotion. |
| `probeIntervalMs` | `number \| undefined` | `undefined` (600 000 ms window) | Backend probe cadence. The demotion window is `max(600000, probeIntervalMs * 5)`. |
| `ep` | `EndpointLike` | none (required) | The endpoint's configured `platform`, `deployProject` and `environment`. |
| `PLATFORM_ORDER` | constant | `["vercel", "cloudflare-pages", "railway", "crunchy"]` | Compiled-in section order for known platforms. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. Its imports are `deployDtoUnconfirmed` from `./row-model`, and `deployTargetKey` and `platformCanon` from `@agentic-toolkit/deploy-platform/canon`.

