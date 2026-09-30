<!-- leaf: implement-status-server-monitor-fetch/vercel-projects--part-2 · source: status-server-monitor-fetch-vercel-projects.md -->

# Status Server Monitor Fetch Vercel Projects — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-fetch/vercel-projects--part-2#<slug>`):

- `deploy-rows-require-real-target` MUST
- `deploy-rows-newest-plus-conclusive` MUST
- `row-id-prefix` MUST
- `row-platform-literal` MUST
- `row-created-at-validated` MUST
- `row-commit-fields-mapped` MUST
- `row-url-scheme-prefixed` MUST
- `row-phases-delegated` MUST
- `row-environment-and-provider-id` MUST
- `blind-project-detection` MUST
- `blind-project-backfill-bounded` MUST
- `blind-project-backfill-query` MUST
- `blind-project-backfill-best-effort` MUST
- `blind-project-backfill-logged` MUST
- `blind-project-backfill-appends` MUST
- `slug-resolved-last` MUST
- `slug-memoized-hourly` MUST
- `slug-direct-then-list-fallback` MUST
- `slug-minimum-call-window` MUST
- `slug-failure-keeps-last-known` MUST
- `slug-reset-seam` MUST
- `stale-definition` MUST
- `serving-deploy-reconstruction` MUST
- `errored-and-behind-different-anchors` MUST
- `preview-deploys-excluded` MUST
- `no-conclusive-deploy-not-stale` MUST
- `zero-created-at-treated-as-unknown` MUST
- `detail-text-composition` MUST
- `now-captured-once` MUST

### Deploy Row Derivation

- **deploy-rows-require-real-target**: `latestDeploysOf` MUST consider only entries of a project's `latestDeployments` array that carry a non-empty `id`, a defined `readyState`, a non-null `target`, and a non-null `createdAt` (`real = latestDeployments.filter(...)`); per the source's own comment, an absent `readyState` "would map to 'building' and manufacture a phantom stuck-build for a healthy project," so such an entry MUST be excluded rather than defaulted.
- **deploy-rows-newest-plus-conclusive**: `latestDeploysOf` MUST return the mapped row for the newest qualifying deployment by `createdAt`, and MUST additionally return the mapped row for the newest CONCLUSIVE qualifying deployment (readyState neither `"CANCELED"` nor `"DELETED"`, per `isConclusive`) only when its `id` differs from the newest deployment's `id`; when the project has no qualifying deployment at all, it MUST return `[]`.
- **row-id-prefix**: Each mapped `ProviderDeploy.id` MUST be the literal string `` vc_ `` concatenated with the Vercel deployment's `id` field.
- **row-platform-literal**: Each mapped row's `platform` field MUST be the literal string `"vercel"`.
- **row-created-at-validated**: Each mapped row's `createdAt` field MUST be the result of `toValidDate(d.createdAt)` (`./provider-deploy`, external); when that call returns `null`, `fetchVercelProductionStates` MUST log `` Vercel project <projectName> deploy <id> has unparseable createdAt <JSON-stringified value> — skipping `` via `console.error` and MUST exclude that one deployment from the returned rows, without dropping any other deployment from the same or any other project.
- **row-commit-fields-mapped**: Each mapped row's `commitHash` field MUST be `shortSha(d.meta?.githubCommitSha)` (`./format`, external); `commitMessage` MUST be `commitFullMessage(d.meta?.githubCommitMessage)`; `branch` MUST be `d.meta?.githubCommitRef ?? null`; `commitRepo` MUST be `` `${d.meta.githubCommitOrg}/${d.meta.githubCommitRepo}` `` when both are present, or `null` otherwise.
- **row-url-scheme-prefixed**: Each mapped row's `url` field MUST be `` `https://${d.url}` `` when `d.url` is set, or `null` otherwise.
- **row-phases-delegated**: Each mapped row's `buildPhase` and `deployPhase` fields MUST be the result of spreading `vercelPhases(d.readyState ?? "", d.readySubstate ?? null, d.target ?? null)` (`./deploy-status`, external, documented in the Status Server Monitor Deploy Status recipe) unchanged; this file performs no phase derivation of its own.
- **row-environment-and-provider-id**: Each mapped row's `environment` field MUST be `d.target ?? null`, and its `providerProjectId` field MUST be the `providerProjectId` parameter passed into `toProviderDeploy` by the caller (`p.id ?? null` from `fetchVercelProductionStates`, or `null` from the conclusive-deploy backfill, which omits the parameter).

### Blind-Project Backfill

- **blind-project-detection**: After deriving `deploys` for every project, and only when `deploys.length > 0` and `Date.now() < deadline`, `fetchVercelProductionStates` MUST compute the set of distinct project names that have at least one row in `deploys` with `buildPhase === "canceled"` and NO row with any other `buildPhase`; a project with zero rows in `deploys` at all (it has never deployed to an env target) MUST NOT be included.
- **blind-project-backfill-bounded**: For every project name in that set, `fetchVercelProductionStates` MUST call `fetchNewestConclusiveDeploy` through a bounded concurrency of 8 concurrent calls (`mapLimit(blind, 8, ...)`).
- **blind-project-backfill-query**: `fetchNewestConclusiveDeploy` MUST request `https://api.vercel.com/v6/deployments` with `app=<projectName>`, `state=READY,ERROR`, `limit=5`, and `teamId=<teamId>` when set, aborted after 5,000ms (`CONCLUSIVE_CALL_TIMEOUT_MS`), and MUST return the mapped row for the newest entry (by `createdAt`) among those with a non-empty `id`, a defined `readyState`, a non-null `target`, and a non-null `createdAt`, or `null` when none qualify.
- **blind-project-backfill-best-effort**: When the `/v6/deployments` request returns a non-ok response or throws, `fetchNewestConclusiveDeploy` MUST return `null` without logging and MUST NOT cause `fetchVercelProductionStates` to fail or return a partial result on that account, per the source's own comment, "a blind spot stays a blind spot, it never fails the poll."
- **blind-project-backfill-logged**: When one or more blind projects are found, `fetchVercelProductionStates` MUST log `` [vercel-projects] <N> project(s) have no verdict in the poll window — reading it directly `` via `console.log` before issuing the backfill calls.
- **blind-project-backfill-appends**: Every non-null row returned by the backfill MUST be appended to `deploys` (not used to replace the existing skip row), so both the project's newest deploy and its recovered verdict are present in the final result.

### Team Slug Resolution

- **slug-resolved-last**: `fetchVercelProductionStates` MUST resolve the team dashboard slug via `fetchTeamSlug` only AFTER the project-enumeration loop, domain resolution, `deploys` derivation, and the blind-project backfill have all completed, so that slug resolution spends only whatever budget those phases did not need.
- **slug-memoized-hourly**: `fetchTeamSlug` MUST cache a resolved non-null slug for 3,600,000ms (`TEAM_SLUG_CACHE_TTL_MS`, 1 hour), keyed by the team id (or the empty string when unset), and MUST return the cached slug without issuing any request when a fresh-enough entry for that key exists.
- **slug-direct-then-list-fallback**: When `teamId` is set, `fetchTeamSlug` MUST first request `/v2/teams/<teamId>` and return its `slug` field when present as a string; otherwise (or when `teamId` is unset), it MUST request `/v2/teams` and return the slug of the entry whose `id` matches `teamId`, or, when no `teamId` was given or no entry matches, the FIRST entry in the list.
- **slug-minimum-call-window**: `fetchTeamSlug`'s internal `get` helper MUST NOT issue a request when the time remaining before `deadlineMs` is less than 500ms (`MIN_SLUG_CALL_MS`), returning `null` for that call instead, per the source's own comment: issuing a request certain to be aborted "only burns a connection and logs a self-inflicted 'aborted due to timeout' that reads like a Vercel outage."
- **slug-failure-keeps-last-known**: When a slug lookup for a given cache key fails to produce a string slug (both the direct lookup and the list fallback return nothing usable), `fetchTeamSlug` MUST return the previously cached slug for that same key if one exists, or `null` if none exists, and MUST NOT overwrite a previously cached slug with `null`.
- **slug-reset-seam**: `__resetTeamSlugCache` MUST clear the module-scope `teamSlugCache` to `null`, exposed solely so a test can force the next call onto the cold-lookup path.

### Production Staleness Evaluation

- **stale-definition**: `evaluateProdStaleness(live, latestDeployments)` MUST return `stale: true` when the reconstructed `errored` is `true` or the reconstructed `behind` is `true`, and `stale: false` otherwise.
- **serving-deploy-reconstruction**: When `live.readyState` is not `"CANCELED"` and not `"DELETED"` (`isConclusive(live)`), `evaluateProdStaleness` MUST treat `live` itself as both the deployment judged for `errored` and the deployment judged for `behind`. When `live` IS a `"CANCELED"`/`"DELETED"` skip, `evaluateProdStaleness` MUST reconstruct two DIFFERENT anchor deployments from `latestDeployments` filtered to `target === "production"`: `errored` MUST be judged against the newest deployment among those that is itself conclusive, while the `liveCreated` returned (and therefore `behind`) MUST be judged against the newest deployment among those whose `readySubstate === "PROMOTED"`, falling back to the conclusive one, falling back to `live`, when no promoted deployment exists.
- **errored-and-behind-different-anchors**: `errored` MUST be `true` only when the conclusive anchor's `readyState === "ERROR"`; `behind` MUST be `true` only when some production deployment's `readyState === "READY"` has a `createdAt` strictly greater than the serving deployment's `createdAt` (`liveCreated`).
- **preview-deploys-excluded**: `evaluateProdStaleness` MUST exclude every entry of `latestDeployments` whose `target !== "production"` from both the `errored` and `behind` reconstructions, so a preview deployment can never mask or manufacture a production staleness signal.
- **no-conclusive-deploy-not-stale**: When `latestDeployments` contains no conclusive production deployment at all (every entry is a skip), `evaluateProdStaleness` MUST return `stale: false`, `errored: false`, and `behind: false` — there is no evidence of a broken or superseded production build to report.
- **zero-created-at-treated-as-unknown**: `staleDetail(errored, behind, liveCreated, nowMs)` MUST treat a `liveCreated` of exactly `0` as "unknown" (passing `null`, not `0`, into `toValidDate`), per the source's own comment "0 = 'unknown', not epoch," so the returned detail line never claims a live build is decades old.
- **detail-text-composition**: `staleDetail` MUST return exactly one of four base reason strings — `"live production build errored; newer build not promoted"` (errored and behind both true), `"live production build errored"` (errored true, behind false), or `"production not updated to the latest build"` (errored false) — and, only when `liveCreated` yields a valid date, MUST append `` · live build <age> old `` where `<age>` is `timeAgo(liveDate.toISOString(), nowMs)` (`./time-ago`, external).
- **now-captured-once**: `fetchVercelProductionStates` MUST capture `now = Date.now()` exactly once, immediately after the project-enumeration loop completes, and MUST reuse that same value as `nowMs` for every `staleDetail` call in the later per-project loop — even though domain resolution, `deploys` derivation, the blind-project backfill, and team-slug resolution all run, and can each consume real wall-clock time, between that capture and its use.

