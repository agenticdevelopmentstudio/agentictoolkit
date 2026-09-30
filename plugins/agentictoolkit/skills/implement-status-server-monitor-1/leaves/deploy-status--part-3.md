<!-- leaf: implement-status-server-monitor-1/deploy-status--part-3 · source: status-server-monitor-deploy-status.md -->

# Status Server Monitor Deploy Status — continued (part 3)

**Rules** (cite as `implement-status-server-monitor-1/deploy-status--part-3#<slug>`):

- `crunchy-no-build-lifecycle` MUST
- `crunchy-bad-state-detection` MUST
- `crunchy-healthy-default` MUST
- `crunchy-phases-terminal` MUST
- `combined-status-evaluation-order` MUST
- `combined-status-failed-precedence` MUST
- `combined-status-canceled` MUST
- `combined-status-unknown-precedence` MUST
- `combined-status-deployed-success` MUST
- `combined-status-deploying-building` MUST
- `combined-status-built-staged-success` MUST
- `combined-status-queued` MUST
- `combined-status-default-building` MUST
- `winui-3` SHOULD — a .NET port models DeployStatus, BuildPhase, and DeployPhase as C# enums and Phases as a readonly record struct { …

### Provider Phase Mapper — Crunchy Bridge

- **crunchy-no-build-lifecycle**: `crunchyPhases` MUST always return `buildPhase: null`, per its own doc comment stating Crunchy Bridge clusters have no build/deploy CI lifecycle — health is the cluster `state` alone.
- **crunchy-bad-state-detection**: `crunchyPhases` MUST return `deployPhase: "failed"` when `isSuspended` is `true`, OR when `state` is `"failed"`, `"creation_failed"`, or `"suspended"` (the module-level `CRUNCHY_BAD_STATES` set), and MUST return `deployPhase: "deployed"` otherwise.
- **crunchy-healthy-default**: Every `state` value other than the three documented bad states — including `"ready"`, every documented routine/transient operation (`creating`, `restarting`, `resizing`, `resuming`, `starting`, `upgrading`, `restoring`, `finalizing`, `replaying`, `destroying`, `suspending`), an empty string, and any unrecognized future value — MUST map to `deployPhase: "deployed"`; per the function's own doc comment, this is a deliberate, owner-chosen "quieter" model: routine maintenance MUST NOT page, and an unrecognized state MUST NOT be assumed bad.
- **crunchy-phases-terminal**: Both fields `crunchyPhases` returns MUST always be terminal (`buildPhase` is always `null`, never an in-flight `BuildPhase`; `deployPhase` is always `"failed"` or `"deployed"`, never `"deploying"` or `"unknown"`), so that, per the doc comment, a caller's stuck-deploy check (`deployIsStuck`, external to this file) never misfires on a Crunchy cluster's arbitrarily old `createdAt`.

### Combined Status Derivation

- **combined-status-evaluation-order**: `combinedStatus` MUST evaluate its rules in exactly this order, as a sequence of early returns rather than independent conditions, because a `Phases` value can match more than one rule and only the first matched rule's result is correct: failed, then canceled, then unknown, then deployed, then deploying, then built, then queued, then the default.
- **combined-status-failed-precedence**: `combinedStatus` MUST return `"failed"` when `buildPhase === "failed"` OR `deployPhase === "failed"`, checked before every other rule, so a failure verdict on one lifecycle wins even when the other lifecycle is `"unknown"`.
- **combined-status-canceled**: `combinedStatus` MUST return `"canceled"` when `buildPhase === "canceled"`, checked after failed and before unknown.
- **combined-status-unknown-precedence**: `combinedStatus` MUST return `"unknown"` when `buildPhase === "unknown"` OR `deployPhase === "unknown"`, checked before the in-flight (`"deploying"`) and built/queued fallthrough rules, so a row whose lifecycle expired unconfirmable MUST NOT re-read as `"building"`.
- **combined-status-deployed-success**: `combinedStatus` MUST return `"success"` when `deployPhase === "deployed"`.
- **combined-status-deploying-building**: `combinedStatus` MUST return `"building"` when `deployPhase === "deploying"`.
- **combined-status-built-staged-success**: `combinedStatus` MUST return `"success"` when `buildPhase === "built"` and none of the preceding rules matched — per the branch's own inline comment, this is a build with no separate deploy step (non-production or staged).
- **combined-status-queued**: `combinedStatus` MUST return `"queued"` when `buildPhase === "queued"` and none of the preceding rules matched.
- **combined-status-default-building**: `combinedStatus` MUST return `"building"` for every remaining combination — `buildPhase === "building"`, `buildPhase === null` with no matching `deployPhase` rule, or any other combination not covered above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `readyState`, `readySubstate`, `target` (parameters to `vercelPhases`) | `string`, `string \| null \| undefined`, `string \| null \| undefined` | none — caller-supplied per call | The Vercel deployment fields the caller (`fetch-vercel.ts`, `webhook-events.ts`, `reconcile-stuck-deploys.ts`, all external) already fetched or received via webhook. |
| `status` (parameter to `railwayPhases`) | `string` | none — caller-supplied per call | The Railway deployment status field the caller already fetched or received via webhook. |
| `state`, `isSuspended` (parameters to `crunchyPhases`) | `string`, `boolean` | none — caller-supplied per call | The Crunchy Bridge cluster's documented state string and its `is_suspended` compute-is-off flag, as fetched by `fetch-crunchy.ts` (external). |
| `prefix` (parameter to `inFlightSql`, `columnOverwritableSql`) | `"" \| "excluded."` | `""` | Selects whether the built predicate reads the stored row (`""`) or an upsert's incoming row (`"excluded."`, the SQLite `ON CONFLICT` alias). |
| `col` (parameter to `columnOverwritableSql`, `webhookKeepsStoredSql`) | `"build_phase" \| "deploy_phase"` | none — required | Selects which single lifecycle column the built predicate evaluates; the TypeScript union type itself is the only validation — no other string is accepted at compile time. |
| `to` (parameter to `collapseInFlightBuildSql`, `collapseInFlightDeploySql`) | `BuildPhase` / `DeployPhase` | none — required | The terminal value the built `CASE` expression collapses an in-flight column to. |

## Privacy

- **Data collected**: none of this file's own — it receives already-fetched provider status strings (`readyState`, `status`, cluster `state`) and cluster metadata (`is_suspended`) as plain function arguments from callers external to this file; it collects nothing itself.
- **Storage**: none. This file holds no state between calls and writes nothing; the SQL fragments it builds are executed by the storage layer (`libsql/schema.ts`, `libsql/stores/*.ts`), external to this file.
- **Transmission**: none. This file performs no network or database call; every SQL fragment it returns is a `string` handed back to its caller, which decides whether and how to execute it.
- **Retention**: not applicable — this file holds no data across calls.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port would model `DeployStatus`, `BuildPhase`, and `DeployPhase` as `Sendable`, `String`-backed `enum`s and `Phases` as a `Sendable struct`; because every function here is a pure, synchronous, non-isolated computation, the ported functions need no `actor` or `@MainActor` isolation at all — plain top-level or static functions are the direct equivalent.
- **Compose**: same non-UI framing. A Kotlin port models the three unions as `enum class`es and the mapper/derivation functions as top-level functions using `when` expressions in place of this file's ternary chains and `switch` statement; the SQL-fragment builders would more idiomatically return a query-builder DSL fragment (Room/SQLDelight `WHERE` clause) rather than a raw interpolated `String`, though the safety property is the same either way since only fixed enum literals are interpolated, never caller input.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/deploy-status.ts` as a plain ESM module on the Node status backend, re-exported at the package's `./deploy-status` subpath (`@agentic-toolkit/status-server/deploy-status`); it has a hand-maintained mirror copy at `packages/web/packages/status-web/src/lib/deploy-status.ts` (external to this file, the two packages share no build) whose drift against this file is asserted only for `IN_FLIGHT_BUILD_PHASES`, `IN_FLIGHT_DEPLOY_PHASE`, `isInFlight`, and `combinedStatus` by `deploy-status-parity.test.ts` — the provider mappers (`vercelPhases`, `railwayPhases`, `crunchyPhases`) and the five SQL-fragment builders have no such cross-package parity guard.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no `Worker`-style per-thread module duplication concern applies to a Swift port the way it might to a Node file with mutable module state, but this file in particular has no mutable state to duplicate in the first place — every function is stateless.
- **WinUI 3**: a .NET port models `DeployStatus`, `BuildPhase`, and `DeployPhase` as C# `enum`s and `Phases` as a `readonly record struct { BuildPhase? BuildPhase; DeployPhase DeployPhase }`, with `VercelPhases`, `RailwayPhases`, `CrunchyPhases`, and `CombinedStatus` as `static` methods (e.g. on a `DeployStatusMapper` class) using C# `switch` expressions in place of this file's ternary chains. For the SQL-fragment builders, a port against the same libSQL/SQLite store via `Microsoft.Data.Sqlite` or EF Core's `FromSqlRaw` can keep this file's literal-interpolation approach with the same safety property — only the module's own fixed enum literals are interpolated, never external input — but where the surrounding query already uses `DbCommand.Parameters`/EF Core parameterization for other values, the port SHOULD interpolate through a small internal helper that still emits only these fixed literals rather than mixing raw string concatenation into an otherwise-parameterized query, to keep the codebase's SQL construction convention consistent.

