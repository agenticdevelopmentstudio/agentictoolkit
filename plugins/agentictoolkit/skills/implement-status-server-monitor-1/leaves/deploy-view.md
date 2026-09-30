<!-- leaf: implement-status-server-monitor-1/deploy-view · source: status-server-monitor-deploy-view.md -->

**Rules** (cite as `implement-status-server-monitor-1/deploy-view#<slug>`):

- `indicator-shape` MUST
- `env-from-project-reexport` MUST
- `branch-env-lookup` MUST
- `branch-env-nullish-input` MUST
- `branch-env-main-excluded` MUST
- `deploy-env-branch-precedence` MUST
- `deploy-env-vercel-fallback` MUST
- `deploy-env-nonvercel-fallback` MUST
- `deploy-env-branch-required-param` MUST
- `is-real-env-deploy-row` MUST
- `is-real-env-deploy-delegates` MUST
- `deploy-links-source-url` MUST
- `deploy-links-live-url` MUST
- `module-state-immutable` MUST

# Status Server Monitor Deploy View

## Overview

`deploy-view.ts` (`packages/web/packages/status-server/src/monitor/deploy-view.ts`) is a pure, synchronous logic module in the status backend. Its own header comment states its scope precisely: deploy/environment derivation plus link derivation, and the `Indicator` shape a sign or pill renders from. Row construction is explicitly out of scope (it lives in the web client's `row-model.ts`); problem derivation — which rows are problems, and what indicator state they carry — is explicitly the server's, in `board/derive-activity.ts`. This file exports two data shapes (`IndicatorState`, `Indicator`), a re-export of `envFromProject` from the shared `@agentic-toolkit/deploy-platform/canon` package, a fixed branch-to-tier lookup (`BRANCH_ENV`) and the function that reads it (`envFromBranch`), the three-signal tier derivation `deployEnv`, the real-environment-deploy predicate in two forms (`isRealEnvDeploy`, `isRealEnvDeployRow`), and `deployLinks`, which builds a deploy row's debug (`sourceUrl`) and live (`liveUrl`) links from a raw provider URL and a resolved live host. `deployEnv` and `isRealEnvDeployRow` are imported and used by `provider-deploy.ts`'s DTO mapper and by `board/ownership.ts` and `board/derive-problems.ts`'s tier derivation; `envFromProject` is re-exported so callers that already import it via `./deploy-view` (e.g. `routes/reads.ts`) keep working after the function itself moved into the shared `canon` package.

## Behavioral Requirements

### Data Shapes

- **indicator-shape**: An `Indicator` value MUST carry exactly two fields — `state: IndicatorState`, where `IndicatorState` is the three-member union `"ok" | "warn" | "down"`, and `count: number` — and a literal using another `state` value or omitting either field MUST fail to type-check.
- **env-from-project-reexport**: This module MUST re-export the `envFromProject` function it imports from `@agentic-toolkit/deploy-platform/canon` unchanged, so a caller importing `envFromProject` from `./deploy-view` gets the identical function, and identical results, as a caller importing it directly from the `canon` package.

### Environment Derivation

- **branch-env-lookup**: `envFromBranch` MUST return `"testing"` for branch `"prepared"`, `"staging"` for branch `"staging"`, and `"production"` for branch `"production"`, and MUST return `null` for any branch string not one of those three, including one that names a property inherited from `Object.prototype` (for example `"constructor"`, `"toString"`, `"valueOf"`, `"hasOwnProperty"`, `"__proto__"`).
- **branch-env-nullish-input**: `envFromBranch` MUST return `null` when its `branch` argument is `null`, `undefined`, or the empty string, without consulting the lookup table.
- **branch-env-main-excluded**: `envFromBranch` MUST return `null` for branch `"main"` specifically; `"main"` MUST NOT appear as a key in the branch-to-tier lookup, per the source's own comment that `main` deploys nothing and therefore carries no evidence about any tier.
- **deploy-env-branch-precedence**: `deployEnv` MUST return whatever `envFromBranch(branch)` returns whenever that call returns a non-null value, regardless of what `platform`, `projectName`, or `storedEnv` are — including when the project-name or stored-environment signal would otherwise disagree with the branch.
- **deploy-env-vercel-fallback**: When `envFromBranch(branch)` returns `null` and `platform === "vercel"`, `deployEnv` MUST return `envFromProject(projectName)`, ignoring `storedEnv` entirely.
- **deploy-env-nonvercel-fallback**: When `envFromBranch(branch)` returns `null` and `platform !== "vercel"`, `deployEnv` MUST return `storedEnv` unchanged when it is a non-empty string, and MUST return `envFromProject(projectName)` when `storedEnv` is `null` or the empty string.
- **deploy-env-branch-required-param**: `deployEnv`'s `branch` parameter MUST have no default value; a caller with no branch to offer MUST pass `null` explicitly rather than omitting the argument.

### Real-Deploy Classification

- **is-real-env-deploy-row**: `isRealEnvDeployRow` MUST return `false` only when `platform === "vercel"` and `environment` is `null` or the empty string, and MUST return `true` for every other combination of `platform` and `environment`, including a non-Vercel platform whose `environment` is `null` or empty.
- **is-real-env-deploy-delegates**: `isRealEnvDeploy` MUST return exactly the value `isRealEnvDeployRow(d.platform, d.environment)` would return for the given `DeploymentDTO d`, reading only its `platform` and `environment` fields.

### Links

- **deploy-links-source-url**: `deployLinks` MUST set the `sourceUrl` field of its result to `projectPageUrl(url)` (from `./url.ts`): for a Vercel inspector URL (hostname `vercel.com` with at least three path segments), the result collapses to `<origin>/<team>/<project>`; for any other URL, for a URL that fails to parse, or when `url` is `null`, the result passes through unchanged.
- **deploy-links-live-url**: `deployLinks` MUST set the `liveUrl` field of its result to `` `https://${liveHost}` `` when `liveHost` is a non-empty string, and to `null` when `liveHost` is `null`, and MUST NOT derive `liveUrl` from `url` or from the computed `sourceUrl` in either case.

### Ordering and Concurrency

- **module-state-immutable**: `BRANCH_ENV` MUST be constructed once, as a read-only `Map`, when the module is loaded, and no exported function in this file MUST mutate it; every derivation in this file MUST be a pure function of the arguments passed to it, with no other module-level mutable state. Because nothing here performs an `await` and JavaScript executes one module instance's code on a single thread, concurrent calls into these functions from the same thread MUST NOT interleave in a way that corrupts a result — this is a structural fact of the runtime and the file's own statelessness, not a lock this file implements.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `platform` (parameter to `deployEnv`, `isRealEnvDeployRow`, and via `d.platform` to `isRealEnvDeploy`) | `string` | none — caller-supplied | The deploy's platform identifier (`"vercel"`, `"railway"`, `"cloudflare-pages"`, `"crunchy"`, ...); only the literal value `"vercel"` changes this file's branching behavior. |
| `projectName` (parameter to `deployEnv`) | `string` | none — caller-supplied | Passed straight through to `envFromProject` on every fallback path this file reaches. |
| `storedEnv` (parameter to `deployEnv`) | `string \| null` | none — caller-supplied | The provider's own reported environment/promotion target; consulted only on the non-Vercel fallback path (deploy-env-nonvercel-fallback). |
| `branch` (parameter to `deployEnv` and `envFromBranch`) | `string \| null` | none — required, no default (deploy-env-branch-required-param) | The deploy's source-control branch; the highest-precedence of the three signals `deployEnv` considers. |
| `url` (parameter to `deployLinks`) | `string \| null` | none — caller-supplied | The provider's raw deploy/inspector URL, reshaped into `sourceUrl` via `projectPageUrl`. |
| `liveHost` (parameter to `deployLinks`) | `string \| null` | none — caller-supplied | A bare hostname (no scheme), per `DeploymentDTO.liveHost`'s own field comment ("resolved live custom domain host"); `deployLinks` prefixes it with `https://` and performs no further validation of its shape. |
| `BRANCH_ENV` (module-level constant) | `ReadonlyMap<string, string>` | fixed 3 entries: `"prepared"` → `"testing"`, `"staging"` → `"staging"`, `"production"` → `"production"` | Not configurable at runtime; adding, removing, or overriding an entry requires editing this file. This file reads no environment variable and consults no injected configuration object of its own. |

## Platform Notes

- **SwiftUI**: not a view-layer concern — this file has no view. A Swift port models `IndicatorState` as an `enum` with three cases and `Indicator` as a `Sendable` `struct` wrapping it plus a `count: Int`; `BRANCH_ENV` becomes a `static let` `[String: String]` dictionary literal, and `envFromBranch`/`deployEnv`/`isRealEnvDeployRow`/`isRealEnvDeploy`/`deployLinks` become plain (non-`actor`, since nothing here is asynchronous or mutates shared state) static functions. Swift's `Dictionary` has no prototype-chain lookup, so the `Map`-vs-object-literal hazard `BRANCH_ENV`'s own comment explains has no Swift analogue — any `String` key, including one spelled `"toString"`, is looked up only among the dictionary's own entries.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `Indicator` as a `data class` wrapping a sealed or enum `IndicatorState`, `BRANCH_ENV` as a `mapOf(...)` literal (a Kotlin `Map`, likewise immune to the JavaScript prototype-pollution hazard), and the derivation functions as top-level `fun`s or an object's methods — no `suspend` modifier is needed anywhere, since nothing in this file performs asynchronous work.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/deploy-view.ts`, a plain module in the Hono status backend (Node), not client-side React. `deployEnv` and `isRealEnvDeployRow` are imported by `provider-deploy.ts`'s DTO mapper and by `board/ownership.ts` and `board/derive-problems.ts`'s tier derivation; `envFromProject` is re-exported here from `@agentic-toolkit/deploy-platform/canon` so a caller importing it via `./deploy-view` (`routes/reads.ts`) is unaffected by that function's move into the shared package. `isRealEnvDeploy`, `deployLinks`, `Indicator`, and `IndicatorState` are exported but, as of this recipe's authoring, have no importer anywhere else in this package.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — nothing here touches a view controller or window. A macOS/iOS host app would consume the Swift port described above from its data/service layer exactly as this file's server-side callers do today, with no framework-specific adaptation needed beyond that layer boundary.
- **WinUI 3**: a .NET port models `Indicator` as a `readonly record struct` wrapping an `IndicatorState` `enum` (`Ok`, `Warn`, `Down`) and a `Count` `int`; `BRANCH_ENV` as a `static readonly Dictionary<string, string>` (or a `FrozenDictionary<string, string>` on .NET 8+, matching the source's own "never mutated after construction" `ReadonlyMap` typing); and `EnvFromBranch`, `DeployEnv`, `IsRealEnvDeployRow`/`IsRealEnvDeploy`, and `DeployLinks` as static methods on a plain static class. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, or `ObservableCollection`/`INotifyPropertyChanged` is needed anywhere in this port, because the source file itself performs no I/O, no asynchronous work, and holds no UI-observable state; `DeployLinks`' URL handling (the analogue of `projectPageUrl`'s `new URL(url)` inside a try/catch) should use `Uri.TryCreate` rather than a thrown-and-caught exception, to match the source's fail-soft "pass the raw string through on a parse failure" behavior without relying on exception flow for an expected case.

