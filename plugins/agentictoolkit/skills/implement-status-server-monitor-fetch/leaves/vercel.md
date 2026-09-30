<!-- leaf: implement-status-server-monitor-fetch/vercel · source: status-server-monitor-fetch-vercel.md -->

# Status Server Monitor Fetch Vercel

## Overview

`fetch-vercel.ts` (`packages/web/packages/status-server/src/monitor/fetch-vercel.ts`) is the Vercel provider adapter behind the status server's deploy-monitor poll cycle (`sync.ts`, external, invoked through its `guard` wrapper). It exports five functions in two groups. The poll group, `fetchVercelDeployments`, paginates Vercel's team-wide deployments list within a bounded overall budget and maps the results into `ProviderDeploy` rows (`./provider-deploy`, external) for the caller to upsert; per its own comment it shares "the same shape (and partial contract) as `fetchVercelProductionStates` and the Railway / Cloudflare fetchers" (`fetch-vercel-projects.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, all external) — a partial poll is handed back with `ok: false` rather than discarded. The on-demand group serves two human-facing reads that the poll never performs: `composeVercelDeployError`/`fetchVercelDeployError` fetch and shape the one-line failure reason for a single failed deployment (consumed by `enrich-deploy-errors.ts`, external, to fill in `error_text` once per failed deploy), and `composeVercelBuildLog`/`fetchVercelBuildLog` fetch and shape that deployment's complete build log (consumed by `routes/deploy-logs.ts`, external, behind `GET /deployments/:id/log`). Each pair splits a pure, directly-unit-tested "compose" half from an async "fetch" half that calls Vercel and delegates shaping to the compose half.

