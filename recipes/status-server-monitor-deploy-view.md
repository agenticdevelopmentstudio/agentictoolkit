---
id: 9b95bde8-c47e-40a4-a21c-4a84c23ddbf1
title: Status Server Monitor Deploy View
domain: agentictoolkit://recipes/status-server-monitor-deploy-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Derives a deploy row's logical tier from its branch, classifies which deploys
  represent a real environment, and builds the debug/live links a deploy row exposes.
platforms:
- typescript
- web
tags:
- monitor
- deploy
- environment
- server
depends-on: []
related: []
references:
- packages/web/packages/status-server/src/monitor/deploy-view.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-env.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/url.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/canon/index.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a logic module (deploy/environment derivation and link building), not a visual component.

## States

Not applicable — this is a logic module with no visual-state table; its only state-like distinctions (which tier a deploy belongs to, whether it counts as a real-environment deploy) are pure return values documented under Behavioral Requirements, not runtime states of a component instance.

## Accessibility

Not applicable — this is a logic module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-deploy-view-001 | branch-env-lookup, branch-env-main-excluded, module-state-immutable | `envFromBranch("prepared")`; `envFromBranch("staging")`; `envFromBranch("production")`; `envFromBranch("main")`, called in that order | Returns `"testing"`, `"staging"`, `"production"`, `null` respectively, each call unaffected by the ones before it — `deploy-env.test.ts` › "maps the three deploying branches to the tiers they build" and "answers null for anything it was not told about, rather than guessing" |
| status-server-monitor-deploy-view-002 | branch-env-nullish-input | `envFromBranch(null)`; `envFromBranch(undefined)`; `envFromBranch("")` | Each call returns `null` — `deploy-env.test.ts`, same "it" block as above |
| status-server-monitor-deploy-view-003 | branch-env-lookup | For each of `"constructor"`, `"toString"`, `"valueOf"`, `"hasOwnProperty"`, `"__proto__"`: `envFromBranch(name)` and `deployEnv("vercel", "hub-help-testing", "production", name)` | `envFromBranch(name)` returns `null` for every name (never the inherited function or object `{}[name]` would return); `deployEnv(...)` returns `"testing"` for every name (falls through to the project-name rule) — `deploy-env.test.ts` › "answers null for a branch that names something on Object.prototype" |
| status-server-monitor-deploy-view-004 | deploy-env-branch-precedence | `deployEnv("vercel", "hub", "production", "prepared")`; `deployEnv("vercel", "hub-help-testing", "production", "production")` | Returns `"testing"` (branch overrides a project name that says nothing about tier) and `"production"` (branch overrides a `-testing` project name that disagrees with it) respectively — `deploy-env.test.ts` › "reads the tier off the BRANCH..." and "lets the branch OVERRIDE a name that disagrees with it" |
| status-server-monitor-deploy-view-005 | deploy-env-vercel-fallback | `deployEnv("vercel", "hub-help-testing", "production", null)`; `deployEnv("vercel", "staging.adh", "production", null)`; `deployEnv("vercel", "hub", "production", null)` | Returns `"testing"`, `"staging"`, `"production"` respectively — `storedEnv` (`"production"` in every case) is ignored throughout — `deploy-env.test.ts` › "falls back to the project name when there is no branch to read" |
| status-server-monitor-deploy-view-006 | deploy-env-nonvercel-fallback | `deployEnv("railway", "adh-backend", "testing", null)`; `deployEnv("cloudflare-pages", "temporal-web", "", null)` | Returns `"testing"` (non-empty `storedEnv` trusted) and `"production"` (empty `storedEnv` falls through to `envFromProject("temporal-web")`) respectively — `deploy-env.test.ts` › "still trusts a non-Vercel platform's reported environment when no branch decides" |
| status-server-monitor-deploy-view-007 | deploy-env-branch-precedence | `deployEnv("railway", "adh-backend", "production", "prepared")` | Returns `"testing"` — the branch outranks a non-Vercel platform's stored `"production"` value, not only Vercel's — `deploy-env.test.ts` › "but the branch outranks a non-Vercel stored environment too" |
| status-server-monitor-deploy-view-008 | is-real-env-deploy-row, is-real-env-deploy-delegates | `isRealEnvDeployRow("vercel", null)`; `isRealEnvDeployRow("vercel", "")`; `isRealEnvDeployRow("vercel", "production")`; `isRealEnvDeployRow("railway", null)`; `isRealEnvDeploy({ ...dto, platform: "vercel", environment: null })` | Returns `false`, `false`, `true`, `true`, `false` respectively — only the Vercel-plus-null-or-empty-environment combination is a non-real deploy; the DTO form agrees with the row form on the same inputs. This exact call shape is not exercised by a dedicated unit test in this package — `isRealEnvDeployRow` is exercised only indirectly, through `providerDeployToDTO`'s `tier` assertions in `deploy-env.test.ts` › "is NULL for a Vercel preview" |
| status-server-monitor-deploy-view-009 | deploy-links-source-url | `deployLinks("https://vercel.com/acme/my-project/dpl_abc123", null)`; `deployLinks("https://dashboard.railway.app/project/xyz", null)`; `deployLinks(null, null)` | Returns `sourceUrl` `"https://vercel.com/acme/my-project"` (Vercel inspector URL collapsed to the project page), `"https://dashboard.railway.app/project/xyz"` (non-Vercel URL passed through unchanged), and `null` respectively — traced to `projectPageUrl`'s own doc comment and implementation in `url.ts`; no dedicated unit test of `deployLinks` or `projectPageUrl` exists in this package |
| status-server-monitor-deploy-view-010 | deploy-links-live-url | `deployLinks(null, "app.example.com")`; `deployLinks("https://vercel.com/acme/my-project/dpl_abc123", null)` | Returns `liveUrl` `"https://app.example.com"` and `null` respectively — the second case's `liveUrl` is `null` even though a `sourceUrl` was computed, because `liveUrl` is never derived from `url`/`sourceUrl` — traced to the source comment "We deliberately do NOT fall back to the deploy/inspector URL" |
| status-server-monitor-deploy-view-011 | env-from-project-reexport | `import { envFromProject } from "./deploy-view"` then `envFromProject("docs-staging")`, `envFromProject("docs-testing")`, `envFromProject("hub")` | Returns `"staging"`, `"testing"`, `"production"` respectively — identical to calling the same inputs against `@agentic-toolkit/deploy-platform/canon`'s `envFromProject` directly, per `canon.test.ts` › "envFromProject reads BOTH name shapes this fleet uses, and defaults to production" |

## Edge Cases

- **Null and empty input**: `envFromBranch(null \| undefined \| "")` returns `null` without consulting the lookup — MUST (branch-env-nullish-input). `deployEnv` with a non-Vercel `platform`, a `null` `branch`, and `storedEnv` equal to `null` or `""` falls through to `envFromProject(projectName)` — MUST (deploy-env-nonvercel-fallback). `isRealEnvDeployRow` treats a `null` or empty `environment` as "not a real deploy" only for `platform === "vercel"`; for every other platform, a `null` or empty `environment` still returns `true` — MUST (is-real-env-deploy-row) — this is a deliberate asymmetry, not an oversight: Vercel previews are the one case reporting no environment while still being a live deploy of something, so a blanket "no environment means not real" rule would misclassify a Railway or Cloudflare row that simply has not had its environment populated yet. `deployLinks(null, null)` returns `{ sourceUrl: null, liveUrl: null }` — MUST.
- **Boundary values**: a `branch` string that exactly matches a name inherited from `Object.prototype` (`"constructor"`, `"toString"`, `"valueOf"`, `"hasOwnProperty"`, `"__proto__"`) is the boundary the `Map`-based lookup exists to cross safely — `envFromBranch` MUST return `null` for each of these, never the inherited function or object a plain object-literal lookup would return (branch-env-lookup). An empty-string `projectName` passed through `deployEnv`'s fallback path reaches `envFromProject("")`, which is external to this file (`@agentic-toolkit/deploy-platform/canon`) and answers `"production"` for any string matching neither its `-staging`/`-testing` suffix nor its `staging.`/`testing.` prefix, including the empty string — stated here as a fact of the composed behavior, not a gap in this file, since `envFromProject` is a different file's contract.
- **Concurrent access**: this file holds no state beyond the read-only `BRANCH_ENV` map, and every exported function is synchronous and pure — MUST NOT require any lock or ordering guarantee, because there is no shared mutable state for concurrent calls to race over (module-state-immutable).
- **Error states**: none of this file's own functions throw on a malformed input. The one operation with a real failure mode — parsing `url` as a `URL` inside `projectPageUrl` (`url.ts`, called by `deployLinks`) — is wrapped in a try/catch there that returns the original string unchanged on a parse failure, so a malformed `url` never propagates an exception into `deployLinks` or its caller — MUST (deploy-links-source-url, by way of `projectPageUrl`'s documented behavior). This file has no dependency on a network, database, or file system of its own to fail.
- **Offline or disconnected state**: Not applicable — this file performs no network I/O, holds no connection, and reads no external service; every function is a synchronous transform of arguments its caller already has in hand. The deploy data these functions operate on was fetched by other files (`fetch-vercel.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, etc., all external to this file), whose own connectivity failure modes are theirs to document, not this module's.

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

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own. `deployLinks` reshapes an already-fetched provider URL and a resolved host into `sourceUrl`/`liveUrl` for display elsewhere; it does not construct a deep link into any screen of this app.

## Localization

Not applicable: this file produces no user-facing string. Its return values are tier identifiers (`"testing"`, `"staging"`, `"production"`), booleans, and URLs consumed by rendering code external to this file — none of it is literal copy a person reads as prose.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system. Its only branching on a fixed value is the literal string comparison `platform === "vercel"` in `deployEnv` and `isRealEnvDeployRow`, which is a data-driven rule, not a flag lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this file performs no data collection, storage, or transmission of its own. Every exported function is a pure, synchronous transform of arguments its caller already supplied — project names, branch names, environment strings, and URLs that originated elsewhere (the provider fetchers, external to this file) and are handed back to the caller as a return value; this file itself never writes them anywhere or sends them anywhere.

## Logging

Not applicable: this file contains no logging call of any kind — no `console.*` call and no structured logger call appears anywhere in its source.

## Platform Notes

- **SwiftUI**: not a view-layer concern — this file has no view. A Swift port models `IndicatorState` as an `enum` with three cases and `Indicator` as a `Sendable` `struct` wrapping it plus a `count: Int`; `BRANCH_ENV` becomes a `static let` `[String: String]` dictionary literal, and `envFromBranch`/`deployEnv`/`isRealEnvDeployRow`/`isRealEnvDeploy`/`deployLinks` become plain (non-`actor`, since nothing here is asynchronous or mutates shared state) static functions. Swift's `Dictionary` has no prototype-chain lookup, so the `Map`-vs-object-literal hazard `BRANCH_ENV`'s own comment explains has no Swift analogue — any `String` key, including one spelled `"toString"`, is looked up only among the dictionary's own entries.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `Indicator` as a `data class` wrapping a sealed or enum `IndicatorState`, `BRANCH_ENV` as a `mapOf(...)` literal (a Kotlin `Map`, likewise immune to the JavaScript prototype-pollution hazard), and the derivation functions as top-level `fun`s or an object's methods — no `suspend` modifier is needed anywhere, since nothing in this file performs asynchronous work.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/deploy-view.ts`, a plain module in the Hono status backend (Node), not client-side React. `deployEnv` and `isRealEnvDeployRow` are imported by `provider-deploy.ts`'s DTO mapper and by `board/ownership.ts` and `board/derive-problems.ts`'s tier derivation; `envFromProject` is re-exported here from `@agentic-toolkit/deploy-platform/canon` so a caller importing it via `./deploy-view` (`routes/reads.ts`) is unaffected by that function's move into the shared package. `isRealEnvDeploy`, `deployLinks`, `Indicator`, and `IndicatorState` are exported but, as of this recipe's authoring, have no importer anywhere else in this package.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — nothing here touches a view controller or window. A macOS/iOS host app would consume the Swift port described above from its data/service layer exactly as this file's server-side callers do today, with no framework-specific adaptation needed beyond that layer boundary.
- **WinUI 3**: a .NET port models `Indicator` as a `readonly record struct` wrapping an `IndicatorState` `enum` (`Ok`, `Warn`, `Down`) and a `Count` `int`; `BRANCH_ENV` as a `static readonly Dictionary<string, string>` (or a `FrozenDictionary<string, string>` on .NET 8+, matching the source's own "never mutated after construction" `ReadonlyMap` typing); and `EnvFromBranch`, `DeployEnv`, `IsRealEnvDeployRow`/`IsRealEnvDeploy`, and `DeployLinks` as static methods on a plain static class. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, or `ObservableCollection`/`INotifyPropertyChanged` is needed anywhere in this port, because the source file itself performs no I/O, no asynchronous work, and holds no UI-observable state; `DeployLinks`' URL handling (the analogue of `projectPageUrl`'s `new URL(url)` inside a try/catch) should use `Uri.TryCreate` rather than a thrown-and-caught exception, to match the source's fail-soft "pass the raw string through on a parse failure" behavior without relying on exception flow for an expected case.

## Design Decisions

- **Decision**: rank the branch signal above both the project-name convention and the platform's own stored environment in `deployEnv`, rather than trusting whichever signal a given platform happens to report.
  **Rationale**: per the source's doc comment on `deployEnv`, the branch "is the pipeline's own input, so it is right by construction for any project, named however it likes, on any platform," while the project-name rule defaults to `"production"` for any name it cannot parse and Vercel's stored environment is `"production"` for every project's promotion target — both of those defaults are wrong in exactly the way that matters most, badging a live testing deploy as production. `deploy-env.test.ts`'s assertion that a Railway environment literally named `"production"` still reads `"testing"` when its branch is `"prepared"` confirms the ranking is about which signal can lie, not about which platform reported it.
  **Approved**: pending
- **Decision**: implement `BRANCH_ENV` as a `Map` rather than a plain object literal, and have `envFromBranch` look a branch up only among that map's own three entries.
  **Rationale**: the source comment explains that indexing a plain object literal reaches `Object.prototype`, so a branch literally named `"toString"` or `"__proto__"` would return a truthy inherited function or object rather than `undefined`, defeating the `?? null` fallback and handing a non-string value to a caller that a `Record<string, string>` type annotation swore was a string all the way to a rendered badge — pinned directly by `deploy-env.test.ts`'s dedicated Object.prototype test.
  **Approved**: pending
- **Decision**: give `deployEnv`'s `branch` parameter no default value, requiring every caller to pass `null` explicitly when it has no branch to offer.
  **Rationale**: the source's own doc comment states a default "would let a new call site silently take the fallible path and badge a testing project PROD, which is the exact regression this parameter was added to close" — an explicit `null` forces a new call site's no-branch state to be visible in its own code rather than inherited silently from a signature default.
  **Approved**: pending
- **Decision**: never fall back from `liveUrl` to the deploy/inspector URL when `liveHost` is `null`.
  **Rationale**: the source comment states "a link rendered as a host must point at the real site, never the build page" — so a missing live host renders as no live link at all, rather than a link that looks like it opens the live site but actually opens the provider's build/inspector page.
  **Approved**: pending
- **Decision**: keep exporting `isRealEnvDeploy`, `deployLinks`, `Indicator`, and `IndicatorState` even though, at the time of this recipe's authoring, no other file in the `status-server` package imports any of the four directly.
  **Rationale**: recorded as an observed fact of the current call graph, not a defect in this file — all four behave exactly as documented, and `isRealEnvDeployRow` (the sibling `isRealEnvDeploy` delegates to) is exercised indirectly through `providerDeployToDTO`'s tier assertions in `deploy-env.test.ts`. Nothing here is broken or unused within this file; a future caller needing a DTO-level real-deploy check, a shared `sourceUrl`/`liveUrl` builder, or the `Indicator` shape has these ready without re-deriving `projectPageUrl`'s Vercel-URL-collapsing logic itself.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` is `partial`: `deploy-env.test.ts` thoroughly exercises `envFromBranch` and `deployEnv`, including the Object.prototype boundary and every signal-precedence case, and exercises `isRealEnvDeployRow` indirectly through `providerDeployToDTO`'s `tier` assertions — but `isRealEnvDeploy`, `deployLinks`, and the `Indicator`/`IndicatorState` shapes have no dedicated test anywhere in this package. `separation-of-concerns` passes: the file's own header comment states its scope precisely (deploy/environment and link derivation only), explicitly disclaiming row construction (the web client's job) and problem derivation (the board's job); it reads no configuration and performs no I/O of its own. `explicit-error-handling` passes: every "no signal" case is propagated as an explicit `null` return (`envFromBranch`, and `isRealEnvDeployRow`'s DTO-level `tier` gate in `provider-deploy.ts`) rather than silently defaulting or throwing, and the one place a real exception could occur — URL parsing inside `projectPageUrl` — is caught there and turned into an explicit fallback value, not swallowed without a trace. `fault-tolerance` passes: the module accepts arbitrary caller-supplied strings (branch names, project names, URLs) including ones deliberately shaped to break a naive object-literal lookup, and every function returns a well-typed result rather than throwing for any input in its documented domain.

`unit-test-coverage`'s gap is the open question on `isRealEnvDeploy`/`deployLinks`/`Indicator`/`IndicatorState` — see the corresponding Design Decision above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
