---
id: 7984f592-a12d-49da-806c-ff39d9557998
title: Status Server Board
domain: agentictoolkit://cookbook/status-server/board
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Status backend''s board fold: the pure functions under `src/board/`
  that reduce deploy, HTTP/DNS, platform-health, GlitchTip-error, and roster
  facts into one `Board` (a Problems list, an Activity feed, an overall
  indicator, and the set of currently monitored targets), plus the target-key
  minting, ownership resolution, and ledger-reconciliation entrypoint that
  keep every board sub-system agreeing on one spelling of "which target".'
platforms:
- typescript
- web
tags:
- monitoring
- status
- deploy
- activity-feed
- pure-function
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/pagination
- agenticdevelopercookbook://guidelines/implementing/networking/idempotency-keys
- agenticdevelopercookbook://guidelines/implementing/testing/testing
related:
- agentictoolkit://cookbook/status-server/auth
references:
- packages/web/packages/status-server/src/board/target-key.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/ownership.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive-problems.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive-activity.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/facts.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/reconcile.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/types.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-target-key.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-ownership.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-deploy.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-endpoint.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-errors.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-monitoring.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-regressions.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-activity.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-activity-page.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-facts.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Board

## Overview

This is the status backend's board fold: eight files under `src/board/`
that reduce every monitoring fact the status site has — provider deploy
polls and webhooks, HTTP/DNS probes, provider platform-health samples,
GlitchTip error groups, the operator's roster configuration, and the
ledger's open-row onsets — into one `Board` value. `types.ts` defines the
fact and output shapes (`BoardFacts`, `Problem`, `ActivityRow`, `Board`) and
the module's constants. `target-key.ts` mints and parses the one canonical
spelling of a deploy target (`boardTargetKey`/`parseBoardTarget`), with
percent-escaping so the mint-parse round trip is total. `ownership.ts`
resolves which roster entry, if any, owns a deploy row or project
(`matchRosterEntry`, `ownedDeployTarget`, `rosterDeployProjects`), matching
by provider id first and project name second. `derive-problems.ts` judges
the five Problem families (deploy, endpoint, platform, stale-prod, error)
and computes `monitoredTargets`, the authoritative "currently watched" set.
`derive-activity.ts` derives the Activity feed as the union of deploy and
issue events (`deriveActivity`), the overall `indicatorFor`, and the
cursor-paginated `pageActivity`. `derive.ts` is the top-level fold,
`deriveBoard`, that combines all of the above into one `Board`.
`facts.ts` is the fold's read-side orchestration (`readBoardFacts`,
`readActivityPage`, `createActivityPageReader`) — the only file in
`src/board/` that touches `Storage`. `reconcile.ts` is the single
reconciliation entrypoint, `reconcileBoardLedger`, that reads facts, folds
them, writes the ledger diff, and flushes alerts, safe to call repeatedly
and from multiple callers. Every derivation function is pure: `nowMs` is a
parameter, there is no IO, and calling one twice with the same facts gives
a deep-equal result — the property the regression suite in
`test/board-regressions.test.ts` pins directly.

## Behavioral Requirements

### Target Keys (target-key.ts)

- **segment-escaping**: `escapeSegment` MUST replace every `%` with `%25`
  before replacing every `|` with `%7C` — escaping the escape character
  first is what keeps the mapping injective.
- **segment-unescaping**: `unescapeSegment` MUST invert `escapeSegment` in
  one left-to-right regex pass (matching `%25` or `%7C` and substituting
  `%` or `|` respectively), never as two sequential global replaces, so
  unescaping `%7C` cannot re-create a literal `%25` that then gets
  misread as a separator.
- **board-target-minting**: `boardTargetKey(platform, id, environment)`
  MUST return `null` when `platformCanon(platform)` is falsy or `id` is
  falsy, and otherwise MUST return `${canonicalPlatform}|${escapeSegment(id)}|${escapeSegment(env)}`
  — always exactly three pipe-separated segments.
- **railway-environment-segment**: `boardTargetKey` MUST populate the
  environment segment, lowercased, only when the canonical platform is
  `"railway"`; for every other platform the segment MUST be the empty
  string, so one non-Railway project collapses to one target regardless
  of environment.
- **board-target-parsing**: `parseBoardTarget` MUST return `null` unless
  the input splits on `|` into exactly three parts with a non-empty
  platform and a non-empty id, and otherwise MUST return
  `{ platform, id: unescapeSegment(id), environment: unescapeSegment(environment ?? "") }`.

### Ownership (ownership.ts)

- **deploy-identity**: `entryIdentity` MUST return the roster entry's
  `providerProjectId` when present, else its `projectName`.
- **deploy-ownership-gate**: a roster entry MUST own a deploy target or
  deploy project (via `rosterTargets`, `rosterDeployProjects`,
  `ownedDeployTarget`) only while it is `isActive`, has `monitorDeploys`
  on, and does not have `ignoreProjectWarning` set.
- **roster-target-indexing**: `rosterTargets` MUST index every
  deploy-owning roster entry twice — under `boardTargetKey` keyed by its
  provider id (when it has one) and under `boardTargetKey` keyed by its
  project name — so a Railway entry's index keys stay environment-scoped
  exactly as the target keys themselves are.
- **vanished-vercel-narrowing**: `rosterTargets` MUST compute
  `vanishedVercel` from `dropVanishedVercelProjects` applied to
  `rosterDeployProjects`' Vercel/Railway/Cloudflare name sets against the
  live Vercel project mirror, and MUST narrow nothing (return an empty
  `vanishedVercel`) when that mirror is empty or would vanish every owned
  Vercel project at once.
- **roster-entry-matching**: `matchRosterEntry` MUST try a provider-id
  match first and a project-name match second, and MUST reject (return
  `null` rather than the name match) when both the deploy row and the
  matched-by-name entry carry a `providerProjectId` and the two disagree.
- **owned-deploy-target-gate**: `ownedDeployTarget` MUST return `null` for
  a row that is not a real-environment deploy row (per
  `isRealEnvDeployRow`), for a Vercel row whose project name is in
  `vanishedVercel`, or for a row no roster entry owns and whose platform
  does not canonicalize to `"crunchy"`.
- **owned-deploy-environment**: `ownedDeployTarget` MUST derive its
  returned `env` by calling `deployEnv(d.platform, d.projectName,
  d.environment, d.branch)` on every row it accepts, never by caching a
  tier per target — the same project's older and newer rows MAY legitimately
  carry different tiers when its production branch was repointed.
- **crunchy-always-visible**: a deploy row whose platform canonicalizes to
  `"crunchy"` MUST be ownable (target minted from the row's own platform
  and project name) even when no roster entry claims it.
- **roster-deploy-projects-grain**: `rosterDeployProjects` MUST record
  both the provider-id and project-name spellings of every deploy-owning
  entry, bucketed by canonical platform and environment-free.
- **owns-deploy-project**: `ownsDeployProject` MUST return `true`
  unconditionally for a Crunchy row, and otherwise MUST return `true` only
  when the row's provider id or project name appears in the matching
  canonical-platform bucket `rosterDeployProjects` produced.

### Problem Derivation (derive-problems.ts)

- **platform-health-target-spelling**: `platformHealthTarget(source)` MUST
  mint `"platform-health|<source>"` (exactly two segments, no trailing
  pipe, never through `boardTargetKey`), and `parsePlatformHealthTarget`
  MUST return the source unvalidated against `IssueSource` when the
  target carries that prefix, else `null`.
- **deploy-verdict-collapse**: `collapseByTarget` MUST reduce multiple
  `DeployFact`s that resolve to one board target to a single row via
  `supersedes`, whose tie-break order is: greater `createdAtMs` wins;
  on a tie, the row carrying a `providerProjectId` wins; on a further
  tie, the greater `projectName` wins; on a final tie, the greater
  `environment` wins.
- **deploy-problem-judging**: `deployProblems` MUST judge a target
  `stuck` only from an in-flight row that is newer than (or the only row
  for) the target's standing concluded verdict and whose `combinedStatus`
  is `building` for at least `STUCK_DEPLOY_MS`; otherwise it MUST judge
  the target `failed` only when the standing concluded verdict's
  `combinedStatus` is bad (per `deployIsBad`); a target with neither MUST
  produce no Problem.
- **deploy-problem-fields**: a `deployProblems` row MUST set `source` to
  the judged row's raw (uncanonicalized) `platform`, `environment` to the
  logical tier `ownedDeployTarget` derived (never the row's raw
  `environment`), `detail` to the first line of the commit message when
  failed or to `"stuck ${status} · ${ageMinutes}m"` when stuck, and
  `branch`/`errorText` from the judged row (the wedged row when stuck, the
  failed row when failed).
- **endpoint-problem-debounce**: `endpointProblems`, via `probeConfirmed`,
  MUST treat a `"down"` endpoint as an immediate Problem and a
  `"degraded"` endpoint as a Problem only once
  `nowMs - badSinceMs >= DEGRADED_CONFIRM_MS`.
- **endpoint-problem-gate**: `endpointProblems` MUST judge only endpoints
  whose roster entry is `isActive` and has `monitorHttp` on; it MUST key
  the Problem's `target` on the endpoint's bare `endpointId`.
- **endpoint-problem-fields**: an endpoint Problem MUST set `severity` to
  `"critical"` when down and `"minor"` when degraded, `source` to `"dns"`
  when `dnsOk` is false and `"http"` otherwise, and MUST leave `branch`
  and `errorText` `null`.
- **platform-problem-debounce**: `platformProblems` MUST judge only a
  platform fact whose `configured` is true, whose `ok` is false, and whose
  `streak` is at least `PLATFORM_UNREACHABLE_POLLS`; a platform that is
  not configured, that is `ok`, or that is below the streak threshold MUST
  produce no Problem.
- **platform-problem-severity**: a platform Problem MUST always carry
  `severity: "minor"`, regardless of provider.
- **stale-prod-problem-suppression**: `staleProdProblems` MUST skip
  (produce no row for) a target already present in its `suppress` set
  argument, and it MUST NOT be passed the error-target suppress set by
  `deriveBoard` (error targets cannot collide with deploy targets).
- **stale-prod-vanish-narrowing**: `staleProdProblems` MUST skip a
  `StaleProdFact` whose `projectName` is in `vanishedVercel`, and MUST
  produce no row for a project no roster entry owns.
- **stale-prod-environment-and-severity**: `staleProdProblems` MUST derive
  `environment` via `deployEnv("vercel", projectName, environment, branch)`
  using the project's *configured* production branch (not any one
  deployment's branch), MUST set `severity` to `"major"` only when that
  derived environment is `"production"` (else `"minor"`), and for a
  non-production tier MUST rewrite the literal word `"production"` in
  `detail` to the derived tier name.
- **error-target-spelling**: `errorsTarget(project)` MUST mint
  `"errors|${escapeSegment(project)}"` (exactly two segments), and
  `parseErrorsTarget` MUST return the unescaped project when the target
  carries that prefix, else `null`.
- **error-problem-grouping**: `errorProblems` MUST open at most one
  Problem per GlitchTip project (never one per error group), and within a
  project MUST rank its issues by `byImpact` — occurrence `count`
  descending, ties broken by ascending `issueKey`.
- **error-problem-level-filter**: `errorProblems`, via `judgedError`, MUST
  judge only an `ErrorFact` whose `level` (lower-cased) is `"error"` or
  `"fatal"` (a `null` or other level is never judged) and, unless the
  error feed is frozen, whose `lastSeenMs` is non-null and within
  `ERROR_RECENT_MS` of `nowMs`.
- **error-feed-freeze**: `errorFeedFrozen` MUST report frozen exactly when
  the `"glitchtip"` platform fact is `configured` and not `ok`; while
  frozen, `judgedError` MUST suspend the recency test (still requiring the
  level filter) so already-counted rows keep being judged instead of
  aging out.
- **error-problem-severity**: an error Problem MUST be `severity: "major"`
  when any counted issue's level is `"fatal"`, else `"minor"`, and MUST
  never be `"critical"`.
- **error-problem-fields**: an error Problem's `detail` MUST read
  `"${count} unresolved error(s) · ${clippedTopTitle}"`, its `sourceUrl`
  MUST be the top-ranked issue's `permalink`, its `errorText` MUST be the
  five highest-impact issues (worst first) each rendered
  `"${count}× ${clippedTitle}"` and newline-joined, and its `branch`
  and `commit*` fields MUST be `null`.
- **error-problem-allowlist**: `errorProblems` and `monitoredTargets`
  MUST both gate a project through the same `allowedProject` check —
  every project when `facts.errorProjectAllowlist` is `null`, else only
  projects present in that list.
- **error-problem-onset**: `errorProblems` MUST date a project's observed
  onset from the earliest `firstSeenMs` among its counted issues, clamped
  to no earlier than `nowMs - ERROR_RECENT_MS`, falling back to `nowMs`
  when no counted issue carries a `firstSeenMs`.
- **error-problem-gate**: `errorProblems` MUST return an empty array
  whenever `facts.errorsConfigured` is false.
- **problem-since-continuity**: `problemSince` MUST return the earlier
  (via `Math.min`) of a target's recorded ledger `openedAtMs` (when one
  exists) and the newly observed onset for that Problem source, so a
  Problem's `since` never resets forward across successive failures of
  the same target.
- **monitored-targets-union**: `monitoredTargets` MUST include: every
  active roster entry's `endpointId` when `monitorHttp` is on; every
  active, non-vanished, `monitorDeploys`-on entry's minted deploy target;
  every `configured` platform's `platformHealthTarget`; when
  `errorsConfigured` is true, every allowed project's error target, every
  open ledger row whose target is an error target, and every windowed
  issue event whose target is an error target; and every target
  `ownedDeployTarget` resolves from `facts.deploys` and
  `facts.inFlightDeploys`.

### Activity Derivation (derive-activity.ts)

- **activity-row-ids**: `deployRowId(deploymentId, step)` MUST mint
  `"deploy:${deploymentId}:${step}"` and `issueRowId(event, step, atMs)`
  MUST mint `"issue:${event.target}:${step}:${atMs}:${event.id}"`; neither
  id MUST ever be built from a mutable field (target, `createdAtMs`,
  branch, or project name for a deploy row).
- **activity-union**: `deriveActivity` MUST emit the union of every
  `deployEvents` row at or after the effective floor (`fromMs` or
  `nowMs - ACTIVITY_WINDOW_MS`) and every `issueEvents` row opened or
  resolved at or after that floor, and MUST NOT treat Activity as the
  complement of the Problems list — a row that is also a current Problem
  still MUST appear.
- **activity-deploy-rows**: for one deploy event, `deriveActivity` MUST
  emit a `"build"` row only when `buildPhase` is non-null, and a
  `"deploy"` row only when `deployPhase` is not `"none"`; a Crunchy row
  (whose `buildPhase` is always `null`) MUST therefore emit only a
  `"deploy"` row.
- **activity-deploy-suppression**: `deriveActivity` MUST suppress an
  issue-opened row for a target only when the feed already carries a
  bad-toned (`buildTone === "bad"` or `deployTone === "bad"`) deploy row
  for that same target; a not-bad (e.g. `built`/`deploying`) deploy row
  MUST NOT suppress a `stale` or `stuck` issue on the same target.
- **activity-issue-gate**: `deriveActivity` MUST drop any issue event
  whose `target` is not in the monitored-targets set (the injected
  `monitoredIn`, or a freshly computed `monitoredTargets` when omitted).
- **activity-resolved-row-gate**: `deriveActivity` MUST emit a resolved
  Activity row for an issue only when `resolvedReason === "recovered"`;
  an `"unmonitored"` or `null` reason MUST emit no resolved row.
- **activity-kind-classification**: `issueKind` MUST classify an issue
  event as `"platform"` when its target parses as a platform-health or
  errors target, as `"probe"` when its `source` is `"http"` or `"dns"`,
  and as `"deploy"` for every other source.
- **activity-sort-and-cap**: `deriveActivity` MUST sort its rows
  oldest-first by `at`, breaking ties on ascending `id`, and MUST keep
  only the newest `cap` rows (default `MAX_ACTIVITY_ROWS`), trimming from
  the front (oldest) end.
- **indicator-derivation**: `indicatorFor` MUST return `"operational"`
  when `problems` is empty, `"outage"` when any problem's `severity` is
  `"critical"`, and `"degraded"` otherwise.
- **activity-page-cursor**: `pageActivity` MUST exclude, when a cursor is
  given, every row that does not sort strictly before the cursor's
  `(atMs, id)` pair (per `beforeCursor`); it MUST treat a cursor id from
  the retired `deploy:<target>:<step>:<atMs>:<deploymentId>` grammar
  (more than three colon-separated parts) as unable to disambiguate a tie
  and therefore serve the whole tie group at that instant.
- **activity-page-progress**: `pageActivity` MUST set `nextCursor` to the
  oldest row it kept (never the oldest row fetched); when it keeps
  nothing, it MUST step the cursor to `floorMs` when `floorMs` narrows
  progress (is older than the cursor, or equals it with a non-empty
  cursor id), else to `cursor.atMs - 1`, and it MUST return `nextCursor:
  null` only when `sourcesExhausted` is true and no row was trimmed from
  the sorted, cursor-filtered candidate set.

### The Fold (derive.ts)

- **board-fold-purity**: `deriveBoard(facts, nowMs)` MUST be a pure
  function — it MUST perform no IO, and calling it twice with the same
  `facts` and `nowMs` MUST produce a deep-equal `Board`.
- **board-problem-ordering**: `deriveBoard` MUST sort the combined
  Problems array by `byRecency` — ascending `since`, ties broken by
  ascending `target`.
- **board-data-clock**: `dataAsOf` MUST compute `Board.dataAsOfMs` as the
  maximum of every endpoint's `checkedAtMs` and every platform fact's
  `sampledAtMs` only, returning `null` when both lists are empty; it MUST
  NOT be moved by any deploy fact, ledger entry, or `StaleProdFact`.
- **board-index-reuse**: `deriveBoard` MUST build one `RosterIndex` (via
  `rosterTargets`) and one `monitoredTargets` result and thread both into
  every Problem-family function and into `deriveActivity`, rather than
  letting each rule re-derive its own.
- **board-stale-suppression**: `deriveBoard` MUST pass the set of
  `deployProblems` targets as the `suppress` argument to
  `staleProdProblems`, and MUST NOT pass a suppress set to
  `errorProblems`.
- **board-activity-window-published**: `deriveBoard` MUST set
  `Board.activityFromMs` to `nowMs - ACTIVITY_WINDOW_MS` — the same
  boundary `deriveActivity` cuts the feed at.

### Fact Reading (facts.ts)

- **deploy-outcome-binning**: `binByOutcome` MUST route a `DeployFact`
  into `concluded` when its `combinedStatus` is bad or resolving (per
  `deployIsBad`/`deployIsResolving`), into `inFlight` when its
  `combinedStatus` is `"building"` or `"queued"`, and into neither when
  `"canceled"` or `"unknown"`.
- **read-board-facts-composition**: `readBoardFacts` MUST assemble one
  `BoardFacts` snapshot for one `nowMs` from: the roster; the binned
  concluded/in-flight deploy rows; every deploy event since
  `nowMs - ACTIVITY_WINDOW_MS` bounded to owned projects; every issue
  event opened or resolved since that same floor; the open ledger rows;
  platform facts; stale-prod facts; the live Vercel project-name mirror;
  and error facts.
- **endpoint-facts-active-only**: `readEndpointFacts` MUST read the
  latest check only for the active roster's `endpointId`s (never the full
  health-check history), and MUST resolve a bad endpoint's `badSinceMs`
  from a persisted bad-run-onset query, falling back to that check's own
  `checkedAtMs` when the onset query returns nothing for it.
- **activity-page-reuse**: `readActivityPage` MUST reuse an injected
  `opts.base` (or read a fresh `readBoardFacts` result when omitted) for
  every field except `deployEvents`/`issueEvents`, which it MUST override
  from three separate cursor-bounded storage reads, and it MUST treat
  `floorMs` as `null` (sources exhausted) only when all three of those
  reads returned fewer rows than their limit.
- **activity-page-derivation**: `readActivityPage` MUST call
  `deriveActivity` with `fromMs: floorMs ?? 0` and `cap: Infinity` (never
  the board's 24-hour floor or `MAX_ACTIVITY_ROWS` cap), because the
  page's candidates are already bounded by the three storage-layer
  `limit`s.
- **activity-base-cache**: `createActivityPageReader` MUST share one
  `readBoardFacts` result across pages requested within
  `ACTIVITY_BASE_FACTS_CACHE_MS` of each other, via a per-instance
  `cachedSingleFlight`, and MUST create a fresh cache per call (never a
  module-level singleton) so tests and parallel instances do not share
  state.

### Ledger Reconciliation (reconcile.ts)

- **reconcile-composition**: `reconcileBoardLedger` MUST, in order: read
  facts via `readBoardFacts`, fold them via `deriveBoard`, then (unless
  skipped) write the resulting `Board` to the ledger via
  `applyBoardToLedger` and flush queued alerts via `flushAlerts`.
- **reconcile-idempotency**: `reconcileBoardLedger` MUST be safe to call
  repeatedly against the same underlying data — a second call in a row
  MUST resolve nothing the first call did not already resolve.
- **reconcile-skip-on-empty-roster**: `reconcileBoardLedger` MUST, when
  `opts.skipOnEmptyRoster` is true and the read roster is empty, return
  `{ board, opened: 0, updated: 0, resolved: 0, resolvedTargets: [],
  skipped: true }` without calling `applyBoardToLedger` or `flushAlerts`.
- **reconcile-alert-flush**: `reconcileBoardLedger` MUST flush alerts
  itself, on every non-skipped call, rather than depending on a caller's
  own cycle to flush them.

### Data Shapes and Invariants (types.ts)

- **board-problem-cardinality**: `Board.problems` MUST contain at most
  one `Problem` per distinct `target` value.
- **activity-row-id-stability**: `ActivityRow.id` MUST remain stable for
  the life of a rendered row — none of its components may be a field that
  a later read can correct in place.
- **resolved-reason-semantics**: `IssueEvent.resolvedReason` MUST
  distinguish `"recovered"` (the thing was observed working again) from
  `"unmonitored"` (it merely stopped being watched) from `null` (resolved
  before the reason column existed), and only a `"recovered"` close may
  ever produce a resolved Activity row.

## Appearance

Not applicable — this is a server-side data-derivation module (a pure fold over monitoring facts into Problems, an Activity feed, and an overall indicator), not a visual component.

## States

Not applicable — this is a server-side data-derivation module, not a visual component; its judgment branches (failed/stuck, down/degraded, unreachable, stale, erroring) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side data-derivation module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| status-server-board-001 | board-target-minting, railway-environment-segment | `boardTargetKey("railway", "prj_x", "Scratch1")` | `"railway\|prj_x\|scratch1"` — `test/board-target-key.test.ts` › "lowercases the Railway env" |
| status-server-board-002 | segment-escaping, board-target-parsing | `boardTargetKey("vercel", "a\|b", null)` then `parseBoardTarget` on the result | round-trips to `{ platform: "vercel", id: "a\|b", environment: "" }` — `test/board-target-key.test.ts` › "escapes the separator instead of refusing to mint" |
| status-server-board-003 | board-target-minting | `boardTargetKey(null, "x", null)` or `boardTargetKey("vercel", "", null)` | `null` — `test/board-target-key.test.ts` › "returns null when the platform or id is missing" |
| status-server-board-004 | board-target-parsing | `parseBoardTarget("a\|b\|c\|d")` | `null` — `test/board-target-key.test.ts` › "rejects a target that is not three segments" |
| status-server-board-005 | roster-entry-matching | a deploy row and a roster entry that both carry a `providerProjectId`, and the ids differ, but the row's project name matches the entry's stale name | `matchRosterEntry` returns `null` — `test/board-ownership.test.ts` › "refuses the name fallback when both sides carry ids that DISAGREE" |
| status-server-board-006 | owned-deploy-target-gate, crunchy-always-visible | a Crunchy deploy row against an empty roster | `ownedDeployTarget` returns a target minted from the row itself, `owner: null` — `test/board-ownership.test.ts` › "mints a target from the row itself against an EMPTY roster" |
| status-server-board-007 | owned-deploy-target-gate | a Vercel row whose `environment` is `null` (or `""`) | `ownedDeployTarget` returns `null` — `test/board-deploy.test.ts` › "10. a Vercel PREVIEW build (environment=null) is never a problem" / "18. a Vercel deploy with environment '' ... is also a preview" |
| status-server-board-008 | deploy-problem-judging | a target's standing verdict is `failed`, and a newer in-flight row is still `building` under `STUCK_DEPLOY_MS` | `deployProblems` returns one Problem, `state: "stuck"`, not `"failed"` — `test/board-deploy.test.ts` › "a retry that WEDGES past the threshold is stuck, even with a failed verdict behind it" |
| status-server-board-009 | deploy-problem-judging | a failed deploy immediately followed by a successful one for the same target | `deployProblems` returns no Problem for that target — `test/board-deploy.test.ts` › "3. THE REGRESSION: a failure followed by a success clears the problem" |
| status-server-board-010 | deploy-verdict-collapse | two `DeployFact`s for one target, one carrying a `providerProjectId` and an older `createdAtMs`, the other carrying none and a newer `createdAtMs` | the newer row (by `createdAtMs`) wins regardless of id presence — `test/board-deploy.test.ts` › "the NEWER of the two spellings decides, whichever order the facts arrive" |
| status-server-board-011 | endpoint-problem-debounce | a `"degraded"` endpoint whose `badSinceMs` is `9` minutes before `nowMs` | `endpointProblems` returns no Problem for it (below `DEGRADED_CONFIRM_MS` = 10 minutes) — `test/board-endpoint.test.ts` › "a DEGRADED endpoint under the confirm window is NOT yet a problem" |
| status-server-board-012 | endpoint-problem-debounce | the same endpoint at `10` minutes | `endpointProblems` returns exactly one Problem — `test/board-endpoint.test.ts` › "a DEGRADED endpoint past the confirm window IS a problem" |
| status-server-board-013 | platform-problem-debounce | a platform fact with `configured: true, ok: false, streak: 1` (below `PLATFORM_UNREACHABLE_POLLS` = 2) | `platformProblems` returns no Problem — `test/board-monitoring.test.ts` › "an unreachable provider under the streak threshold is not a problem" |
| status-server-board-014 | stale-prod-problem-suppression | a target present in both `facts.staleProd` and the deploy-problem `suppress` set | `staleProdProblems` returns no row for that target — `test/board-monitoring.test.ts` › "staleness is SUPPRESSED when the same target already has a failed-deploy problem" |
| status-server-board-015 | stale-prod-environment-and-severity | a stale-prod fact whose project's configured production branch reads as tier `"testing"` | `severity: "minor"`, and `detail` has `"production"` rewritten to `"testing"` — `test/board-monitoring.test.ts` › "a stale TESTING project is downgraded to minor, and its detail no longer claims production" |
| status-server-board-016 | error-problem-grouping | three `ErrorFact`s for one GlitchTip project | `errorProblems` returns exactly one Problem for that project — `test/board-errors.test.ts` › "opens ONE problem per GlitchTip project, whatever the issue count" |
| status-server-board-017 | error-problem-level-filter | an `ErrorFact` with `level: null` | `errorProblems` never counts it — `test/board-errors.test.ts` › "ignores an issue with no level at all" |
| status-server-board-018 | error-feed-freeze | GlitchTip's own platform fact is `configured: true, ok: false`, and an error's `lastSeenMs` is older than `ERROR_RECENT_MS` | the issue is still judged (frozen), rather than expiring — `test/board-errors.test.ts` › "drops the watch set at the same moment, so the frozen row closes silently" (freeze behavior) |
| status-server-board-019 | error-problem-onset | an issue's `firstSeenMs` predates `nowMs - ERROR_RECENT_MS` | the Problem's `since` is clamped to the window start, not the true first-seen time — `test/board-errors.test.ts` › onset tests under "errorProblems — onset" |
| status-server-board-020 | monitored-targets-union | a Railway roster entry's `isActive` flips to `false` | `monitoredTargets` no longer contains its target, and its open ledger row (if any) closes as unmonitored, not recovered — `test/board-monitoring.test.ts` › "16. isActive=false removes EVERY problem for that site at once" |
| status-server-board-021 | activity-union | a deploy that both failed (a Problem) and is within the activity window | it appears in both `Board.problems` and `Board.activity` — `test/board-activity.test.ts` › "REGRESSION c40b87542: a FAILED deploy stays in Activity even though it is also a Problem" |
| status-server-board-022 | activity-deploy-suppression | an issue opens for a target on which the feed also carries a `built` (not-bad) deploy row | the issue-opened row still appears (not suppressed) — `test/board-activity.test.ts` › "FIX 1: a BUILT (not-bad) deploy row does NOT suppress a STALE issue on the same target" |
| status-server-board-023 | activity-resolved-row-gate | an issue closes with `resolvedReason: "unmonitored"` | `deriveActivity` emits no resolved row for it — `test/board-activity.test.ts` › "emits NOTHING for an UNMONITORED close" |
| status-server-board-024 | activity-sort-and-cap | more than `MAX_ACTIVITY_ROWS` (300) events in the window | `deriveActivity` returns exactly 300 rows, the newest ones — `test/board-activity.test.ts` › "caps the feed at MAX_ACTIVITY_ROWS, keeping the newest" |
| status-server-board-025 | indicator-derivation | `problems` contains one `severity: "critical"` Problem among others | `indicatorFor` returns `"outage"` — `derive-activity.ts`'s `indicatorFor`, exercised via `test/board-monitoring.test.ts`'s indicator-adjacent fold tests |
| status-server-board-026 | activity-page-cursor, activity-page-progress | a page whose sources returned fewer rows than requested and the fold kept every candidate row | `pageActivity` returns `nextCursor: null` — `test/board-activity-page.test.ts` › "reports exhaustion only when the sources were exhausted AND nothing was trimmed" |
| status-server-board-027 | activity-page-progress | a page that kept zero rows and `sourcesExhausted` is false | `pageActivity` steps `nextCursor` to `floorMs` rather than one tick back — `test/board-activity-page.test.ts` › "steps an empty page back to the page floor, not one tick" |
| status-server-board-028 | board-fold-purity | `deriveBoard(facts, nowMs)` called twice with the same arguments | deep-equal `Board` both times — `test/board-monitoring.test.ts` › "is pure — same facts and same nowMs give a deep-equal board" |
| status-server-board-029 | board-data-clock | facts frozen except the derivation's own `nowMs` advances | `Board.dataAsOfMs` does not move — `test/board-regressions.test.ts` › "does NOT move when the facts are frozen and only the derivation clock advances" |
| status-server-board-030 | reconcile-idempotency | `reconcileBoardLedger` called twice in a row against unchanged storage | the second call resolves nothing the first did not — `reconcile.ts`'s own doc comment, exercised end to end via `test/board-facts.test.ts`'s "END TO END" cases |
| status-server-board-031 | reconcile-skip-on-empty-roster | `reconcileBoardLedger(storage, config, { skipOnEmptyRoster: true })` with an empty roster read | returns `{ ..., skipped: true }` and calls neither `applyBoardToLedger` nor `flushAlerts` — `reconcile.ts`'s own doc comment (the `skipOnEmptyRoster` contract) |
| status-server-board-032 | problem-since-continuity | a target fails, is recorded in the ledger, then fails again later | `since` stays at the earlier onset rather than resetting to the second failure — `test/board-regressions.test.ts` › "does NOT reset when a broken target fails AGAIN — successive failures are one outage" |

## Edge Cases

- **Null and empty input**: `boardTargetKey` with a `null` platform, `null`/empty `id`, or `null` environment on a non-Railway platform (the environment segment is always empty for those); `entryIdentity` on an entry with neither `providerProjectId` nor a usable `projectName`; an `ErrorFact` with `level: null` or `lastSeenMs: null`.
- **Boundary values**: an endpoint exactly at `DEGRADED_CONFIRM_MS`; a platform exactly at `PLATFORM_UNREACHABLE_POLLS`; a deploy exactly at `STUCK_DEPLOY_MS`; an issue's `lastSeenMs` exactly at `ERROR_RECENT_MS`; an activity event exactly at the 24-hour window edge (kept, per `test/board-activity.test.ts` › "keeps an event exactly at the window edge").
- **Tie-breaking**: two deployments of one project created within the same second (`supersedes`' full tie-break chain); two issue events on one target in one second; a count tie between two GlitchTip issues (`byImpact`'s `issueKey` tie-break); a `pageActivity` tie group whose cursor uses the retired id grammar.
- **Concurrent / repeated invocation**: `reconcileBoardLedger` called from multiple threads or API routes against the same storage; `deriveBoard` called twice with identical facts (purity); a scrolled activity page reusing a cached `base` via `createActivityPageReader` while newer facts land underneath it.
- **Upstream deletion / renaming**: a Vercel project deleted upstream (`vanishedVercel`) while a live sibling project survives; a project renamed upstream, matched by provider id despite the name change; an empty or all-vanished `liveVercelProjects` read, which MUST narrow nothing rather than silence the whole fleet.
- **Malformed or legacy targets**: a ledger row minted before the escaping fix, holding a raw four-segment target that can no longer be parsed and closes as unmonitored; an activity cursor id from the retired five-plus-segment deploy-row grammar.
- **Configuration-off states**: `monitorHttp`, `monitorDeploys`, or `isActive` turned off on a roster entry (Requirement A: every dependent Problem and watch-set membership must disappear); GlitchTip unconfigured (`errorsConfigured: false`, which MUST empty both `errorProblems` and the error portion of `monitoredTargets`).
- **Provider-unreachable / frozen-feed state**: a platform whose poll cannot reach the provider API (frozen error feed, suspended recency test, but never silently "not configured"); a Crunchy cluster, which has no HTTP host at all but MUST still be watched.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `nowMs` (deriveBoard, deployProblems, endpointProblems, platformProblems, staleProdProblems, errorProblems, deriveActivity, reconcileBoardLedger's `opts.nowMs`) | `number` | `Date.now()` (only at `reconcileBoardLedger`'s boundary; every pure function requires it explicitly) | The derivation clock, epoch ms. Passed explicitly so every fold is pure and testable. |
| `index` / `RosterIndex` (deployProblems, staleProdProblems, deriveActivity's optional param) | `RosterIndex \| undefined` | freshly computed via `rosterTargets` when omitted | Lets a unit test call any rule directly with just facts; `deriveBoard` builds it once and threads it through. |
| `fromMs` (deriveActivity) | `number \| undefined` | `nowMs - ACTIVITY_WINDOW_MS` | The inclusive floor for an event's timestamp; a history page passes its own cursor-derived floor. |
| `cap` (deriveActivity) | `number \| undefined` | `MAX_ACTIVITY_ROWS` | How many rows the fold may return; a history page passes `Infinity`. |
| `opts.skipOnEmptyRoster` (reconcileBoardLedger) | `boolean` | `false` | Whether an empty roster read should skip the ledger sweep (config mutations that *caused* the emptiness leave this off; passive observers like `sync.ts` turn it on). |
| `config.probeIntervalSeconds` (readBoardFacts, via `StatusConfig`) | `number` (caller-supplied) | none — required | Read into `BoardFacts.probeIntervalMs` (× 1000) because the fold itself is pure and `config` is IO. |
| `config.glitchtipProjects` (readBoardFacts, via `StatusConfig`) | `readonly string[] \| null` (caller-supplied) | `null` (every project) | Carried into `BoardFacts.errorProjectAllowlist`, the one ownership gate `errorProblems` has in place of site ownership. |
| `config.alertWebhookUrl` (reconcileBoardLedger, via `StatusConfig`) | `string \| undefined` (caller-supplied) | none | Passed to `flushAlerts` after the ledger write. |
| `ACTIVITY_WINDOW_MS` (types.ts constant) | `number` | `86_400_000` (24 hours) | The Activity feed's window, and `ERROR_RECENT_MS`'s value. |
| `MAX_ACTIVITY_ROWS` (types.ts constant) | `number` | `300` | The live feed's row cap. |
| `MAX_ERROR_FACTS` (types.ts constant) | `number` | `100` | How many unresolved error groups `readBoardFacts` reads, matching the GlitchTip fetcher's own limit. |
| `DEGRADED_CONFIRM_MS` (types.ts constant) | `number` | `600_000` (10 minutes) | How long an endpoint must stay `degraded` before `endpointProblems` counts it. |
| `ACTIVITY_BASE_FACTS_CACHE_MS` (facts.ts constant) | `number` | `5_000` | How long `createActivityPageReader` may reuse a cached `readBoardFacts` result across scrolled pages. |
| `STUCK_DEPLOY_MS` (external constant, `../monitor/issue-sources`, consumed by `deployProblems`) | `number` | `1_800_000` (30 minutes) | How long a `building` deploy must run before it is judged `stuck`. |
| `PLATFORM_UNREACHABLE_POLLS` (external constant, `../monitor/issue-sources`, consumed by `platformProblems`) | `number` | `2` | Consecutive failed polls before a platform is judged unreachable. |
| `ERROR_JUDGED_LEVELS` (derive-problems.ts constant) | `Set<string>` | `{"error", "fatal"}` | The GlitchTip levels `errorProblems` counts as incidents. |

## Deep Linking

Not applicable — this is a server-side data-derivation module with no client-facing routes or URLs of its own.

## Localization

| String | Source | Notes |
|--------|--------|-------|
| `"stuck ${status} · ${minutes}m"` | `derive-problems.ts`'s `stuckDetail` | Hardcoded English; the interpolated status word itself also comes from an English vocabulary map. |
| `"${label} API unreachable — ${cost}"` | `derive-problems.ts`'s `platformProblems` | `cost` defaults to `"deploys for this platform can't be monitored"`, overridden per-provider in `PLATFORM_UNREACHABLE_COST`. |
| `"HTTP ${statusCode}"` / `"no response"` / `"DNS did not resolve"` | `derive-problems.ts`'s `endpointProblems` | Hardcoded English detail strings for an endpoint Problem. |
| `"${count} unresolved error${count === 1 ? "" : "s"} · ${title}"` | `derive-problems.ts`'s `errorProblems` | English pluralization is hand-rolled (a ternary), not run through an i18n pluralizer. |
| `"${count}× ${title}"` | `derive-problems.ts`'s `errorProblems` (the `errorText` block) | Uses the literal `×` character, not a localized multiplication sign. |
| Build/deploy/issue verbs (`"queued"`, `"building"`, `"built"`, `"build failed"`, `"canceled"`, `"outcome unknown"`, `"deploying"`, `"deployed"`, `"deploy failed"`, and every `ISSUE_VERB` entry: `"down"`, `"degraded"`, `"deploy failed"`, `"deploy stuck"`, `"deployment failed"`, `"platform unreachable"`, `"app errors"`) | `derive-activity.ts`'s `BUILD_VERB`/`DEPLOY_VERB`/`ISSUE_VERB` maps | The entire Activity-row vocabulary is hardcoded English, mirrored byte-for-byte by a client-side copy per the source's own comment — a hardcoded string is a fact to record here, not a gap to excuse. |

## Accessibility Options

Not applicable — this is a server-side data-derivation module with no rendering surface of its own.

## Feature Flags

Not applicable — none of these files read a feature-flag system; `config.glitchtipProjects` and `config.probeIntervalSeconds` are operator configuration, not flags, and are documented under Configuration.

## Analytics

Not applicable — none of these files emit analytics events.

## Privacy

- **Data handled**: deploy metadata (provider platform, project name, branch, commit hash/message/repo, provider error text, source/live URLs) already persisted upstream; HTTP/DNS probe results; provider platform-health samples; GlitchTip error-group summaries (issue title, culprit, level, counts, first/last-seen times, permalink) already persisted upstream; roster configuration (endpoint id, label, platform, project identity, monitoring switches, probed URL).
- **Storage / transmission / retention**: none of these files decide storage, transmission, or retention themselves — `facts.ts` only reads what other modules (`storage.board.*`, `storage.health.*`, `storage.deploy.*`) already persisted, and `reconcile.ts` writes back only the derived `Board`'s Problem/ledger state through `applyBoardToLedger`, a port implemented elsewhere.
- **End-user PII**: none of the fact shapes in `types.ts` carry end-user personal data (no email, no name, no IP address); commit messages, error titles, and culprit strings are free-form text from connected providers and MAY incidentally contain arbitrary text, but these files apply no PII-specific handling to them — they pass the fields through unchanged.

## Logging

Not applicable — none of these files call a logger, write to stdout/stderr, or otherwise produce log output; any logging of the facts they read or the `Board` they derive is the caller's responsibility.

## Platform Notes

- **TypeScript / Node (source)**: the fold is implemented as a set of pure functions over plain interfaces (`BoardFacts`, `Problem`, `ActivityRow`, `Board`) with no classes and no shared mutable state; `Map`/`Set` do the per-derivation indexing (`rosterTargets`, `onsetMap`, `collapseByTarget`), and every constant (`ACTIVITY_WINDOW_MS`, `DEGRADED_CONFIRM_MS`, etc.) is a plain exported `const`.
- **Swift (SwiftUI/AppKit/UIKit hosts)**: model `BoardFacts`, `Problem`, `ActivityRow`, and `Board` as `Equatable` `struct`s (value semantics make the purity/deep-equal contract free), the fold as a free function or a `static func` taking `facts` and `now: Date` explicitly, and the per-target indexing with `Dictionary`/`Set` exactly as the source's `Map`/`RosterIndex` does; keep `nowMs` (or a `Date`) an explicit parameter rather than reading `Date()` inside the fold, so XCTest can assert a deep-equal result the same way `test/board-regressions.test.ts` does.
- **Kotlin (Jetpack Compose hosts)**: model the same shapes as immutable `data class`es (structural `equals`/`hashCode` come for free, matching the deep-equal purity contract), the fold as a top-level function or an object method taking `facts: BoardFacts` and `nowMs: Long` explicitly, and the indexing with `Map`/`Set` from `kotlin.collections`.
- **C# / WinUI 3 (.NET / Windows App SDK hosts)**: model the shapes as immutable C# `record` types (e.g. `record Board(string GeneratedAt, long? DataAsOfMs, IReadOnlyList<Problem> Problems, ...)`, using `System.Collections.Immutable.ImmutableArray<T>` for the `Problems`/`Activity` lists so equality is structural), the fold as a `static` method on a plain class taking `BoardFacts facts` and `long nowMs` explicitly, and the per-target indexing with `System.Collections.Generic.Dictionary<TKey,TValue>`/`HashSet<T>`; if the derived `Board` crosses a process boundary to a UI layer, serialize it with `System.Text.Json` rather than hand-rolling a second shape.
- **Web client**: the client is documented in the source comments as holding byte-identical copies of exactly two pieces of this vocabulary — `ISSUE_VERB` (exported here for that reason) and the `STATE_LABEL` map described in `derive-activity.ts`'s comment on `ISSUE_VERB` — and a parity test (`row-vocabulary-parity.test.ts`, referenced in that comment) is what is meant to keep the two in sync; a client host porting this recipe should keep that parity test rather than letting the two vocabularies drift.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/board/` |

## Design Decisions

- **Decision**: keep `deployProblems`' concluded and in-flight deploy lists
  separate, and judge a retry's in-flight row only for `stuck`, rather
  than collapsing both lists to one "latest row per target" before
  judging.
  **Rationale**: the source comment states this directly — collapsing was
  the regression this code replaces: a retry's `BUILDING` row would win,
  the target would look neither failed nor stuck, `applyBoardToLedger`
  would read the resulting silence as a recovery, and on-call would be
  paged that a build passed while production still served the broken one.
  **Approved**: pending
- **Decision**: mint a deployment's Activity row ids from only its
  immutable provider id and lifecycle step
  (`deploy:<deploymentId>:<step>`), never from its target, timestamp,
  branch, or project name.
  **Rationale**: the source comment explains that `created_at`, `branch`,
  and `project_name` are all corrected in place by `upsertDeployments`; an
  id built from any of them would mint a second id for the same
  deployment once corrected, and the client's `useActivityHistory` keeps
  an id that leaves the live window forever — the "several sites stuck on
  building hours after they went green" defect the comment describes.
  **Approved**: pending
- **Decision**: derive `Board.dataAsOfMs` from only health-check
  (`checkedAtMs`) and platform-sample (`sampledAtMs`) observations,
  explicitly excluding deploy facts, ledger entries, and stale-prod facts.
  **Rationale**: the source comment explains each exclusion is deliberate
  — a deploy row carries the provider's own clock and can be written by a
  webhook on the API thread while the monitor process is wedged, which
  would refresh this clock without a monitor cycle having run; the ledger
  is the board's own output, so counting it would let the board's writes
  certify its own freshness; `staleProd` carries no observation timestamp
  at all. Every exclusion is chosen so the clock can only read older than
  reality, never fresher.
  **Approved**: pending
- **Decision**: suppress an issue-opened Activity row for a target only
  when the feed already carries a *bad-toned* deploy row for that target
  — never a not-bad (`built`/`deploying`) one.
  **Rationale**: the source comment (labeled "FIX 1" in the regression
  suite) states that a not-bad deploy row says the opposite of a `stale`
  or `stuck` issue on the same target, so it must not be allowed to
  silence the issue that is reporting the actual problem.
  **Approved**: pending
- **Decision**: freeze `errorProblems`' recency test — judging
  already-counted issues indefinitely rather than letting them age out —
  while GlitchTip's own platform-health fact is `configured` and not
  `ok`.
  **Rationale**: the source comment explains the alternative directly: a
  failed GlitchTip poll persists nothing, so every row's `lastSeen`
  simply stops advancing; without the freeze, exactly `ERROR_RECENT_MS`
  after the outage began every error row would silently expire and
  `applyBoardToLedger` would close the open row as `"recovered"` — an
  all-clear page for errors nobody has been able to observe for a day.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | passed | Access Patterns |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

`separation-of-concerns` passes: `facts.ts` is documented as "the only file
in `src/board/` that orchestrates the reads," and every other file
(`derive.ts`, `derive-problems.ts`, `derive-activity.ts`, `ownership.ts`,
`target-key.ts`) is a pure function of already-read facts with no IO of
its own; `reconcile.ts` composes the read, the fold, and the write as
three distinct calls rather than interleaving them. `unit-test-coverage`
passes: the eight source files are covered by at least fifteen dedicated
test files (`board-target-key.test.ts`, `board-ownership.test.ts`,
`board-deploy.test.ts`, `board-endpoint.test.ts`, `board-errors.test.ts`,
`board-monitoring.test.ts`, `board-regressions.test.ts`,
`board-activity.test.ts`, `board-activity-page.test.ts`,
`board-facts.test.ts`, among others), including a dedicated purity/deep-equal
assertion and dozens of numbered regression cases each pinned to a specific
prior defect. `idempotent-operations` passes: `reconcileBoardLedger`'s own
doc comment states plainly that it is "safe to call on every mutation: it
is idempotent and derives from the DB, so calling it twice resolves nothing
the second time" — the exact property this check requires of a retriable
write operation. `pagination-support` passes: `pageActivity` implements
cursor-based pagination over the Activity feed with an explicit
`(atMs, id)` cursor, a `nextCursor` that narrows monotonically, and a
documented exhaustion signal (`sourcesExhausted`) distinct from "this page
happened to be empty" — the collection-returning surface this module
contributes (`readActivityPage`/`GET /activity`) does not return an
unbounded list. `data-integrity` passes for the read/write surface these
files own: `boardTargetKey`/`parseBoardTarget` guarantee a total mint-parse
round trip (escaping rather than silently dropping a separator character,
per `target-key.ts`'s own comment), `parseErrorsTarget`/
`parsePlatformHealthTarget` return `null` rather than a wrong answer for a
target that is not theirs, and `deriveBoard`'s purity contract is itself
verified by a deep-equal regression test — corrupt or malformed input
(a legacy four-segment target, an unparseable target) is detected by
returning `null`/being excluded rather than being silently misinterpreted.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
