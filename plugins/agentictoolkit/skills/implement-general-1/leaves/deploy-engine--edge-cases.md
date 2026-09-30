<!-- leaf: implement-general-1/deploy-engine--edge-cases · source: deploy-engine.md -->

# Deploy Engine

## Edge Cases

- **Empty/null input**: `platformCanon(null)`/`platformCanon(undefined)`
  return `""`, not a thrown error; `domainFamily("")` and
  `domainFamily("localhost")` (no dot) return `null`; `uniqueSiteIdentity`
  with an empty base slug and no host to fall back on returns the base
  unchanged rather than numbering a nonsense identity like `" (2)"`.
- **Boundary values**: `siteApex` never reduces a host below two
  dot-separated labels (`"staging.io"` stays `"staging.io"`); `mapLimit`'s
  worker count is `Math.min(limit, items.length)`, so a `limit` larger than
  `items.length` degrades to one worker per item, not an over-allocation;
  `noteRateLimited`'s cooldown length is clamped to `MAX_COOLDOWN_MS`
  regardless of how large a Retry-After header demands; `uniqueSiteIdentity`
  tries at most 98 numbered variants (`-2` through `-99`) before giving up
  and returning the unmodified base for the caller's create call to reject.
- **Concurrent access**: The cooldown registry's `SharedArrayBuffer` is read
  and written from two different threads (the worker-thread monitor cycle
  and the API-thread enumeration) using `Atomics.load`/`Atomics.store`
  exclusively — no other access pattern is used anywhere in the module.
  `cachedSingleFlight` funnels every concurrent miss into one in-flight
  `build()` promise. `applySequentially` and `mapLimit` both bound
  concurrency deliberately: the former to exactly 1 (sequencing correctness,
  since later applies read earlier applies' in-memory state), the latter to
  a caller-supplied `limit`.
- **Error states**: A rejected `applyOne` inside `applySequentially` is
  caught and recorded in `skipped`, never fatal to the run. A rejected
  `createEndpoint` after a successful `createSite` triggers a best-effort
  `deleteSite` rollback and always rethrows the original error. Every
  provider adapter (`listWorkerScripts`, `listWorkerCustomDomains`,
  `listRailwayProjects`, `listRailwayProjectDomains`,
  `fetchProjectDomainList`) returns a typed failure/fallback value rather
  than letting a network or parse error propagate to its caller.
- **Offline/unreachable server**: `withTimeout` bounds an outbound call with
  an `AbortController`-driven `AbortSignal`; Cloudflare's account-resolution
  helpers each apply an independent 6-second window per network step so one
  slow call cannot consume a downstream call's budget; Vercel's domain fetch
  applies its own 5-second `AbortSignal.timeout`. A 429 response from any of
  the three providers is recorded via the shared cooldown registry so a
  polling caller backs off rather than immediately re-hitting an already
  rate-limited provider.
- **Vercel domain cache scope**: `domainListCache` in `providers/vercel.ts`
  is keyed only by `projectName`, not by `(teamId, projectName)`, so two
  Vercel teams sharing a project name, or one account switching `teamId` for
  the same project, read and overwrite each other's cached domain list for
  up to the one-hour TTL.
- **map-limit-non-positive-limit**: NEEDS REVIEW: Not implemented in source. `mapLimit` sizes its worker pool as `Math.min(limit, items.length)` with no check that `limit >= 1`; a `limit <= 0` yields zero workers, so every result stays `undefined` with no item processed and no error, and `map-limit.test.ts` has no case for it — whether a non-positive `limit` should throw, clamp to 1, or stay the caller's responsibility is undecided.
