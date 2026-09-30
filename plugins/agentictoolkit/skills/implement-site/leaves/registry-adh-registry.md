<!-- leaf: implement-site/registry-adh-registry · source: site-registry-adh-registry.md -->

**Rules** (cite as `implement-site/registry-adh-registry#<slug>`):

- `dev-deployment-envs-list` MUST
- `dev-env-membership-check` MUST
- `dev-env-fail-closed` MUST
- `dev-env-server-side-scope` MUST
- `dev-build-literal-comparisons` MUST
- `dev-build-load-time-evaluation` MUST
- `dev-build-agrees-with-server-gate` MUST
- `dev-env-type-guard-narrowing` MUST
- `chunk-gate-inline-comparison-requirement` MUST
- `chunk-gate-subpath-specifier-requirement` MUST
- `dev-build-safe-for-non-chunk-gating-uses` MUST
- `cross-repo-allowlist-parity` MUST
- `module-load-is-total` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DEPLOYMENT_ENV` (server-only process env) | `string \| undefined` | none — MUST be set by the deploy pipeline | Read by callers of `isDevDeploymentEnv`; carries no `NEXT_PUBLIC_` prefix, so it never reaches the browser. |
| `NEXT_PUBLIC_DEPLOYMENT_ENV` (build-time-inlined process env) | `string \| undefined` | `undefined`, which folds `DEV_BUILD` to `false` | Read once at module load to compute `DEV_BUILD`; per the source's doc comment, promoted from the server-side `DEPLOYMENT_ENV` by `adhNextConfig()` (`@agentic-toolkit/adh-next-config`) so one deploy-time value produces both reads. |
| `env` parameter of `isDevDeploymentEnv(env)` | `string \| null \| undefined` | caller-supplied, no default | The value tested against `DEV_DEPLOYMENT_ENVS`; production callers pass `process.env.DEPLOYMENT_ENV`. |

