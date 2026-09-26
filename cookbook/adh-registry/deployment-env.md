---
id: 8d05d4b2-06a8-44db-816a-ce839836fd71
title: DeploymentEnv
domain: agentictoolkit://cookbook/adh-registry/deployment-env
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The fail-closed dev-deployment allowlist read two ways: a server-render
  gate and a bundler-foldable build flag.'
platforms:
- typescript
- web
tags:
- web
- deployment-env
- feature-gating
- build-config
depends-on: []
related: []
references:
- packages/web/packages/adh-registry/src/deployment-env.ts (agentictoolkit)
- packages/web/packages/adh-registry/src/__tests__/deploymentEnv.test.ts (agentictoolkit)
- packages/web/packages/adh-registry/src/seo/metadata.ts (agentictoolkit)
- packages/web/packages/adh/src/__tests__/productionBundleGates.test.ts (agentictoolkit)
- adhbackend/src/adh/test/themeSurfaceEnv.test.ts (adhbackend)
approved-by: ''
approved-date: ''
---

# DeploymentEnv

## Overview

`deployment-env.ts` is the framework-free logic module inside
`@agentic-toolkit/adh-registry` that answers one question — "is this a dev
deployment?" — in the two different ways its two different audiences need
it answered. `isDevDeploymentEnv(env)` is a server-side type guard, evaluated
against `process.env.DEPLOYMENT_ENV` (never shipped to the browser), that
decides what a page RENDERS. `DEV_BUILD` is a module-level boolean, computed
once from `process.env.NEXT_PUBLIC_DEPLOYMENT_ENV` (a build-time-inlined,
bundler-visible variable), that decides what a dev BUILD DOES — which menu
entries exist, which helper gets called. Both read the same three-entry
allowlist, `DEV_DEPLOYMENT_ENVS = ['local', 'testing', 'staging']`, but the
two exports cannot be merged into one function because `DEV_BUILD` also has
to stay in a shape webpack/Next's constant folder can reduce to a literal at
build time — routing it through the shared array would leave a runtime
lookup the folder cannot see through. The module replaced seven modules that
each spelled the same allowlist out independently, on the mistaken theory
that a shared constant would defeat the `NEXT_PUBLIC_*` inlining, and it now
anchors a cross-repo drift guard: `adhbackend`'s backend process keeps its
own independent copy of the same allowlist, checked against this file's
literal source text by `adhbackend/src/adh/test/themeSurfaceEnv.test.ts`. It
lives in `adh-registry` rather than in the `adh` package where most of its
consumers are, specifically so `adh-registry`'s own `seo/metadata.ts` can
read it too without creating an import cycle.

## Behavioral Requirements

- **dev-deployment-envs-list**: `DEV_DEPLOYMENT_ENVS` MUST be exported as the
  fixed three-element array `['local', 'testing', 'staging']`, and
  `DevDeploymentEnv` MUST be the literal union type derived from it
  (`(typeof DEV_DEPLOYMENT_ENVS)[number]`).
- **dev-env-membership-check**: `isDevDeploymentEnv(env)` MUST return `true`
  when, and only when, `env` is non-null, non-undefined, and an exact,
  case-sensitive match for one of the three entries in
  `DEV_DEPLOYMENT_ENVS`.
- **dev-env-fail-closed**: `isDevDeploymentEnv(env)` MUST return `false` for
  `null`, `undefined`, the empty string, `"production"`, and any string that
  does not exactly match an allowlisted entry — including a differently-cased
  or whitespace-padded near-match such as `"LOCAL"`, `"Local"`, or
  `"staging "` — so an unset, misspelled, or unrecognized environment hides
  the dev affordance rather than exposing it.
- **dev-env-server-side-scope**: `isDevDeploymentEnv` MUST be evaluated
  against `process.env.DEPLOYMENT_ENV`, an environment variable carrying no
  `NEXT_PUBLIC_` prefix and therefore never delivered to the browser; its
  result MUST be used only to decide what a server render emits, never what
  code a client bundle contains.
- **dev-build-literal-comparisons**: `DEV_BUILD` MUST be assigned the result
  of exactly three `===` comparisons —
  `process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'local'`, `... === 'testing'`,
  `... === 'staging'` — joined with `||`, and MUST NOT be expressed as
  `DEV_DEPLOYMENT_ENVS.includes(...)`, `.some(...)`, or `.indexOf(...)`,
  because the build-time bundler substitutes the `NEXT_PUBLIC_*` text and
  constant-folds only a comparison against a string literal; routing the same
  check through an array method leaves a runtime lookup the folder cannot
  resolve, so every branch gated on the result survives into the production
  bundle.
- **dev-build-load-time-evaluation**: `DEV_BUILD` MUST be computed exactly
  once, at module evaluation time, from whatever value
  `process.env.NEXT_PUBLIC_DEPLOYMENT_ENV` holds at that moment; it MUST NOT
  be re-computed or re-read on a later access.
- **dev-build-agrees-with-server-gate**: For every environment value either
  function accepts, the boolean `DEV_BUILD` computes from
  `NEXT_PUBLIC_DEPLOYMENT_ENV` MUST equal what `isDevDeploymentEnv` computes
  from the same string value read as `DEPLOYMENT_ENV` — two separate
  declarations reading two separate (server-only vs.
  `NEXT_PUBLIC_`-prefixed) environment variables, but stating one fact.
- **dev-env-type-guard-narrowing**: `isDevDeploymentEnv` MUST be declared as
  a TypeScript type predicate (`env is DevDeploymentEnv`), so that code
  branching on a `true` result narrows `env`'s static type from
  `string | null | undefined` to the literal union
  `'local' | 'testing' | 'staging'`.
- **chunk-gate-inline-comparison-requirement**: Any caller elsewhere in the
  codebase that gates a dynamic `import()` on this module's dev/production
  distinction MUST write the three `NEXT_PUBLIC_DEPLOYMENT_ENV === '<env>'`
  comparisons directly at the `import()` call site rather than branching on
  an imported identifier such as `DEV_BUILD`, because the bundler's
  dead-code elimination for a dynamic import resolves only a literal
  comparison it can see while parsing that exact call site, and does not
  follow an imported identifier back to where it is defined.
- **chunk-gate-subpath-specifier-requirement**: A module gated per
  chunk-gate-inline-comparison-requirement MUST be reached through its
  package subpath specifier (e.g. `@agentic-toolkit/adh/...`), never a
  relative path, whenever the importing package's bundler configuration
  (such as tsup's `splitting: false`) would otherwise inline a relative
  import's code into the same output file and erase the module boundary the
  gate depends on.
- **dev-build-safe-for-non-chunk-gating-uses**: Importing and branching on
  `DEV_BUILD` directly for a non-`import()` decision (such as computing a
  boolean flag) MUST be treated as safe and equivalent to re-declaring the
  same three comparisons locally, because the `NEXT_PUBLIC_*` substitution
  and constant fold apply to every module the bundler processes — node_modules
  included — so a shared `DEV_BUILD` import folds to the same literal a local
  restatement would.
- **cross-repo-allowlist-parity**: The three literal strings inside
  `DEV_DEPLOYMENT_ENVS` MUST remain exactly the set that `adhbackend`'s
  independently declared `isThemeSurfaceEnv` allowlist also names, because a
  separate backend process reads its own `DEPLOYMENT_ENV` copy to decide
  whether to serve theme data, and a divergence between the two lists either
  serves a theme surface the frontend has already hidden, or hides one the
  frontend still asks for.
- **module-load-is-total**: Loading this module MUST perform only a single
  synchronous read of `process.env.NEXT_PUBLIC_DEPLOYMENT_ENV` (to compute
  `DEV_BUILD`); it MUST NOT perform file, network, or other I/O, and MUST NOT
  throw for any input, including when `NEXT_PUBLIC_DEPLOYMENT_ENV` is unset.

## Appearance

Not applicable — this is a deployment-environment gate, not a visual component.

## States

Not applicable — this is a deployment-environment gate, not a visual component.

## Accessibility

Not applicable — this is a deployment-environment gate, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| DE-001 | dev-deployment-envs-list | Read `DEV_DEPLOYMENT_ENVS` directly | Equals `['local', 'testing', 'staging']` — `deploymentEnv.test.ts`: "allowlists exactly local / testing / staging" |
| DE-002 | dev-env-membership-check | `isDevDeploymentEnv('local')`, `isDevDeploymentEnv('testing')`, `isDevDeploymentEnv('staging')` | All three return `true` — same test |
| DE-003 | dev-env-fail-closed | `isDevDeploymentEnv(x)` for `x` in `[null, undefined, '', 'prod', 'Production', 'preview', 'LOCAL']` | All return `false` — `deploymentEnv.test.ts`: "fails SAFE on anything unrecognised" |
| DE-004 | dev-env-fail-closed | `isDevDeploymentEnv('production')` | Returns `false` — `deploymentEnv.test.ts`: "rejects production" |
| DE-005 | dev-env-server-side-scope | Search `deployment-env.ts`'s source text for the substring `NEXT_PUBLIC_` | It appears only inside the `DEV_BUILD` declaration and its doc comment, never in `isDevDeploymentEnv`'s signature or body — confirms `isDevDeploymentEnv` reads only the non-prefixed, server-only variable |
| DE-006 | dev-build-literal-comparisons, dev-build-load-time-evaluation | Fresh-import the module with `NEXT_PUBLIC_DEPLOYMENT_ENV` stubbed to each of `'local'`, `'testing'`, `'staging'` | `DEV_BUILD === true` for all three — `deploymentEnv.test.ts`: "is on in the three dev envs" |
| DE-007 | dev-build-load-time-evaluation, dev-env-fail-closed | Fresh-import with `NEXT_PUBLIC_DEPLOYMENT_ENV` set to `'production'`, `'preview'`, unset, `''`, `'Local'`, or `'staging '` | `DEV_BUILD === false` for all six — `deploymentEnv.test.ts`: "is OFF in production, in an unknown env, and when unset" |
| DE-008 | dev-build-agrees-with-server-gate | For each of `['local', 'testing', 'staging', 'production', 'preview', 'prod', '']`, compare a fresh `DEV_BUILD` against `isDevDeploymentEnv` called with the same string | Equal on every value — `deploymentEnv.test.ts`: "agrees with isDevDeploymentEnv on every env either one accepts" |
| DE-009 | dev-build-literal-comparisons | Read `deployment-env.ts`'s source text and extract the `DEV_BUILD` initializer expression | Contains the literal text `process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === 'local'` (and the `'testing'`/`'staging'` equivalents), and does not match a pattern for `.includes`, `.some`, or `.indexOf` — `deploymentEnv.test.ts`: "stays written as constant-foldable literal comparisons" |
| DE-010 | dev-env-type-guard-narrowing | TypeScript-compile a callback that checks `if (isDevDeploymentEnv(x)) { const y: DevDeploymentEnv = x }` | Compiles with no type error — `x` narrows to `DevDeploymentEnv` inside the branch; not exercised by a dedicated runtime test in the given suite, traced directly to the `env is DevDeploymentEnv` return-type annotation |
| DE-011 | chunk-gate-inline-comparison-requirement, chunk-gate-subpath-specifier-requirement | `productionBundleGates.test.ts` statically inspects each of the four dev-only gate sites (the site-theme console, adh's theme taxonomy, the DB-theme applier, and the theme-preview carry helper) for a literal `NEXT_PUBLIC_DEPLOYMENT_ENV === '<env>'` comparison per entry in `DEV_DEPLOYMENT_ENVS`, a package-subpath specifier, a matching tsup entry plus `external` membership, and a package.json export | All four legs are present at every gate site — `@agentic-toolkit/adh`'s `productionBundleGates.test.ts` |
| DE-012 | dev-build-safe-for-non-chunk-gating-uses | `seo/metadata.ts`'s `const NOINDEX_BUILD = DEV_BUILD` (a direct alias, not an `import()` gate), evaluated with `NEXT_PUBLIC_DEPLOYMENT_ENV` set to each of the three dev envs and to `'production'` | `NOINDEX_BUILD` matches `DEV_BUILD` exactly (true in the three dev envs, false in production) — traced to `seo/metadata.ts`'s `NOINDEX_BUILD` declaration and its doc comment; no dedicated test in the given suite for this specific alias, inferred from `DEV_BUILD`'s own coverage since the alias performs no transformation |
| DE-013 | cross-repo-allowlist-parity | `adhbackend`'s `themeSurfaceEnv.test.ts` regex-extracts `DEV_DEPLOYMENT_ENVS`'s literal array text from this file's source and calls `isThemeSurfaceEnv()` for every extracted value plus `'production'`, `'preview'`, `'demo'`, `'prod'`, `''` | Each value's `isThemeSurfaceEnv()` result equals whether that value was in the extracted list — `adhbackend/src/adh/test/themeSurfaceEnv.test.ts`: "agrees with the frontend allowlist it is a copy of" |
| DE-014 | module-load-is-total | Import the module with `NEXT_PUBLIC_DEPLOYMENT_ENV` unset, in a sandbox with no filesystem or network access | Import completes synchronously; `DEV_BUILD === false`; no exception is thrown — traced to the module's full source containing no I/O call of any kind |

## Edge Cases

- **Null or undefined `env`.** `isDevDeploymentEnv(null)` and
  `isDevDeploymentEnv(undefined)` MUST return `false` — the function's
  signature accepts both explicitly and its `env != null` guard rejects
  each before the allowlist check runs.
- **Empty string `env`.** `isDevDeploymentEnv('')` MUST return `false` — the
  empty string is not one of the three allowlisted spellings.
- **Case-mismatched `env`.** `isDevDeploymentEnv('LOCAL')`,
  `isDevDeploymentEnv('Production')`, `isDevDeploymentEnv('PRODUCTION')` MUST
  return `false` — the comparison is case-sensitive and the source performs
  no normalization step.
- **Whitespace-padded `NEXT_PUBLIC_DEPLOYMENT_ENV`.** A value of
  `'staging '` (trailing space, the shape of a real `.env` typo) MUST leave
  `DEV_BUILD` at `false` — `===` performs no trimming.
- **`NEXT_PUBLIC_DEPLOYMENT_ENV` unset at module load.** `DEV_BUILD` MUST be
  `false` — all three comparisons fail against `undefined`.
- **Environment value changes after module load.** `DEV_BUILD` MUST NOT
  reflect a later change to `NEXT_PUBLIC_DEPLOYMENT_ENV` in the same running
  process — it was computed once at first module evaluation; observing a new
  value requires a fresh module evaluation (a process restart or, in tests,
  `vi.resetModules()` plus a re-import).
- **Non-string runtime value reaching `isDevDeploymentEnv`.** If a value
  that is not a string (e.g. a number) crosses from untyped JavaScript
  despite the TypeScript signature, `Array.prototype.includes` uses strict
  equality, so the value simply fails to match any of the three strings and
  the function MUST return `false` without throwing.
- **Malformed or invalid input needing sanitization.** Not applicable beyond
  the fail-closed cases above — the function's entire purpose IS the
  validation (a strict allowlist membership test); there is no separate
  class of "malformed but not-yet-rejected" input.
- **Concurrent access.** Not applicable in the usual sense — `DEV_DEPLOYMENT_ENVS`
  and `DEV_BUILD` are immutable values computed once at module load in
  JavaScript's single-threaded execution model, and `isDevDeploymentEnv` is a
  pure function with no shared mutable state, so no two calls can interleave
  to produce an inconsistent result; this is a fact of the execution model,
  not an untested assumption.
- **Error / dependency-unavailable states.** Not applicable — the module
  performs no file, network, or database I/O, so there is no dependency that
  can be "unavailable."
- **Offline or disconnected state.** Not applicable — the module makes no
  network call of any kind.
- **Cancellation and timeouts.** Not applicable — every operation is a
  synchronous, in-memory comparison; there is no asynchronous or long-running
  work to cancel or time out.
- **Missing file or unreachable server.** Not applicable to this module at
  runtime — it reads only `process.env`. (The cross-repo drift check that
  reads this file's *source text* runs inside `adhbackend`'s own test suite,
  not inside this module.)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DEPLOYMENT_ENV` (server-only process env) | `string \| undefined` | none — MUST be set by the deploy pipeline | Read by callers of `isDevDeploymentEnv`; carries no `NEXT_PUBLIC_` prefix, so it never reaches the browser. |
| `NEXT_PUBLIC_DEPLOYMENT_ENV` (build-time-inlined process env) | `string \| undefined` | `undefined`, which folds `DEV_BUILD` to `false` | Read once at module load to compute `DEV_BUILD`; per the source's doc comment, promoted from the server-side `DEPLOYMENT_ENV` by `adhNextConfig()` (`@agentic-toolkit/adh-next-config`) so one deploy-time value produces both reads. |
| `env` parameter of `isDevDeploymentEnv(env)` | `string \| null \| undefined` | caller-supplied, no default | The value tested against `DEV_DEPLOYMENT_ENVS`; production callers pass `process.env.DEPLOYMENT_ENV`. |

## Deep Linking

Not applicable: `deployment-env.ts` defines no routes, URLs, or navigable
destinations — it exports only an allowlist constant, a type guard, and a
boolean.

## Localization

Not applicable: the module contains no user-facing string literal — its
three string literals (`'local'`, `'testing'`, `'staging'`) are internal
deployment-environment identifiers compared against process-env values, and
are never rendered to a user.

## Accessibility Options

Not applicable: the module renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color).

## Feature Flags

Not applicable: the module implements no feature-flag or remote-config
lookup of its own — `DEV_DEPLOYMENT_ENVS`, `isDevDeploymentEnv`, and
`DEV_BUILD` are themselves the primitive that other modules' feature gates
(e.g. `devToolsEntries.ts`'s dev-tools-build flag) are built from, not a
consumer of one.

## Analytics

Not applicable: the module makes no analytics or telemetry call — it exports
pure constants and a pure function with no event emission.

## Privacy

Not applicable: `deployment-env.ts` carries no user data, credential, or
token — its inputs, `DEPLOYMENT_ENV` and `NEXT_PUBLIC_DEPLOYMENT_ENV`, are
deployment-tier configuration strings that identify which environment a
build runs in, not any person or secret.

## Logging

Not applicable: the module contains no logger, `console`, or `print` call of
any kind — every path returns a plain boolean or array with no diagnostic
emitted on any input, including the fail-closed paths.

## Platform Notes

- **SwiftUI**: There is no bundler-level, text-substitution build step in a
  compiled Swift app, so the `DEV_BUILD`-vs.-`isDevDeploymentEnv` split has
  no direct motivation. Model `DevDeploymentEnv` as a
  `CaseIterable enum: String { case local, testing, staging }` and replace
  both exports with one function, `isDevDeploymentEnv(_ env: String?) ->
  Bool { env.flatMap(DevDeploymentEnv.init(rawValue:)) != nil }`, read from
  `ProcessInfo.processInfo.environment["DEPLOYMENT_ENV"]`. Keep the fail-closed
  contract (an unrecognized or missing value returns `false`) rather than
  inverting to `!= "production"`.
- **Compose**: `enum class DevDeploymentEnv { LOCAL, TESTING, STAGING }` with
  a `companion object` `fromEnv(env: String?): DevDeploymentEnv?` doing an
  exact, case-sensitive lookup against the enum's declared names (not a
  case-insensitive `equalsIgnoreCase`, to preserve the source's case-sensitive
  fail-closed behavior). Gradle build variants (`buildConfigField`) are the
  build-time-inlined analog of `NEXT_PUBLIC_*`, resolved per build
  type/flavor at compile time rather than per module-load; there is no
  Kotlin/Gradle equivalent of the chunk-gate contract's dynamic-`import()`
  concern, since Gradle's dead-code elimination (R8/ProGuard) works on
  compiled bytecode, not on textual environment-variable substitution.
- **React/Web**: (source) `packages/web/packages/adh-registry/src/deployment-env.ts`,
  with its own tests in `src/__tests__/deploymentEnv.test.ts`; exposed
  outside the package through the `./deployment-env` subpath declared in
  `package.json`'s `exports`, and re-verified from outside the package by
  `@agentic-toolkit/adh`'s `productionBundleGates.test.ts` and, across a repo
  boundary, by `adhbackend`'s `src/adh/test/themeSurfaceEnv.test.ts`. What is
  specific to this platform: the entire `DEV_BUILD`-vs.-`isDevDeploymentEnv`
  split, and the whole chunk-gate contract, exist only because Next.js/webpack
  inlines `process.env.NEXT_PUBLIC_*` as text before bundling and then
  performs dead-code elimination purely on syntactic literal comparisons — a
  constraint with no equivalent on a platform without build-time text
  substitution.
- **AppKit / UIKit**: Same approach as SwiftUI — a `CaseIterable` enum (or a
  small `Set<String>` allowlist) behind one pure function; AppKit/UIKit code
  would call it identically to SwiftUI code, since this is UI-framework-agnostic
  logic with no view dependency. There is no chunk-gating concern the way
  there is in a Next.js bundle, because Xcode performs no build-time textual
  substitution of environment variables followed by dead-code elimination.
- **WinUI 3**: This is the platform this recipe exists to steer. Read the
  deployment tier from an environment variable at startup
  (`Environment.GetEnvironmentVariable("DEPLOYMENT_ENV")`, or an app-config
  setting for a packaged MSIX app), and expose the equivalent of
  `DEV_DEPLOYMENT_ENVS` as an `enum DevDeploymentEnv { Local, Testing, Staging }`
  with a static `IsDevDeploymentEnv(string? env)` method doing the same
  exact, case-sensitive, fail-closed membership test — never `!= "production"`.
  Because a WinUI 3/MSIX app has no bundler-level, build-time text
  substitution and dead-code-elimination step analogous to webpack's
  `NEXT_PUBLIC_*` fold, the `DEV_BUILD`-vs.-`isDevDeploymentEnv` duplication
  and the chunk-gate contract (inlined comparisons, package-subpath imports)
  have no direct equivalent; a WinUI 3 port needs only ONE gate, most
  naturally exposed as a `Lazy<bool>` (no `Task`/`async` needed — this is a
  synchronous environment read) evaluated once at app startup and passed down
  to whichever XAML `Page`/`Frame` decides whether to show dev-only UI (a
  settings toggle, a debug menu item), gated with an `x:Bind`/`Visibility`
  binding rather than a dynamic module load. If a future WinUI 3 build
  genuinely needs to keep an entire dev-only page or assembly out of the
  shipped MSIX package, that is a packaging/project-reference concern (a
  project reference included only for Debug/Staging build configurations via
  a conditional `<ItemGroup Condition="...">` in the `.csproj`), not a
  runtime import-site gate — WinUI 3 has no equivalent of a JavaScript
  dynamic `import()` chunk boundary.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-registry/src/deployment-env.ts` |

## Design Decisions

- **Decision**: Duplicate the "is this a dev env" fact as two separate
  declarations — `isDevDeploymentEnv` reading `DEPLOYMENT_ENV`, and
  `DEV_BUILD` reading `NEXT_PUBLIC_DEPLOYMENT_ENV` via three literal `===`
  comparisons — rather than deriving one from the other.
  **Rationale**: per the source's own comment, they answer different
  questions for different audiences (what a server RENDERS vs. what a dev
  BUILD DOES), and `DEV_BUILD` additionally has to stay in a form the
  bundler's constant folder can reduce to a literal, which
  `DEV_DEPLOYMENT_ENVS.includes(...)` would defeat; the duplication is
  therefore load-bearing, not an oversight, and it is pinned by
  `deploymentEnv.test.ts`'s "stays written as constant-foldable literal
  comparisons" test.
  **Approved**: pending
- **Decision**: Reserve `DEV_BUILD`/`isDevDeploymentEnv` for what gets
  rendered or what a dev build does, and require any consumer that gates a
  dynamic `import()` on the dev/production distinction to follow a separate
  four-leg chunk-gate contract (inline literal comparisons at the import
  site, a package-subpath specifier, a matching bundler entry plus
  `external`, and a package.json export) instead of importing `DEV_BUILD` at
  that site.
  **Rationale**: the source's own top-of-file comment states this is why an
  earlier `DEV_BUILD ? dynamic(() => import('./X'))` shipped the whole
  site-theme editor, Monaco included, into every production build of every
  site — a bundler's dead-code elimination for a dynamic import resolves
  only a literal comparison visible while parsing that exact call site, and
  does not follow an imported identifier back to its definition.
  **Approved**: pending
- **Decision**: Place this module in `@agentic-toolkit/adh-registry` rather
  than in `@agentic-toolkit/adh`, where most of its consumers live.
  **Rationale**: `adh` depends on `adh-registry`, so a home in `adh-registry`
  is readable from both sides of that dependency edge — including
  `adh-registry`'s own `seo/metadata.ts`, which needs the same fact — while a
  home inside `adh` could not be read from `seo/metadata.ts` without
  introducing a dependency cycle.
  **Approved**: pending
- **Decision**: Guard the cross-repo copy of this allowlist
  (`adhbackend`'s `isThemeSurfaceEnv`) by having
  `adhbackend/src/adh/test/themeSurfaceEnv.test.ts` regex-extract
  `DEV_DEPLOYMENT_ENVS`'s literal array text out of this file's source text,
  rather than importing the module.
  **Rationale**: `adhbackend` is a standalone pnpm package that must not take
  a build dependency on the frontend package this file lives in; reading the
  source text instead lets the two lists be checked for drift in both
  directions without creating that dependency, at the cost of coupling the
  check to this file staying at its current path and keeping the array
  written as a literal the regex can match — the test's own comment states
  it "fails loudly if that file moves."
  **Approved**: pending
- **Decision**: Allowlist the three dev environments explicitly
  (`=== 'local' || === 'testing' || === 'staging'`) rather than testing the
  inverse (`!== 'production'`), in both `isDevDeploymentEnv` and
  `DEV_BUILD`.
  **Rationale**: per the source comment, this makes an unset or misspelled
  environment fail SAFE (dev tooling hidden) instead of failing OPEN (dev
  tooling exposed to real visitors) — the asymmetry matters because a
  wrongly-"dev" gate does not crash and is not noticed by CI, it just ships
  extra code and behavior to production silently.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

Notes: separation-of-concerns passes because the module does exactly one
job — answering "is this a dev deployment?" — with no UI, no unrelated
business logic, and no infrastructure code; its two audiences (server render
vs. bundler fold) are kept as two clearly-named exports rather than one
overloaded function. unit-test-coverage passes because
`deploymentEnv.test.ts` exercises every exported member
(`DEV_DEPLOYMENT_ENVS`, `isDevDeploymentEnv`, `DEV_BUILD`), including the
fail-closed paths, and the contract is checked again from outside the
package by `productionBundleGates.test.ts` and, cross-repo, by
`adhbackend`'s `themeSurfaceEnv.test.ts`. good-test-properties passes because
the test suite isolates itself with `vi.stubEnv`/`vi.resetModules` inside
`afterEach`, asserts concrete boolean outcomes with no shared mutable
fixture, and needs no external service. fault-tolerance passes because
`isDevDeploymentEnv` and `DEV_BUILD` are total functions of their inputs —
every tested input, including `null`, `undefined`, mis-cased strings, and a
whitespace-padded string, returns a boolean with no throw.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
