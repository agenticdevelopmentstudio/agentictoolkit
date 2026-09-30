<!-- leaf: implement-status-web-src-lib-1/overview · source: status-web-src-lib-overview.md -->

**Rules** (cite as `implement-status-web-src-lib-1/overview#<slug>`):

- `indicator-state-union` MUST
- `indicator-shape` MUST
- `indicator-signature` MUST
- `indicator-count` MUST
- `indicator-empty-ok` MUST
- `indicator-critical-down` MUST
- `indicator-otherwise-warn` MUST
- `indicator-server-parity` MUST
- `indicator-filtered-input` MUST
- `indicator-map-values` MUST
- `indicator-map-exhaustive` MUST
- `indicator-map-sole-translation` MUST
- `counts-signature` MUST
- `counts-deploy-kind-only` MUST
- `counts-window-cutoff` MUST
- `counts-builds` MUST
- `counts-deploys` MUST
- `counts-null-step` MUST
- `counts-failures` MUST
- `counts-server-window` MUST
- `counts-no-rejudging` MUST
- `window-signature` MUST
- `window-hours` MUST
- `window-days` MUST
- `window-hours-label` MUST
- `window-min-one-hour` MUST
- `window-server-boundary` MUST
- `headline-signature` MUST
- `headline-ok` MUST
- `headline-warn-singular` MUST
- `headline-warn-plural` MUST
- `headline-down-singular` MUST
- `headline-down-plural` MUST
- `headline-single-wording` MUST
- `real-env-row-signature` MUST
- `real-env-vercel-preview` MUST
- `real-env-vercel-target` MUST
- `real-env-other-platforms` MUST
- `real-env-dto-delegates` MUST
- `real-env-case-sensitive` MUST
- `pure-functions` MUST

# Overview Projections

## Overview

`overview.ts` (`packages/web/packages/status-web/src/lib/overview.ts`) holds the status dashboard's rendering projections of the server-owned `Board`. Its header comment is explicit that it derives nothing the server owns: row construction lives in `row-model.ts`, problem derivation and indicator state belong to the server's `Board`, and a row's environment tier is stamped by the server (`deployEnv` in `src/monitor/deploy-view.ts`) before the row ships. What remains here are small, pure, synchronous helpers:

- `IndicatorState` and `Indicator` — the sign / pill vocabulary (`"ok" | "warn" | "down"` plus a count).
- `indicatorFromProblems(problems)` — sign state and count over the problems a pane is showing, transcribed from the server's `indicatorFor`.
- `INDICATOR_STATE` — the one translation from the wire `Indicator` (`operational`/`degraded`/`outage`) to `IndicatorState`.
- `deployCounts(activity, sinceMs)` — build/deploy/failure tallies for the stats strip.
- `activityWindowLabel(fromMs, toMs)` — the "24h" / "7d" caption for the window the server chose.
- `headlineFor(state, count)` — the headline shared by the mobile hero sign and the desktop top-bar pill.
- `isRealEnvDeploy(d)` and `isRealEnvDeployRow(platform, environment)` — the predicate that excludes Vercel preview builds.

Callers: `OverviewTab.tsx` (`indicatorFromProblems`, `INDICATOR_STATE`), `use-portfolio-indicator.ts` (`INDICATOR_STATE`), `OverviewStats.tsx` (`deployCounts`, `activityWindowLabel`), `BigIndicator.tsx`, `BoardShell.tsx` and `WallboardStatus.tsx` (`headlineFor`), and `StatusSign.tsx` / `status-sublabel.ts` (the `IndicatorState` type). No file in `status-web` calls `isRealEnvDeploy` or `isRealEnvDeployRow` outside this module and its test; the server carries its own copy in `status-server/src/monitor/deploy-view.ts`. Types come from Board Types (`ActivityRow`, `Indicator`, `Problem`) and `../types` (`DeploymentDTO`).

## Behavioral Requirements

### Types

- **indicator-state-union**: `IndicatorState` MUST be exactly the string union `"ok" | "warn" | "down"`.
- **indicator-shape**: `Indicator` MUST be an object with `state: IndicatorState` and `count: number`.

### indicatorFromProblems

- **indicator-signature**: `indicatorFromProblems` MUST take `problems: Problem[]` and MUST return an `Indicator`.
- **indicator-count**: The returned `count` MUST equal `problems.length`.
- **indicator-empty-ok**: For an empty array the function MUST return `{ state: "ok", count: 0 }`.
- **indicator-critical-down**: When at least one problem has `severity === "critical"`, the function MUST return `state: "down"`.
- **indicator-otherwise-warn**: When the array is non-empty and no problem is `"critical"` (only `"major"` and/or `"minor"`), the function MUST return `state: "warn"`.
- **indicator-server-parity**: On any problem set, `indicatorFromProblems(problems)` MUST equal `{ state: INDICATOR_STATE[indicatorFor(problems)], count: problems.length }`, where `indicatorFor` is the server rule in `status-server/src/board/derive-activity.ts`. The doc comment calls it "a rendering projection of severities the server already assigned — not a second opinion"; `board-types-parity.test.ts` pins the two on empty, minor-only, major-only and critical-bearing sets.
- **indicator-filtered-input**: The function MUST judge only the problems it is given. `OverviewTab` passes a filtered subset (`board.problems.filter(keep)`) when a filter is active and otherwise uses the server's `board.indicator` through `INDICATOR_STATE`.

### INDICATOR_STATE

- **indicator-map-values**: `INDICATOR_STATE` MUST map `operational` to `"ok"`, `degraded` to `"warn"` and `outage` to `"down"`.
- **indicator-map-exhaustive**: `INDICATOR_STATE` MUST have exactly the three keys `degraded`, `operational`, `outage` — one per member of the wire `Indicator` union, with no extras (typed as `Record<BoardIndicator, IndicatorState>` and checked by key in `board-types-parity.test.ts`).
- **indicator-map-sole-translation**: `INDICATOR_STATE` MUST be the only place that translates the wire indicator into `IndicatorState`; the doc comment names it "The ONLY translation between the two."

### deployCounts

- **counts-signature**: `deployCounts` MUST take `activity: ActivityRow[]` and `sinceMs: number` and MUST return `{ builds: number; deploys: number; failures: number }`.
- **counts-deploy-kind-only**: Rows whose `kind` is not `"deploy"` (`"probe"`, `"platform"`) MUST NOT contribute to any count.
- **counts-window-cutoff**: A deploy row whose `Date.parse(at)` is strictly less than `sinceMs` MUST NOT contribute to any count; a row exactly at `sinceMs` MUST be counted.
- **counts-builds**: Each counted row with `step === "build"` MUST add 1 to `builds`.
- **counts-deploys**: Each counted row with `step === "deploy"` MUST add 1 to `deploys`.
- **counts-null-step**: A counted row with `step === null` MUST add to neither `builds` nor `deploys`.
- **counts-failures**: Each counted row with `tone === "bad"` MUST add 1 to `failures`, independently of its `step`, so a failed build row counts as one build and one failure.
- **counts-server-window**: The caller MUST pass the board's own `activityFromMs` as `sinceMs`; the doc comment states "the client never picks the window". `OverviewStats` passes `board.activityFromMs`.
- **counts-no-rejudging**: The function MUST read `step` and `tone` as they arrive on the wire and MUST NOT recompute them.

### activityWindowLabel

- **window-signature**: `activityWindowLabel` MUST take `fromMs: number` and `toMs: number` and MUST return a string.
- **window-hours**: The function MUST compute `hours = Math.max(1, Math.round((toMs - fromMs) / 3_600_000))`.
- **window-days**: When `hours >= 48` and `hours` is a whole multiple of 24, the function MUST return `` `${hours / 24}d` `` (for example `"7d"`).
- **window-hours-label**: Otherwise the function MUST return `` `${hours}h` `` (for example `"24h"`, `"47h"`).
- **window-min-one-hour**: A window shorter than 30 minutes, zero, or negative MUST be captioned `"1h"`, never `"0h"`.
- **window-server-boundary**: The caller MUST derive both bounds from the board (`OverviewStats` passes `board.activityFromMs` and `Date.parse(board.generatedAt)`); the doc comment forbids a hardcoded caption because the server owns `ACTIVITY_WINDOW_MS`.

### headlineFor

- **headline-signature**: `headlineFor` MUST take `state: IndicatorState` and `count: number` and MUST return a string.
- **headline-ok**: For `state === "ok"` the function MUST return `"ALL SYSTEMS OPERATIONAL"`, ignoring `count`.
- **headline-warn-singular**: For `state === "warn"` and `count === 1` it MUST return `"1 SERVICE NEEDS ATTENTION"`.
- **headline-warn-plural**: For `state === "warn"` and any other count it MUST return `` `${count} SERVICES NEED ATTENTION` ``.
- **headline-down-singular**: For `state === "down"` and `count === 1` it MUST return `"1 PROBLEM"`.
- **headline-down-plural**: For `state === "down"` and any other count it MUST return `` `${count} PROBLEMS` ``.
- **headline-single-wording**: Every surface that announces the sign's headline (hero sign, top-bar pill accessible name, wallboard pill) MUST obtain it from `headlineFor`, so they cannot word it differently. The "unknown" state is outside `IndicatorState`; callers word it themselves (`BoardShell` uses `"Status unknown"`, `WallboardStatus` uses `"UNKNOWN"`).

### isRealEnvDeploy / isRealEnvDeployRow

- **real-env-row-signature**: `isRealEnvDeployRow` MUST take `platform: string` and `environment: string | null` and MUST return a boolean.
- **real-env-vercel-preview**: `isRealEnvDeployRow` MUST return `false` when `platform === "vercel"` and `environment` is `null`, `undefined` or `""`.
- **real-env-vercel-target**: `isRealEnvDeployRow` MUST return `true` when `platform === "vercel"` and `environment` is any non-empty string.
- **real-env-other-platforms**: `isRealEnvDeployRow` MUST return `true` for every platform other than the exact string `"vercel"`, whatever `environment` is (including `null`).
- **real-env-dto-delegates**: `isRealEnvDeploy(d)` MUST return `isRealEnvDeployRow(d.platform, d.environment)` for a `DeploymentDTO`.
- **real-env-case-sensitive**: The platform comparison MUST be exact and case-sensitive; `"Vercel"` is treated as a non-Vercel platform.
- **real-env-server-agreement**: The doc comment says the predicate is "Shared so the issue recorder and the UI can never disagree", but `status-server/src/monitor/deploy-view.ts` defines its own textual copy of `isRealEnvDeploy` / `isRealEnvDeployRow`, and the web copy has no caller in `status-web`. No parity test pins the two copies (unlike `indicatorFromProblems`). A port keeps one definition that the server and the UI both use.

### Purity and concurrency

- **pure-functions**: Every exported function MUST be synchronous and pure: no I/O, no logging, no mutation of its inputs, no module state. The result depends only on the arguments.
- **no-throw**: No function throws on inputs of its declared types; malformed values degrade as described under Edge Cases rather than raising.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread, so calls cannot interleave and no ordering rule is needed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `problems` | `Problem[]` | none (required) | The problems a pane is showing, as assigned severities by the server. |
| `activity` | `ActivityRow[]` | none (required) | The board's activity rows. |
| `sinceMs` | `number` | none (required) | Window start; the caller passes `board.activityFromMs`. |
| `fromMs` / `toMs` | `number` | none (required) | Window bounds; the caller passes `board.activityFromMs` and `Date.parse(board.generatedAt)`. |
| `state` / `count` | `IndicatorState` / `number` | none (required) | Inputs to `headlineFor`. |
| `platform` / `environment` | `string` / `string \| null` | none (required) | Deploy provider and environment target. |
| 48-hour day threshold | constant | 48 | Minimum hours before the caption switches to days, compiled in. |

The module reads no environment variables or settings keys and takes no injected dependencies. It imports only types.

