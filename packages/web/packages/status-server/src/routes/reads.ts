import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { and, desc, eq, gte, sql } from 'drizzle-orm';
import type { Db } from '../libsql/client';
import type { Tier } from '../middleware/auth';
import {
  healthChecks,
  deployments as deploymentsTable,
} from '../libsql/schema';
import {
  deriveBoard, matchRosterEntry, ownedDeploysWhere, ownsDeployProject, parseErrorsTarget, parsePlatformHealthTarget,
  readBoardFacts, readRoster, rosterDeployProjects, rosterTargets,
  type DeployIdentity, type Problem,
} from '../board';
import {
  listActiveEndpoints,
  listEndpoints,
  listIgnoredProjects,
  type ConfiguredEndpoint,
} from '../storage/config-store';
import { latestCheckBySlugSql, type LatestCheckRow } from '../storage/health-store';
import { computeOverall, publicOverall, type OverallStatus } from '../monitor/overall';
import type { HealthStatus } from '../monitor/health';
import type { BuildPhase, DeployPhase } from '../monitor/deploy-status';
import { deployEventsSince } from '../monitor/live-buffer';
import { providerDeployToDTO, type ProviderDeploy } from '../monitor/provider-deploy';
import { deployTargetKey, platformCanon } from '../monitor/overview';
import { envFromProject } from '../monitor/deploy-view';
import { hostOf } from '../monitor/url';
import type { StatusConfig } from '../config/port';
import { siteLinks, type PlatformMeta } from '../lib/links';
import { cachedSingleFlight } from '@agentic-toolkit/deploy-platform/util';
import { providerConnFromConfig } from '@agentic-toolkit/deploy-platform/conn';
import {
  refreshVercelProjectMetaFromConfig,
  liveVercelProjectNames,
  type VercelRefreshResult,
} from '../monitor/refresh-project-meta';
import { enumerateDeployProjects, enumerateDeployProjectsVerified, type EnumeratedProject } from '@agentic-toolkit/deploy-platform/enumerate';
import { partitionPending, endpointUnconfigured } from '@agentic-toolkit/deploy-platform/engine';
import { uptimePercent, dayStatus, type Counts } from '../monitor/uptime';
import { runIntegrationsCheck } from '../monitor/integrations';
import type {
  LiveSnapshot,
  LiveServiceDTO,
  StaleProdDTO,
  ProviderKey,
} from '../monitor/live-types';
import type {
  ServiceStatusDTO,
  DeploymentDTO,
  UptimeResponse,
  UptimeService,
} from '../monitor/types';

// ---------------------------------------------------------------------------
// The READ API — cheap DB reads of the last monitoring cycle's state. The
// in-process timer (runCycle) does ALL the probing/provider polling and PERSISTS
// the results; these handlers never re-poll providers. They reshape the persisted
// rows into the same DTOs the standalone status site's Next routes returned, so
// the existing frontend renders unchanged.
//
//   /live              full LiveSnapshot (parity contract) — from DB + live-buffer
//   /status            overall + per-service summary
//   /snapshot          compact per-monitor unit the fleet consumes (buildSnapshot)
//   /history           one endpoint's recent checks
//   /uptime            per-endpoint daily uptime
//   /response-history  portfolio-wide response-time sparkline
//   /deploy-projects   the deploy projects you can wire an endpoint to
//   /integrations      provider reachability + stats freshness
// ---------------------------------------------------------------------------

const MAX_DEPLOYS = 250;
const RESPONSE_BUCKETS = 60;

/** The latest health-check row for each requested (active) endpoint slug, keyed by
 *  slug. Slugs with no recorded checks are simply absent (callers render 'unknown').
 *  `dnsOk` rides along unused by most callers — `buildLiveSnapshot` is the one that
 *  reads it, as the fallback for an endpoint the Problem fold has no opinion about.
 *
 *  The statement itself lives in `storage/health-store.ts` because the BOARD reads the
 *  same thing (`readEndpointFacts`); two spellings of "the newest probe" is how `/live`
 *  came to disagree with the board about a same-second tie. */
async function latestCheckBySlug(
  db: Db,
  slugs: string[],
): Promise<Map<string, { status: HealthStatus | 'unknown'; responseTimeMs: number | null; statusCode: number | null; error: string | null; checkedAt: Date; dnsOk: boolean }>> {
  if (slugs.length === 0) return new Map();
  const rows = await db.all<LatestCheckRow>(latestCheckBySlugSql(slugs));
  const map = new Map<
    string,
    { status: HealthStatus | 'unknown'; responseTimeMs: number | null; statusCode: number | null; error: string | null; checkedAt: Date; dnsOk: boolean }
  >();
  for (const r of rows) {
    map.set(r.service_slug, {
      status: r.status as HealthStatus,
      responseTimeMs: r.response_time_ms,
      statusCode: r.status_code,
      error: r.error,
      checkedAt: new Date(r.checked_at * 1000),
      dnsOk: !!r.dns_ok,
    });
  }
  return map;
}

/** The newest checked_at across ALL history (one MAX index seek on
 *  idx_health_checked). The poller's "last ran" clock must read the whole table,
 *  NOT the active-slug map: during an endpoint-roster swap the active slugs may
 *  have no rows yet, and retired slugs' rows are exactly the evidence of when the
 *  poller last completed — a map-derived clock reads "fresh" while it is wedged. */
async function newestCheckAt(db: Db): Promise<Date | null> {
  const rows = await db.all<{ last: number | null }>(sql`select max(checked_at) as last from health_checks`);
  const last = rows[0]?.last;
  return last == null ? null : new Date(Number(last) * 1000);
}

/** A ServiceStatusDTO per active endpoint, from its config + latest check. */
function serviceDtos(
  endpoints: ConfiguredEndpoint[],
  latest: Awaited<ReturnType<typeof latestCheckBySlug>>,
): ServiceStatusDTO[] {
  return endpoints.map((ep): ServiceStatusDTO => {
    const c = latest.get(ep.slug);
    return {
      slug: ep.slug,
      group: ep.group,
      name: ep.name,
      url: ep.url,
      environment: ep.environment ?? '',
      platform: ep.platform,
      deployProject: ep.deployProject,
      status: c?.status ?? 'unknown',
      responseTimeMs: c?.responseTimeMs ?? null,
      statusCode: c?.statusCode ?? null,
      error: c?.error ?? null,
      lastCheckedAt: c ? c.checkedAt.toISOString() : null,
    };
  });
}

/** The roster entry indexes ownership is resolved against — see `src/board/ownership.ts`. */
type Owners = ReturnType<typeof rosterTargets>;

/**
 * The live custom-domain host for a deploy row: the URL of the endpoint that OWNS it,
 * from the explicit wiring. Resolved through the board's `matchRosterEntry` (provider id
 * first, then name) rather than the name-keyed `deployTargetKey` map this replaces — the
 * two disagreed for a project renamed upstream, and the row lost the one link that points
 * at the thing that is broken. The environment scoping is unchanged: `boardTargetKey` and
 * `deployTargetKey` both carry an env segment for railway only.
 */
function ownerHostFor(d: DeployIdentity, owners: Owners): string | null {
  const owner = matchRosterEntry(d, owners.byId, owners.byName);
  const host = owner?.url ? hostOf(owner.url).toLowerCase() : '';
  return host || null;
}

/** A persisted deployments row → the in-memory ProviderDeploy the DTO mapper takes. */
function rowToProviderDeploy(d: typeof deploymentsTable.$inferSelect): ProviderDeploy {
  return {
    id: d.id,
    platform: d.platform,
    projectName: d.projectName,
    providerProjectId: d.providerProjectId,
    buildPhase: d.buildPhase as BuildPhase | null,
    deployPhase: d.deployPhase as DeployPhase,
    environment: d.environment,
    commitHash: d.commitHash,
    commitMessage: d.commitMessage,
    branch: d.branch,
    commitRepo: d.commitRepo,
    url: d.url,
    errorText: d.errorText,
    createdAt: d.createdAt,
    // fetched_at is when a poll / by-id reconcile / webhook last confirmed the
    // phases — the freshness the client's in-flight demotion judges against.
    confirmedAt: d.fetchedAt,
  };
}

/** The deployments to serve: the persisted rows (most recent N), shaped to DTOs
 *  with their config-matched live host, then overlaid with any webhook events the
 *  live-buffer received since `bufferSince` (the buffer wins the id-merge — it's
 *  newer than the last persisted cycle). Mirrors the source /api/live merge.
 *
 *  `keep` gates BOTH sources on the same rule — the webhook overlay is a second,
 *  independent way a dead project's build re-enters the board, so gating only the
 *  persisted rows would let every provider retry put the Problem straight back. */
function deploymentDtos(
  rows: (typeof deploymentsTable.$inferSelect)[],
  owners: Owners,
  bufferSince: number,
  keep: (d: DeployIdentity) => boolean = () => true,
): DeploymentDTO[] {
  const byId = new Map<string, DeploymentDTO>();
  for (const r of rows) {
    if (!keep(r)) continue;
    byId.set(r.id, providerDeployToDTO(rowToProviderDeploy(r), r.liveHost ?? ownerHostFor(r, owners)));
  }
  // Overlay webhook events received since the last cycle — newer info wins. The
  // webhook's receipt time IS the phase confirmation (provider-pushed truth).
  for (const b of deployEventsSince(bufferSince)) {
    const d = { ...b.deploy, confirmedAt: new Date(b.receivedAt) };
    if (!keep(d)) continue;
    byId.set(d.id, providerDeployToDTO(d, ownerHostFor(d, owners)));
  }
  return [...byId.values()].sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
}

/**
 * The open problems, DERIVED. Was a straight read of the `issues` table, which is why
 * /snapshot, /public/status, the MCP tools and the CLI could each disagree with the
 * board. One producer now — so every surface agrees by construction rather than by
 * four separate fixes.
 *
 * Every caller — including `/live`, which only ever reads `.problems` off the result —
 * runs the WHOLE fold (`readBoardFacts` + `deriveBoard`), even though `activity` and
 * `monitoredTargets` go unused there. That is deliberate, not unoptimized: splitting the
 * fold so a caller could take a cheaper problems-only path would recreate two producers
 * of the same facts — the exact defect this function exists to eliminate.
 *
 * The cost of NOT splitting it is now bounded rather than unknown. Every read
 * `readBoardFacts` performs is anchored to an index seek or to a roster-sized list: the
 * endpoint read is `latestCheckBySlugSql` over the active slugs (it used to be an
 * unpredicated scan of all retained `health_checks` — the outage this comment used to
 * shrug at), the deploy reads are grouped over the retention window, and the ledger reads
 * are bounded. So the fold's cost grows with the SIZE OF THE ROSTER, not with history.
 */
export async function boardProblems(db: Db, config: StatusConfig): Promise<Problem[]> {
  const nowMs = Date.now();
  return deriveBoard(await readBoardFacts(db, nowMs, config), nowMs).problems;
}

/**
 * staleProd, read off the board. `staleProdProblems` already applies the roster gate AND
 * the vanished-project gate this function used to re-apply against the issues table, so
 * nothing is left to filter here — only to reshape. That is the point: the existence
 * rules live in the fold, in one place, instead of being restated at every read.
 */
function staleProdFromBoard(problems: Problem[]): StaleProdDTO[] {
  return problems
    .filter((p) => p.state === 'stale')
    .map((p): StaleProdDTO => ({
      projectName: p.name,
      environment: p.environment ?? '',
      detail: p.detail,
      sourceUrl: p.sourceUrl,
      liveUrl: p.liveUrl,
    }));
}

/** Whether each provider is configured (active integration WITH a token) and
 *  whether its last poll reached the API. Configured comes from the resolved
 *  connection (token presence); ok comes from the absence of a `platform-health|<source>`
 *  Problem (the board's own PLATFORM_UNREACHABLE_POLLS-debounced verdict — NOT
 *  platformHealthState.reachable directly, which is the raw last-poll flag and would flip
 *  the provider pill on a single 429). */
async function providerHealth(
  db: Db,
  problems: Problem[],
): Promise<Record<ProviderKey, { configured: boolean; ok: boolean }>> {
  const conn = await providerConnFromConfig(db);
  // `platformProblems` applies the PLATFORM_UNREACHABLE_POLLS debounce, so this set means
  // the same thing it always did: repeatedly unreachable, not momentarily unlucky. Do NOT
  // shortcut to platformHealthState.reachable — that is the raw last-poll flag.
  const unreachable = new Set(
    problems
      .map((p) => parsePlatformHealthTarget(p.target))
      .filter((source): source is string => source !== null),
  );
  // "configured" stays cheap (token presence) — it must NOT probe the network, since this
  // feeds the frequently-polled /api/live snapshot. The account is resolvable from the
  // token via discovery; whether it ACTUALLY resolves/reaches CF is reported by the
  // integrations self-check (which probes) and the `ok` flag, not by this coarse boolean.
  return {
    vercel: { configured: !!conn.vercel.token, ok: !unreachable.has('vercel') },
    'cloudflare-pages': {
      configured: !!conn.cloudflare.token,
      ok: !unreachable.has('cloudflare-pages'),
    },
    railway: { configured: !!conn.railway.token, ok: !unreachable.has('railway') },
    crunchy: { configured: !!conn.crunchy.token, ok: !unreachable.has('crunchy') },
  };
}

/** The two credentials `platformDashboardUrl` needs, read once per build so every
 *  `siteLinks` call shares one lookup instead of re-reading `config.credentials`.
 *  Exported: the `get_links` MCP tool builds the same links from the same config. */
export function platformMetaFromConfig(config: StatusConfig): PlatformMeta {
  return { vercelTeamId: config.credentials.VERCEL_TEAM_ID, cloudflareAccountId: config.credentials.CLOUDFLARE_ACCOUNT_ID };
}

/** Build the full LiveSnapshot from the persisted last-cycle state. */
export async function buildLiveSnapshot(db: Db, config: StatusConfig): Promise<LiveSnapshot> {
  const [endpoints, roster, liveVercel] = await Promise.all([
    listActiveEndpoints(db),
    readRoster(db),
    liveVercelProjectNames(db),
  ]);
  // ONE resolution of "which deploy projects does a live site monitor", shared with the
  // fold (`src/board/ownership.ts`) instead of re-derived here by project name. It has to
  // be applied to this read: `deployments` rows are history that outlives both the site
  // that monitored them and the project that produced them, and nothing prunes them for
  // 90 days (purgeEndpointHistory can't — a deploy target isn't keyed by endpoint), so
  // un-narrowed the tab re-serves a deleted site's last failed build forever.
  //
  // Resolved BEFORE the reads below because it also bounds the deployments query itself
  // (see ownedDeploysWhere) — filtering 250 fetched rows in JS is not the same thing.
  const owners = rosterTargets(roster, liveVercel);
  const projects = rosterDeployProjects(roster);

  // The SECOND gate, and a different question: not "does a site monitor this project" but
  // "does this project still EXIST upstream". A project deleted at Vercel leaves its site
  // wired to a target that can never build again, so its last failed build would sit in
  // the tab forever. Read off the roster index rather than recomputed here: this file
  // computed it, `staleProdProblems` computed it again, and the deploy half of the fold
  // computed it nowhere — so the tab hid a dead project's build while the Problems list
  // kept paging for it.
  const keepDeploy = (d: DeployIdentity): boolean =>
    ownsDeployProject(d, projects) &&
    !(platformCanon(d.platform) === 'vercel' && owners.vanishedVercel.has(d.projectName));

  // DATA-FRESHNESS clock (lastCheckAt): the newest persisted probe time (the cycle
  // writes one health_checks row per endpoint EVERY cycle, so this advances only
  // when a poll actually completed). Unlike `generatedAt` (stamped at READ time,
  // always "now"), this exposes a wedged / never-redeployed poller — the client
  // warns when it lags. Deliberately read from ALL history via newestCheckAt, not
  // the active-slug `latest` map, so an endpoint-roster swap while the poller is
  // wedged cannot blank the clock into "fresh". Null only when nothing has EVER
  // been probed (a brand-new monitor → no false alarm).
  const [latest, deployRows, problems, lastCheckAt] = await Promise.all([
    latestCheckBySlug(db, endpoints.map((ep) => ep.slug)),
    db
      .select()
      .from(deploymentsTable)
      .where(ownedDeploysWhere(projects))
      .orderBy(desc(deploymentsTable.createdAt))
      .limit(MAX_DEPLOYS),
    boardProblems(db, config),
    newestCheckAt(db),
  ]);

  const generatedAt = new Date().toISOString();
  const services: LiveServiceDTO[] = serviceDtos(endpoints, latest).map((s) => {
    const c = latest.get(s.slug);
    // A `dns`-source open problem means the hostname failed to resolve. `dnsOk` IS a
    // persisted column (schema.ts:32) — the reason to derive from the Problem rather
    // than read it straight off `c` is that the Problem is the single producer, so
    // `/live` cannot contradict what the board itself claims about the same endpoint.
    // (`providerHealth` must skip `platformHealthState.reachable` for the same reason
    // PLUS a debounce; there is no debounce on this field — see the last paragraph.)
    //
    // `c?.dnsOk === false` is a FALLBACK, not the primary source: it only fires when
    // the fold has no opinion to disagree with in the first place — `monitorHttp:
    // false` excludes the endpoint from `endpointProblems` entirely (Requirement A),
    // so `problems` never carries a `dns` row for it no matter what the latest probe
    // saw. Without the fallback that endpoint's `/live` row claimed `dnsOk: true` from
    // having nothing to ask, not from an actual DNS check — a health claim from an
    // absence of data. For a MONITORED endpoint the fallback changes nothing: a DNS
    // failure sets `status: "down"` unconditionally (probe.ts), and `probeConfirmed`
    // confirms "down" with no debounce, so the raw column and the Problem always agree.
    const dnsBad = problems.some((p) => p.target === s.slug && p.source === 'dns') || c?.dnsOk === false;
    // Server-truth "down since": the open http/dns problem's onset for this endpoint.
    // (Problems are keyed by endpoint slug for http/dns sources.) Durable across browsers,
    // unlike the client store's onset — so the retire surface judges real persistence.
    const downProblem = problems.find((p) => p.target === s.slug && (p.source === 'dns' || p.source === 'http'));
    // lastCheckedAt on the live snapshot is the cycle clock (generatedAt) when a
    // check exists, matching the source which stamped every service with the sweep
    // time; null only when the endpoint has never been probed.
    return { ...s, lastCheckedAt: c ? generatedAt : null, dnsOk: !dnsBad, downSince: downProblem?.since ?? null };
  });

  // `deployments` is the MONITORED deploy feed, not an account-wide one — every consumer
  // (the Problems fold, the per-platform KPI pills, the per-endpoint failure list) is
  // scoped to monitored sites already, and a deploy nobody monitors has no row to attach
  // to. Surfaces that legitimately need the whole account enumerate it live via
  // /deploy-projects and are untouched by this. The second gate here is for the
  // webhook-buffer overlay, which never passed through ownedDeploysWhere.
  const deployments = deploymentDtos(deployRows, owners, 0, keepDeploy);
  const staleProd = staleProdFromBoard(problems);
  const providers = await providerHealth(db, problems);

  return {
    generatedAt,
    lastCycleAt: lastCheckAt?.toISOString() ?? null,
    probeIntervalMs: config.probeIntervalSeconds * 1000,
    monitorVersion: config.gitCommitSha,
    services,
    deployments,
    staleProd,
    providers,
    // A successful DB read is never the static-fallback degraded path.
    configDegraded: false,
    configReason: null,
  };
}

export interface CompactSnapshot {
  generatedAt: string;
  overall: 'healthy' | 'degraded' | 'down';
  services: ServiceStatusDTO[];
  openIssues: {
    target: string;
    source: string;
    name: string;
    environment: string | null;
    severity: string;
    state: string;
    detail: string | null;
    openedAt: string;
    // Where to go next, and what shipped — all recorded on the issue row when it
    // was opened. A snapshot consumer (the fleet board, `adh-status issues show`)
    // could otherwise only say WHAT is broken, never point at the failing build,
    // the live site, or the commit that caused it.
    sourceUrl: string | null;
    liveUrl: string | null;
    commitHash: string | null;
    commitMessage: string | null;
    commitRepo: string | null;
  }[];
}

/** The compact per-monitor unit a fleet aggregator consumes — overall rollup +
 *  the per-service statuses + the open-issue list. SINGLE source of truth for the
 *  /snapshot payload (the /fleet route reuses this in a later task). */
export async function buildSnapshot(db: Db, config: StatusConfig): Promise<CompactSnapshot> {
  const endpoints = await listActiveEndpoints(db);
  const [latest, allProblems] = await Promise.all([
    latestCheckBySlug(db, endpoints.map((ep) => ep.slug)),
    boardProblems(db, config),
  ]);
  const services = serviceDtos(endpoints, latest);

  // ERROR PROBLEMS ARE OPERATOR-ONLY, and this is the place that decision takes effect
  // rather than the rule that mints them — `deriveBoard` still returns them in full, and
  // `GET /board` (authenticated) is where an operator sees them.
  //
  // The exclusion is about DISCLOSURE, not about severity. An error Problem's `name` is
  // the GlitchTip project and its `detail` is the top exception's title and culprit —
  // internal identifiers, chosen by whoever created the project, describing where our code
  // throws. This snapshot is not an operator surface: `/public/status-summary` is built
  // from it with no auth at all, and `buildStatusSummary` puts every non-endpoint problem
  // into `downSites` BY NAME, so an unfiltered error problem would publish that project
  // name and its onset to anonymous readers of the public wallboard. Nothing downstream
  // can re-gate it — by the time the DTO exists the provenance is gone.
  //
  // Cheap to reverse in the other direction if the fleet ever wants it: drop the filter
  // and error problems rejoin `hasNonEndpointProblem` below, taking the public headline to
  // "experiencing issues" exactly as a failed build does (never `major_outage` —
  // `errorProblems` mints no `critical`). Reversing it would mean choosing to publish
  // those names, which is a decision to make deliberately rather than by omission.
  const problems = allProblems.filter((p) => parseErrorsTarget(p.target) === null);

  // Deploy/stale/platform problems aren't endpoint health checks — a live site serves
  // HTTP 200 while its newest build fails — so the endpoint rollup can't see them. Any
  // open Problem not tied to a monitored endpoint slug is one of these; fold its presence
  // into the headline, or the public landing reads "All systems operational" while the
  // wallboard shows red build failures.
  const serviceSlugs = new Set(services.map((s) => s.slug));
  const hasNonEndpointProblem = problems.some((p) => !serviceSlugs.has(p.target));
  const overallStatus = publicOverall(
    services.map((s) => s.status).filter((s): s is HealthStatus => s !== 'unknown'),
    hasNonEndpointProblem,
  );
  // Collapse the 4-state overall onto the fleet's 3-state pill.
  const overall: CompactSnapshot['overall'] =
    overallStatus === 'major_outage' ? 'down' : overallStatus === 'degraded' ? 'degraded' : 'healthy';

  return {
    generatedAt: new Date().toISOString(),
    overall,
    services,
    // The board's problems, not the `issues` ledger: the fold is the source of truth, and
    // a ledger row is its record. The issue's links (sourceUrl/liveUrl/commit*) that main
    // added here are carried by `Problem` too, so the payload is unchanged in shape — only
    // in provenance, and `openedAt` is now the problem's onset rather than the ledger
    // write time (see `problemSince`).
    openIssues: problems.map((p) => ({
      target: p.target, source: p.source, name: p.name, environment: p.environment,
      severity: p.severity, state: p.state, detail: p.detail, openedAt: p.since,
      sourceUrl: p.sourceUrl, liveUrl: p.liveUrl,
      commitHash: p.commitHash, commitMessage: p.commitMessage, commitRepo: p.commitRepo,
    })),
  };
}

// --- secondary read DB queries (port the source stats-store SQL) -------------

const clamp = (v: number, lo: number, hi: number): number => Math.min(Math.max(v, lo), hi);
const intParam = (raw: string | undefined, fallback: number): number => {
  const n = parseInt(raw ?? '', 10);
  return Number.isFinite(n) && n !== 0 ? n : fallback;
};

/** One endpoint's health-check samples within the last `hours`, ascending. */
async function historyFor(
  db: Db,
  slug: string,
  hours: number,
): Promise<{ status: string; responseTimeMs: number | null; statusCode: number | null; error: string | null; checkedAt: Date }[]> {
  const cutoff = new Date(Date.now() - hours * 3_600_000);
  const rows = await db
    .select({
      status: healthChecks.status,
      responseTimeMs: healthChecks.responseTimeMs,
      statusCode: healthChecks.statusCode,
      error: healthChecks.error,
      checkedAt: healthChecks.checkedAt,
    })
    .from(healthChecks)
    .where(and(eq(healthChecks.serviceSlug, slug), gte(healthChecks.checkedAt, cutoff)))
    .orderBy(healthChecks.checkedAt);
  return rows;
}

/** One endpoint's per-UTC-day check counts over the last `days`, ascending. */
async function uptimeDaily(db: Db, slug: string, days: number): Promise<(Counts & { day: string })[]> {
  const cutoff = new Date(Date.now() - days * 86_400_000);
  const rows = await db.all<{
    day: string;
    total: number;
    healthy: number;
    degraded: number;
    down: number;
  }>(sql`
    select
      strftime('%Y-%m-%d', checked_at, 'unixepoch') as day,
      count(*) as total,
      sum(case when status = 'healthy' then 1 else 0 end) as healthy,
      sum(case when status = 'degraded' then 1 else 0 end) as degraded,
      sum(case when status = 'down' then 1 else 0 end) as down
    from health_checks
    where service_slug = ${slug} and checked_at >= ${Math.floor(cutoff.getTime() / 1000)}
    group by day
    order by day asc
  `);
  return rows.map((r) => ({
    day: r.day,
    total: Number(r.total),
    healthy: Number(r.healthy),
    degraded: Number(r.degraded),
    down: Number(r.down),
  }));
}

/** Portfolio-wide response-time sparkline: `buckets` buckets over the last `hours`
 *  (oldest → newest), each the avg response of UP checks, null where no data.
 *
 *  Aggregation happens IN SQL, and the SOURCE depends on the window:
 *
 *  - Fine windows (bucket span < 1h) group the raw `health_checks` range. The
 *    two-sided range on the bare column keeps it an idx_health_checked range seek,
 *    and SQLite reduces it to at most `buckets` rows before JS sees it — the
 *    previous form hydrated every row of the span (millions, at the 7-day default)
 *    into JS objects first, burning seconds of event-loop CPU per call, refetched
 *    every 60s per open dashboard.
 *  - Long windows (bucket span >= 1h — e.g. the 90-day sparkline) read the hourly
 *    rollup instead, whose row count is bounded by hours x fleet no matter how
 *    fast we probe; the raw range for those spans is unbounded by cadence. Each
 *    hour's avg is weighted by its UP-check count, so a down-only hour (zero
 *    weight) can't drag a bucket. Caveat: the rollup's avg spans ALL checks in
 *    the hour, so a long-window bucket is a trend line where an outage-hour skew
 *    is signal, not noise.
 */
async function responseBuckets(db: Db, hours: number, buckets: number): Promise<(number | null)[]> {
  const nowMs = Date.now();
  const spanMs = hours * 3_600_000;
  const bucketMs = Math.max(1, Math.round(spanMs / buckets));
  // The range is the exact SQL image of the old JS `age < 0 || age >= spanMs` skip
  // for integer checked_at: `> cutoff` (not >=) excludes the floored-cutoff second,
  // whose rows are all age >= spanMs; `<= nowSec` excludes future-dated rows.
  const cutoff = Math.floor((nowMs - spanMs) / 1000);
  const nowSec = Math.floor(nowMs / 1000);

  // Long windows: read the bounded hourly rollup rather than the raw range (see
  // the doc comment). The bucket index math is identical — bucket 0 = newest.
  if (bucketMs >= 3_600_000) {
    const rows = await db.all<{ hour: number; ups: number; weighted: number }>(sql`
      select hour,
             sum(case when avg_response_time_ms is not null then healthy_checks + degraded_checks else 0 end) as ups,
             sum(case when avg_response_time_ms is not null then avg_response_time_ms * (healthy_checks + degraded_checks) else 0 end) as weighted
      from metrics_hourly
      where hour > ${cutoff} and hour <= ${nowSec}
      group by hour
    `);
    const sums = new Array<number>(buckets).fill(0);
    const counts = new Array<number>(buckets).fill(0);
    for (const r of rows) {
      const idx = Math.min(buckets - 1, Math.floor((nowMs - Number(r.hour) * 1000) / bucketMs));
      sums[idx]! += Number(r.weighted);
      counts[idx]! += Number(r.ups);
    }
    return Array.from({ length: buckets }, (_, i) => {
      const b = buckets - 1 - i;
      return counts[b]! > 0 ? Math.round(sums[b]! / counts[b]!) : null;
    });
  }

  // bucket 0 = newest; min() clamps the rounding edge where bucketMs·buckets < spanMs.
  // The cast is LOAD-BEARING on remote (hrana) connections, which bind JS numbers as
  // REAL — without it the division yields fractional buckets and GROUP BY fragments.
  const rows = await db.all<{ bucket: number; s: number; n: number }>(sql`
    select min(cast((${nowMs} - checked_at * 1000) / ${bucketMs} as integer), ${buckets - 1}) as bucket,
           sum(response_time_ms) as s, count(*) as n
    from health_checks
    where checked_at > ${cutoff}
      and checked_at <= ${nowSec}
      and status in ('healthy', 'degraded')
      and response_time_ms is not null
    group by bucket
  `);
  // Number() like uptimeDaily above: under a bigint intMode, raw aggregates would
  // silently miss the numeric Map keys (blank sparkline) or throw in Math.round.
  const byBucket = new Map(rows.map((r) => [Number(r.bucket), { s: Number(r.s), n: Number(r.n) }]));
  // oldest → newest (left → right); empty buckets stay null (a group always has n >= 1).
  return Array.from({ length: buckets }, (_, i) => {
    const r = byBucket.get(buckets - 1 - i);
    return r ? Math.round(r.s / r.n) : null;
  });
}

// --- read services (shared by the HTTP routes AND the /mcp tools) ------------
// These own the reshape a read exposes, so GET /history, GET /uptime,
// GET /deploy-projects/unconfigured and their read-only MCP-tool twins can never
// drift. Callers pass already-validated numbers (the route clamps query params;
// the tool clamps its typed args) — the body here is identical either way.

/** One endpoint's recent checks, shaped for the /history payload. */
export async function queryHistory(
  db: Db,
  slug: string,
  hours: number,
): Promise<{
  service: string;
  hours: number;
  checks: { status: string; responseTimeMs: number | null; statusCode: number | null; error: string | null; checkedAt: string }[];
}> {
  const checks = await historyFor(db, slug, hours);
  return {
    service: slug,
    hours,
    checks: checks.map((s) => ({
      status: s.status,
      responseTimeMs: s.responseTimeMs,
      statusCode: s.statusCode,
      error: s.error,
      checkedAt: s.checkedAt.toISOString(),
    })),
  };
}

/** Per-endpoint daily uptime over the last `days`. */
export async function buildUptime(db: Db, days: number): Promise<UptimeResponse> {
  const endpoints = await listActiveEndpoints(db);
  const services: UptimeService[] = await Promise.all(
    endpoints.map(async (svc): Promise<UptimeService> => {
      const rows = await uptimeDaily(db, svc.slug, days);
      const daily = rows.map((r) => {
        const c2: Counts = { total: r.total, healthy: r.healthy, degraded: r.degraded, down: r.down };
        return { day: r.day, status: dayStatus(c2), uptimePercent: uptimePercent(c2) };
      });
      const totals = rows.reduce<Counts>(
        (acc, r) => ({
          total: acc.total + r.total,
          healthy: acc.healthy + r.healthy,
          degraded: acc.degraded + r.degraded,
          down: acc.down + r.down,
        }),
        { total: 0, healthy: 0, degraded: 0, down: 0 },
      );
      return { slug: svc.slug, name: svc.name, uptimePercent: uptimePercent(totals), totalChecks: totals.total, daily };
    }),
  );
  return { services, days };
}

/** The configuration-gap partition: pending/addable deploy projects + endpoints that
 *  aren't wired to one. Takes the already-enumerated list (the caller owns cache-vs-fresh). */
export async function findUnconfiguredSites(db: Db, enumerated: EnumeratedProject[]) {
  const projects = await buildDeployProjects(db, enumerated);
  const { pending, addable } = partitionPending(projects);
  const noDomain = pending.filter((p) => !p.domain);
  // The other configuration gap: endpoints that should be wired to a deploy project but
  // aren't. `slug` IS the endpoint id (see listActiveEndpoints), so it's a stable key.
  // `listActiveEndpoints` is load-bearing, not incidental: a monitor with monitoring
  // switched off is OUT of the auto-configure conversation entirely (the same rule the
  // web's `endpointConfigStatus` applies via `isActive`), so it is never reported as a
  // site to fix. Note the OTHER axis above reads every endpoint — a paused monitor still
  // CLAIMS its deploy project; it just isn't nagged about its own missing wiring.
  const endpoints = await listActiveEndpoints(db);
  const unconfiguredSites = endpoints.filter(endpointUnconfigured).map((e) => ({ id: e.slug, name: e.name }));
  // The INVERSE gap — a monitor wired to a project deleted upstream — is deliberately NOT
  // reported here. It is not a configuration gap the operator has to close: the monitor
  // cycle retires such a monitor outright (see `retireUnclaimedMonitors` in monitor/sync),
  // so by the time anything could act on it the row is gone.
  return { pending, addable, noDomain, unconfiguredSites };
}

// ---------------------------------------------------------------------------
// The route factory. Plain Hono GET handlers (OpenAPI doc coverage is a later
// task); they sit behind the app-wide requireAuth (view tier suffices, and
// /snapshot also accepts PEER_TOKEN — both handled by the middleware).
// ---------------------------------------------------------------------------

const PROVIDER_READ_CACHE_MS = 30_000;

/**
 * Re-verify the Vercel project table, THEN enumerate — the one read every deploy-project
 * surface goes through (both GETs here, the MCP twins, Auto Configure).
 *
 * The two halves are inseparable: the enumeration derives "which Vercel projects exist"
 * from `deploy_project_meta`, so enumerating without refreshing first keeps offering a
 * project deleted upstream (and leaves its still-wired site unflagged) until the next
 * monitor cycle. Bundling them also means a caller can never be handed the enumeration
 * built by the OTHER half of the pair — a pre-prune list.
 *
 * The refresh is a `deploy_project_meta` write on a read path. That is intended: the table
 * is a derived mirror of the account, and reconciling it is idempotent — but it is why the
 * routes below go through the cache rather than calling this per request.
 */
export async function refreshAndEnumerateDeployProjects(
  db: Db,
): Promise<{ vercel: VercelRefreshResult; enumerated: EnumeratedProject[]; verifiedPlatforms: string[] }> {
  const vercel = await refreshVercelProjectMetaFromConfig(db);
  const { projects, verifiedPlatforms } = await enumerateDeployProjectsVerified(db);
  // The enumeration vouches for the platforms it polls live (Railway, Cloudflare); Vercel's
  // projects come from `deploy_project_meta`, and only THIS function knows whether the
  // refresh that just reconciled that table was a complete, authenticated account read.
  // `ok` is exactly that (false for a tokenless, partial, or failed read), so it is the one
  // fact that licenses reading a Vercel project's ABSENCE as "deleted upstream".
  return { vercel, enumerated: projects, verifiedPlatforms: vercel.ok ? [...verifiedPlatforms, 'vercel'] : verifiedPlatforms };
}

export function readsRoutes(db: Db, config: StatusConfig): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();
  // Only the PROVIDER-facing halves are cached; the DB reads (wired/ignored
  // flags) stay live so a config edit shows immediately.
  // SHARED by both deploy-project routes so a burst (the badge loop + an open modal +
  // several tabs) coalesces onto ONE account scan — and so `fresh=1` on either route
  // means fresh all the way down, refresh included.
  const cachedEnumerate = cachedSingleFlight(PROVIDER_READ_CACHE_MS, () => refreshAndEnumerateDeployProjects(db));
  const cachedIntegrations = cachedSingleFlight(PROVIDER_READ_CACHE_MS, () => runIntegrationsCheck(db, config));
  const platformMeta = platformMetaFromConfig(config);

  app.get('/live', async (c) => c.json(await buildLiveSnapshot(db, config)));

  app.get('/status', async (c) => {
    const endpoints = await listActiveEndpoints(db);
    const latest = await latestCheckBySlug(db, endpoints.map((ep) => ep.slug));
    // Each /status entry is one endpoint: `links.live` is its own URL; `links.platform`
    // is the deploy-platform dashboard for its (platform, deployProject) pair (null when
    // one can't be built). Additive — the existing fields are untouched.
    const services = serviceDtos(endpoints, latest).map((s) => ({
      ...s,
      links: siteLinks(
        { platform: s.platform, projectName: s.deployProject },
        [{ url: s.url, environment: s.environment }],
        platformMeta,
      ),
    }));
    const overall: OverallStatus = computeOverall(
      services.map((s) => s.status).filter((s): s is HealthStatus => s !== 'unknown'),
    );
    return c.json({ overall, services, checkedAt: new Date().toISOString() });
  });

  app.get('/snapshot', async (c) => c.json(await buildSnapshot(db, config)));

  app.get('/history', async (c) => {
    // The source param was `service`; the standalone backend uses `slug` (also
    // accept `service` for drop-in parity with the existing frontend's query).
    const slug = c.req.query('slug') ?? c.req.query('service');
    // Throw (not c.json) so app.onError shapes it as the documented { error: { message } }
    // envelope, matching the 400 the OpenAPI spec declares for this route.
    if (!slug) throw new HTTPException(400, { message: 'Missing required parameter: slug' });
    const hours = clamp(intParam(c.req.query('hours'), 24), 1, 168);
    return c.json(await queryHistory(db, slug, hours));
  });

  app.get('/uptime', async (c) => {
    const days = clamp(intParam(c.req.query('days'), 90), 1, 365);
    return c.json(await buildUptime(db, days));
  });

  app.get('/response-history', async (c) => {
    const hours = clamp(intParam(c.req.query('hours'), 24), 1, 24 * 90);
    const buckets = clamp(intParam(c.req.query('buckets'), RESPONSE_BUCKETS), 1, 240);
    const points = await responseBuckets(db, hours, buckets);
    return c.json({ hours, points });
  });

  app.get('/deploy-projects', async (c) => {
    const { enumerated, verifiedPlatforms } = await cachedEnumerate(c.req.query('fresh') === '1');
    const built = await buildDeployProjects(db, enumerated);
    // Each project entry gains canonical `links`: `live` is its primary domain
    // (falling back to the first of `domains`), `platform` its deploy dashboard.
    // Additive — every existing field is preserved.
    const projects = built.map((p) => ({
      ...p,
      links: siteLinks(
        { platform: p.platform, projectName: p.projectName },
        (p.domain ? [p.domain] : p.domains).map((d) => ({ url: d, environment: p.environment })),
        platformMeta,
      ),
    }));
    // Which platforms THIS enumeration can speak for. The client's per-row Add plans with
    // the same engine as the server-side run, and the engine may only read a project's
    // absence as "retired" on a platform that was actually listed — so the fact has to
    // travel with the list. Omitting it would silently make the row button conservative
    // where the Auto Configure button repairs, for the very same project.
    return c.json({ projects, verifiedPlatforms });
  });

  // The review UI's data source (and Spec C's "is anything unconfigured?" probe): the
  // partition the web used to compute client-side from /deploy-projects. Shares the SAME
  // 30s cachedEnumerate instance as the sibling /deploy-projects route, so the badge/board's
  // 60s refetch loop coalesces on that cache instead of fanning out a full provider scan per
  // tab per minute; `?fresh=1` (sent when a user opens the Auto Configure modal) bypasses the
  // TTL, identical semantics to /deploy-projects?fresh=1. View tier — sits with the reads.
  app.get('/deploy-projects/unconfigured', async (c) => {
    const { enumerated } = await cachedEnumerate(c.req.query('fresh') === '1');
    return c.json(await findUnconfiguredSites(db, enumerated));
  });

  app.get('/integrations', async (c) => c.json(await cachedIntegrations(c.req.query('fresh') === '1')));

  return app;
}

// enumerateDeployProjects (with its EnumeratedProject shape and the internal
// resolveRailwayDomains helper) now lives in @agentic-toolkit/deploy-platform/enumerate.
// Imported above for use in readsRoutes; re-exported here so this module's public surface
// (the enumerate function + its type) is unchanged for any downstream importer.
export { enumerateDeployProjects };
export type { EnumeratedProject } from '@agentic-toolkit/deploy-platform/enumerate';

/**
 * Enrich the raw enumerated deploy projects with their live wiring + ignored flags —
 * the single body behind BOTH GET /deploy-projects and GET /deploy-projects/unconfigured
 * AND the server-side auto-configure classify, so all three judge a project
 * monitored/ignored the exact same way (they can't drift). Takes the already-enumerated
 * list (the caller owns cache-vs-fresh) and joins it to EVERY endpoint's wiring (paused
 * ones included — see `listEndpointsForWiring`) + the ignored table. The returned shape is
 * the web's `DeployProject`.
 */
export async function buildDeployProjects(db: Db, enumerated: EnumeratedProject[]) {
  const [eps, ignoredRows] = await Promise.all([listEndpointsForWiring(db), listIgnoredProjects(db)]);
  return correlateDeployProjects(enumerated, eps, ignoredRows);
}

/** The endpoint fields the wiring correlation reads — see `listEndpointsForWiring`. */
export interface EndpointWiring {
  platform: string | null;
  deployProject: string | null;
  environment: string | null;
  url: string;
}

/**
 * The pure half of {@link buildDeployProjects}: enumerated projects × endpoint wiring ×
 * ignored rows → the web's `DeployProject` list. Split out so the wired/ignored rules —
 * per-environment keying, the Railway host-membership fallback, and "a paused monitor
 * still claims its project" — are unit-testable without a database.
 */
export function correlateDeployProjects(
  enumerated: EnumeratedProject[],
  eps: EndpointWiring[],
  ignoredRows: { platform: string; projectName: string }[],
) {
  // Ignore is PROJECT-level (the ignored table has no environment column), so a Railway
  // project's every-environment entry shares one ignored flag — you ignore a project
  // wholesale (the infra projects you ignore have a single domain-less entry anyway).
  const ignored = new Set(ignoredRows.map((r) => `${platformCanon(r.platform)}|${r.projectName}`));
  // Wired is per-ENVIRONMENT, via the same deployTargetKey a deploy + endpoint agree on:
  // env-specific for Railway, env-agnostic for Vercel/Cloudflare. So a Railway project's
  // production entry can read "monitored" while its staging entry stays "not monitored".
  // A Railway project's per-environment host sets, so an endpoint can be attributed to the
  // env whose domains actually contain its host (below) — not just its stored env label.
  const railwayEnvsByProject = new Map<string, { environment: string | null; hosts: Set<string> }[]>();
  for (const p of enumerated) {
    if (platformCanon(p.platform) !== 'railway') continue;
    const list = railwayEnvsByProject.get(p.projectName) ?? [];
    list.push({ environment: p.environment, hosts: new Set(p.domains.map((d) => d.toLowerCase())) });
    railwayEnvsByProject.set(p.projectName, list);
  }
  const wired = new Set<string>();
  for (const e of eps) {
    const key = deployTargetKey(e.platform, e.deployProject, e.environment);
    if (key) wired.add(key);
    // Host-membership fallback: a Railway endpoint added before per-env wiring was tagged
    // env="production" by host-parsing (a provider host has no env prefix), so its staging/
    // testing project entry would wrongly read "not monitored". Attribute it instead to the
    // env whose domain set actually contains its host, so the correct env reads "monitored".
    if (platformCanon(e.platform) === 'railway' && e.deployProject) {
      const host = endpointHost(e.url);
      if (host) {
        for (const env of railwayEnvsByProject.get(e.deployProject) ?? []) {
          if (env.hosts.has(host)) {
            const k = deployTargetKey('railway', e.deployProject, env.environment);
            if (k) wired.add(k);
          }
        }
      }
    }
  }

  return enumerated.map((p) => {
    const targetKey = deployTargetKey(p.platform, p.projectName, p.environment);
    return {
      platform: p.platform,
      projectName: p.projectName,
      environment: p.environment,
      // The env list shown in the picker: Railway reports its real env directly; Vercel
      // encodes env in the project name; Cloudflare has none.
      environments:
        p.platform === 'railway' ? (p.environment ? [p.environment] : []) : p.platform === 'vercel' ? [envFromProject(p.projectName)] : [],
      latestAt: null,
      deployCount: 0,
      latestStatus: null,
      wired: targetKey !== null && wired.has(targetKey),
      ignored: ignored.has(`${platformCanon(p.platform)}|${p.projectName}`),
      domain: p.domain,
      domains: p.domains,
      gitRepo: p.gitRepo,
      gitBranch: p.gitBranch,
      rootDirectory: p.rootDirectory,
      framework: p.framework,
    };
  });
}

/**
 * The platform/project/environment wiring on EVERY endpoint (for /deploy-projects).
 * Environment is included so the per-environment `wired` correlation (deployTargetKey)
 * can tell a Railway project's production endpoint from its staging one.
 *
 * Deliberately NOT `listActiveEndpoints`: `wired` answers "is a monitor CONFIGURED for
 * this project?", which is a configuration fact, not a runtime one. A monitor with
 * monitoring switched off (`isActive = false`) is paused, not absent — reading the probe
 * list here made its project read "not monitored", so the Auto Configure banner nagged
 * about a project that is already set up, and a run would have added a SECOND monitor for
 * a URL that already has one. Pause state belongs to the probe list (`listActiveEndpoints`,
 * which the sync and the board still use), not to this one.
 */
async function listEndpointsForWiring(db: Db): Promise<EndpointWiring[]> {
  const eps = await listEndpoints(db);
  return eps.map((e) => ({ platform: e.platform, deployProject: e.deployProject, environment: e.environment, url: e.url }));
}

/** The lowercased host of an endpoint URL (with or without a scheme), or null if unparseable. */
function endpointHost(url: string): string | null {
  try {
    return new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(url) ? url : `https://${url}`).hostname.toLowerCase();
  } catch {
    return null;
  }
}
