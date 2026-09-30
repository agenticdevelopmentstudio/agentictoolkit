<!-- leaf: implement-status-server/board--part-2 · source: status-server-board.md -->

# Status Server Board — continued (part 2)

**Rules** (cite as `implement-status-server/board--part-2#<slug>`):

- `platform-health-target-spelling` MUST
- `deploy-verdict-collapse` MUST
- `deploy-problem-judging` MUST
- `deploy-problem-fields` MUST
- `endpoint-problem-debounce` MUST
- `endpoint-problem-gate` MUST
- `endpoint-problem-fields` MUST
- `platform-problem-debounce` MUST
- `platform-problem-severity` MUST
- `stale-prod-problem-suppression` MUST
- `stale-prod-vanish-narrowing` MUST
- `stale-prod-environment-and-severity` MUST
- `error-target-spelling` MUST
- `error-problem-grouping` MUST
- `error-problem-level-filter` MUST
- `error-feed-freeze` MUST
- `error-problem-severity` MUST
- `error-problem-fields` MUST
- `error-problem-allowlist` MUST
- `error-problem-onset` MUST
- `error-problem-gate` MUST
- `problem-since-continuity` MUST
- `monitored-targets-union` MUST
- `activity-row-ids` MUST
- `activity-union` MUST
- `activity-deploy-rows` MUST
- `activity-deploy-suppression` MUST
- `activity-issue-gate` MUST
- `activity-resolved-row-gate` MUST
- `activity-kind-classification` MUST
- `activity-sort-and-cap` MUST
- `indicator-derivation` MUST
- `activity-page-cursor` MUST
- `activity-page-progress` MUST

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

