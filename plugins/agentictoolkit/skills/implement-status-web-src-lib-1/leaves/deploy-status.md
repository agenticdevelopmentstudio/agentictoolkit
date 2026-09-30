<!-- leaf: implement-status-web-src-lib-1/deploy-status · source: status-web-src-lib-deploy-status.md -->

**Rules** (cite as `implement-status-web-src-lib-1/deploy-status#<slug>`):

- `deploy-status-union` MUST
- `build-phase-union` MUST
- `deploy-phase-union` MUST
- `phases-shape` MUST
- `null-build-phase` MUST
- `unknown-terminal` MUST
- `in-flight-build-phases` MUST
- `in-flight-deploy-phase` MUST
- `server-parity-constants` MUST
- `is-in-flight-signature` MUST
- `is-in-flight-build` MUST
- `is-in-flight-deploy` MUST
- `is-in-flight-terminal` MUST
- `server-parity-is-in-flight` MUST
- `in-flight-statuses` MUST
- `deploy-status-in-flight` MUST
- `in-flight-statuses-cover` MUST
- `vercel-signature` MUST
- `vercel-build-ready` MUST
- `vercel-build-error` MUST
- `vercel-build-canceled` MUST
- `vercel-build-queued` MUST
- `vercel-build-fallback` MUST
- `vercel-deploy-default` MUST
- `vercel-deploy-promoted` MUST
- `vercel-deploy-rolling` MUST
- `vercel-deploy-staged` MUST
- `vercel-never-unknown` MUST
- `railway-signature` MUST
- `railway-building` MUST
- `railway-deploying` MUST
- `railway-success` MUST
- `railway-crashed` MUST
- `railway-failed` MUST
- `railway-queued` MUST
- `railway-canceled` MUST
- `railway-fallback` MUST
- `combined-signature` MUST
- `combined-failed-first` MUST
- `combined-canceled` MUST
- `combined-unknown` MUST
- `combined-deployed` MUST
- `combined-deploying` MUST
- `combined-built` MUST
- `combined-queued` MUST
- `combined-fallback` MUST
- `server-parity-combined` MUST
- `pure-functions` MUST
- `no-throw` MUST

# Status Web Deploy Status

## Overview

`deploy-status.ts` (`packages/web/packages/status-web/src/lib/deploy-status.ts`) is the status dashboard's copy of the platform-independent deploy vocabulary. It defines three string unions (`DeployStatus`, `BuildPhase`, `DeployPhase`), the `Phases` pair, the in-flight vocabulary (`IN_FLIGHT_BUILD_PHASES`, `IN_FLIGHT_DEPLOY_PHASE`, `isInFlight`), the in-flight `DeployStatus` values (`IN_FLIGHT_STATUSES`, `deployStatusInFlight`), two provider mappers (`vercelPhases`, `railwayPhases`) and the collapse function `combinedStatus`.

The module's own comment calls it "A HAND MIRROR of the server's deploy-status.ts (there is no shared build between the two packages)". The server original is specified in Status Server Monitor Deploy Status. `deploy-status-parity.test.ts` imports both modules and asserts they agree across the full phase space.

Inside the web app, `types.ts` imports the three unions to type `DeploymentDTO.status`, `buildPhase` and `deployPhase`. `deploy-display.ts` imports `DeployStatus`. `row-model.ts` calls `deployStatusInFlight` in `deployDtoUnconfirmed` to decide whether a `DeploymentDTO` asserts live progress that may need demoting. The module has no state, no I/O and no side effects.

## Behavioral Requirements

### Vocabulary types

- **deploy-status-union**: `DeployStatus` MUST be exactly the string union `"success" | "failed" | "building" | "queued" | "canceled" | "unknown"`.
- **build-phase-union**: `BuildPhase` MUST be exactly the string union `"queued" | "building" | "built" | "failed" | "canceled" | "unknown"`.
- **deploy-phase-union**: `DeployPhase` MUST be exactly the string union `"none" | "deploying" | "deployed" | "failed" | "unknown"`.
- **phases-shape**: `Phases` MUST have two fields: `buildPhase: BuildPhase | null` and `deployPhase: DeployPhase`.
- **null-build-phase**: A `buildPhase` of `null` MUST mean the platform reports no build lifecycle. The source comment gives Cloudflare Workers as the example, which "list only already-live deployments".
- **unknown-terminal**: The `unknown` phase MUST be treated as terminal. Per the source comment it is "an in-flight phase the backend could not re-confirm for its expiry window", and "Like `canceled` it is the ABSENCE of a verdict — never good or bad".

### In-flight vocabulary

- **in-flight-build-phases**: `IN_FLIGHT_BUILD_PHASES` MUST be the read-only array `["building", "queued"]`, in that order.
- **in-flight-deploy-phase**: `IN_FLIGHT_DEPLOY_PHASE` MUST be `"deploying"`.
- **server-parity-constants**: `IN_FLIGHT_BUILD_PHASES` and `IN_FLIGHT_DEPLOY_PHASE` MUST equal the server module's constants of the same names, element for element.
- **is-in-flight-signature**: `isInFlight` MUST take `buildPhase: string | null` and `deployPhase: string`, and MUST return a `boolean`.
- **is-in-flight-build**: `isInFlight` MUST return `true` when `buildPhase` is a member of `IN_FLIGHT_BUILD_PHASES`, whatever `deployPhase` is.
- **is-in-flight-deploy**: `isInFlight` MUST return `true` when `deployPhase` equals `IN_FLIGHT_DEPLOY_PHASE`, whatever `buildPhase` is.
- **is-in-flight-terminal**: `isInFlight` MUST return `false` for every other pair, including a `null` build phase with a non-deploying deploy phase, and any string outside the unions.
- **server-parity-is-in-flight**: `isInFlight` MUST return the same result as the server's `isInFlight` for every pair in the product of `{null, queued, building, built, failed, canceled, unknown}` and `{none, deploying, deployed, failed, unknown}`.

### In-flight statuses (web only)

- **in-flight-statuses**: `IN_FLIGHT_STATUSES` MUST be the read-only array `["building", "queued"]`.
- **deploy-status-in-flight**: `deployStatusInFlight(status)` MUST return `true` exactly when `status` is `"building"` or `"queued"`, and `false` for `"success"`, `"failed"`, `"canceled"` and `"unknown"`.
- **in-flight-statuses-cover**: `IN_FLIGHT_STATUSES` MUST cover every `DeployStatus` that `combinedStatus` produces from an in-flight `Phases`. Per the doc comment, `combinedStatus` maps a deploying phase to `"building"` and a queued build to `"queued"`.
- **web-only-exports**: `IN_FLIGHT_STATUSES` and `deployStatusInFlight` exist only in the web module. The server module has no counterpart, and the parity test does not compare them.

### vercelPhases

- **vercel-signature**: `vercelPhases` MUST take `readyState: string`, `readySubstate: string | null | undefined` and `target: string | null | undefined`, and MUST return `Phases`. Per the doc comment, `readyState` is the build and `readySubstate` (production only) is the deploy.
- **vercel-build-ready**: A `readyState` of `"READY"` MUST map to `buildPhase` `"built"`.
- **vercel-build-error**: A `readyState` of `"ERROR"` MUST map to `buildPhase` `"failed"`.
- **vercel-build-canceled**: A `readyState` of `"CANCELED"` or `"DELETED"` MUST map to `buildPhase` `"canceled"`.
- **vercel-build-queued**: A `readyState` of `"QUEUED"` MUST map to `buildPhase` `"queued"`.
- **vercel-build-fallback**: Every other `readyState` MUST map to `buildPhase` `"building"`. The source comment lists `BUILDING`, `INITIALIZING`, `BLOCKED` and unknown values. Matching is exact and case-sensitive.
- **vercel-deploy-default**: `deployPhase` MUST be `"none"` unless `buildPhase` is `"built"` and `target` is exactly `"production"`.
- **vercel-deploy-promoted**: For a built production deployment, a `readySubstate` of `"PROMOTED"` MUST map to `deployPhase` `"deployed"`.
- **vercel-deploy-rolling**: For a built production deployment, a `readySubstate` of `"ROLLING"` MUST map to `deployPhase` `"deploying"`.
- **vercel-deploy-staged**: For a built production deployment, any other `readySubstate` (including `"STAGED"`, `null` and `undefined`) MUST map to `deployPhase` `"none"`. The source comment says STAGED means "built but never promoted → no deploy entry yet".
- **vercel-never-unknown**: `vercelPhases` MUST NOT produce the `unknown` phase on either lifecycle, and MUST NOT produce a `failed` deploy phase.

### railwayPhases

- **railway-signature**: `railwayPhases` MUST take `status: string` and MUST return `Phases`. Per the doc comment, Railway reports both phases natively in one enum.
- **railway-building**: `"BUILDING"` and `"INITIALIZING"` MUST map to `{ buildPhase: "building", deployPhase: "none" }`.
- **railway-deploying**: `"DEPLOYING"` MUST map to `{ buildPhase: "built", deployPhase: "deploying" }`.
- **railway-success**: `"SUCCESS"` MUST map to `{ buildPhase: "built", deployPhase: "deployed" }`.
- **railway-crashed**: `"CRASHED"` MUST map to `{ buildPhase: "built", deployPhase: "deployed" }`. The source comment says a runtime crash "is a health concern, not a deploy failure".
- **railway-failed**: `"FAILED"` MUST map to `{ buildPhase: "failed", deployPhase: "none" }`. The source comment says the enum "can't separate build-fail from deploy-fail; build is the common case".
- **railway-queued**: `"WAITING"` and `"NEEDSAPPROVAL"` MUST map to `{ buildPhase: "queued", deployPhase: "none" }`.
- **railway-canceled**: `"REMOVED"` and `"SKIPPED"` MUST map to `{ buildPhase: "canceled", deployPhase: "none" }`.
- **railway-fallback**: Every other `status`, including the empty string and lowercase spellings, MUST map to `{ buildPhase: "building", deployPhase: "none" }`.

### combinedStatus

- **combined-signature**: `combinedStatus` MUST take a `Phases` value and MUST return one `DeployStatus`. Per the doc comment it is the single status for "the Details matrix / KPI strip / deploy-issue recorder".
- **combined-failed-first**: `combinedStatus` MUST return `"failed"` when `buildPhase` or `deployPhase` is `"failed"`, before any other rule.
- **combined-canceled**: When no phase is `"failed"`, `combinedStatus` MUST return `"canceled"` if `buildPhase` is `"canceled"`, whatever `deployPhase` is.
- **combined-unknown**: When neither earlier rule applies, `combinedStatus` MUST return `"unknown"` if `buildPhase` or `deployPhase` is `"unknown"`. This check MUST run before the in-flight rules, so that "an expired row can never re-read as building".
- **combined-deployed**: When no earlier rule applies, a `deployPhase` of `"deployed"` MUST give `"success"`, including with a `null` build phase.
- **combined-deploying**: When no earlier rule applies, a `deployPhase` of `"deploying"` MUST give `"building"`.
- **combined-built**: When no earlier rule applies, a `buildPhase` of `"built"` with `deployPhase` `"none"` MUST give `"success"`. The source comment says this is "built, no separate deploy step (non-prod / staged)".
- **combined-queued**: When no earlier rule applies, a `buildPhase` of `"queued"` MUST give `"queued"`.
- **combined-fallback**: Every remaining input MUST give `"building"`. That covers `buildPhase` `"building"`, and `buildPhase` `null` with `deployPhase` `"none"`.
- **server-parity-combined**: `combinedStatus` MUST return the same result as the server's `combinedStatus` for every pair in the product of `{null, queued, building, built, failed, canceled, unknown}` and `{none, deploying, deployed, failed, unknown}`.

### Purity and concurrency

- **pure-functions**: Every exported function MUST be pure and synchronous. None performs I/O, logs, mutates its arguments or holds state.
- **no-throw**: Every exported function MUST NOT throw for any input of its declared types. Unrecognized strings fall through to a defined default instead.
- **single-threaded**: The module is stateless and runs on the single JavaScript thread, so concurrent calls cannot interleave and no ordering rule is needed.

