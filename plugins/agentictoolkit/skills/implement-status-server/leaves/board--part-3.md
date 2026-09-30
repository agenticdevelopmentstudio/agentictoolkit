<!-- leaf: implement-status-server/board--part-3 · source: status-server-board.md -->

# Status Server Board — continued (part 3)

**Rules** (cite as `implement-status-server/board--part-3#<slug>`):

- `board-fold-purity` MUST
- `board-problem-ordering` MUST
- `board-data-clock` MUST
- `board-index-reuse` MUST
- `board-stale-suppression` MUST
- `board-activity-window-published` MUST
- `deploy-outcome-binning` MUST
- `read-board-facts-composition` MUST
- `endpoint-facts-active-only` MUST
- `activity-page-reuse` MUST
- `activity-page-derivation` MUST
- `activity-base-cache` MUST
- `reconcile-composition` MUST
- `reconcile-idempotency` MUST
- `reconcile-skip-on-empty-roster` MUST
- `reconcile-alert-flush` MUST
- `board-problem-cardinality` MUST
- `activity-row-id-stability` MUST
- `resolved-reason-semantics` MUST

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

## Localization

| String | Source | Notes |
|--------|--------|-------|
| `"stuck ${status} · ${minutes}m"` | `derive-problems.ts`'s `stuckDetail` | Hardcoded English; the interpolated status word itself also comes from an English vocabulary map. |
| `"${label} API unreachable — ${cost}"` | `derive-problems.ts`'s `platformProblems` | `cost` defaults to `"deploys for this platform can't be monitored"`, overridden per-provider in `PLATFORM_UNREACHABLE_COST`. |
| `"HTTP ${statusCode}"` / `"no response"` / `"DNS did not resolve"` | `derive-problems.ts`'s `endpointProblems` | Hardcoded English detail strings for an endpoint Problem. |
| `"${count} unresolved error${count === 1 ? "" : "s"} · ${title}"` | `derive-problems.ts`'s `errorProblems` | English pluralization is hand-rolled (a ternary), not run through an i18n pluralizer. |
| `"${count}× ${title}"` | `derive-problems.ts`'s `errorProblems` (the `errorText` block) | Uses the literal `×` character, not a localized multiplication sign. |
| Build/deploy/issue verbs (`"queued"`, `"building"`, `"built"`, `"build failed"`, `"canceled"`, `"outcome unknown"`, `"deploying"`, `"deployed"`, `"deploy failed"`, and every `ISSUE_VERB` entry: `"down"`, `"degraded"`, `"deploy failed"`, `"deploy stuck"`, `"deployment failed"`, `"platform unreachable"`, `"app errors"`) | `derive-activity.ts`'s `BUILD_VERB`/`DEPLOY_VERB`/`ISSUE_VERB` maps | The entire Activity-row vocabulary is hardcoded English, mirrored byte-for-byte by a client-side copy per the source's own comment — a hardcoded string is a fact to record here, not a gap to excuse. |

