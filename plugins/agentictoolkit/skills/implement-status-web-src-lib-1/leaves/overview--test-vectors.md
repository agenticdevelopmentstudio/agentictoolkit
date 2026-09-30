<!-- leaf: implement-status-web-src-lib-1/overview--test-vectors · source: status-web-src-lib-overview.md -->

# Overview Projections

## Conformance Test Vectors

Vectors 001–006 are traced to `overview.test.ts`; 007–010 to `board-types-parity.test.ts`; the rest to the function bodies. `H` = 3 600 000 ms. `deploy(...)` is an `ActivityRow` with `kind: "deploy"`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| overview-001 | real-env-vercel-preview, real-env-dto-delegates | `isRealEnvDeploy` of a DTO with `platform: "vercel"`, `environment: null`, `status: "failed"` | `false` |
| overview-002 | real-env-vercel-target, real-env-dto-delegates | `isRealEnvDeploy` of a DTO with `platform: "vercel"`, `environment: "production"` | `true` |
| overview-003 | real-env-other-platforms | `isRealEnvDeploy` of a DTO with `platform: "cloudflare-pages"`, `environment: null` | `true` |
| overview-004 | real-env-row-signature, real-env-vercel-preview, real-env-vercel-target, real-env-other-platforms | `isRealEnvDeployRow` with ("vercel", null), ("vercel", ""), ("vercel", "production"), ("railway", null), ("cloudflare-pages", null) | `false`, `false`, `true`, `true`, `true` |
| overview-005 | window-hours, window-hours-label, window-days | `activityWindowLabel(0, 24*H)`; `activityWindowLabel(0, 7*24*H)`; `activityWindowLabel(0, 47*H)` | `"24h"`; `"7d"`; `"47h"` |
| overview-006 | window-min-one-hour | `activityWindowLabel(0, 60000)` | `"1h"` |
| overview-007 | indicator-map-exhaustive, indicator-map-values | Sorted keys of `INDICATOR_STATE`; its values | `["degraded","operational","outage"]`; `"warn"`, `"ok"`, `"down"` |
| overview-008 | indicator-empty-ok, indicator-server-parity | `indicatorFromProblems([])` | `{ state: "ok", count: 0 }` |
| overview-009 | indicator-otherwise-warn, indicator-count | problems with severities `minor, minor`; then `major, minor` | `{ state: "warn", count: 2 }` both times |
| overview-010 | indicator-critical-down, indicator-count | problems with severities `minor, major, critical` | `{ state: "down", count: 3 }` |
| overview-011 | headline-ok | `headlineFor("ok", 5)` | `"ALL SYSTEMS OPERATIONAL"` |
| overview-012 | headline-warn-singular, headline-warn-plural | `headlineFor("warn", 1)`; `headlineFor("warn", 3)` | `"1 SERVICE NEEDS ATTENTION"`; `"3 SERVICES NEED ATTENTION"` |
| overview-013 | headline-down-singular, headline-down-plural | `headlineFor("down", 1)`; `headlineFor("down", 4)` | `"1 PROBLEM"`; `"4 PROBLEMS"` |
| overview-014 | counts-builds, counts-deploys, counts-failures | `deployCounts` over deploy rows at `sinceMs` or later: `step "build", tone "good"`; `step "build", tone "bad"`; `step "deploy", tone "good"` | `{ builds: 2, deploys: 1, failures: 1 }` |
| overview-015 | counts-deploy-kind-only, counts-window-cutoff | `deployCounts` with a `kind: "probe"` row (`tone "bad"`), a deploy row at `sinceMs - 1`, and a deploy build row exactly at `sinceMs` | `{ builds: 1, deploys: 0, failures: 0 }` |
| overview-016 | counts-null-step, counts-failures | `deployCounts` with one deploy row, `step: null`, `tone: "bad"`, inside the window | `{ builds: 0, deploys: 0, failures: 1 }` |
| overview-017 | window-days, window-hours-label | `activityWindowLabel(0, 48*H)`; `activityWindowLabel(0, 72*H)`; `activityWindowLabel(0, 24*H)` stays hours | `"2d"`; `"3d"`; `"24h"` |
| overview-018 | window-min-one-hour | `activityWindowLabel(10*H, 0)` (negative span) | `"1h"` |
| overview-019 | real-env-case-sensitive | `isRealEnvDeployRow("Vercel", null)` | `true` |
