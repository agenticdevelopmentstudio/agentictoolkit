<!-- leaf: implement-status-web-src-lib-1/deploy-view--test-vectors · source: status-web-src-lib-deploy-view.md -->

# Deploy View

## Conformance Test Vectors

Unless stated, every deploy is a `DeploymentDTO` with `platform: "vercel"`, `projectName: "test-project"`, `environment: "production"`, and `createdAt` and `phaseConfirmedAt` equal to `NOW = Date.parse("2026-06-12T12:00:00.000Z")`, so nothing is demoted. Vectors 001 to 017 are traced to assertions in `deploy-view.test.ts`. Vectors 018 to 022 are traced to the source bodies of `summarizeByPlatform`, `deployDtoUnconfirmed` and `deployTargetKey`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-view-001 | summarize-empty | `summarizeByPlatform([], NOW)` | `[]` |
| deploy-view-002 | summarize-demotion, summarize-total | Two vercel `building` deploys; one has `phaseConfirmedAt` = NOW minus 3 600 000 ms | `building` 1, `total` 2 |
| deploy-view-003 | summarize-ready, summarize-building, summarize-failed, summarize-total-only-statuses | Vercel deploys with statuses success, building, queued, failed, canceled | One summary: `{ platform: "vercel", ready: 1, building: 2, failed: 1, total: 5 }` |
| deploy-view-004 | summarize-group-key, summarize-entry-creation | vercel success ×2, cloudflare-pages success, railway failed | 3 summaries; vercel `ready` 2; cloudflare-pages `ready` 1, `failed` 0; railway `failed` 1 |
| deploy-view-005 | summarize-order-known | Deploys in the order railway, vercel, cloudflare-pages | Platforms `["vercel", "cloudflare-pages", "railway"]` |
| deploy-view-006 | summarize-order-unknown | vercel, then custom-host | `result[0].platform` is `"vercel"`, `result[1].platform` is `"custom-host"` |
| deploy-view-007 | summarize-total-only-statuses | Two vercel `canceled` | `total` 2; `ready`, `building` and `failed` all 0 |
| deploy-view-008 | latest-terminal-pick, latest-terminal-skip | Endpoint vercel/hub-production; deploys success at 10:00, failed at 11:00, canceled at 12:00, building at 12:30 | Returns the `failed` deploy |
| deploy-view-009 | latest-terminal-none | Same endpoint; only canceled and building deploys | `null` |
| deploy-view-010 | endpoint-no-target | Endpoint with no platform or deployProject; one vercel deploy | `[]` |
| deploy-view-011 | endpoint-match, endpoint-non-railway-env | Endpoint vercel/hub-staging (env staging); deploys hub-production, hub-staging, hub-testing | Exactly one, with `projectName` `"hub-staging"` |
| deploy-view-012 | endpoint-railway-env | Endpoint railway/adh-backend, env staging; deploys of adh-backend in production, staging and testing | Exactly one, with `environment` `"staging"` |
| deploy-view-013 | endpoint-cloudflare-alias | Endpoint platform `"cloudflare"`, project temporal-web; cloudflare-pages deploys temporal-web and temporal-other | Exactly one, with `projectName` `"temporal-web"` |
| deploy-view-014 | endpoint-sort | Endpoint vercel/hub-production; createdAt 2024-01-03, 2024-01-01, 2024-01-02 | Order 2024-01-03, 2024-01-02, 2024-01-01 |
| deploy-view-015 | failures-zero | `failuresForEndpoint([], ep)` with ep vercel/"nope" | 0 |
| deploy-view-016 | failures-count | Matching deploys failed, success, failed, building | 2 |
| deploy-view-017 | failures-count | Matching deploys building and canceled | 0 |
| deploy-view-018 | summarize-demotion-rule | One vercel `queued` deploy with `phaseConfirmedAt: "garbage"` | `building` 0, `total` 1 (fails closed) |
| deploy-view-019 | summarize-demotion-rule | Vercel `building`, `phaseConfirmedAt` = NOW minus 900 000 ms; call once with no `probeIntervalMs` and once with `probeIntervalMs` 300 000 | No interval: `building` 0 (900 000 > 600 000). Interval 300 000: `building` 1 (900 000 ≤ 1 500 000) |
| deploy-view-020 | summarize-demotion-rule, summarize-ready | Vercel `success` with `phaseConfirmedAt` = NOW minus 3 600 000 ms | `ready` 1 (terminal statuses never demote) |
| deploy-view-021 | summarize-group-key | One `"cloudflare"` success and one `"cloudflare-pages"` success | Two summaries: `"cloudflare-pages"` first (known), then `"cloudflare"` (unknown) |
| deploy-view-022 | endpoint-railway-env, target-key-format | Endpoint railway/adh-backend, env `"Staging"`; deploy railway/adh-backend, env `"staging"` | The deploy matches (both sides key to railway, adh-backend, staging) |
