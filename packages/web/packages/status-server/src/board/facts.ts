import {
  and, desc, eq, getTableColumns, gte, inArray, isNotNull, isNull, lt, lte, max, ne, not, notInArray, or, sql,
} from "drizzle-orm";
import type { SQL } from "drizzle-orm";
import { cachedSingleFlight } from "@agentic-toolkit/deploy-platform/util";
import { glitchtipConfigured, type StatusConfig } from "../config/port";
import type { Db } from "../libsql/client";
import {
  deployProjectMeta, deployments, errors, issues,
  monitoredEndpoints, monitoredSites, platformHealthState, vercelProdState,
} from "../libsql/schema";
import { combinedStatus, inFlightSql } from "../monitor/deploy-status";
import type { BuildPhase, DeployPhase } from "../monitor/deploy-status";
import { deployIsBad, deployIsResolving } from "../monitor/issue-sources";
import type { IssueSource } from "../monitor/issue-sources";
import { liveVercelProjectNames } from "../monitor/refresh-project-meta";
import { badRunOnsetBySlugSql, latestCheckBySlugSql } from "../storage/health-store";
import type { BadRunOnsetRow, LatestCheckRow } from "../storage/health-store";
import { deriveActivity, pageActivity } from "./derive-activity";
import { monitoredTargets } from "./derive-problems";
import { rosterDeployProjects } from "./ownership";
import { ACTIVITY_WINDOW_MS, MAX_ACTIVITY_ROWS, MAX_ERROR_FACTS } from "./types";
import type {
  ActivityCursor, ActivityPage, BoardFacts, DeployFact, EndpointFact, ErrorFact, IssueEvent, PlatformFact,
  RosterEntry, StaleProdFact,
} from "./types";

/**
 * Rows that will never carry a verdict, whatever happens next. `canceled` is the absence
 * of a verdict (Vercel's Ignored Build Step cancels a build for every site a commit did
 * not touch, so it is the ordinary newest row of a low-churn site), and a lifecycle that
 * expired to `unknown` masks the last real verdict. Judging either would pin a problem
 * open forever or hide a real failure behind a skip. Excluded from BOTH selections below.
 */
const HAS_OUTCOME = and(
  or(isNull(deployments.buildPhase), notInArray(deployments.buildPhase, ["canceled", "unknown"])),
  ne(deployments.deployPhase, "unknown"),
);

/**
 * A row with no build lifecycle AND no deploy entry has nothing to conclude —
 * `combinedStatus` reads `{ buildPhase: null, deployPhase: "none" }` as `building`. It is
 * not caught by `inFlightSql()` (which tests the phase LITERALS), so it is named here
 * explicitly and binned with the in-flight rows. Without this the two SQL pre-filters and
 * `combinedStatus` would disagree about exactly one shape of row.
 */
const NO_LIFECYCLE = sql`(${deployments.buildPhase} is null and ${deployments.deployPhase} = 'none')`;

/**
 * THE two selections behind the deploy state projection, and why there are two.
 *
 * `combinedStatus` partitions a row three ways: a VERDICT (`failed`/`success`), still IN
 * FLIGHT (`building`/`queued`), or no verdict at all (`canceled`/`unknown`). Only a
 * verdict may be judged for `failed`, and only an in-flight row can ever be `stuck` —
 * `deployIsStuck` tests `status === "building"`. Selecting one row per target across BOTH
 * kinds is what produced the regression this pair replaces: a retry's `BUILDING` row won
 * the group, the target looked neither failed nor stuck, and `applyBoardToLedger` read
 * that absence of a verdict as a RECOVERY and paged on-call while production was still
 * serving the broken build.
 *
 * These predicates are a PRE-FILTER, not the vocabulary: `binByOutcome` re-derives the
 * partition from `combinedStatus` itself, so the words have exactly one producer and a
 * row either predicate mis-bins still lands where `combinedStatus` says.
 */
const CONCLUDED = and(HAS_OUTCOME, not(sql.raw(inFlightSql())), not(NO_LIFECYCLE));
const IN_FLIGHT = and(HAS_OUTCOME, or(sql.raw(inFlightSql()), NO_LIFECYCLE));

/**
 * `isRealEnvDeployRow` (`monitor/deploy-view.ts`) spelled for the planner — a Vercel row
 * with no environment target is a PREVIEW/branch build, not a deployment of any live
 * environment. Applied only to the ACTIVITY read, where it is a budget question (see
 * below); the fold still runs the TypeScript predicate as its gate, so the two cannot
 * drift into disagreeing about what a preview is — one rejects rows early, the other
 * decides. Deliberately raw `'vercel'` rather than a canonical form: that is exactly what
 * `isRealEnvDeployRow` tests, and `deployments.platform` holds the provider's own word.
 */
const NOT_PREVIEW = sql`not (${deployments.platform} = 'vercel' and (${deployments.environment} is null or ${deployments.environment} = ''))`;

/** The raw platform spellings each canonical platform can appear under in `deployments`. */
const PLATFORM_SPELLINGS: [canon: string, raw: string[]][] = [
  ["vercel", ["vercel"]],
  ["railway", ["railway"]],
  ["cloudflare", ["cloudflare", "cloudflare-pages"]],
];

/**
 * `ownsDeployProject` spelled for the planner: a SQL PRE-FILTER that narrows a LIMITed
 * window of `deployments` to rows some live site monitors. Not an optimisation — `sync`
 * upserts a row for EVERY project the tokens can see (145+ Vercel projects, most monitored
 * by no site), so a limit spent before this narrowing yields a handful of owned rows and
 * can strand the newest event for an owned target outside the window entirely.
 *
 * Deliberately a SUPERSET, not the rule: it matches EITHER spelling of a monitored
 * project's identity (provider id or name), because a row written before a rename carries
 * the old name and one written after carries the new one, and both belong to the same
 * monitored project. The authoritative gate stays in TypeScript and runs afterwards —
 * `ownsDeployProject` for the Deployments tab (which must also judge the webhook-buffer
 * overlay, and that never passes through SQL at all), `ownedDeployTarget` for the fold.
 * Whatever the two disagree about, the JS rule wins.
 *
 * Exported because the Activity read below and `routes/reads.ts` both need it, and two
 * spellings of the ownership rule in SQL is the same defect as two spellings of it in
 * TypeScript.
 */
export function ownedDeploysWhere(projects: Map<string, { ids: Set<string>; names: Set<string> }>): SQL | undefined {
  // Crunchy clusters aren't site-bound and are always shown — see `ownsDeployProject`.
  const clauses: SQL[] = [eq(deployments.platform, "crunchy")];
  for (const [canon, raw] of PLATFORM_SPELLINGS) {
    const bucket = projects.get(canon);
    if (!bucket) continue;
    const spellings = [
      bucket.names.size > 0 ? inArray(deployments.projectName, [...bucket.names]) : undefined,
      bucket.ids.size > 0 ? inArray(deployments.providerProjectId, [...bucket.ids]) : undefined,
    ].filter((c): c is SQL => c !== undefined);
    if (spellings.length === 0) continue;
    const clause = and(inArray(deployments.platform, raw), or(...spellings));
    if (clause) clauses.push(clause);
  }
  return or(...clauses);
}

/**
 * Split the two selections by what `combinedStatus` says, so the SQL above can only ever
 * decide which rows are worth READING and never what they mean. `canceled`/`unknown` rows
 * fall out of both lists: they are the absence of a verdict, and the board claims nothing
 * from an absence.
 */
function binByOutcome(rows: DeployFact[]): { concluded: DeployFact[]; inFlight: DeployFact[] } {
  const concluded: DeployFact[] = [];
  const inFlight: DeployFact[] = [];
  for (const f of rows) {
    const status = combinedStatus({ buildPhase: f.buildPhase, deployPhase: f.deployPhase });
    // `deployIsBad` and `deployIsResolving` ARE the verdict vocabulary — the same pair
    // `derive-problems.ts` judges with, imported from `monitor/issue-sources.ts` rather
    // than respelled here, so the binning and the judging cannot drift apart.
    if (deployIsBad(status) || deployIsResolving(status)) concluded.push(f);
    // The two statuses that can still change. `building` is the only one `deployIsStuck`
    // can ever judge; `queued` is deliberately never stuck (an intentional hold).
    else if (status === "building" || status === "queued") inFlight.push(f);
  }
  return { concluded, inFlight };
}

/**
 * One deployment row → one fact. Shared by `deploys` and `inFlightDeploys` (the state
 * projection the Problem rules judge) and `deployEvents` (every row in the window,
 * recorded by the Activity feed): different selections of the same rows, so the
 * translation is one piece of knowledge and lives in one place.
 */
function toDeployFact(d: typeof deployments.$inferSelect): DeployFact {
  return {
    deploymentId: d.id,
    platform: d.platform,
    providerProjectId: d.providerProjectId,
    projectName: d.projectName,
    environment: d.environment,
    // The tier signal. Carried raw; `deployEnv` (via `ownedDeployTarget`) is the only
    // thing that interprets it, so the fact stays a transcription of the row.
    branch: d.branch,
    buildPhase: d.buildPhase as BuildPhase | null,
    deployPhase: d.deployPhase as DeployPhase,
    createdAtMs: d.createdAt.getTime(),
    commitHash: d.commitHash,
    commitMessage: d.commitMessage,
    commitRepo: d.commitRepo,
    errorText: d.errorText,
    sourceUrl: d.url,
    liveUrl: d.liveHost ? `https://${d.liveHost}` : null,
  };
}

/**
 * One `issues` row → one `IssueEvent`. Shared by `readBoardFacts`' windowed read and
 * `readActivityPage`'s paged one: different selections of the same rows, so the
 * translation is one piece of knowledge and lives in one place — exactly the reason
 * `toDeployFact` above exists.
 */
function toIssueEvent(r: typeof issues.$inferSelect): IssueEvent {
  return {
    id: r.id,
    target: r.target,
    source: r.source as IssueSource,
    name: r.name,
    environment: r.environment,
    state: r.state,
    // The pane paints tone from severity, exactly as `issueToRow` did — a `minor` row is
    // amber, not red. Carrying it is reading a column, not re-deriving a judgement.
    severity: r.severity as IssueEvent["severity"],
    detail: r.detail,
    sourceUrl: r.sourceUrl,
    liveUrl: r.liveUrl,
    commitHash: r.commitHash,
    commitMessage: r.commitMessage,
    commitRepo: r.commitRepo,
    openedAtMs: r.openedAt.getTime(),
    resolvedAtMs: r.resolvedAt?.getTime() ?? null,
    // Anything other than the two known words is unknown, and unknown claims nothing.
    resolvedReason:
      r.resolvedReason === "recovered" || r.resolvedReason === "unmonitored" ? r.resolvedReason : null,
  };
}

/**
 * THE roster read: every monitored endpoint with the columns ownership is resolved from.
 *
 * Exported because the fold is no longer its only consumer — the webhook door, the
 * Deployments tab and the live-host stamp resolve ownership through `src/board/ownership.ts`
 * against this same roster (fix 0.3). They used to read their own narrower projections
 * (`listActiveEndpointWiring`, `listActiveEndpoints` — the first now deleted) and gated by
 * project NAME, which is how three surfaces came to disagree with the board about which
 * deploy targets exist.
 *
 * Deliberately UNFILTERED on `isActive` / `monitorDeploys`: the switches are read by
 * `rosterTargets` (Requirement A) and by `endpointProblems`, which need different subsets
 * of the same rows. Filtering here would give each caller a different roster.
 */
export async function readRoster(db: Db): Promise<RosterEntry[]> {
  return await db
    .select({
      endpointId: monitoredEndpoints.id,
      label: monitoredSites.name,
      platform: monitoredEndpoints.platform,
      projectName: monitoredEndpoints.deployProject,
      providerProjectId: monitoredEndpoints.deployProjectId,
      environment: monitoredEndpoints.environment,
      isActive: monitoredEndpoints.isActive,
      monitorHttp: monitoredEndpoints.monitorHttp,
      monitorDeploys: monitoredEndpoints.monitorDeploys,
      // A REAL, already-shipped column (`schema.ts:193`) — the operator's opt-out from
      // deploy-project wiring. `ownsDeploys` (`board/ownership.ts`) honours it for every
      // deploy surface at once, so hardcoding `false` here would make the roster disagree
      // with the operator's own switch the moment anyone sets it.
      ignoreProjectWarning: monitoredEndpoints.ignoreProjectWarning,
      url: monitoredEndpoints.url,
    })
    .from(monitoredEndpoints)
    .innerJoin(monitoredSites, eq(monitoredEndpoints.siteId, monitoredSites.id));
}

/**
 * Read every fact the board needs, and nothing else. THE ONLY FILE IN src/board/ THAT
 * TOUCHES DRIZZLE — keeping the fold pure is what makes the regression suite cheap.
 */
export async function readBoardFacts(db: Db, nowMs: number, config: StatusConfig): Promise<BoardFacts> {
  const roster = await readRoster(db);

  // The latest CONCLUDED row, and separately the latest IN-FLIGHT row, per deploy
  // *identity spelling*. `max(createdAt)` alongside the bare columns is SQLite's
  // documented bare-column rule: in a query whose only aggregate is a single min/max, the
  // non-aggregated columns come from the row that supplied the extreme. That is a
  // guarantee, not an accident, and it is why this is two queries instead of the window
  // functions libSQL would also accept but Drizzle spells worse. `_latest` is never read —
  // it exists to make the aggregate the one SQLite resolves.
  //
  // This `groupBy` is a cheap PRE-reduction keyed on the row's own columns, NOT the
  // board's identity: it cannot see that `providerProjectId` and `projectName` are two
  // spellings of one project, so a rename or a late id adoption still yields two groups
  // for one target. The AUTHORITATIVE per-target collapse is the fold's
  // (`derive-problems.ts`), which resolves each fact to a board target first and then
  // keeps the newest per target. This query only shrinks what the fold has to read.
  //
  // The grouping keeps `environment` in the key, so a Vercel PREVIEW row (environment
  // null/"") lands in its own group and can never displace the production row for the
  // same project. `deployProblems` then drops the preview group via `isRealEnvDeployRow`.
  const concludedRows = await db
    .select({ ...getTableColumns(deployments), _latest: max(deployments.createdAt) })
    .from(deployments)
    .where(CONCLUDED)
    .groupBy(deployments.platform, deployments.projectName, deployments.environment);

  const inFlightRows = await db
    .select({ ...getTableColumns(deployments), _latest: max(deployments.createdAt) })
    .from(deployments)
    .where(IN_FLIGHT)
    .groupBy(deployments.platform, deployments.projectName, deployments.environment);

  const { concluded: deploys, inFlight: inFlightDeploys } = binByOutcome([
    ...concludedRows.map(toDeployFact),
    ...inFlightRows.map(toDeployFact),
  ]);

  // EVERY deployment inside the activity window, ungrouped and NOT filtered by
  // `HAS_OUTCOME`. `deploys` above is the state projection the Problem rules judge; this is
  // the LOG the Activity feed records. The two differ on purpose:
  //   - ungrouped, because a site that deployed six times today has six events and one
  //     current state, and collapsing them is how Activity became a projection twice
  //     (regressions 18199fb82 and c40b87542);
  //   - unfiltered, because `HAS_OUTCOME` exists to stop a `canceled` row masking a
  //     verdict — a Problems concern only. A canceled build is a real thing that
  //     happened, and the feed has always shown it.
  //
  // The limit is NOT a free budget. `deriveActivity` drops every row `ownedDeployTarget`
  // rejects — every Vercel PREVIEW build (persisted with a null environment by
  // `fetch-vercel.ts`) and every project no live roster entry owns — and then expands the
  // survivors into up to TWO rows each. Spending the 300 on rows the fold will certainly
  // reject is how a fleet-wide push (~48 projects fanning out, plus PR previews) empties
  // the feed's deploy half exactly when the most is happening, while `facts.deploys`
  // (unlimited) keeps reporting failures the feed shows nothing about — the `c40b87542`
  // symptom through a different door.
  //
  // So BOTH certain rejections are applied HERE, in SQL, BEFORE the limit. The preview half
  // alone was not enough: `sync` upserts a row for every project the tokens can see, and
  // the unmonitored ones outnumber the monitored ones roughly 3:1, so 300 rows of "newest
  // deployments anywhere" still reduced to a near-empty feed on a busy day. Neither
  // predicate is the gate — `isRealEnvDeployRow` and `ownsDeployProject` stay the fold's,
  // in TypeScript. These are the same rules spelled for the planner.
  const eventRows = await db
    .select()
    .from(deployments)
    .where(and(
      gte(deployments.createdAt, new Date(nowMs - ACTIVITY_WINDOW_MS)),
      NOT_PREVIEW,
      ownedDeploysWhere(rosterDeployProjects(roster)),
    ))
    .orderBy(desc(deployments.createdAt))
    .limit(MAX_ACTIVITY_ROWS);

  const deployEvents: DeployFact[] = eventRows.map(toDeployFact);

  // Issues that opened OR closed inside the window. Both halves are events, and an issue
  // can contribute one row, two, or none depending on where its two timestamps fall.
  //
  // Bounded like `deployEvents` — this read runs per request on several uncached routes
  // (/live, /snapshot, /fleet, /badge, GET /board, every SSE publish), and an incident
  // that opens thousands of rows in a day is exactly when nobody can afford the board to
  // get slower. Ordered by the LATER of the two timestamps so the newest events are the
  // ones that survive the cut: an issue that opened yesterday and closed a minute ago is
  // fresher than one that opened this morning and is still open.
  const issueEvents: IssueEvent[] = (
    await db
      .select()
      .from(issues)
      .where(
        or(
          gte(issues.openedAt, new Date(nowMs - ACTIVITY_WINDOW_MS)),
          gte(issues.resolvedAt, new Date(nowMs - ACTIVITY_WINDOW_MS)),
        ),
      )
      .orderBy(desc(sql`max(${issues.openedAt}, coalesce(${issues.resolvedAt}, 0))`))
      .limit(MAX_ACTIVITY_ROWS)
  ).map(toIssueEvent);

  const ledger = (
    await db.select({ target: issues.target, openedAt: issues.openedAt }).from(issues).where(isNull(issues.resolvedAt))
  ).map((r) => ({ target: r.target, openedAtMs: r.openedAt.getTime() }));

  const platforms: PlatformFact[] = (await db.select().from(platformHealthState)).map((p) => ({
    source: p.source as IssueSource,
    configured: p.configured,
    ok: p.reachable,
    streak: p.consecutiveFailures,
    // WHEN this row was written, not what it says. `recordPlatformObservations` stamps it
    // every cycle, so it is the one fact that proves the monitor is still running.
    sampledAtMs: p.updatedAt.getTime(),
  }));

  // Only the STALE rows are facts the fold needs; a healthy project contributes nothing.
  // `environment` is deliberately NULL here: `vercelProdState` judges each project's
  // PRODUCTION PROMOTION in Vercel's sense, which is a different thing from the logical
  // environment the project serves — `hub-help-testing`'s Vercel production is our
  // testing tier. The table cannot tell them apart, so it says nothing and
  // `staleProdProblems` derives the logical env via `deployEnv`.
  // Writing "production" here would make every stale testing project claim to be a
  // production incident, which is shipped fix #9 undone.
  //
  // The LEFT join supplies what it derives that env FROM: the project's configured
  // production branch. Left, not inner — a project with no meta row yet (never polled, or
  // polled before the mirror existed) must still contribute its staleness, with a null
  // branch that falls back to the name rule, rather than vanish from the board.
  // `deploy_project_meta` is unique on (platform, project_name), so this cannot fan a
  // stale row out into several.
  const staleProd: StaleProdFact[] = (
    await db
      .select({ s: getTableColumns(vercelProdState), branch: deployProjectMeta.gitBranch })
      .from(vercelProdState)
      .leftJoin(
        deployProjectMeta,
        and(
          eq(deployProjectMeta.platform, "vercel"),
          eq(deployProjectMeta.projectName, vercelProdState.projectName),
        ),
      )
      .where(eq(vercelProdState.stale, true))
  ).map(({ s, branch }) => ({
    platform: "vercel",
    // No id: `vercel_prod_state` is keyed on the project NAME (it has no id column), so a
    // stale-prod fact can only be name-identified. A rename self-heals here anyway —
    // `dropVanishedVercelProjects` narrows against the live project list every poll.
    providerProjectId: null,
    projectName: s.projectName,
    environment: null,
    branch,
    detail: s.detail,
    sourceUrl: s.sourceUrl,
    liveUrl: s.liveUrl,
  }));

  // The projects that still exist upstream, from the mirror the cycle reconciles. EMPTY
  // means "we have never completed an authenticated read", not "everything was deleted" —
  // `dropVanishedVercelProjects` refuses to narrow on an empty set, so an unpopulated
  // mirror silences nothing. A read that failed leaves yesterday's rows in place, which
  // errs toward keeping problems visible; that is the safe direction.
  //
  // Reads via `liveVercelProjectNames` (`refresh-project-meta.ts:172`) rather than
  // re-spelling the query a second time: that module has no import cycle with `facts.ts`
  // (`monitor/` never imports `board/`), so there is no justification for a second copy of
  // the same SELECT.
  const liveVercelProjects = [...(await liveVercelProjectNames(db))];

  // The unresolved error groups, and separately EVERY project the table has ever held.
  //
  // Bounded and index-served. `readBoardFacts` runs on /live, /snapshot, /fleet, /badge,
  // GET /board and every SSE publish, so an unbounded read here would be paid on all of
  // them; `idx_error_last_seen` orders it and the limit caps it at the same 100 the
  // errors read route serves. Ordering newest-activity-first is what makes the cap safe
  // for the fold's recency rule specifically: the rows the limit sheds are the STALEST,
  // which are exactly the ones `errorProblems` would have discarded anyway.
  //
  // The `resolved = false` narrowing is a FACT-level filter, not the verdict — the same
  // split `staleProd` makes by selecting `stale = true` in SQL. What counts as bad enough
  // to be a Problem (level, recency) stays in the fold, in one place, where a test can
  // drive it.
  const errorRows = await db
    .select()
    .from(errors)
    .where(eq(errors.resolved, false))
    // `issueKey` breaks the tie, and it is not cosmetic. `last_seen` is stored at
    // SECOND resolution, so a burst writes dozens of rows sharing one value and SQLite may
    // return them in any order — which 100 rows survive the cap would then differ between
    // two reads of an unchanged database. `errorProblems` computes severity, detail and the
    // top-five block over exactly that set, so an unstable window flips a problem between
    // major and minor with nothing changing upstream, rewriting the ledger row and
    // repainting every SSE subscriber each cycle. `uniq_error_issue` makes the order total.
    .orderBy(desc(errors.lastSeen), desc(errors.issueKey))
    .limit(MAX_ERROR_FACTS);

  const errorFacts: ErrorFact[] = errorRows.map((r) => ({
    issueKey: r.issueKey,
    project: r.project,
    title: r.title,
    culprit: r.culprit,
    level: r.level,
    count: r.count,
    userCount: r.userCount,
    firstSeenMs: r.firstSeen?.getTime() ?? null,
    lastSeenMs: r.lastSeen?.getTime() ?? null,
    permalink: r.permalink,
  }));

  return {
    roster,
    // The monitor's own cadence, read HERE because the fold is pure and `config` is IO.
    // It rides the board so the client's freshness windows are scaled by the same number
    // the monitor actually probes at, from the same read they are judging.
    probeIntervalMs: config.probeIntervalSeconds * 1000,
    deploys,
    inFlightDeploys,
    deployEvents,
    // Driven from the ACTIVE roster, never from `health_checks` itself: an unpredicated
    // read of that table costs the whole retained history (1M–6M rows) on every board
    // read, and every row it returns for a retired endpoint is discarded by the roster
    // gate anyway. `monitorHttp` is deliberately NOT applied here — that switch is
    // `endpointProblems`' verdict gate, and narrowing the FACTS by it would also hide
    // the endpoint's observation timestamp from anything that measures freshness.
    endpoints: await readEndpointFacts(
      db,
      roster.filter((e) => e.isActive).map((e) => e.endpointId),
    ),
    platforms,
    staleProd,
    ledger,
    issueEvents,
    liveVercelProjects,
    errors: errorFacts,
    errorsConfigured: glitchtipConfigured(config),
    errorProjectAllowlist: config.glitchtipProjects,
  };
}

/**
 * One paged source read, with the tie group its LIMIT cut through completed.
 *
 * Every timestamp these tables store is a whole unix SECOND (drizzle `mode: "timestamp"`),
 * so ties are pervasive and `ORDER BY ts DESC LIMIT n` routinely stops in the MIDDLE of a
 * second, in whatever order the planner happened to emit. A page that reported that second
 * as its floor would be claiming to have read completely an instant it read only partly,
 * and the unread remainder would be stranded: it is older than the page's own next cursor
 * and newer than every cursor after it, so no page would ever ask for it again.
 *
 * So: when the limit was filled, re-read the boundary instant WITHOUT a limit and splice it
 * in. The extra query costs one second's worth of rows and buys the invariant everything
 * downstream assumes — `floorMs` is an instant read COMPLETELY, and the fold may emit
 * every row at or above it.
 */
async function readSourcePage<T>(spec: {
  limit: number;
  page: T[];
  tsOf: (row: T) => number;
  readInstant: (ms: number) => Promise<T[]>;
}): Promise<{ rows: T[]; floorMs: number | null }> {
  const { limit, page, tsOf, readInstant } = spec;
  if (page.length < limit) return { rows: page, floorMs: null };
  const boundary = tsOf(page[page.length - 1]!);
  const complete = await readInstant(boundary);
  return { rows: [...page.filter((r) => tsOf(r) > boundary), ...complete], floorMs: boundary };
}

/**
 * One PAGE of the activity feed, ending strictly before `cursor` — the cold path behind
 * `GET /activity`, deliberately NOT part of `readBoardFacts`.
 *
 * `readBoardFacts` runs on `/live`, `/snapshot`, `/fleet`, `/badge`, `GET /board` and every
 * SSE publish. Threading a cursor through it would put a rarely-used parameter on the
 * most-executed query in the service, so this reader sits beside it and is reached only
 * when a human scrolls.
 *
 * It reuses `readBoardFacts` for everything except the two event lists, then overrides
 * those. `deriveActivity` gates issue rows through `monitoredTargets`, which reads the
 * roster, the platform rows and BOTH deploy state lists — re-deriving a narrower version
 * of that here would be a second spelling of the ownership rule, which is exactly what
 * `src/board/` exists to prevent. One extra board-facts read per scrolled page is the
 * price, on a path no automated caller touches.
 */
export async function readActivityPage(
  db: Db,
  nowMs: number,
  config: StatusConfig,
  opts: { cursor: ActivityCursor | null; limit: number; base?: BoardFacts },
): Promise<ActivityPage> {
  const { cursor, limit } = opts;
  // `base` is injectable so a burst of pages can share ONE board-facts read — see
  // `createActivityPageReader`, which is how the route calls this. Without it, a reader
  // scrolling back pays the full `readBoardFacts` (two unbounded GROUP BY scans among it)
  // once per page, and the client fires up to five back-to-back on its own.
  const base = opts.base ?? (await readBoardFacts(db, nowMs, config));

  // `<=`, not `<`: the cursor is a (time, id) PAIR, and a row sharing the cursor's
  // timestamp may still sort before it. SQL narrows by time only and `pageActivity`
  // applies the exact pair comparison.
  //
  // The one exception is the EMPTY-ID sentinel a stalled page mints (`pageActivity`'s
  // empty branch): no real row id is empty, so `r.id < ""` is false for every row at that
  // instant and the pair comparison excludes the whole second. Reading it back would burn
  // the page's limit on rows that cannot survive the filter — and, when the second is
  // over-full, would return the same rows forever. `<` in SQL matches what the sentinel
  // already means and makes progress unconditional.
  const beforeMs = cursor?.atMs ?? null;
  const tsBefore = (
    col: typeof deployments.createdAt | typeof issues.openedAt | typeof issues.resolvedAt,
  ): SQL | undefined => {
    if (beforeMs == null) return undefined;
    const before = new Date(beforeMs);
    return cursor!.id === "" ? lt(col, before) : lte(col, before);
  };

  const deployOwnership = and(NOT_PREVIEW, ownedDeploysWhere(rosterDeployProjects(base.roster)));
  const eventRead = await readSourcePage({
    limit,
    page: await db
      .select()
      .from(deployments)
      .where(and(tsBefore(deployments.createdAt), deployOwnership))
      .orderBy(desc(deployments.createdAt))
      .limit(limit),
    tsOf: (r) => r.createdAt.getTime(),
    readInstant: (ms) =>
      db
        .select()
        .from(deployments)
        .where(and(eq(deployments.createdAt, new Date(ms)), deployOwnership)),
  });

  // The issue reads carry the SAME ownership narrowing the deploy read does, for the same
  // reason: `issues` is a LEDGER, it retains rows for targets the roster no longer
  // watches, and `deriveActivity` drops every one of them. Without this predicate a
  // stretch of history dominated by de-configured targets fills all three limits, derives
  // nothing, and costs the reader a whole round trip per page-floor of crawling.
  //
  // `monitoredTargets` reads the roster, the platform rows and both deploy-state lists —
  // none of which this function overrides — so it is the SAME set `deriveActivity` will
  // gate on, not a second spelling of it.
  // An empty roster watches nothing, so no issue row could survive the fold either way —
  // spelled out rather than left to `inArray`'s empty-list behaviour.
  const watched = monitoredTargets(base);
  const issueOwnership: SQL = watched.length > 0 ? inArray(issues.target, watched) : sql`0`;

  // The OR in `readBoardFacts`' issue read is not sargable and its expression ORDER BY
  // defeats both legs. Split into two INDEXED reads (idx_issue_opened, idx_issue_resolved)
  // and merge here: over 90 days of history the planner's choice is the difference between
  // a seek and a growing full scan.
  const openedRead = await readSourcePage({
    limit,
    page: await db
      .select()
      .from(issues)
      .where(and(tsBefore(issues.openedAt), issueOwnership))
      .orderBy(desc(issues.openedAt))
      .limit(limit),
    tsOf: (r) => r.openedAt.getTime(),
    readInstant: (ms) =>
      db
        .select()
        .from(issues)
        .where(and(eq(issues.openedAt, new Date(ms)), issueOwnership)),
  });
  const resolvedRead = await readSourcePage({
    limit,
    page: await db
      .select()
      .from(issues)
      .where(and(isNotNull(issues.resolvedAt), tsBefore(issues.resolvedAt), issueOwnership))
      .orderBy(desc(issues.resolvedAt))
      .limit(limit),
    tsOf: (r) => r.resolvedAt!.getTime(),
    readInstant: (ms) =>
      db
        .select()
        .from(issues)
        .where(and(eq(issues.resolvedAt, new Date(ms)), issueOwnership)),
  });

  const byId = new Map<number, typeof issues.$inferSelect>();
  for (const r of [...openedRead.rows, ...resolvedRead.rows]) byId.set(r.id, r);

  // A source that returned fewer rows than it was asked for has provably nothing older.
  // ALL THREE must be exhausted before the feed may claim the end of history.
  //
  // Each source that DID fill its limit stopped somewhere, and `readSourcePage` has
  // already re-read that instant in full, so its floor is an instant read COMPLETELY. The
  // NEWEST of the three is the oldest instant this PAGE read completely: below it some
  // source still has unread rows. It becomes the fold's floor (nothing partial is
  // derived — every row at or above it is present) and the pager's step-back target (a
  // page that keeps nothing resumes exactly there instead of crawling).
  const floors = [eventRead.floorMs, openedRead.floorMs, resolvedRead.floorMs].filter(
    (f): f is number => f != null,
  );
  const floorMs = floors.length > 0 ? Math.max(...floors) : null;
  const sourcesExhausted = floorMs == null;

  const pageFacts: BoardFacts = {
    ...base,
    deployEvents: eventRead.rows.map(toDeployFact),
    issueEvents: [...byId.values()].map(toIssueEvent),
  };

  // The cursor query already chose the window, so the fold must not apply the board's 24h
  // floor on top of it — and must not apply the board's row CAP either: that cap sheds the
  // OLDEST candidates, which on this path are the ones the reader is scrolling towards.
  // The input is already bounded by the three SQL limits above.
  const derived = deriveActivity(pageFacts, nowMs, undefined, undefined, floorMs ?? 0, Infinity);
  return pageActivity(derived, cursor, limit, sourcesExhausted, floorMs);
}

/** How long a scrolled page may reuse the previous page's board facts. */
const ACTIVITY_BASE_FACTS_CACHE_MS = 5_000;

/**
 * `readActivityPage` bound to ONE short-lived board-facts cache.
 *
 * The base facts (roster, platforms, both deploy-state lists) decide OWNERSHIP, and
 * ownership does not change between two pages a reader scrolls through seconds apart —
 * but re-reading it does, at the cost of the most expensive query shape in the service.
 * Per-instance, created inside the route factory, so tests and parallel app instances
 * don't share state through a module-level singleton (the same rule `cachedSingleFlight`'s
 * own docs state, and the same way `/public/status-summary` uses it).
 */
export function createActivityPageReader(
  db: Db,
  config: StatusConfig,
): (nowMs: number, opts: { cursor: ActivityCursor | null; limit: number }) => Promise<ActivityPage> {
  const cachedBase = cachedSingleFlight(ACTIVITY_BASE_FACTS_CACHE_MS, () => readBoardFacts(db, Date.now(), config));
  return async (nowMs, opts) => readActivityPage(db, nowMs, config, { ...opts, base: await cachedBase() });
}

/**
 * The newest probe per endpoint, plus the onset of its current bad run read from the
 * persisted history — so "down since" is server truth that survives a browser reload,
 * and the degraded debounce is measured against it.
 *
 * Reads through `latestCheckBySlugSql`, the SAME statement `/live` uses, for two reasons
 * that were separately load-bearing:
 *
 *  - COST. The previous form (`max(checked_at)` grouped by slug, unpredicated) planned as
 *    `SCAN health_checks` — every retained row, on every board read, SSE publish and
 *    unauthenticated summary. That is the exact read `routes/reads.ts` was rewritten to
 *    kill, reintroduced past its own regression guard, which is bound to the statement
 *    rather than to the table.
 *  - AGREEMENT. `checked_at` is whole seconds, and the bare-column rule SQLite resolves a
 *    grouped `max()` with is documented as arbitrary among ties. Two probes in the same
 *    second let `/live` and the board pick different rows and publish different verdicts
 *    for one endpoint in one request. One statement, one `checked_at desc, id desc`.
 */
async function readEndpointFacts(db: Db, slugs: string[]): Promise<EndpointFact[]> {
  // `serviceSlug` IS the endpoint id — sync.ts:296 writes `serviceSlug: r.slug` and
  // config-store.ts:162 deletes these rows by endpoint id. There is no endpointId column.
  if (slugs.length === 0) return [];
  const latest = await db.all<LatestCheckRow>(latestCheckBySlugSql(slugs));

  const isBad = (status: string) => status === "down" || status === "degraded";
  // ONE onset query for every bad endpoint at once. This used to be a sequentially-awaited
  // query PER bad endpoint, so the cost scaled with the size of the outage — worst exactly
  // when the board matters most, and paid again on every SSE publish. Skipped entirely when
  // nothing is bad, which is the ordinary case.
  const badSlugs = latest.filter((h) => isBad(h.status)).map((h) => h.service_slug);
  const onsetSec = new Map<string, number>();
  if (badSlugs.length > 0) {
    for (const r of await db.all<BadRunOnsetRow>(badRunOnsetBySlugSql(badSlugs))) {
      if (r.since != null) onsetSec.set(r.service_slug, Number(r.since));
    }
  }

  return latest.map((h) => {
    // Epoch SECONDS out of raw SQL (drizzle's timestamp mode), not a Date.
    const checkedAtMs = h.checked_at * 1000;
    const since = onsetSec.get(h.service_slug);
    return {
      endpointId: h.service_slug,
      status: h.status as EndpointFact["status"],
      statusCode: h.status_code,
      dnsOk: !!h.dns_ok,
      checkedAtMs,
      // A bad endpoint the onset query returned nothing for falls back to this check's own
      // timestamp — the run started now as far as anything we can see goes.
      badSinceMs: isBad(h.status) ? (since != null ? since * 1000 : checkedAtMs) : null,
    };
  });
}
