<!-- leaf: implement-site/registry-adh-registry--edge-cases · source: site-registry-adh-registry.md -->

# DeploymentEnv

**Rules** (cite as `implement-site/registry-adh-registry--edge-cases#<slug>`):

- `null-or-undefined-env` MUST — isDevDeploymentEnv(null) and isDevDeploymentEnv(undefined) MUST return false — the function's signature accepts both …
- `empty-string-env` MUST — isDevDeploymentEnv('') MUST return false — the empty string is not one of the three allowlisted spellings.
- `case-mismatched-env` MUST — isDevDeploymentEnv('LOCAL'), isDevDeploymentEnv('Production'), isDevDeploymentEnv('PRODUCTION') MUST return false — the …
- `whitespace-padded-next-public-deployment-env` MUST — A value of 'staging ' (trailing space, the shape of a real .env typo) MUST leave DEV_BUILD at false — === performs no …
- `next-public-deployment-env-unset-at-module-load` MUST — DEV_BUILD MUST be false — all three comparisons fail against undefined.
- `environment-value-changes-after-module-load` MUST — DEV_BUILD MUST NOT reflect a later change to NEXT_PUBLIC_DEPLOYMENT_ENV in the same running process — it was computed …
- `non-string-runtime-value-reaching-isdevdeploymentenv` MUST — If a value that is not a string (e.g. a number) crosses from untyped JavaScript despite the TypeScript signature, …

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
