import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { Db } from '../libsql/client';
import type { Tier } from '../middleware/auth';
import { requireAdmin } from '../middleware/auth';
import {
  listEndpoints as storeListEndpoints,
  listSites as storeListSites,
  updateEndpoint as storeUpdateEndpoint,
  createSite as storeCreateSite,
  createEndpoint as storeCreateEndpoint,
  deleteSite as storeDeleteSite,
  addIgnoredProjects,
  type EndpointRow,
} from '../storage/config-store';
import {
  runAutoConfigure,
  wireMatchingEndpoints,
  partitionPending,
  indexLiveProjects,
  type StatusAddApi,
  type EndpointLite,
} from '@agentic-toolkit/deploy-platform/engine';
import { buildDeployProjects, refreshAndEnumerateDeployProjects } from './reads';
import { platformCanon } from '../monitor/overview';

// ---------------------------------------------------------------------------
// Server-side Auto Configure — the engine's I/O side, moved off the web client.
//
// The web used to run the whole engine in the browser against the /config/*
// endpoints; now it POSTs its intent (which projects to ignore, whether to create
// missing sites) here and the server runs enumerate → classify → project-axis
// match/create → endpoint-axis wire in ONE request. The engine stays pure — this
// module supplies its StatusAddApi via direct config-store calls (no HTTP hop).
// ---------------------------------------------------------------------------

/**
 * "Leave this monitor alone" — the two ways an operator says it, as one predicate:
 *   • the per-endpoint opt-out (the editor's "Automatically Configure", unchecked), and
 *   • monitoring switched off for the whole site — paused, and so out of the
 *     auto-configure conversation entirely (the same rule the web's
 *     `endpointConfigStatus` and `findUnconfiguredSites` apply).
 *
 * It governs the ENDPOINT axis only. The PROJECT axis must still see an opted-out monitor,
 * because it is the existing claim on its deploy project — hiding it there would have Auto
 * Configure create a second monitor for a URL that already has one.
 */
export function autoConfigureOptedOut(e: Pick<EndpointRow, 'ignoreProjectWarning' | 'isActive'>): boolean {
  return e.ignoreProjectWarning === true || e.isActive === false;
}

/** Map a stored endpoint row onto the engine's EndpointLite view (the fields the
 *  planner/matcher read). Carries the REAL row id + siteId so a just-created
 *  endpoint chains correctly against later variants in the same run.
 *
 *  `ignoreProjectWarning` is carried too — it was being DROPPED here, so the endpoint axis
 *  (`wireMatchingEndpoints`, which filters on the engine's `endpointUnconfigured`) read
 *  every opted-out monitor as undecided and wired it anyway. It carries
 *  {@link autoConfigureOptedOut}, not the raw column: the engine has one opt-out flag, and
 *  both of the operator's opt-outs mean exactly what it means. */
function toLite(e: EndpointRow): EndpointLite {
  return {
    id: e.id,
    siteId: e.siteId,
    url: e.url,
    kind: e.kind,
    environment: e.environment,
    platform: e.platform,
    deployProject: e.deployProject,
    ignoreProjectWarning: autoConfigureOptedOut(e),
  };
}

/** Read a nullable string field off the engine's loosely-typed write body. */
function str(v: unknown): string | null | undefined {
  return v as string | null | undefined;
}

/**
 * The engine's StatusAddApi backed by DIRECT `storage/config-store` calls — the
 * in-process replacement for the web client that used to hit /config/*. The delete
 * path MUST use the purging `deleteSite` (it drops the rolled-back site's history +
 * issues), and `createEndpoint` returns the created row mapped to `EndpointLite` with
 * its real server id so intra-run chaining wires against the actual endpoint.
 */
export function statusAdapter(db: Db): StatusAddApi {
  return {
    async listAllEndpoints() {
      // ALL endpoints (active + inactive), same set the web client's listAllEndpoints
      // (GET /config/endpoints) returned — so the planner sees every existing monitor.
      const rows = await storeListEndpoints(db);
      return rows.map(toLite);
    },
    async listSites() {
      // Slug + group only: the create path uses them to disambiguate a taken slug and to
      // file a new site with its domain family's group.
      const rows = await storeListSites(db);
      return rows.map((s) => ({ id: s.id, slug: s.slug, groupId: s.siteGroupId }));
    },
    updateEndpoint(id, body) {
      return storeUpdateEndpoint(db, id, {
        platform: str(body.platform),
        deployProject: str(body.deployProject),
        // wireMatchingEndpoints omits environment; undefined is dropped from the SET
        // clause (drizzle) so it never NULLs an operator-set environment.
        environment: str(body.environment),
      });
    },
    async createSite(body) {
      const row = await storeCreateSite(db, { name: body.name, slug: body.slug, siteGroupId: body.groupId });
      return { id: row.id };
    },
    async createEndpoint(siteId, body) {
      const row = await storeCreateEndpoint(db, {
        siteId,
        url: String(body.url),
        environment: str(body.environment),
        platform: str(body.platform),
        deployProject: str(body.deployProject),
      });
      return toLite(row);
    },
    async deleteSite(id) {
      await storeDeleteSite(db, id);
    },
  };
}

/** Keep the first row per `keyOf`, preserving input order. */
function dedupeBy<T>(rows: T[], keyOf: (row: T) => string): T[] {
  const seen = new Set<string>();
  return rows.filter((r) => {
    const key = keyOf(r);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Collapse repeats of the same `project: reason` pair, keeping first-seen order.
 *
 * The endpoint axis reports one row PER ENDPOINT, so a project whose four endpoints all
 * fail the same way contributes that identical line four times — and the dialog only shows
 * the first five, so one repeated cause can crowd out every other project's. The COUNT
 * (`skipped`) is deliberately left un-deduped: it counts work items left undone, and four
 * unwired endpoints really are four.
 */
export function dedupeDetail(rows: { project: string; reason: string }[]): { project: string; reason: string }[] {
  return dedupeBy(rows, (r) => `${r.project}|${r.reason}`);
}

export const autoConfigureBody = z.object({
  // Projects the operator chose to exempt from the "unconfigured" warning this run.
  // Persisted FIRST so the classify below (and its addable set) excludes them.
  ignore: z.array(z.object({ platform: z.string(), projectName: z.string() })).optional().default([]),
  // Opt-in creation: the group new sites are filed under. null/absent → match-only.
  // `forceGroup` makes that group AUTHORITATIVE — without it, a new site whose domain
  // family another group already owns joins THAT group (and the run says so in `notes`).
  create: z.object({ groupId: z.string(), forceGroup: z.boolean().optional() }).nullable().optional().default(null),
});

export type AutoConfigureInput = z.infer<typeof autoConfigureBody>;

/**
 * Run the full server-side Auto Configure pass (enumerate → classify → project-axis
 * match/create → endpoint-axis wire) for the given intent. The single body behind BOTH
 * POST /auto-configure AND the run_auto_configure MCP tool, so both drive the engine
 * identically and can never diverge.
 */
export async function performAutoConfigure(db: Db, { ignore, create }: AutoConfigureInput) {
  // 1. Persist the operator's ignores BEFORE enumerating so the fresh classify treats
  //    them as ignored (dropping them from the addable set the project axis acts on).
  if (ignore.length) await addIgnoredProjects(db, ignore);

  // 2. Re-verify Vercel and enumerate, in that order and as one unit (the shared reader —
  //    never the routes' 30s cache; a write run always looks). The enumeration derives
  //    "which Vercel projects exist" from `deploy_project_meta`, so without the refresh a
  //    project deleted upstream is still offered — and accepting it creates a site wired to
  //    a dead target whose last failed build becomes an unclearable Problem. Fail CLOSED: a
  //    read we couldn't complete (partial page walk, API error) means Vercel contributes
  //    NOTHING this run rather than suggestions from a table we can't vouch for.
  const { vercel, enumerated, verifiedPlatforms } = await refreshAndEnumerateDeployProjects(db);

  // 3. Enrich with wired/ignored flags, then classify — the SAME model /deploy-projects and
  //    the banner derive from.
  const all = await buildDeployProjects(db, enumerated);
  const projects = vercel.ok ? all : all.filter((p) => platformCanon(p.platform) !== 'vercel');
  const { addable, noDomain } = partitionPending(projects);

  const api = statusAdapter(db);
  // 4. Project axis: match each addable project to the site that monitors its domain,
  //    or CREATE one (in create.groupId) when nothing monitors it yet.
  //
  //    `liveProjects` lets the planner repair an endpoint still wired to a project that no
  //    longer exists — renamed, or left behind by a migration to another platform. Without
  //    it the new name reads unmonitored while its own domain sits monitored under the dead
  //    name, and every run refuses it as a conflict: an alert with no action that clears it.
  //
  //    `verifiedPlatforms` is what makes acting on an ABSENCE sound, and it is deliberately
  //    NOT inferred from the list: a Railway token that can't enumerate degrades to the
  //    CONFIGURED project list, which looks exactly like a complete one and is missing every
  //    project nobody wrote down. Only platforms we listed live and in full are named, so an
  //    unverifiable platform leaves its wiring untouched instead of being clobbered.
  const { added, created, skipped, notes } = await runAutoConfigure(addable, {
    api,
    create: create ?? undefined,
    liveProjects: indexLiveProjects(projects, verifiedPlatforms),
  });

  // 5. Endpoint axis: wire any still-unconfigured endpoint to the (non-ignored) project
  //    that serves its host, matched against the project's FULL domain list. Runs over
  //    every project NOT ignored THIS run (byte-identical key to the web's projectKeyOf:
  //    raw platform, so a previously-ignored project still contributes its domains).
  const ignoredThisRun = new Set(ignore.map((r) => `${r.platform}|${r.projectName}`));
  const nonIgnored = projects.filter((p) => !ignoredThisRun.has(`${p.platform}|${p.projectName}`));
  const { wired, skipped: wireSkipped } = await wireMatchingEndpoints(nonIgnored, { api });

  return {
    added: added.length,
    created: created.length,
    wired,
    skipped: skipped.length + wireSkipped.length,
    // WHY each leftover was left. Without this the whole run collapses to "N unmatched" —
    // which is how a permanent, self-repeating failure (a slug that 409s every single run)
    // stayed invisible: the count looked the same as "nothing to do here".
    skippedDetail: dedupeDetail([
      ...skipped.map((s) => ({ project: s.project.projectName, reason: s.reason })),
      ...wireSkipped,
    ]),
    // Projects that WERE configured, with something we decided FOR the operator: a new site
    // filed with its domain family's group instead of the selected one, or a monitor taken
    // over from a project the platform no longer has. Reported for the same reason as
    // skippedDetail — a change nobody is told about reads as "it went exactly as you asked",
    // and the operator can only correct what they can see.
    notes: dedupeBy(
      notes.map((n) => ({ project: n.project.projectName, note: n.note })),
      (n) => `${n.project}|${n.note}`,
    ),
    // Carried so the web's summarizeAutoConfigure can name the "(N with no domain)"
    // leftovers — pending projects with no domain the project axis can't match.
    noDomain,
    // true → Vercel IS configured here, but its project list couldn't be verified this run,
    // so it was skipped entirely. Reported rather than swallowed: "nothing to match" and
    // "we didn't look" must not read the same to the operator. Gated on `configured` so an
    // install with no Vercel token — a permanent steady state, not an incident — never
    // carries the caveat.
    vercelUnverified: vercel.configured && !vercel.ok,
    // How many projects that skip actually cost, so the caveat can't contradict the counts:
    // every other number in this response is 0 when Vercel is dropped, which reads as
    // "nothing to do" unless the size of what we didn't look at is stated.
    vercelSkipped: all.length - projects.length,
  };
}

export function autoConfigureRoutes(db: Db): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  // requireAdmin is applied PER-ROUTE (not blanket `use('*')`): this sub-app mounts at the
  // ROOT prefix beside readsRoutes, and a root-mounted `use('*')` guard leaks onto every
  // sibling route registered after it (configRoutes gets away with blanket only because it
  // mounts under /config). Guarding the one write here keeps the admin gate scoped to it.
  app.post('/auto-configure', requireAdmin, async (c) => {
    const raw = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const parsed = autoConfigureBody.safeParse(raw);
    if (!parsed.success) throw new HTTPException(400, { message: `Invalid request body: ${String(parsed.error)}` });
    return c.json(await performAutoConfigure(db, parsed.data));
  });

  return app;
}
