import { and, asc, eq, inArray, isNull, notInArray, notExists, sql } from "drizzle-orm";
import type { Db } from "../libsql/client";
import { platformHealthSource } from "../monitor/issue-sources";
import { normalizePeerBaseUrl } from "../peers/base-url";
import {
  siteGroups,
  monitoredSites,
  monitoredEndpoints,
  deployIntegrations,
  ignoredDeployProjects,
  peers,
  healthChecks,
  metricsHourly,
  issues,
  platformHealthState,
} from "../libsql/schema";

// ---------------------------------------------------------------------------
// The DB-backed config store — Group → Site → Endpoint, deploy-platform
// integrations, ignored projects, and peers. Every function takes the Db as a
// parameter (dependency-injection; no singleton) so the sync cycle, the CRUD
// routes (Task 13), and tests all share one store over an explicit connection.
//
// libSQL over HTTP does NOT enforce ON DELETE CASCADE, so group→site→endpoint
// deletes cascade in application code here (see deleteGroup/deleteSite).
// ---------------------------------------------------------------------------

/** One ACTIVE endpoint flattened with its site + group names — the list the
 *  probes (and /api/live) run against. */
export interface ConfiguredEndpoint {
  slug: string; // stable per endpoint — the problem target key
  group: string;
  name: string;
  environment: string | null;
  url: string;
  kind: string;
  platform: string | null; // explicit deploy-target wiring (correlation key)
  deployProject: string | null;
  /** Operator opt-out: when true, this endpoint is intentionally NOT tied to a deploy
   *  project (auto-wire must skip it, the "unconfigured" warning is suppressed). */
  ignoreProjectWarning?: boolean;
  expectedStatus: number;
  /** Optional body-content marker (see EndpointRow.expectBody). */
  expectBody?: string | null;
  /** DNS-resolution check toggles (A/AAAA/CNAME). Undefined → every type on, the
   *  pre-toggle default (see monitor/probe.ts dnsChecksOf). */
  dnsCheckA?: boolean;
  dnsCheckAaaa?: boolean;
  dnsCheckCname?: boolean;
}

export type GroupRow = typeof siteGroups.$inferSelect;
export type SiteRow = typeof monitoredSites.$inferSelect;
export type EndpointRow = typeof monitoredEndpoints.$inferSelect;
export type IntegrationRow = typeof deployIntegrations.$inferSelect;
export type PeerRow = typeof peers.$inferSelect;

export interface IgnoredProject {
  platform: string;
  projectName: string;
}

// --- groups -----------------------------------------------------------------

export function listSiteGroups(db: Db): Promise<GroupRow[]> {
  return db.select().from(siteGroups).orderBy(asc(siteGroups.name));
}

export async function createGroup(
  db: Db,
  input: { name: string; slug: string; retentionDays?: number },
): Promise<GroupRow> {
  const [row] = await db
    .insert(siteGroups)
    .values({ name: input.name, slug: input.slug, retentionDays: input.retentionDays })
    .returning();
  return row!;
}

export async function updateGroup(
  db: Db,
  id: string,
  patch: { name?: string; slug?: string; retentionDays?: number },
): Promise<GroupRow | null> {
  const [row] = await db
    .update(siteGroups)
    .set({ ...patch, updatedAt: new Date() })
    .where(eq(siteGroups.id, id))
    .returning();
  return row ?? null;
}

export async function deleteGroup(db: Db, id: string): Promise<void> {
  // libSQL doesn't enforce ON DELETE CASCADE over HTTP — delete children explicitly
  // so removing a group doesn't orphan its sites + their endpoints.
  const sites = await db
    .select({ id: monitoredSites.id })
    .from(monitoredSites)
    .where(eq(monitoredSites.siteGroupId, id));
  const siteIds = sites.map((s) => s.id);
  if (siteIds.length) {
    // Collect EVERY endpoint id across the group's sites BEFORE the cascade, then purge
    // their history + issues so the deleted group's sites vanish from Activity/Problems
    // immediately instead of waiting for the cycle sweep.
    const eps = await db
      .select({ id: monitoredEndpoints.id })
      .from(monitoredEndpoints)
      .where(inArray(monitoredEndpoints.siteId, siteIds));
    await purgeEndpointHistory(db, eps.map((e) => e.id));
    await db.delete(monitoredEndpoints).where(inArray(monitoredEndpoints.siteId, siteIds));
    await db.delete(monitoredSites).where(inArray(monitoredSites.id, siteIds));
  }
  await db.delete(siteGroups).where(eq(siteGroups.id, id));
}

// --- sites ------------------------------------------------------------------

export function listSites(db: Db): Promise<SiteRow[]> {
  return db.select().from(monitoredSites).orderBy(asc(monitoredSites.name));
}

export async function createSite(
  db: Db,
  input: { name: string; slug: string; siteGroupId: string },
): Promise<SiteRow> {
  const [row] = await db
    .insert(monitoredSites)
    .values({ name: input.name, slug: input.slug, siteGroupId: input.siteGroupId })
    .returning();
  return row!;
}

export async function updateSite(
  db: Db,
  id: string,
  patch: { name?: string; slug?: string; siteGroupId?: string },
): Promise<SiteRow | null> {
  const [row] = await db
    .update(monitoredSites)
    .set({ ...patch, updatedAt: new Date() })
    .where(eq(monitoredSites.id, id))
    .returning();
  return row ?? null;
}

/**
 * Purge an endpoint's monitoring HISTORY and close its open issues — `health_checks` +
 * `metrics_hourly` (both keyed by `service_slug` = endpoint id) are DELETED; `issues`
 * (keyed by `target` = endpoint id) are RESOLVED. An endpoint's public slug IS its row id
 * (see `listActiveEndpoints`), so deleting a monitor must do this in the same request or
 * the gone endpoint lingers in Activity/Problems until the next cycle sweep. Every delete
 * path (site / endpoint-retire / group) funnels through here so the store consistently
 * owns it; the cross-cutting orphaned-issue reconcile stays the route's job.
 * Exported so a shared platform core can lift it later.
 *
 * Issues are resolved rather than deleted deliberately: a Problem is a RECORD of an
 * outage, and the incident history outlives the monitor that observed it. Stamping
 * `resolved_at` drops the row out of Problems (which reads `resolved_at is null`) while
 * leaving it readable as history. The raw probe rows have no such value — they are
 * volume, not history — so those really are deleted.
 */
export async function purgeEndpointHistory(db: Db, epIds: string[]): Promise<void> {
  if (epIds.length === 0) return;
  await db.delete(healthChecks).where(inArray(healthChecks.serviceSlug, epIds));
  await db.delete(metricsHourly).where(inArray(metricsHourly.serviceSlug, epIds));
  // Only the still-open rows: an already-resolved issue keeps the timestamp it actually
  // closed at, rather than being restamped with the moment its site was deleted.
  //
  // `unmonitored`, explicitly: the monitor was deleted, so nothing was observed to
  // recover. NULL would read as "resolved before this column existed" — the one thing
  // this close is not.
  await db
    .update(issues)
    .set({ resolvedAt: new Date(), resolvedReason: "unmonitored", updatedAt: new Date() })
    .where(and(inArray(issues.target, epIds), isNull(issues.resolvedAt)));
}

export async function deleteSite(db: Db, id: string): Promise<void> {
  // libSQL doesn't enforce ON DELETE CASCADE over HTTP — delete endpoints first, purging
  // their history + issues so a deleted site vanishes from Activity/Problems immediately
  // instead of waiting for the cycle sweep.
  const eps = await db
    .select({ id: monitoredEndpoints.id })
    .from(monitoredEndpoints)
    .where(eq(monitoredEndpoints.siteId, id));
  await purgeEndpointHistory(db, eps.map((e) => e.id));
  await db.delete(monitoredEndpoints).where(eq(monitoredEndpoints.siteId, id));
  await db.delete(monitoredSites).where(eq(monitoredSites.id, id));
}

// --- endpoints --------------------------------------------------------------

export function listEndpoints(db: Db, siteId?: string): Promise<EndpointRow[]> {
  const base = db.select().from(monitoredEndpoints);
  const filtered = siteId ? base.where(eq(monitoredEndpoints.siteId, siteId)) : base;
  return filtered.orderBy(asc(monitoredEndpoints.url));
}

export async function createEndpoint(
  db: Db,
  input: {
    siteId: string;
    url: string;
    kind?: string;
    environment?: string | null;
    platform?: string | null;
    deployProject?: string | null;
    deployProjectId?: string | null;
    ignoreProjectWarning?: boolean;
    expectedStatus?: number;
    expectBody?: string | null;
    dnsCheckA?: boolean;
    dnsCheckAaaa?: boolean;
    dnsCheckCname?: boolean;
    checkIntervalSeconds?: number;
    isActive?: boolean;
    monitorHttp?: boolean;
    monitorDeploys?: boolean;
  },
): Promise<EndpointRow> {
  const [row] = await db
    .insert(monitoredEndpoints)
    .values({
      siteId: input.siteId,
      url: input.url,
      kind: input.kind,
      environment: input.environment,
      platform: input.platform,
      deployProject: input.deployProject,
      deployProjectId: input.deployProjectId,
      ignoreProjectWarning: input.ignoreProjectWarning,
      expectedStatus: input.expectedStatus,
      expectBody: input.expectBody,
      dnsCheckA: input.dnsCheckA,
      dnsCheckAaaa: input.dnsCheckAaaa,
      dnsCheckCname: input.dnsCheckCname,
      checkIntervalSeconds: input.checkIntervalSeconds,
      isActive: input.isActive,
      monitorHttp: input.monitorHttp,
      monitorDeploys: input.monitorDeploys,
    })
    .returning();
  return row!;
}

export async function updateEndpoint(
  db: Db,
  id: string,
  patch: {
    url?: string;
    kind?: string;
    environment?: string | null;
    platform?: string | null;
    deployProject?: string | null;
    deployProjectId?: string | null;
    ignoreProjectWarning?: boolean;
    expectedStatus?: number;
    expectBody?: string | null;
    dnsCheckA?: boolean;
    dnsCheckAaaa?: boolean;
    dnsCheckCname?: boolean;
    checkIntervalSeconds?: number;
    isActive?: boolean;
    monitorHttp?: boolean;
    monitorDeploys?: boolean;
  },
): Promise<EndpointRow | null> {
  const [row] = await db
    .update(monitoredEndpoints)
    .set({ ...patch, updatedAt: new Date() })
    .where(eq(monitoredEndpoints.id, id))
    .returning();
  return row ?? null;
}

export async function deleteEndpoint(db: Db, id: string): Promise<void> {
  await db.delete(monitoredEndpoints).where(eq(monitoredEndpoints.id, id));
}

// --- the assembled probe list the sync reads (replaces ACTIVE_SERVICES) ------

/** Active endpoints joined to their site + group — the list the health sync probes. */
export async function listActiveEndpoints(db: Db): Promise<ConfiguredEndpoint[]> {
  const rows = await db
    .select({
      epId: monitoredEndpoints.id,
      url: monitoredEndpoints.url,
      kind: monitoredEndpoints.kind,
      environment: monitoredEndpoints.environment,
      platform: monitoredEndpoints.platform,
      deployProject: monitoredEndpoints.deployProject,
      ignoreProjectWarning: monitoredEndpoints.ignoreProjectWarning,
      expectedStatus: monitoredEndpoints.expectedStatus,
      expectBody: monitoredEndpoints.expectBody,
      dnsCheckA: monitoredEndpoints.dnsCheckA,
      dnsCheckAaaa: monitoredEndpoints.dnsCheckAaaa,
      dnsCheckCname: monitoredEndpoints.dnsCheckCname,
      isActive: monitoredEndpoints.isActive,
      siteName: monitoredSites.name,
      groupName: siteGroups.name,
    })
    .from(monitoredEndpoints)
    .innerJoin(monitoredSites, eq(monitoredEndpoints.siteId, monitoredSites.id))
    .innerJoin(siteGroups, eq(monitoredSites.siteGroupId, siteGroups.id));
  return rows
    .filter((r) => r.isActive)
    .map((r) => ({
      slug: r.epId,
      group: r.groupName,
      name: r.siteName,
      environment: r.environment,
      url: r.url,
      kind: r.kind,
      platform: r.platform,
      deployProject: r.deployProject,
      ignoreProjectWarning: r.ignoreProjectWarning ?? false,
      expectedStatus: r.expectedStatus,
      expectBody: r.expectBody,
      dnsCheckA: r.dnsCheckA,
      dnsCheckAaaa: r.dnsCheckAaaa,
      dnsCheckCname: r.dnsCheckCname,
    }));
}

/**
 * Prune config rows NOT owned by a configured site — the structural counterpart to
 * `reconcileBoardLedger` (which closes issues no live target claims). A *configured site* is a
 * `monitored_sites` row that belongs to an existing `site_group`: the full
 * group→site→endpoint chain `listActiveEndpoints` inner-joins on. libSQL doesn't
 * enforce `ON DELETE CASCADE` over HTTP, and a partial/failed delete — or a legacy
 * auto-created row — can leave an endpoint whose site is gone, or a site whose group
 * is gone. Such a row is invisible to the probe (the inner-join drops it) yet lingers
 * in the editor's site/endpoint lists forever. This removes them so an endpoint can
 * never outlive its owning site, and a site can never outlive its group.
 *
 * SAFETY: if there are ZERO configured sites it does nothing — a transient or
 * pre-seed empty config must never be read as "everything is orphaned, delete it
 * all" (mirrors the `endpoints.length > 0` guard the issue reconcile uses). And a
 * cheap one-query probe lets the steady state (always so under prod FK cascade) skip
 * the deletes entirely. Returns the pruned endpoint ids so the caller can resolve
 * their open issues even when the prune empties the active list (which would
 * otherwise skip the gated issue reconcile).
 *
 * Note this does NOT remove a live endpoint whose DOMAIN merely stopped resolving —
 * that endpoint IS owned by a configured site, and a real DNS outage must surface,
 * not silently self-delete. Retiring a dead-domain monitor is an explicit delete.
 */
export async function reconcileOrphanedEndpoints(
  db: Db,
): Promise<{ endpoints: number; sites: number; prunedEndpointIds: string[] }> {
  const none = { endpoints: 0, sites: 0, prunedEndpointIds: [] as string[] };
  // One round-trip probe: how many orphans exist, and is there any configured site?
  // Steady state (and always under prod FK cascade) is zero orphans → skip all writes.
  const probe = await db.get<{ orphanEndpoints: number; orphanSites: number; configuredSites: number }>(sql`
    select
      (select count(*) from monitored_endpoints e
         where e.site_id not in (select s.id from monitored_sites s join site_groups g on s.site_group_id = g.id)) as "orphanEndpoints",
      (select count(*) from monitored_sites s
         where s.site_group_id not in (select id from site_groups)) as "orphanSites",
      (select count(*) from monitored_sites s join site_groups g on s.site_group_id = g.id) as "configuredSites"
  `);
  if (!probe || (Number(probe.orphanEndpoints) === 0 && Number(probe.orphanSites) === 0)) return none;
  if (Number(probe.configuredSites) === 0) return none; // never mass-delete an empty/transient config

  // The set of CONFIGURED site ids (a site joined to a live group) — recomputed fresh
  // as a subquery at DELETE time, so orphan determination and deletion happen in ONE
  // atomic statement: a concurrent createSite/createEndpoint can't be observed-absent-
  // then-deleted (the TOCTOU a read-ids-then-delete sequence would have). `.returning`
  // gives the rows that were ACTUALLY removed (honest counts even on a partial failure).
  const configuredSiteIds = () =>
    db.select({ id: monitoredSites.id }).from(monitoredSites).innerJoin(siteGroups, eq(monitoredSites.siteGroupId, siteGroups.id));
  let prunedEndpointIds: string[] = [];
  let sites = 0;
  try {
    const epDeleted = await db
      .delete(monitoredEndpoints)
      .where(notInArray(monitoredEndpoints.siteId, configuredSiteIds()))
      .returning({ id: monitoredEndpoints.id });
    prunedEndpointIds = epDeleted.map((r) => r.id);
    const siteDeleted = await db
      .delete(monitoredSites)
      .where(notInArray(monitoredSites.id, configuredSiteIds()))
      .returning({ id: monitoredSites.id });
    sites = siteDeleted.length;
  } catch (err) {
    console.error(`[config] orphan endpoint/site reconcile failed:`, err);
  }
  return { endpoints: prunedEndpointIds.length, sites, prunedEndpointIds };
}

/**
 * Delete one endpoint and, IFF its site has no endpoints left, the site too — the
 * server-side owner of the "retire a monitor" operation. The empty-site check is a
 * single atomic conditional delete (`... AND NOT EXISTS (endpoints for this site)`),
 * so the decision is made on FRESH server state, never a stale client count, and a
 * concurrent createEndpoint for the same site can't be cascade-deleted out from under
 * it. Replaces the old client-side "deleteEndpoint then maybe deleteSite" dance (which
 * could cascade-delete a healthy sibling when the client's endpoint list was stale).
 *
 * The statements are NOT one transaction (the embedded driver's `transaction()` is not
 * available over the HTTP connection mode `createDb` also supports), so their ORDER is the
 * durability story: the endpoint row — the only one whose loss can't be reconstructed or
 * swept — goes FIRST. A failure after that leaves orphaned checks/metrics/issues, which the
 * cycle's own reconcile and the retention prune already clean up. The reverse order is what
 * must not happen: purging first and then failing to delete leaves a LIVE monitor whose
 * history was erased, which silently resets both its uptime record and the very clock that
 * condemned it.
 */
export async function retireEndpoint(db: Db, id: string): Promise<{ endpointDeleted: boolean; siteDeleted: boolean }> {
  const [ep] = await db.select({ siteId: monitoredEndpoints.siteId }).from(monitoredEndpoints).where(eq(monitoredEndpoints.id, id));
  if (!ep) return { endpointDeleted: false, siteDeleted: false };
  await db.delete(monitoredEndpoints).where(eq(monitoredEndpoints.id, id));
  // Purge exactly the id being removed by THIS call so retiring a monitor clears it from
  // Activity/Problems in-request. If this empties the site (and the site is deleted
  // below), the site had no OTHER endpoints — so there is nothing else to purge; a
  // sibling endpoint that keeps the site alive keeps its own history untouched.
  await purgeEndpointHistory(db, [id]);
  const siteGone = await db
    .delete(monitoredSites)
    .where(
      and(
        eq(monitoredSites.id, ep.siteId),
        notExists(db.select({ one: sql`1` }).from(monitoredEndpoints).where(eq(monitoredEndpoints.siteId, ep.siteId))),
      ),
    )
    .returning({ id: monitoredSites.id });
  return { endpointDeleted: true, siteDeleted: siteGone.length > 0 };
}

// --- deploy-platform integrations -------------------------------------------

export function listIntegrations(db: Db): Promise<IntegrationRow[]> {
  return db.select().from(deployIntegrations).orderBy(asc(deployIntegrations.platform));
}

export async function createIntegration(
  db: Db,
  input: {
    platform: string;
    label: string;
    config?: unknown;
    tokenEnvVar?: string | null;
    isActive?: boolean;
  },
): Promise<IntegrationRow> {
  const [row] = await db
    .insert(deployIntegrations)
    .values({
      platform: input.platform,
      label: input.label,
      // The core deploy_integrations.config column is $type<Record<string, unknown>>;
      // the public input stays `unknown`, so cast at the drizzle boundary (runtime value
      // unchanged — an object or the `{}` default).
      config: (input.config ?? {}) as Record<string, unknown>,
      tokenEnvVar: input.tokenEnvVar,
      isActive: input.isActive,
    })
    .returning();
  return row!;
}

export async function updateIntegration(
  db: Db,
  id: string,
  patch: { platform?: string; label?: string; config?: unknown; tokenEnvVar?: string | null; isActive?: boolean },
): Promise<IntegrationRow | null> {
  const [row] = await db
    .update(deployIntegrations)
    // config stays `unknown` on the public patch; cast it to the core column's
    // $type<Record<string, unknown>> at the boundary. When patch omits config the value
    // is undefined, which drizzle drops from the SET clause — behavior unchanged.
    .set({ ...patch, config: patch.config as Record<string, unknown> | undefined, updatedAt: new Date() })
    .where(eq(deployIntegrations.id, id))
    .returning();
  return row ?? null;
}

/**
 * Delete a deploy-platform integration, AND un-configure the platform-health row it was
 * the last active speaker for — in one batch, because the two are one fact.
 *
 * The second half is what makes the callers' `reconcileBoardLedger(db)` sweep actually do
 * what they say. `platformProblems` reads `facts.platforms`, a straight read of
 * `platform_health_state`, whose `configured` column is otherwise only ever rewritten by
 * `recordPlatformObservations` inside a monitor cycle. Deleting just the integration row
 * therefore left that column saying `true`, the Problem was still derivable, the target
 * was still in `monitoredTargets`, and the open ledger row stayed open until the next full
 * cycle — exactly what the sweep documents itself as preventing (constraint 8), and
 * Requirement A ("turning off any monitoring switch removes the site from Problems")
 * unmet for platform health while it held for endpoint switches.
 *
 * ONLY EVER WRITES `false`, and only when NO active integration for that platform is left.
 * The monitor's own rule is stricter still (it also requires a token), so this can only
 * agree with it or lag it — never claim `configured` where the cycle would not. That
 * one-directional weakening is what keeps this from becoming a second producer of "is this
 * platform configured" (constraint 1): the cycle remains the only thing that can turn it
 * back on.
 *
 * `updatedAt` is deliberately NOT touched. That column is the monitor's heartbeat and one
 * of the two families `Board.dataAsOfMs` is built from (`board/derive.ts`); stamping it
 * from an API-thread config mutation would be the same "a write that is not a cycle
 * refreshes the data clock" defect that fix, in the deploy families' shape.
 *
 * The two writes go through `db.batch`, NOT `db.transaction`. The libSQL sqlite3 client's
 * `transaction()` hands the caller its connection and sets its own handle to null, so the
 * next statement lazily opens a NEW connection — which for the `:memory:` URL every test
 * uses is a brand-new EMPTY database. `batch()` keeps the one connection and wraps the
 * statements in BEGIN/COMMIT itself, so it is atomic here and works in-memory too.
 */
export async function deleteIntegration(db: Db, id: string): Promise<void> {
  // One read of a table with a handful of rows, BEFORE the delete: `batch` takes prepared
  // statements, so the "is anyone else still speaking for this platform" question has to be
  // answered up front rather than between the two writes.
  const rows = await db.select().from(deployIntegrations);
  const del = db.delete(deployIntegrations).where(eq(deployIntegrations.id, id));

  const gone = rows.find((i) => i.id === id);
  // Absent row: already deleted, nothing for this call to un-configure. A platform we never
  // poll (`source === null`) has no health row to speak for. And a surviving ACTIVE
  // integration keeps the platform configured — compared through `platformHealthSource`
  // rather than on the raw string, so a second row spelled `cloudflare-pages` still counts
  // as speaking for the `cloudflare` one.
  const source = gone ? platformHealthSource(gone.platform) : null;
  const stillSpokenFor =
    source !== null && rows.some((i) => i.id !== id && i.isActive && platformHealthSource(i.platform) === source);
  if (source === null || stillSpokenFor) {
    await del;
    return;
  }

  await db.batch([
    del,
    db.update(platformHealthState).set({ configured: false }).where(eq(platformHealthState.source, source)),
  ]);
}

// --- ignored deploy projects ------------------------------------------------

/**
 * Projects explicitly exempted from the "unconfigured" warning. Resilient ONLY to
 * the one expected transient: the table is recent, and a deploy whose build-time
 * migration hasn't reached this DB yet must NOT 500 the project list — an absent
 * table reads as "nothing ignored". Any OTHER DB error (outage, auth, quota) is
 * rethrown so the route's error handling surfaces it instead of masking the outage.
 */
export async function listIgnoredProjects(db: Db): Promise<IgnoredProject[]> {
  try {
    return await db
      .select({ platform: ignoredDeployProjects.platform, projectName: ignoredDeployProjects.projectName })
      .from(ignoredDeployProjects);
  } catch (err) {
    if (/no such table|does not exist|not found/i.test(String(err))) return [];
    throw err;
  }
}

export async function addIgnoredProject(db: Db, platform: string, projectName: string): Promise<void> {
  await db.insert(ignoredDeployProjects).values({ platform, projectName }).onConflictDoNothing();
}

/** Bulk-ignore many projects in one statement (for "Ignore all"). */
export async function addIgnoredProjects(db: Db, rows: IgnoredProject[]): Promise<void> {
  if (rows.length === 0) return;
  await db.insert(ignoredDeployProjects).values(rows).onConflictDoNothing();
}

export async function removeIgnoredProject(db: Db, platform: string, projectName: string): Promise<void> {
  await db
    .delete(ignoredDeployProjects)
    .where(and(eq(ignoredDeployProjects.platform, platform), eq(ignoredDeployProjects.projectName, projectName)));
}

// --- peers ------------------------------------------------------------------

/** Drop the secret `token` column before a peer row leaves the process, replacing it
 *  with `hasToken` — WHETHER one is set, which is all any read surface (REST
 *  GET/POST/PATCH or the MCP `list_peers`/`add_peer` tools) may know. The PEER_TOKEN
 *  itself is a fleet shared secret and is never echoed back; without the boolean a
 *  config UI cannot tell "no token" from "token hidden", so it would have to guess.
 *  Callers that need to return a peer row map it through this first. */
export function redactPeer<T extends { token?: unknown }>(peer: T): Omit<T, 'token'> & { hasToken: boolean } {
  const { token, ...rest } = peer;
  return { ...rest, hasToken: typeof token === 'string' && token !== '' };
}

export function listPeers(db: Db): Promise<PeerRow[]> {
  return db.select().from(peers).orderBy(asc(peers.label));
}

export async function createPeer(
  db: Db,
  input: { label: string; baseUrl: string; token?: string | null; isActive?: boolean },
): Promise<PeerRow> {
  const [row] = await db
    .insert(peers)
    .values({
      label: input.label,
      baseUrl: normalizePeerBaseUrl(input.baseUrl),
      token: input.token,
      isActive: input.isActive,
    })
    .returning();
  return row!;
}

export async function updatePeer(
  db: Db,
  id: string,
  patch: { label?: string; baseUrl?: string; token?: string | null; isActive?: boolean },
): Promise<PeerRow | null> {
  const [row] = await db
    .update(peers)
    .set({
      ...patch,
      ...(patch.baseUrl === undefined ? {} : { baseUrl: normalizePeerBaseUrl(patch.baseUrl) }),
      updatedAt: new Date(),
    })
    .where(eq(peers.id, id))
    .returning();
  return row ?? null;
}

export async function deletePeer(db: Db, id: string): Promise<void> {
  await db.delete(peers).where(eq(peers.id, id));
}
