import type { BuildPhase, DeployPhase } from "../monitor/deploy-status";
import type { IssueSource } from "../monitor/issue-sources";
import type { HealthStatus } from "../monitor/health";

/**
 * One monitored endpoint, as the board sees it. THE ROSTER ENTRY OWNS IDENTITY:
 * it mints the target key for the deploy target it is wired to, and a deploy row
 * matches an entry by provider id when both carry one, else by project name. That
 * ordering is what stops the provider-id cutover from producing two spellings of
 * one target and double-counting it.
 */
export interface RosterEntry {
  /** `monitoredEndpoints.id` — a text uuid, and the value `healthChecks.serviceSlug` holds. */
  endpointId: string;
  /** Display name — comes from `monitoredSites.name`; endpoints have no label column. */
  label: string;
  /** Raw platform as configured (`cloudflare-pages` allowed — canonicalised on use). */
  platform: string | null;
  /** The provider's immutable project id, when we have one. Null until adopted. */
  providerProjectId: string | null;
  /** The provider's project NAME. The identity fallback, and always the display name. */
  projectName: string | null;
  environment: string | null;
  /** Master switch. False → this endpoint contributes NOTHING to the board. */
  isActive: boolean;
  /** Per-signal switch: HTTP/DNS probing. */
  monitorHttp: boolean;
  /** Per-signal switch: deploy monitoring. */
  monitorDeploys: boolean;
  /** Opted out of deploy-project matching — owns no deploy target at all. */
  ignoreProjectWarning: boolean;
  /** The URL probed, for display and links. */
  url: string | null;
}

/**
 * ONE deployment row, as the board sees it. Which rows are present depends on the list
 * this fact came from (`deploys`, `inFlightDeploys`, `deployEvents`) — a `DeployFact` on
 * its own carries no claim about being the newest of anything, because the row's own
 * columns cannot tell the fold that two spellings of a project are one target. The
 * per-target collapse happens in the fold, not here.
 */
export interface DeployFact {
  /**
   * The provider's own deployment id — `deployments.id`, the table's primary key.
   *
   * The ONE field on this fact guaranteed unique per row, which is why the Activity feed's
   * row ids are minted from it. Everything else that looked identifying is not: the board
   * target collapses every environment of a non-railway project into one key
   * (`target-key.ts` sets the env segment to "" off railway), and `createdAtMs` comes from
   * a column stored in whole SECONDS. Two deployments of one project in one second are
   * ordinary — a push that lands `main` and `staging` together, or a redeploy — and
   * without this they minted byte-identical row ids, which is not a cosmetic problem: the
   * page cursor is the (atMs, id) PAIR, so a duplicate id makes the feed's order not a
   * total order and one of the twins unreachable by any page.
   */
  deploymentId: string;
  platform: string;
  providerProjectId: string | null;
  projectName: string;
  environment: string | null;
  /**
   * The git ref this deployment was built from (`deployments.branch`), or null for a row
   * written before the column was populated or by a platform that reported none.
   *
   * THE tier signal. `environment` is the provider's promotion target and the project
   * name is a convention; the branch is the deploy pipeline's own input, so it is the one
   * of the three that cannot be wrong. `deployEnv` ranks it first — see the ordering
   * documented there and on `ownedDeployTarget`.
   */
  branch: string | null;
  buildPhase: BuildPhase | null;
  deployPhase: DeployPhase;
  /** Epoch ms. Never a Date — the fold is pure and compares numbers. */
  createdAtMs: number;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  /**
   * The provider's own words about why this deploy failed (`deployments.error_text`),
   * already shaped by `monitor/deploy-error-shaping.ts` at ingest. Null on a success and
   * on a failure the provider explained nothing about.
   */
  errorText: string | null;
  /** Provider-side build/deploy page. */
  sourceUrl: string | null;
  /** The deployed site itself. */
  liveUrl: string | null;
}

/** The current HTTP/DNS observation for one endpoint. */
export interface EndpointFact {
  /** The endpoint's text uuid — `healthChecks.serviceSlug`. Also the issue TARGET, bare. */
  endpointId: string;
  /** `"healthy" | "degraded" | "down"` — there is no `"up"`. */
  status: HealthStatus;
  statusCode: number | null;
  /**
   * False → the hostname failed DNS resolution, making this a `dns` problem rather than
   * an `http` one. Read from the persisted `health_checks.dns_ok` column added in Task 8.
   * It was NOT persisted before: `reads.ts:367` derived it from "does this endpoint have
   * an open dns issue", which is circular the moment the ledger is written FROM the board.
   */
  dnsOk: boolean;
  /** Epoch ms of the probe. */
  checkedAtMs: number;
  /**
   * Epoch ms the endpoint FIRST entered its current bad state, from the persisted
   * health-check history — server truth, durable across browsers. Null when healthy.
   * The 10-minute degraded debounce is measured from here.
   */
  badSinceMs: number | null;
}

/** One provider API's reachability this cycle. */
export interface PlatformFact {
  source: IssueSource;
  /** Do we poll this platform at all (active integration WITH a token)? */
  configured: boolean;
  /** Did the latest poll reach the provider API? */
  ok: boolean;
  /** Consecutive failed polls, persisted across cycles. */
  streak: number;
  /**
   * Epoch ms this observation was RECORDED (`platform_health_state.updated_at`), not the
   * time of anything the provider reported. `recordPlatformObservations` rewrites it every
   * cycle whether or not the verdict changed, which makes it the monitor's heartbeat and
   * the only fact that keeps ticking on a fleet where nobody is deploying. One of the only
   * TWO families `Board.dataAsOfMs` is built from (the other being the health check's own
   * `checkedAtMs`) — see there for why a board needs a clock that is not its own, and why a
   * deploy row's provider-side timestamp is not allowed to move it.
   */
  sampledAtMs: number;
}

/** A Vercel project whose LIVE production deploy is errored or behind its latest build. */
/**
 * One unresolved error group, as GlitchTip summarizes it (`errors` table, written by
 * `telemetry/stores/errors.ts`). A SUMMARY, never an event: `count` is how many times
 * this one grouped issue has fired, so the list length is the number of DISTINCT
 * problems, not the volume.
 *
 * The store reconciles against GlitchTip's `is:unresolved` query, so a row's presence
 * here means "still open upstream". Resolving it in GlitchTip removes it from the next
 * poll, the store marks it resolved, and it stops being a fact — which is the whole
 * mechanism by which an error Problem closes.
 */
export interface ErrorFact {
  /** GlitchTip's issue id — the store's upsert key, and stable across polls. */
  issueKey: string;
  /** GlitchTip project slug. Today the fleet has exactly ONE (`adh`), so this is the
   *  grain an error Problem is keyed at rather than the site: nothing in the payload
   *  attributes an error to one of the 40-odd sites, and inventing an attribution the
   *  data cannot support would put a red row against an arbitrary site. */
  project: string;
  title: string;
  culprit: string | null;
  /** GlitchTip's level — `error`, `fatal`, `warning`, `info`, or null on an old row. */
  level: string | null;
  /** Occurrences of THIS grouped issue. */
  count: number;
  userCount: number;
  firstSeenMs: number | null;
  lastSeenMs: number | null;
  permalink: string | null;
}

export interface StaleProdFact {
  platform: string;
  providerProjectId: string | null;
  projectName: string;
  environment: string | null;
  /**
   * The project's CONFIGURED production branch (`deploy_project_meta.git_branch`), not the
   * branch of any one deployment — a stale-prod fact is a verdict about a project, and the
   * project it describes may not have deployed at all recently.
   *
   * It is the same evidence a `DeployFact.branch` carries, asked of the project rather
   * than of a build: a project whose production branch is `prepared` builds testing, so
   * its staleness is a testing incident whatever its name happens to be.
   */
  branch: string | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
}

/** The onset time already recorded in the ledger for a target, if any. */
export interface LedgerEntry {
  target: string;
  /**
   * Epoch ms the ledger row was OPENED — the moment `applyBoardToLedger` first wrote it,
   * not the moment the thing broke (nothing passes an observed onset to `openIssue`).
   *
   * The board reuses it for CONTINUITY ACROSS SUCCESSIVE FAILURES, not to survive
   * restarts: `badSinceMs` and `deployments.createdAt` are columns too, so the observed
   * onsets already survive a restart. What they do not survive is the NEXT failure —
   * each new failed build resets the observed onset forward, and a target that has been
   * broken all week would keep re-reporting itself as broken for a minute. This value is
   * the floor that stops that. It is only ever a floor: `problemSince` takes the earlier
   * of the two, because this one is late by construction and gets reset outright whenever
   * a target is respelled.
   */
  openedAtMs: number;
}

/**
 * An issue the ledger opened or resolved. The Activity feed is the union of deployments
 * and issue events (spec §Activity): a recovery has to leave a "[down] resolved" row the
 * way `activity-store.ts:210-229` did on the client, or every recovery disappears from
 * the pane and `ActivityKind`'s "probe" and "platform" members become unreachable.
 *
 * Distinct from `LedgerEntry`, which is only an onset time for a still-open row. This is
 * the event record, and it includes closed rows.
 */
export interface IssueEvent {
  /**
   * `issues.id` — the ledger row's primary key, and the only unique thing about this
   * event. `target` is not: an endpoint's `http` and `dns` issues share it, so two of them
   * opening in the same second (a host that vanishes fails both probes at once) minted one
   * row id for two events. See `DeployFact.deploymentId` for why a duplicate id is a
   * paging defect and not a cosmetic one.
   */
  id: number;
  /** The ledger's target, in whichever of the three spellings applies. */
  target: string;
  source: IssueSource;
  name: string;
  environment: string | null;
  /** The state it was opened AS — "down", "degraded", "failed", "stuck", "stale", "unreachable". */
  state: string;
  /** `issues.severity` — the tone the pane paints this row. Minor is amber, not red. */
  severity: "critical" | "major" | "minor";
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  /** Epoch ms the issue opened. */
  openedAtMs: number;
  /** Epoch ms it closed. Null while still open. */
  resolvedAtMs: number | null;
  /**
   * WHY it closed. `recovered` = the thing was observed working again. `unmonitored` =
   * it merely stopped being watched, and NOTHING was observed to recover. Only a
   * `recovered` close may emit a resolved Activity row — see the rule in this task's
   * header. `resolveIssue` has always known the reason (`issues.ts:265`) and only used it
   * to decide whether to page; Task 8 persists it. Null for rows resolved before that
   * column existed: unknown, so no row, because the safe default is to claim nothing.
   */
  resolvedReason: "recovered" | "unmonitored" | null;
}

/** Everything `deriveBoard` is allowed to look at. Assembled by `readBoardFacts`. */
export interface BoardFacts {
  roster: RosterEntry[];
  /**
   * The monitor's probe cadence in ms, read from config by `readBoardFacts`. A FACT rather
   * than something `deriveBoard` reads for itself: the fold is pure, and `config` is IO.
   */
  probeIntervalMs: number;
  /**
   * Deploy rows that CONCLUDED — `combinedStatus` reads each as `failed` or `success`.
   * Only these carry a verdict, and only a verdict may be judged `failed`. At most one row
   * per (platform, projectName, environment); the fold collapses further, to one per board
   * TARGET.
   */
  deploys: DeployFact[];
  /**
   * Deploy rows still IN FLIGHT — `combinedStatus` reads each as `building` or `queued`.
   * Separate from `deploys` because an in-flight row is the ABSENCE of a verdict, not a
   * good one: a retry that is still building must not clear the failure it is retrying
   * (which is what pages on-call with a false recovery), and only an in-flight row can
   * ever be `stuck`. Same grouping, same further collapse in the fold.
   */
  inFlightDeploys: DeployFact[];
  /**
   * EVERY deployment row inside the activity window, ungrouped and unfiltered by outcome.
   * This is the LOG; `deploys`/`inFlightDeploys` above are the STATE PROJECTION. They are
   * separate lists deliberately: the Problem rules need the current state per target, and
   * the feed needs what actually happened. Folding them into one is precisely how
   * Activity became a projection of current state — regressions 18199fb82 and c40b87542,
   * both times.
   */
  deployEvents: DeployFact[];
  /** Issues opened or resolved inside the activity window. The other half of the feed. */
  issueEvents: IssueEvent[];
  endpoints: EndpointFact[];
  platforms: PlatformFact[];
  staleProd: StaleProdFact[];
  /** Open ledger rows, keyed by target — the ONSET times, not the truth. */
  ledger: LedgerEntry[];
  /**
   * Vercel projects that still exist upstream. Empty means "we could not read the
   * account", NOT "everything was deleted" — the fold narrows nothing when it is empty.
   */
  liveVercelProjects: string[];
  /** Error groups still unresolved in GlitchTip, newest activity first. */
  errors: ErrorFact[];
  /**
   * Is GlitchTip actually wired up (URL + token + org)? Read from env by `readBoardFacts`
   * for the same reason `probeIntervalMs` is — the fold is pure and `config` is IO.
   *
   * It gates BOTH the rule and the watch set, and it has to gate both. `collectTelemetry`
   * skips the poll entirely when GlitchTip is unconfigured (`server.ts:52`), so the
   * `errors` rows FREEZE at whatever was last seen rather than emptying. Judging those
   * frozen rows would pin a Problem open with nothing left in the system able to close
   * it; dropping the target from the watch set at the same moment is what makes the
   * already-open row close quietly instead of paging a recovery that was really a
   * switch-off.
   */
  errorsConfigured: boolean;

  /**
   * `GLITCHTIP_PROJECTS`, or NULL for "every project the poll returns" — see
   * `config.glitchtipProjects`. Carried as a FACT rather than read in the fold because
   * `deriveBoard` is pure; this is the one gate error Problems have in place of the site
   * ownership every other rule uses.
   */
  errorProjectAllowlist: readonly string[] | null;
}

/** One row of the Problems list. This is the wire shape the client renders. */
export interface Problem {
  /**
   * For a deploy target, `boardTargetKey()` output. For an endpoint, the endpoint's
   * BARE id — `reads.ts:437` and `app.ts:91` both tell endpoint problems from the rest
   * by testing `serviceSlugs.has(target)`, so wrapping it would break both. For platform
   * health, `platform-health|<source>` — TWO segments, no trailing pipe. That is the
   * spelling already in the `issues` table (`issues.ts:611`), and it is deliberately not
   * minted by `boardTargetKey()`: a provider is not a deploy target, and giving it a
   * third segment would orphan every live platform-health row for no gain.
   */
  target: string;
  source: IssueSource;
  /** Human name — the project or site name, never the id. */
  name: string;
  environment: string | null;
  severity: "critical" | "major" | "minor";
  /** What kind of problem: `failed`, `stuck`, `down`, `degraded`, `stale`, `unreachable`. */
  state: string;
  statusCode: number | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  /**
   * The git ref the deploy was built from, RAW — the same `DeployFact.branch` the tier in
   * `environment` was derived from, carried on as well because the details pane's Git tab
   * shows the branch itself next to the commit. A stale-production problem carries the
   * project's CONFIGURED production branch instead, which is the same question asked of a
   * project rather than of a build. Null on every problem that is not about a deploy: an
   * HTTP probe and an unreachable provider have no branch, and saying so explicitly is
   * what keeps the pane from inventing one.
   */
  branch: string | null;
  /**
   * The provider's own words about the failure (`DeployFact.errorText`), which the details
   * pane renders as its error block — the only place an operator can read WHY a build
   * failed without opening the provider. Null wherever there is no provider text: a
   * success, a non-deploy problem, a staleness verdict we derived ourselves.
   */
  errorText: string | null;
  /** ISO time the problem began — from the ledger when known, else first observation. */
  since: string;
}

export type ActivityKind = "deploy" | "probe" | "platform";

/**
 * The row's colour/weight axis, matching the client's `RowTone` one-for-one so the
 * pane renders the wire value directly instead of re-deriving it. `stale` = the row's
 * claim could not be re-confirmed (an `unknown` phase) — muted, neither progress amber
 * nor a verdict's colour.
 */
export type ActivityTone = "good" | "bad" | "progress" | "neutral" | "stale";

/** One row of the Activity feed — a RECORD of something that happened. */
export interface ActivityRow {
  /**
   * Stable identity for React keys, dedup, and the `(at, id)` paging cursor.
   *
   * `deploy:<deploymentId>:<step>` for a deployment's build/deploy rows;
   * `issue:<target>:opened|resolved:<atMs>:<issueId>` for issue rows.
   *
   * STABLE is the load-bearing word, not merely unique. Every component must be immutable
   * for the life of the fact: the client keys history by this string and cannot tell a row
   * that was renamed from a row that was withdrawn and replaced. Deploy rows carry no
   * target and no timestamp precisely because `deployments.created_at`, `project_name` and
   * `branch` are all corrected after the row first renders — see `deriveActivity`'s
   * `deployRowId`, and `docs/status-site/status-activity-row-ids-must-not-move.md`.
   */
  id: string;
  kind: ActivityKind;
  /**
   * Which lifecycle step this row records. A deployment emits a build row and, when it
   * got that far, a deploy row — the two are distinct events and the pane has always
   * shown them as separate lines. Null for probe/platform rows.
   */
  step: "build" | "deploy" | null;
  /**
   * The provider/probe this row came from, in the SAME `IssueSource` spelling
   * `Problem.source` uses (`"cloudflare-pages"`, never `boardTargetKey`'s canonical
   * `"cloudflare"`) — a deploy row's platform, or an issue row's `IssueEvent.source`
   * (http/dns/vercel/railway/cloudflare-pages/platform id). Null only if genuinely
   * unknown. Without this the client cannot tell an http/dns row apart from any other,
   * which is exactly the regression Fix Round 2 item 1 restores (`activity-store.ts`'s
   * `serviceProblemRow` used to set it before the board model replaced it).
   */
  source: IssueSource | null;
  /**
   * Tone is DERIVED FROM the event, and `kind` is never recomputed from tone.
   * (activity-store.ts:322 did exactly that, which is defect #1 in the spec.)
   */
  tone: ActivityTone;
  /**
   * The rendered status word — "building", "build failed", "deployed", "[down] resolved".
   * On the wire because the server owns what a row SAYS, exactly as it owns whether the
   * row exists. The client copies it into `Row.statusWord` and renders it; it does not
   * own a second verb table for this pane.
   */
  verb: string;
  target: string;
  name: string;
  environment: string | null;
  detail: string | null;
  sourceUrl: string | null;
  liveUrl: string | null;
  commitHash: string | null;
  commitMessage: string | null;
  commitRepo: string | null;
  /** The deploy's git ref, raw — see `Problem.branch`. Null on an issue row. */
  branch: string | null;
  /** The provider's failure text — see `Problem.errorText`. Null on an issue row. */
  errorText: string | null;
  /** ISO time the event happened. */
  at: string;
}

export type Indicator = "operational" | "degraded" | "outage";

/** The whole board. One read, one clock, one truth. */
export interface Board {
  /** ISO server clock at derivation — the client's only time reference. */
  generatedAt: string;
  /** Epoch ms of the newest fact THE MONITOR ITSELF wrote on its own cadence — a health
   *  check or a platform sample — and null when there is none. NOT `generatedAt`: a
   *  wedged monitor keeps minting a fresh generatedAt over frozen data. Deliberately not
   *  every fact the board was derived from: a deploy row carries the PROVIDER's clock and
   *  can be written by a webhook while the monitor is wedged, which would refresh this
   *  clock without a cycle having run. See `dataAsOf` in `derive.ts`. */
  dataAsOfMs: number | null;
  /**
   * The monitor's probe cadence in ms — the CLIENT'S freshness windows are scaled by it,
   * so it has to travel with the board that those windows judge.
   *
   * It used to reach the client only on the SSE stream, which meant `useBoard` read it off
   * the live-snapshot singleton with `useSyncExternalStore` and got `null` for every
   * consumer that never opens a stream, plus every consumer that opens one before the
   * first frame lands. A board that answers "how stale is too stale" out of one feed while
   * being judged out of another is two sources of truth for one question — the shape this
   * whole branch removes.
   */
  probeIntervalMs: number;
  /**
   * Epoch ms of the OLDEST event `activity` can contain (`generatedAt - ACTIVITY_WINDOW_MS`).
   * The feed's window is the server's, so anything that counts or captions those rows must
   * read the boundary from here rather than re-deriving one. `OverviewStats` hardcoded its
   * own 24h and its own "· 24h" labels; changing `ACTIVITY_WINDOW_MS` would have left the
   * counts silently disagreeing with the list they are counting.
   */
  activityFromMs: number;
  /**
   * GUARANTEED at most ONE row per `target`. Every rule that mints problems collapses its
   * facts to one per target before judging them, because the ledger writer keys on the
   * target (`applyBoardToLedger` builds `new Map(problems.map(p => [p.target, p]))`): a
   * second row for the same target is not an extra problem, it is a row that silently
   * overwrites the first, and which one survives would depend on the order two spellings
   * of one project happened to come back from SQLite. The client dedups on target too.
   */
  problems: Problem[];
  activity: ActivityRow[];
  indicator: Indicator;
  /**
   * Every target the board is CURRENTLY WATCHING — the roster's own targets, whether or
   * not they have a problem. This is what separates "this target recovered" from "this
   * target is no longer monitored" when closing a ledger row, and those two must not be
   * confused: `resolveIssue` alerts on the first and stays silent on the second, so
   * closing a de-configured target as "recovered" pages on-call that an outage cleared
   * when it may still be burning.
   *
   * Replaces `/live`'s `deployTargets?: string[]`, which existed so the CLIENT could run
   * its own orphan sweep. The sweep is the server's now; the list stays because the
   * ledger writer needs it.
   */
  monitoredTargets: string[];
}

/** Activity feed window and cap. */
export const ACTIVITY_WINDOW_MS = 24 * 60 * 60 * 1000;
export const MAX_ACTIVITY_ROWS = 300;

/**
 * How many unresolved error groups `readBoardFacts` reads. Matches the limit the fetcher
 * asks GlitchTip for (`glitchtip.ts:83`) and the one `/errors` serves, so the board can
 * never be judging a wider set than either of the other two readers can show.
 */
export const MAX_ERROR_FACTS = 100;

/**
 * A position in the activity feed. The PAIR, not the timestamp alone: a deployment's
 * build and deploy rows share one `createdAtMs`, so a time-only cursor would either
 * re-serve one of them every page or skip it entirely.
 */
export interface ActivityCursor {
  atMs: number;
  id: string;
}

/** One page of activity, oldest-first like the feed itself. */
export interface ActivityPage {
  rows: ActivityRow[];
  /** Where the NEXT (older) page starts, or null when the facts are exhausted. */
  nextCursor: ActivityCursor | null;
}

/**
 * How long an endpoint must stay `degraded` before it becomes a Problem. `down` is
 * NOT debounced — it is unambiguous. Moved here from the client's
 * `activity-store.ts:32`, where every browser tab measured it against its own clock.
 */
export const DEGRADED_CONFIRM_MS = 10 * 60 * 1000;
