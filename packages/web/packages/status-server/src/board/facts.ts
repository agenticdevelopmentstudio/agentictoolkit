import { cachedSingleFlight } from "@agentic-toolkit/deploy-platform/util";
import { glitchtipConfigured, type StatusConfig } from "../config/port";
import { combinedStatus } from "../monitor/deploy-status";
import { deployIsBad, deployIsResolving } from "../monitor/issue-sources";
import type { PageCursor, Storage } from "../storage/ports";
import { deriveActivity, pageActivity } from "./derive-activity";
import { monitoredTargets } from "./derive-problems";
import { rosterDeployProjects } from "./ownership";
import { ACTIVITY_WINDOW_MS } from "./types";
import type { ActivityCursor, ActivityPage, BoardFacts, DeployFact, EndpointFact, IssueEvent } from "./types";

// ---------------------------------------------------------------------------
// The fold's fact-gathering layer. Every DB read behind `readBoardFacts` and
// `readActivityPage` now lives in `storage.board` (see `libsql/stores/board-store.ts`)
// — this file is pure orchestration + the one piece of business logic
// (`binByOutcome`) that decides what a deploy row's raw phases MEAN, which is a
// fold concern, not a query concern.
// ---------------------------------------------------------------------------

/**
 * Split deploy-outcome candidates by what `combinedStatus` says, so the storage layer
 * can only ever decide which rows are worth READING and never what they mean.
 * `canceled`/`unknown` rows fall out of both lists: they are the absence of a verdict,
 * and the board claims nothing from an absence.
 */
function binByOutcome(rows: DeployFact[]): { concluded: DeployFact[]; inFlight: DeployFact[] } {
  const concluded: DeployFact[] = [];
  const inFlight: DeployFact[] = [];
  for (const f of rows) {
    const status = combinedStatus({ buildPhase: f.buildPhase, deployPhase: f.deployPhase });
    // `deployIsBad` and `deployIsResolving` ARE the verdict vocabulary — the same pair
    // `derive-problems.ts` judges with, so the binning and the judging cannot drift apart.
    if (deployIsBad(status) || deployIsResolving(status)) concluded.push(f);
    // The two statuses that can still change. `building` is the only one `deployIsStuck`
    // can ever judge; `queued` is deliberately never stuck (an intentional hold).
    else if (status === "building" || status === "queued") inFlight.push(f);
  }
  return { concluded, inFlight };
}

/**
 * Read every fact the board needs, and nothing else. THE ONLY FILE IN src/board/ THAT
 * ORCHESTRATES THE READS — keeping the fold pure is what makes the regression suite
 * cheap. Every read is anchored to an index seek or a roster-sized list (see the
 * corresponding `storage.board.*` method), so the fold's cost grows with the SIZE OF
 * THE ROSTER, not with history.
 */
export async function readBoardFacts(storage: Storage, nowMs: number, config: StatusConfig): Promise<BoardFacts> {
  const roster = await storage.board.readRoster();

  // The state projection the Problem rules judge (concluded + in-flight, collapsed to
  // one verdict per deploy identity spelling by the adapter's grouped reads).
  const { concluded: deploys, inFlight: inFlightDeploys } = binByOutcome(
    await storage.board.readDeployOutcomeCandidates(),
  );

  // EVERY deployment inside the activity window, ungrouped and unfiltered by outcome —
  // the LOG the Activity feed records, as opposed to `deploys`/`inFlightDeploys` above
  // (the STATE PROJECTION). Bounded to owned projects — see `ownedDeploysWhere`.
  const deployEvents = await storage.board.readDeployEvents(nowMs - ACTIVITY_WINDOW_MS, rosterDeployProjects(roster));

  // Issues that opened OR closed inside the window — the other half of the feed.
  const issueEvents = await storage.board.readIssueEvents(nowMs - ACTIVITY_WINDOW_MS);

  // Open ledger rows, keyed by target — the ONSET times, not the truth.
  const ledger = await storage.board.readOpenIssueTargets();

  const platforms = await storage.board.readPlatformFacts();
  const staleProd = await storage.board.readStaleProdFacts();

  // The projects that still exist upstream, from the mirror the cycle reconciles. EMPTY
  // means "we have never completed an authenticated read", not "everything was
  // deleted" — see `storage.deploy.listProjectMetaNames`'s callers for the narrowing rule.
  const liveVercelProjects = await storage.deploy.listProjectMetaNames("vercel");

  const errorFacts = await storage.board.readErrorFacts();

  return {
    roster,
    // The monitor's own cadence, read HERE because the fold is pure and `config` is IO.
    probeIntervalMs: config.probeIntervalSeconds * 1000,
    deploys,
    inFlightDeploys,
    deployEvents,
    // Driven from the ACTIVE roster, never from all health-check history — see
    // `readEndpointFacts`. `monitorHttp` is deliberately NOT applied here — that switch
    // is `endpointProblems`' verdict gate, and narrowing the FACTS by it would also hide
    // the endpoint's observation timestamp from anything that measures freshness.
    endpoints: await readEndpointFacts(
      storage,
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
  storage: Storage,
  nowMs: number,
  config: StatusConfig,
  opts: { cursor: ActivityCursor | null; limit: number; base?: BoardFacts },
): Promise<ActivityPage> {
  const { cursor, limit } = opts;
  // `base` is injectable so a burst of pages can share ONE board-facts read — see
  // `createActivityPageReader`, which is how the route calls this.
  const base = opts.base ?? (await readBoardFacts(storage, nowMs, config));

  // `<=`, not `<`: the cursor is a (time, id) PAIR, and a row sharing the cursor's
  // timestamp may still sort before it. The one exception is the EMPTY-ID sentinel a
  // stalled page mints (`pageActivity`'s empty branch) — `strict: true` matches what
  // that sentinel already means: no real row id is empty, so `<` at that instant makes
  // progress unconditional instead of re-serving the same rows forever.
  const pageCursor: PageCursor = { beforeMs: cursor?.atMs ?? null, strict: cursor?.id === "", limit };

  const owned = rosterDeployProjects(base.roster);
  const eventRead = await storage.board.readDeployActivityPage(pageCursor, owned);

  // The issue reads carry the SAME ownership narrowing the deploy read does: `issues`
  // is a LEDGER that retains rows for targets the roster no longer watches, and
  // `deriveActivity` drops every one of them. `monitoredTargets` reads the roster, the
  // platform rows and both deploy-state lists — none of which this function overrides
  // — so it is the SAME set `deriveActivity` will gate on, not a second spelling of it.
  const watched = monitoredTargets(base);
  const openedRead = await storage.board.readIssueOpenedPage(pageCursor, watched);
  const resolvedRead = await storage.board.readIssueResolvedPage(pageCursor, watched);

  const byId = new Map<number, IssueEvent>();
  for (const r of [...openedRead.rows, ...resolvedRead.rows]) byId.set(r.id, r);

  // A source that returned fewer rows than it was asked for has provably nothing older.
  // ALL THREE must be exhausted before the feed may claim the end of history. Each
  // source that DID fill its limit stopped somewhere, and the adapter has already
  // re-read that instant in full, so its floor is an instant read COMPLETELY. The
  // NEWEST of the three is the oldest instant this PAGE read completely: below it some
  // source still has unread rows. It becomes the fold's floor and the pager's
  // step-back target.
  const floors = [eventRead.floorMs, openedRead.floorMs, resolvedRead.floorMs].filter(
    (f): f is number => f != null,
  );
  const floorMs = floors.length > 0 ? Math.max(...floors) : null;
  const sourcesExhausted = floorMs == null;

  const pageFacts: BoardFacts = {
    ...base,
    deployEvents: eventRead.rows,
    issueEvents: [...byId.values()],
  };

  // The cursor query already chose the window, so the fold must not apply the board's 24h
  // floor on top of it — and must not apply the board's row CAP either: that cap sheds the
  // OLDEST candidates, which on this path are the ones the reader is scrolling towards.
  // The input is already bounded by the three storage-layer limits above.
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
  storage: Storage,
  config: StatusConfig,
): (nowMs: number, opts: { cursor: ActivityCursor | null; limit: number }) => Promise<ActivityPage> {
  const cachedBase = cachedSingleFlight(ACTIVITY_BASE_FACTS_CACHE_MS, () => readBoardFacts(storage, Date.now(), config));
  return async (nowMs, opts) => readActivityPage(storage, nowMs, config, { ...opts, base: await cachedBase() });
}

/**
 * The newest probe per endpoint, plus the onset of its current bad run read from the
 * persisted history — so "down since" is server truth that survives a browser reload,
 * and the degraded debounce is measured against it.
 *
 * Reads through `storage.health.latestChecks`, the SAME statement `/live` uses, so
 * `/live` and the board can never pick different rows and publish different verdicts
 * for one endpoint in one request.
 */
async function readEndpointFacts(storage: Storage, slugs: string[]): Promise<EndpointFact[]> {
  // `serviceSlug` IS the endpoint id — there is no separate endpointId column.
  if (slugs.length === 0) return [];
  const latest = await storage.health.latestChecks(slugs);

  const isBad = (status: string) => status === "down" || status === "degraded";
  // ONE onset query for every bad endpoint at once — cost scales with the size of the
  // outage, not with the roster, and is skipped entirely when nothing is bad.
  const badSlugs = latest.filter((h) => isBad(h.status)).map((h) => h.service_slug);
  const onsetSec = new Map<string, number>();
  if (badSlugs.length > 0) {
    for (const r of await storage.health.badRunOnsets(badSlugs)) {
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
