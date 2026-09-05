import { sql, eq, and, inArray, isNull, type SQL } from "drizzle-orm";
import { checkpointWal, type Db, type LibsqlConnection } from "../libsql/client";
import type { StatusConfig } from "../config/port";
import { deployments, healthChecks, siteGroups, issues, monitoredEndpoints } from "../libsql/schema";
import {
  listActiveEndpoints,
  reconcileOrphanedEndpoints,
  retireEndpoint,
  type ConfiguredEndpoint,
} from "../storage/config-store";
import { probeEndpoints } from "./probe";
import { matchRosterEntry, readRoster, reconcileBoardLedger, rosterTargets } from "../board";
import { recordPlatformObservations, recordVercelProdStates, type PlatformObservation } from "./observations";
import { providerConnFromConfig, type ProviderConn } from "@agentic-toolkit/deploy-platform/conn";
import { endpointsClaimedByNothing, platformCanon } from "@agentic-toolkit/deploy-platform";
import { enumerateDeployProjectsVerified } from "@agentic-toolkit/deploy-platform/enumerate";
import { fetchVercelDeployments } from "./fetch-vercel";
import { fetchVercelProductionStates, type VercelProjectsResult } from "./fetch-vercel-projects";
import { syncVercelProjectMeta } from "./refresh-project-meta";
import { fetchCloudflareDeployments } from "./fetch-cloudflare";
import { resolveCfAccountForConn } from "@agentic-toolkit/deploy-platform/providers";
import { fetchRailwayDeployments } from "./fetch-railway";
import { fetchCrunchyClusters } from "./fetch-crunchy";
import { webhookKeepsStoredSql } from "./deploy-status";
import { enrichDeployErrors } from "./enrich-deploy-errors";
import { reconcileVanishedDeploys, expireUnconfirmedDeploys } from "./reconcile-stuck-deploys";
import type { ProviderDeploy } from "./provider-deploy";
import { rateLimitedUntil, type ProviderName } from "@agentic-toolkit/deploy-platform/cooldown";
import { hostOf } from "./url";
import { notifyIssueAlert } from "./alerts";

// ---------------------------------------------------------------------------
// The periodic monitoring cycle — composed from the ported monitor modules.
// `runCycle` is the full server-side sweep that the pre-redesign cron + the live
// route did between them: probe every active endpoint, persist the checks, roll
// up the hourly metrics, poll the deploy providers, upsert their deployments,
// and derive the issue rows. `runMaintenance` is the retention prune.
//
// Every PROVIDER poll is individually guarded (try/catch each) so a missing
// token or a provider API error degrades to "unreachable" for THAT provider and
// records a platform-health blind spot — it never aborts the cycle. The fetchers
// already encode network errors as `{ ok: false }`; the guard here additionally
// catches a thrown error (an unexpected throw inside a fetcher) and turns it into
// the same `ok: false` shape so the cycle is fail-soft. (dependency-injection:
// the Db is always passed in; no singleton.)
// ---------------------------------------------------------------------------

const EMPTY_DEPLOYS = { ok: false as const, deploys: [] as ProviderDeploy[] };
const EMPTY_PROJECTS: VercelProjectsResult = { ok: false, states: [], meta: [], deploys: [] };

/** Hard cap on a single provider poll. Without it, ONE slow/hung platform (a
 *  serial per-project loop, or an un-timed-out `fetch`) can run long enough that
 *  the whole cycle blows the scheduler's watchdog budget and never completes —
 *  which makes the supervisor's `/health` read stale and restart the container.
 *  Sized well under the cycle budget so several capped polls still fit. */
const PROVIDER_POLL_TIMEOUT_MS = 20_000;

/**
 * Delete a set of monitors that describe something which no longer exists, and return the
 * endpoints that survive.
 *
 * `retireEndpoint` is the same operation the editor's Delete performs: it purges the
 * endpoint's checks and hourly metrics, resolves its open issues, and drops the owning site
 * when that was its last monitor — so what disappeared leaves the board completely rather
 * than trading a stale Problem for a stale row.
 *
 * Per-endpoint failures are logged and swallowed: the cycle must not abort mid-sweep, and a
 * retire that didn't land is simply retried next cycle — `retireEndpoint` is idempotent, an
 * already-deleted id is a no-op, and it deletes the endpoint row FIRST so a partial failure
 * can't leave a live monitor with its history (and its clock) erased. `why` is per-endpoint
 * so the log says which evidence condemned this row; picking the doomed set is entirely the
 * callers' job (below), because that is where the safety lives.
 *
 * Every removal also ALERTS. This is the only automatic deletion of operator config in the
 * system, and a `[sync]` line in container stdout is not a notification — worse, the target
 * usually has an `opened` alert outstanding from days ago, and deleting the monitor deletes
 * the only thing that could ever have closed it. `retired` is its own kind precisely so the
 * close doesn't masquerade as a recovery (see alerts.ts).
 */
async function retireMonitors(
  db: Db,
  endpoints: ConfiguredEndpoint[],
  doomed: readonly ConfiguredEndpoint[],
  why: (ep: ConfiguredEndpoint) => string,
): Promise<ConfiguredEndpoint[]> {
  if (doomed.length === 0) return endpoints;
  const retired = new Set<string>();
  for (const ep of doomed) {
    const reason = why(ep);
    try {
      await retireEndpoint(db, ep.slug);
      retired.add(ep.slug);
      console.log(`[sync] removed monitor ${ep.name} (${ep.url}) — ${reason}`);
      notifyIssueAlert({
        kind: "retired",
        target: ep.slug,
        name: ep.name,
        environment: ep.environment,
        state: null,
        detail: reason,
      });
    } catch (err) {
      console.error(`[sync] failed to remove monitor ${ep.slug} (${reason}):`, err);
    }
  }
  return endpoints.filter((e) => !retired.has(e.slug));
}

/**
 * Remove every monitor that describes something no platform has any more — the ONE
 * automatic deletion rule.
 *
 * Two lists decide it, and both are read fresh in the same cycle: the PLATFORM INVENTORY
 * (every project on every configured provider, plus the domains each one serves) and the
 * board's OWN config (this `endpoints` list, already pruned of anything structurally
 * orphaned by step 0's `reconcileOrphanedEndpoints`). A monitor wired to a project the
 * inventory no longer lists, or an unwired monitor whose host no project serves, is config
 * describing something that stopped existing — so it goes, rather than being surfaced as a
 * chore. `endpointsClaimedByNothing` owns the rule and every precondition on it; nothing is
 * re-derived here, because a second copy of that safety is a second thing to drift.
 *
 * DNS is not consulted. A name that stopped resolving explains why an endpoint is DOWN; it
 * is not evidence that its deployment was deleted, and a broken site's monitor is the alarm,
 * not the mess.
 *
 * Two things this caller owns because the rule can't see them:
 *
 *  • `stillServing` — the endpoints this cycle probed HEALTHY — VETOES removal. A project is
 *    keyed by NAME, so a rename or a team transfer reads exactly like a deletion, and a URL
 *    that is answering is a site worth watching whatever the inventory says. (A genuinely
 *    deleted project takes its deployment down with it, so the healthy case is precisely the
 *    ambiguous one.) This is the last line of defence against acting on a wrong-scope read.
 *  • the `withheld` lines are LOGGED. An empty verdict from a blind pass and an empty
 *    verdict from a healthy fleet are opposite facts and must never look alike in the log.
 */
async function retireUnclaimedMonitors(
  db: Db,
  endpoints: ConfiguredEndpoint[],
  projects: readonly { platform: string; projectName: string; domains: string[] }[],
  evidence: { configuredPlatforms: string[]; verifiedPlatforms: string[]; verifiedDomains: string[] },
  stillServing: ReadonlySet<string>,
): Promise<ConfiguredEndpoint[]> {
  const { doomed, withheld } = endpointsClaimedByNothing(endpoints, projects, evidence);
  for (const reason of withheld) console.log(`[sync] not removing monitors — ${reason}`);
  return retireMonitors(
    db,
    endpoints,
    doomed.filter((ep) => !stillServing.has(ep.slug)),
    (ep) =>
      ep.deployProject
        ? `its ${platformCanon(ep.platform ?? "")} project "${ep.deployProject}" no longer exists`
        : `no deploy project serves ${hostOf(ep.url)} any more`,
  );
}

/** Run one provider poll, guarded: a thrown error OR a poll that exceeds
 *  {@link PROVIDER_POLL_TIMEOUT_MS} degrades to `{ ok: false }` (the same shape the
 *  fetchers return on a network failure) so the cycle never aborts — or wedges —
 *  on one provider. A poll abandoned by the timeout keeps running to its own
 *  AbortController deadline, so its sockets settle on their own. */
export async function guard<T extends { ok: boolean }>(
  label: string,
  provider: ProviderName | null,
  fallback: T,
  fn: () => Promise<T>,
): Promise<T> {
  // The cooldown gate lives HERE, at the one wrapper every cycle poll crosses —
  // not only inside each fetcher, where it is a convention a new provider's author
  // has to remember (and where a typo'd name would silently disable it). A
  // rate-limited provider is skipped outright: `ok:false` so the caller treats it
  // as unreachable (skipping the prune) without spending a request that would only
  // extend the throttle.
  if (provider) {
    const until = rateLimitedUntil(provider);
    if (until) {
      console.error(`[sync] ${label} is rate-limited — skipping until ${new Date(until).toISOString()}`);
      return fallback;
    }
  }
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      fn(),
      new Promise<T>((resolve) => {
        timer = setTimeout(() => {
          console.error(`[sync] ${label} poll exceeded ${PROVIDER_POLL_TIMEOUT_MS}ms — treating as unreachable`);
          resolve(fallback);
        }, PROVIDER_POLL_TIMEOUT_MS);
      }),
    ]);
  } catch (err) {
    console.error(`[sync] ${label} poll threw — treating as unreachable:`, err);
    return fallback;
  } finally {
    clearTimeout(timer);
  }
}

function cfg(conn: ProviderConn): {
  vercelToken: boolean;
  cloudflareToken: boolean;
  railwayToken: boolean;
  crunchyToken: boolean;
} {
  return {
    vercelToken: !!conn.vercel.token,
    cloudflareToken: !!conn.cloudflare.token,
    railwayToken: !!conn.railway.token,
    crunchyToken: !!conn.crunchy.token,
  };
}

/**
 * One full monitoring cycle.
 *
 * Steps:
 *  1. Read the active endpoint list (`listActiveEndpoints`).
 *  2. Probe every endpoint (`probeEndpoints`).
 *  3. Insert one `health_checks` row per probe.
 *  4. Roll up `metrics_hourly` for the touched service/hour buckets.
 *  5. Record this poll's observations — the health checks above, and later the Vercel
 *     production-staleness mirror and each provider's reachability. The cycle only ever
 *     RECORDS what it saw; deciding what is a Problem is `deriveBoard`'s job alone.
 *  6. Poll each deploy provider from the DB integration config — EACH guarded.
 *  7. Upsert the fetched deploys into `deployments`, prune old rows (only when a
 *     fetch succeeded), stamp each deploy's live host from the explicit endpoint
 *     wiring, and upsert Vercel project metadata.
 *  8. Enumerate the platform inventory and remove any monitor it no longer accounts for
 *     (`retireUnclaimedMonitors`), then fold every fact into a board and write that
 *     verdict to the ledger (`reconcileBoardLedger`).
 *
 * Config is DELETED for having stopped existing in exactly two places, and each answers a
 * different half of the same question. Step 0 is STRUCTURAL — an endpoint or site the
 * configured group→site→endpoint chain no longer owns. Step 8 is the PLATFORM inventory —
 * a monitor no project accounts for. Both are gated on evidence that survives a transient
 * failure (see `reconcileOrphanedEndpoints` and `endpointsClaimedByNothing`), and neither
 * leaves anything for the operator to clean up by hand: a monitor for something that is gone
 * is simply gone.
 *
 * `opts.skipDeploys` runs steps 0-5 (the cheap endpoint probe + its ledger write) plus the
 * bounded in-flight reconcile, then returns before the rest of step 6. The scheduler passes
 * it on the fast probe-only ticks so the expensive provider polls (steps 6-8: four provider
 * APIs, each up to the 20s `guard`) run on a slower cadence instead of starving the HTTP
 * event loop every probe interval — the decoupling that keeps the container's `/health`
 * responsive (see index.ts + [[fetch-railway]]). The reconcile is exempt because it is the
 * only thing keeping an in-flight row honest between polls; it is by-id, capped, and a
 * no-op when nothing is in flight.
 */
export async function runCycle(db: Db, config: StatusConfig, opts?: { skipDeploys?: boolean }): Promise<void> {
  // --- 0. config integrity -------------------------------------------------
  // The structural half of the ownership reconcile: prune any endpoint or site no
  // longer owned by a configured site (group→site→endpoint chain intact) BEFORE
  // reading the active list, so the whole cycle — probe, recorders, and the ledger
  // write below (reconcileBoardLedger) — operates on owned config only. Its own guard
  // skips an empty/transient config; it never deletes a live endpoint whose domain
  // merely went down.
  const pruned = await reconcileOrphanedEndpoints(db);
  if (pruned.prunedEndpointIds.length > 0) {
    // Resolve the pruned endpoints' open issues here and now. The ledger write below
    // passes `skipOnEmptyRoster: true`; if this prune emptied the roster that call skips,
    // leaving a phantom open issue. Targeted to the pruned slugs only — never a
    // mass-resolve.
    //
    // `unmonitored`, explicitly: the endpoint stopped being watched, and NOTHING was
    // observed to recover. Leaving the reason NULL would be silent by accident — NULL is
    // documented as "resolved before this column existed, so we claim nothing", and this
    // close knows exactly why it happened.
    await db
      .update(issues)
      .set({ resolvedAt: new Date(), resolvedReason: "unmonitored", updatedAt: new Date() })
      .where(and(isNull(issues.resolvedAt), inArray(issues.target, pruned.prunedEndpointIds)));
  }

  // --- 1. config -----------------------------------------------------------
  const endpoints = await listActiveEndpoints(db);

  // The endpoints that still describe something real. Narrowed as the cycle learns what has
  // disappeared — hosts here in step 5, deploy projects in step 8 — so every step downstream
  // judges only surviving config and can't re-derive anything for a monitor already deleted.
  // `endpoints` stays the list we READ, which is what the emptiness guards below key on.
  let live = endpoints;

  // The endpoints this cycle probed HEALTHY. Read by step 8's retire as a veto: a URL that
  // is serving is a site worth watching whatever its deploy wiring claims. Empty until the
  // probe block runs — which, when step 8 runs at all, it has (the early return below).
  let stillServing: ReadonlySet<string> = new Set<string>();

  // --- 2-5. probe → record → rollup ----------------------------------------
  if (endpoints.length > 0) {
    const results = await probeEndpoints(endpoints);
    stillServing = new Set(results.filter((r) => r.status === "healthy").map((r) => r.slug));

    await db.insert(healthChecks).values(
      results.map((r) => ({
        serviceSlug: r.slug,
        status: r.status,
        responseTimeMs: r.responseTimeMs,
        statusCode: r.statusCode,
        error: r.error,
        dnsOk: r.dnsOk,
      })),
    );

    await rollupMetrics(
      db,
      results.map((r) => r.slug),
    );
  }

  // Fast probe-only tick: steps 0-5 (probe + the ledger write) are cheap and MUST run every
  // interval to keep freshness green; the deploy block below (poll → upsert → derive issues)
  // is the expensive, loop-starving phase, so on these ticks we stop here and let the
  // slower-cadence full sync (index.ts) do it. Steps 6-8 are the tail of the cycle, so this
  // single early return cleanly skips the expensive poll with nothing left unrun.
  //
  // The ONE exception is healing in-flight rows. Only the deploy block terminalizes a
  // finished build, so at its 5-minute cadence the board kept asserting "building" for
  // deploys the provider had marked READY minutes earlier. This re-fetch is NOT the poll:
  // it is by-id, capped at RECONCILE_MAX_PER_CYCLE, and no-ops on an indexed candidate
  // query whenever nothing is in flight — the steady state — so it costs one small query
  // per tick and only does real work during a deploy burst, which is exactly when the
  // board goes stale. `providerConnFromConfig` is a small local read (integrations table +
  // env), not a provider call, so it is safe at this cadence.
  if (opts?.skipDeploys) {
    await reconcileVanishedDeploys(db, await providerConnFromConfig(db));
    // The fast tick must still write the ledger. applyHttpIssues used to run above this
    // return, and opening an HTTP issue is what pages on-call; folding here keeps
    // probe-to-alert at the probe interval instead of the 5-minute full-sync cadence.
    // Folding the WHOLE board on a probe-only tick is correct and cheap: it reads
    // persisted deploy rows, so it re-derives the same deploy verdicts and writes nothing.
    await reconcileBoardLedger(db, config, { skipOnEmptyRoster: true });
    return;
  }

  // --- 6. poll providers (each guarded) ------------------------------------
  // Connections come from the DB integrations table — non-secret config there,
  // tokens from env by name. The token presence drives whether a provider is even
  // polled (and whether it counts as "configured" for platform-health).
  const conn = await providerConnFromConfig(db);
  const has = cfg(conn);

  // The live-production-vs-latest-build staleness check (a project frozen on an old
  // errored production deploy while newer builds pile up unpromoted).
  const prod = has.vercelToken
    ? await guard("vercel-projects", "vercel", EMPTY_PROJECTS, () =>
        fetchVercelProductionStates({ VERCEL_API_TOKEN: conn.vercel.token, VERCEL_TEAM_ID: conn.vercel.teamId }),
      )
    : EMPTY_PROJECTS;

  // Resolve the CF account (token alone suffices, via memoized discovery) so the poll
  // cycle fetches CF deploys even when CLOUDFLARE_ACCOUNT_ID is blank — consistent with
  // auto-wire. The memo means this is a single network probe, not one per cycle.
  const cfAccount = has.cloudflareToken ? await resolveCfAccountForConn(conn.cloudflare) : null;

  const [vc, cf, ry, cr] = await Promise.all([
    has.vercelToken
      ? guard("vercel", "vercel", EMPTY_DEPLOYS, () =>
          fetchVercelDeployments({ VERCEL_API_TOKEN: conn.vercel.token, VERCEL_TEAM_ID: conn.vercel.teamId }),
        )
      : Promise.resolve(EMPTY_DEPLOYS),
    cfAccount
      ? guard("cloudflare", "cloudflare", EMPTY_DEPLOYS, () =>
          fetchCloudflareDeployments({
            CLOUDFLARE_API_TOKEN: conn.cloudflare.token,
            CLOUDFLARE_ACCOUNT_ID: cfAccount,
            workerScripts: conn.cloudflare.workerScripts,
          }),
        )
      : Promise.resolve(EMPTY_DEPLOYS),
    has.railwayToken
      ? guard("railway", "railway", EMPTY_DEPLOYS, () =>
          fetchRailwayDeployments({ RAILWAY_API_TOKEN: conn.railway.token, projects: conn.railway.projects }),
        )
      : Promise.resolve(EMPTY_DEPLOYS),
    has.crunchyToken
      ? guard("crunchy", "crunchy", EMPTY_DEPLOYS, () =>
          fetchCrunchyClusters({ CRUNCHY_API_TOKEN: conn.crunchy.token }),
        )
      : Promise.resolve(EMPTY_DEPLOYS),
  ]);

  // --- 7. upsert deploys + prune + stamp hosts + project meta --------------
  const fetched = [...prod.deploys, ...vc.deploys, ...cf.deploys, ...ry.deploys, ...cr.deploys];
  await upsertDeployments(db, fetched);
  await learnDeployProjectIds(db, fetched);

  // Explain the FAILED deploys: fetch each one's provider failure reason (Vercel
  // errorMessage / Railway build-log tail) ONCE and persist it, so the details
  // pane shows WHY a build failed. Best-effort + bounded (see enrichDeployErrors);
  // it never throws, so it can't abort the cycle.
  await enrichDeployErrors(db, conn);

  // Heal in-flight rows the recent-deploys window can no longer see: a deploy
  // burst pushes unfinished ids past the provider's ~100-row window, freezing
  // them at "building" — re-fetch those by id and persist their real phases.
  // Best-effort + bounded (see reconcileVanishedDeploys); never throws.
  await reconcileVanishedDeploys(db, conn);

  // Terminal backstop behind the healer: an in-flight row NOTHING has managed to
  // confirm for hours stops being asserted at all (→ `unknown`) instead of
  // reading "building" forever. Never throws.
  await expireUnconfirmedDeploys(db);

  // Only prune stale records if at least one fetcher succeeded, to avoid deleting
  // history when a temporary outage makes all fetchers return ok:false.
  if (vc.ok || cf.ok || ry.ok || prod.ok || cr.ok) {
    await db.delete(deployments).where(sql`${deployments.createdAt} < unixepoch() - 90 * 86400`);
  } else {
    console.error("[sync] all deploy fetchers failed — skipping prune");
  }

  // Stamp each deploy's live host from its matched monitored endpoint — the
  // EXPLICIT config, not per-platform domain enumeration.
  const roster = await readRoster(db);
  await stampLiveHosts(db, roster);
  // The same correlation for the stale-production states, which carry a project NAME and
  // nothing else — so this is the one caller with no id to try first. Routed through
  // `matchRosterEntry` anyway so there is one lookup rule rather than a second one that
  // happens to agree today.
  // No account mirror: this caller only needs the ownership MAPS, and narrowing a
  // deleted Vercel project is a Problems decision, not a correlation one. An empty
  // set is `rosterTargets`' documented way to say so — it narrows nothing.
  const { byId, byName } = rosterTargets(roster, []);
  for (const s of prod.states) {
    const owner = matchRosterEntry(
      { platform: "vercel", providerProjectId: null, projectName: s.projectName, environment: null },
      byId,
      byName,
    );
    const host = owner?.url ? hostOf(owner.url).toLowerCase() : "";
    s.liveUrl = host ? `https://${host}` : null;
  }

  // Persist Vercel project metadata (domain, repo, branch, root dir, framework) for the
  // project browser AND evict the projects this poll proves are gone — the table is the
  // enumeration's only source of "which Vercel projects exist", so leaving a deleted one
  // in it keeps offering that project forever (see refresh-project-meta). Uses the poll
  // we already ran; it never fetches again.
  // `live` is that reconcile's verdict on what still exists — non-null ONLY for a complete
  // authenticated read. Taking it from here rather than re-deriving `prod.meta`/`prod.ok`
  // below keeps ONE definition of "this read may be acted on".
  const { live: liveVercelProjects } = await syncVercelProjectMeta(db, {
    meta: prod.meta,
    ok: prod.ok,
    configured: has.vercelToken,
  });

  // --- 8. retire what vanished, then fold the world into the ledger --------
  // A Problem may only exist for a live SITE, and only while its project still EXISTS.
  // Both rules are `deriveBoard`'s now — it owns the roster and narrows Vercel targets
  // against the same `deploy_project_meta` mirror this cycle just reconciled — so the
  // cycle no longer computes an owned set of its own.
  //
  // What remains here is the monitor itself. Resolving the Problem but keeping the row
  // would only
  // move the mess: the board would carry a monitor for something that no longer exists,
  // waiting on a click to say so.
  //
  // This is the ONE place config is deleted for having stopped existing, and it needs the
  // full platform INVENTORY — every project and the domains it serves, the same read Auto
  // Configure adds from — so that adding a monitor and removing one finally judge from one
  // list. It is deliberately on the full-sync cadence (the fast probe-only ticks returned
  // long before here): the per-project domain fan-out is the expensive half, and nothing is
  // gained by noticing a deleted project seconds sooner. A throw would be a blind pass, not
  // a licence to delete, so it degrades to an unverified enumeration that condemns nothing.
  if (live.length > 0) {
    const enumerated = await enumerateDeployProjectsVerified(db).catch((err) => {
      console.error("[sync] deploy-project enumeration failed — skipping monitor removal:", err);
      return { projects: [], verifiedPlatforms: [] as string[], verifiedDomains: [] as string[] };
    });
    // Vercel's projects come from the `deploy_project_meta` mirror rather than from a call
    // the enumeration makes, so only this cycle — which just reconciled that table — can
    // vouch for them: `liveVercelProjects` is non-null ONLY for a complete authenticated
    // read. And a platform's domain lists are no more complete than the project list they
    // were fanned out over, so the domain set is intersected with the project set.
    const verifiedPlatforms = [...enumerated.verifiedPlatforms, ...(liveVercelProjects ? ["vercel"] : [])];
    live = await retireUnclaimedMonitors(
      db,
      live,
      enumerated.projects,
      {
        configuredPlatforms: [
          ...(has.vercelToken ? ["vercel"] : []),
          ...(has.railwayToken ? ["railway"] : []),
          ...(has.cloudflareToken ? ["cloudflare"] : []),
        ],
        verifiedPlatforms,
        verifiedDomains: enumerated.verifiedDomains.filter((p) => verifiedPlatforms.includes(p)),
      },
      stillServing,
    );
  }

  // The staleness mirror is site-bound INPUT, so it is recorded only when we actually have
  // sites: an empty endpoint list (only ever a transient read away) would otherwise let a
  // read narrowed to nothing rewrite the table. The guard reads `endpoints` — the list as
  // READ, before either retire — on purpose: it defends against an emptiness we merely
  // OBSERVED, not one we just CAUSED. Skipped entirely when the projects fetch failed
  // (ok:false → empty states) so a transient Vercel outage can't mass-resolve.
  if (endpoints.length > 0) {
    if (prod.ok) {
      await recordVercelProdStates(db, prod.states);
    }
  }

  // Platform-level health: a configured provider whose poll FAILED (ok:false) is
  // unreachable, so we can't see any of its deploys — record that blind spot.
  // `configured` gates on a token being present (a tokenless fetcher returns
  // ok:true, so it never looks "unreachable").
  const platformObservations: PlatformObservation[] = [
    { source: "vercel", configured: has.vercelToken, reachable: vc.ok },
    { source: "cloudflare-pages", configured: has.cloudflareToken, reachable: cf.ok },
    { source: "railway", configured: has.railwayToken, reachable: ry.ok },
    { source: "crunchy", configured: has.crunchyToken, reachable: cr.ok },
  ];
  await recordPlatformObservations(db, platformObservations);
  // AFTER both recorders and OUTSIDE the endpoints guard, so the fold sees this cycle's
  // own writes — including platform observations, which are not roster-bound and are
  // recorded past the guard's closing brace.
  //
  // `skipOnEmptyRoster` replaces the `if (endpoints.length > 0)` guard the recorders used
  // to sit behind, and is the better of the two: it keys off `facts.roster`, which
  // `readBoardFacts` selects with no `where` clause at all, while `listActiveEndpoints`
  // filters on `isActive`. Deactivating every endpoint therefore empties `endpoints` but
  // not `roster` — under the old guard that would freeze every open issue forever. Under
  // the flag it sweeps and Problems empties, which is what switching monitoring off means.
  await reconcileBoardLedger(db, config, { skipOnEmptyRoster: true });
}

/**
 * The per-tick `metrics_hourly` upsert, as SQL. Exported so the test can EXPLAIN the
 * REAL statement (see rollup-metrics.int.test.ts) rather than a copy that could drift.
 *
 * The hour predicate must stay a RANGE OVER THE BARE COLUMN. Wrapping `checked_at` in
 * arithmetic — `(checked_at / 3600) * 3600 = (unixepoch() / 3600) * 3600`, as this did —
 * is not sargable, so SQLite cannot use `idx_health_service_checked` to seek the hour and
 * instead walks EVERY historical row of every probed slug, on every tick. Against a
 * 2.7M-row table that measured 740ms of CPU per tick versus 5ms for this form (~148x) —
 * and since the table grows forever, so did the cost, until the container's CPU quota
 * could no longer absorb a tick and the supervisor restarted it. Keep the arithmetic in
 * the SELECT list (it only labels the bucket); keep it OUT of the WHERE.
 */
export function rollupMetricsSql(serviceSlugs: string[]): SQL {
  return sql`
    insert into metrics_hourly (
      service_slug, hour, total_checks, healthy_checks, degraded_checks,
      down_checks, avg_response_time_ms, min_response_time_ms, max_response_time_ms
    )
    select
      service_slug,
      (checked_at / 3600) * 3600 as hour,
      count(*),
      sum(case when status = 'healthy' then 1 else 0 end),
      sum(case when status = 'degraded' then 1 else 0 end),
      sum(case when status = 'down' then 1 else 0 end),
      avg(response_time_ms),
      min(response_time_ms),
      max(response_time_ms)
    from health_checks
    where service_slug in (${sql.join(serviceSlugs, sql`, `)})
      and checked_at >= (unixepoch() / 3600) * 3600
      and checked_at < (unixepoch() / 3600) * 3600 + 3600
    group by service_slug, hour
    on conflict(service_slug, hour) do update set
      total_checks = excluded.total_checks,
      healthy_checks = excluded.healthy_checks,
      degraded_checks = excluded.degraded_checks,
      down_checks = excluded.down_checks,
      avg_response_time_ms = excluded.avg_response_time_ms,
      min_response_time_ms = excluded.min_response_time_ms,
      max_response_time_ms = excluded.max_response_time_ms
  `;
}

/** Roll up `metrics_hourly` for the hour buckets touched by this cycle's checks.
 *  Recomputes each (service, hour) bucket from `health_checks` and upserts it, so
 *  reruns are idempotent (the unique index keeps one row per service+hour). */
async function rollupMetrics(db: Db, serviceSlugs: string[]): Promise<void> {
  const slugs = [...new Set(serviceSlugs)];
  if (slugs.length === 0) return;
  // `checked_at` is unix-seconds; aggregate only the services we just probed (their
  // current hour bucket is what changed).
  await db.run(rollupMetricsSql(slugs));
}

/** Upsert fetched provider deploys into the `deployments` table by id (phases win
 *  the update so a re-fetched build moves to its latest state). Exported for the
 *  webhook routes: a provider-pushed terminal state persists even when the deploy
 *  has already left the recent-deploys poll window. */
export async function upsertDeployments(
  db: Db,
  deploys: ProviderDeploy[],
  opts: { source?: "poll" | "webhook" } = {},
): Promise<void> {
  // Dedup by id within this batch (the projects fetch + recent fetch overlap) —
  // recent rows are appended after prod, so last-write-wins on identical data.
  const byId = new Map<string, ProviderDeploy>();
  for (const d of deploys) {
    // LAST LINE OF DEFENCE for the timestamp. Every fetcher validates at its own
    // boundary, but that is a convention each one must remember; this is the choke
    // point EVERY deploy crosses before the DB. An Invalid Date reaching the insert
    // fails the whole batch — and since the deploy stays in the provider's window,
    // it fails it again every cycle: /health goes stale and the container
    // restart-loops. One bad row must cost that row, never the cycle.
    if (!Number.isFinite(d.createdAt?.getTime?.())) {
      console.error(`[sync] deploy ${d.id} has an invalid createdAt — dropping it (fetcher should have caught this)`);
      continue;
    }
    byId.set(d.id, d);
  }
  const rows = [...byId.values()];
  if (rows.length === 0) return;

  // Webhooks arrive OUT OF ORDER — relative to the poll (a delayed deployment.created
  // after the poll already recorded READY) and relative to EACH OTHER (a redelivered
  // `created` after its own `build-requested`). Either way a webhook upsert must never
  // walk a row backwards. `webhookKeepsStoredSql` is the whole rule and states its own
  // reasoning; it lives beside the phase vocabulary so no query can drift from it.
  //
  // The POLL takes no guard: its by-id state is current truth, and a genuine
  // terminal→in-flight transition (Vercel re-promotion → ROLLING) must go through.
  const guardRegression = opts.source === "webhook";
  const phase = (col: "build_phase" | "deploy_phase"): ReturnType<typeof sql.raw> =>
    guardRegression
      ? sql.raw(`CASE WHEN ${webhookKeepsStoredSql(col)} THEN ${col} ELSE excluded.${col} END`)
      : sql.raw(`excluded.${col}`);

  await db
    .insert(deployments)
    .values(
      rows.map((d) => ({
        id: d.id,
        platform: d.platform,
        projectName: d.projectName,
        providerProjectId: d.providerProjectId ?? null,
        buildPhase: d.buildPhase,
        deployPhase: d.deployPhase,
        environment: d.environment,
        commitHash: d.commitHash,
        commitMessage: d.commitMessage,
        branch: d.branch,
        commitRepo: d.commitRepo,
        url: d.url,
        createdAt: d.createdAt,
      })),
    )
    .onConflictDoUpdate({
      target: deployments.id,
      set: {
        buildPhase: phase("build_phase"),
        deployPhase: phase("deploy_phase"),
        // NOT COALESCE and not omitted: a project renamed upstream keeps re-reporting
        // its existing deploys under the NEW name, and a row frozen at the old name
        // would sit in the table for the full 90-day retention minting a second group
        // for a single target. `platform` is deliberately absent — it is part of the
        // identity, not a description of it.
        projectName: sql`excluded.project_name`,
        // Descriptive fields COALESCE so a sparser source (a webhook event
        // without commit meta) can update the PHASES without erasing what a
        // richer fetch already recorded.
        // COALESCE, like the other descriptive columns: a webhook carries no project id,
        // and a sparser source must never erase what a richer fetch already recorded.
        providerProjectId: sql`COALESCE(excluded.provider_project_id, provider_project_id)`,
        environment: sql`COALESCE(excluded.environment, environment)`,
        commitHash: sql`COALESCE(excluded.commit_hash, commit_hash)`,
        commitMessage: sql`COALESCE(excluded.commit_message, commit_message)`,
        branch: sql`COALESCE(excluded.branch, branch)`,
        commitRepo: sql`COALESCE(excluded.commit_repo, commit_repo)`,
        url: sql`COALESCE(excluded.url, url)`,
        // Keep the EARLIEST creation time seen: webhook rows carry event-emission
        // time (later than true creation), so letting them overwrite would skew
        // ordering, the reconcile window, and stuck-deploy detection.
        createdAt: sql`min(excluded.created_at, created_at)`,
        fetchedAt: sql`(unixepoch())`,
      },
    });
}

/**
 * Learn each endpoint's provider project id from the deploys we just fetched, keyed by the
 * NAME that already matches. One poll arms every already-wired endpoint; from then on a
 * rename upstream resolves by id even though `deploy_project` still holds the OLD name,
 * which is the entire point of adopting ids.
 *
 * Idempotent and null-only: it never overwrites an id, so an operator's hand-entered value
 * always wins and a re-run is free. Nested maps rather than a composite string key — the
 * only function allowed to mint a target string is `boardTargetKey`, and this is not one
 * (a Railway project id is environment-independent, so a target key would be the wrong
 * shape here anyway).
 */
export async function learnDeployProjectIds(db: Db, deploys: ProviderDeploy[]): Promise<void> {
  const idByPlatform = new Map<string, Map<string, string>>();
  for (const d of deploys) {
    if (!d.providerProjectId) continue;
    const platform = platformCanon(d.platform);
    const byName = idByPlatform.get(platform) ?? new Map<string, string>();
    if (!byName.has(d.projectName)) byName.set(d.projectName, d.providerProjectId);
    idByPlatform.set(platform, byName);
  }
  if (idByPlatform.size === 0) return;

  const rows = await db
    .select({
      id: monitoredEndpoints.id,
      platform: monitoredEndpoints.platform,
      deployProject: monitoredEndpoints.deployProject,
    })
    .from(monitoredEndpoints)
    .where(isNull(monitoredEndpoints.deployProjectId));

  for (const r of rows) {
    if (!r.platform || !r.deployProject) continue;
    const hit = idByPlatform.get(platformCanon(r.platform))?.get(r.deployProject);
    if (!hit) continue;
    await db
      .update(monitoredEndpoints)
      .set({ deployProjectId: hit, updatedAt: new Date() })
      .where(eq(monitoredEndpoints.id, r.id));
  }
}

/**
 * Reconcile each deploy row's `live_host` with the configured endpoint wiring — only
 * writing rows whose host actually changed.
 *
 * Correlates through the BOARD's ownership rule (`src/board/ownership.ts`), not the
 * name-keyed `deployTargetKey` map it used to build. The two disagree for a project
 * renamed upstream: the board resolves the old rows by provider id and shows a Problem
 * for them, while the name lookup missed and NULLED their `live_host` — so the Problem
 * lost its `liveUrl`, the one link pointing at the thing that is broken. Environment
 * scoping is unchanged; `boardTargetKey` and `deployTargetKey` both carry an env segment
 * for railway only.
 */
async function stampLiveHosts(db: Db, roster: Awaited<ReturnType<typeof readRoster>>): Promise<void> {
  // No account mirror: this caller only needs the ownership MAPS, and narrowing a
  // deleted Vercel project is a Problems decision, not a correlation one. An empty
  // set is `rosterTargets`' documented way to say so — it narrows nothing.
  const { byId, byName } = rosterTargets(roster, []);
  const rows = await db
    .select({
      id: deployments.id,
      platform: deployments.platform,
      providerProjectId: deployments.providerProjectId,
      projectName: deployments.projectName,
      environment: deployments.environment,
      liveHost: deployments.liveHost,
    })
    .from(deployments);
  for (const d of rows) {
    const owner = matchRosterEntry(d, byId, byName);
    const host = (owner?.url ? hostOf(owner.url).toLowerCase() : "") || null;
    if ((d.liveHost ?? null) !== host) {
      await db.update(deployments).set({ liveHost: host }).where(eq(deployments.id, d.id));
    }
  }
}

/** Rows deleted per DELETE statement, and per {@link runMaintenance} call. Chunked so the
 *  prune is many small transactions instead of one enormous one: the first real prune on a
 *  long-unpruned table has millions of rows to clear, and a single DELETE of that size on a
 *  container volume means one giant transaction and a WAL to match. Bounded per call, it
 *  simply catches up over successive cycles. */
export const PRUNE_CHUNK_ROWS = 25_000;
export const PRUNE_MAX_ROWS_PER_RUN = 100_000;

/** metrics_hourly horizon: /response-history serves sparklines up to 90 days, so
 *  keep at least that — longer when a group's configured retention exceeds it. */
export const METRICS_MIN_RETENTION_DAYS = 90;
/** analytics_metrics horizon: the trend store is only ever read as "the newest
 *  rows" (see telemetry/stores/analytics.ts), so 90 days is already generous. */
export const ANALYTICS_RETENTION_DAYS = 90;
/** RESOLVED issues horizon. Closed incidents are kept as history (deleting a site resolves
 *  its Problems rather than erasing them), but "history" is bounded like every other
 *  accruing table — a self-healing flap can close and reopen an issue every cycle, so
 *  without this the one table nothing prunes grows fastest. Open issues are untouched:
 *  `resolved_at < cutoff` is never true for NULL. */
export const ISSUE_RESOLVED_RETENTION_DAYS = 90;

/** One table's chunked age prune: delete rows whose `timeCol` is before
 *  `cutoffSec`, by id from an indexed seek, at most `budget` rows in chunks of
 *  `chunkRows`. `done` is false when the budget ran out with backlog remaining. */
async function pruneChunked(
  db: Db,
  table: 'health_checks' | 'metrics_hourly' | 'analytics_metrics' | 'issues',
  timeCol: 'checked_at' | 'hour' | 'captured_at' | 'resolved_at',
  cutoffSec: number,
  chunkRows: number,
  budget: number,
): Promise<{ deleted: number; done: boolean }> {
  let deleted = 0;
  while (deleted < budget) {
    const limit = Math.min(chunkRows, budget - deleted);
    const res = await db.run(sql`
      delete from ${sql.raw(table)}
      where id in (select id from ${sql.raw(table)} where ${sql.raw(timeCol)} < ${cutoffSec} limit ${limit})
    `);
    const n = Number(res.rowsAffected ?? 0);
    deleted += n;
    if (n < limit) return { deleted, done: true }; // drained this table's backlog
  }
  return { deleted, done: false }; // budget exhausted; more next run
}

/**
 * Retention prune over EVERY accruing table — an unpruned table is a future
 * CPU/disk bomb (per-tick and per-read costs that scale with total history are
 * exactly what took the container down via `health_checks`):
 *
 *  - `health_checks`: past the longest configured group `retentionDays`.
 *  - `metrics_hourly`: past max(90d sparkline horizon, longest group retention).
 *  - `analytics_metrics`: past 90 days (only ever read as "the newest rows").
 *  - `issues`: RESOLVED rows past 90 days. Every reader filters `resolved_at is null`,
 *    so a closed issue is history — kept, but bounded like the rest.
 *  - `sessions`: expired rows (otherwise reaped only if that exact token is
 *    presented again — a session that just lapses lingers forever).
 *
 * THE SCHEDULER MUST CALL THIS (see index.ts). It used to be reachable only via
 * `POST /cron/maintenance`, which nothing on Railway ever called — so health_checks was
 * never pruned at all and grew ~193k rows/day forever, until a tick could no longer fit
 * in the container's CPU quota and the supervisor's /health probes started timing out.
 *
 * The chunk budget (`maxRows`) is shared across the chunked tables, so one huge backlog
 * is drained over successive cycles without starving the others forever. Returns total
 * rows deleted and whether every backlog is fully caught up (`done`).
 *
 * `conn` is OPTIONAL: the monitor cycle (which owns the connection) passes it so the
 * WAL truncation below runs; `POST /cron/maintenance` (no connection in its AppDeps —
 * only `db`) calls this without one and gets the prune with the checkpoint skipped
 * rather than failing the whole route over a disk-reclaim step it cannot drive.
 */
export async function runMaintenance(
  db: Db,
  conn?: LibsqlConnection,
  opts: { maxRows?: number; chunkRows?: number } = {},
): Promise<{ deleted: number; done: boolean }> {
  const maxRows = opts.maxRows ?? PRUNE_MAX_ROWS_PER_RUN;
  const chunkRows = opts.chunkRows ?? PRUNE_CHUNK_ROWS;

  const groups = await db.select({ retentionDays: siteGroups.retentionDays }).from(siteGroups);
  // The conservative horizon: keep checks at least as long as the LONGEST
  // configured retention. A per-service prune would need the endpoint→group join
  // for every slug; the longest-horizon sweep is the simple, safe prune the
  // maintenance cron needs (the UI never reads beyond the longest window anyway).
  const maxRetentionDays = groups.reduce((max, g) => Math.max(max, g.retentionDays), 14);
  const nowSec = Math.floor(Date.now() / 1000);

  const sweeps = [
    { table: 'health_checks', timeCol: 'checked_at', cutoffSec: nowSec - maxRetentionDays * 86_400 },
    {
      table: 'metrics_hourly',
      timeCol: 'hour',
      cutoffSec: nowSec - Math.max(METRICS_MIN_RETENTION_DAYS, maxRetentionDays) * 86_400,
    },
    { table: 'analytics_metrics', timeCol: 'captured_at', cutoffSec: nowSec - ANALYTICS_RETENTION_DAYS * 86_400 },
    // Only CLOSED incidents age out — an open issue has a NULL resolved_at, which no
    // `<` comparison ever selects.
    { table: 'issues', timeCol: 'resolved_at', cutoffSec: nowSec - ISSUE_RESOLVED_RETENTION_DAYS * 86_400 },
  ] as const;

  let deleted = 0;
  let done = true;
  for (const s of sweeps) {
    const budget = maxRows - deleted;
    if (budget <= 0) {
      done = false; // budget exhausted before this table got a turn
      break;
    }
    const r = await pruneChunked(db, s.table, s.timeCol, s.cutoffSec, chunkRows, budget);
    deleted += r.deleted;
    if (!r.done) {
      done = false;
      break;
    }
  }

  // Expired sessions: a tiny table (rows = logins), so one unchunked statement
  // outside the budget.
  const reaped = await db.run(sql`delete from sessions where expires_at < ${nowSec}`);
  deleted += Number(reaped.rowsAffected ?? 0);

  // Pruning rows frees PAGES, not BYTES: the deletes above are the biggest write
  // transaction this process runs, and the WAL they inflate is reused-in-place rather
  // than shrunk. Truncate it here — immediately after the sweep that grew it — so the
  // volume gets the space back instead of carrying the high-water mark forever.
  // Fail-soft: a busy checkpoint just retries next pass; a throw must not lose the
  // prune result we already earned.
  if (conn) {
    try {
      await checkpointWal(db, conn);
    } catch (err) {
      console.error(`[maintenance] wal checkpoint failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return { deleted, done };
}
