import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import type { StatusConfig, StatusCredentialName } from '../config/port';
import type { SeedEnvironment, SeedRoster } from '../config/seed';
import { reconcileBoardLedger } from '../board';
import {
  DUPLICATE_PEER_MESSAGE,
  isDuplicatePeerError,
  isSelfPeerUrl,
  isValidPeerBaseUrl,
} from '../peers/base-url';
import { requireAdmin } from '../middleware/auth';
import type { Tier } from '../middleware/auth';
import { redactPeer, type Storage } from '../storage/ports';

// ---------------------------------------------------------------------------
// Zod insert schemas — plain shapes matching each ConfigStore write's input type
// (../storage/ports.ts). They used to be derived from the drizzle tables; this
// module sits above the storage boundary and may not import `../libsql/schema`,
// so the shapes are spelled out, in the tables' column order and with the same
// optionality, and the committed openapi.json (pinned by test/openapi.test.ts)
// proves the public contract did not move.
// ---------------------------------------------------------------------------

/** What a `{ mode: 'json' }` column accepts: any JSON value. */
const jsonValue = z.union([
  z.union([z.string(), z.number(), z.boolean(), z.null()]),
  z.record(z.string(), z.unknown()),
  z.array(z.unknown()),
]);

export const siteGroupInsert = z.object({
  slug: z.string(),
  name: z.string(),
  retentionDays: z.number().int().optional(),
});
export const siteGroupPatch = siteGroupInsert.partial();

export const monitoredSiteInsert = z.object({
  siteGroupId: z.string(),
  slug: z.string(),
  name: z.string(),
});
export const monitoredSitePatch = monitoredSiteInsert.partial();

export const monitoredEndpointInsert = z.object({
  siteId: z.string(),
  url: z.string(),
  kind: z.string().optional(),
  environment: z.string().nullable().optional(),
  platform: z.string().nullable().optional(),
  deployProject: z.string().nullable().optional(),
  deployProjectId: z.string().nullable().optional(),
  ignoreProjectWarning: z.boolean().optional(),
  expectedStatus: z.number().int().optional(),
  expectBody: z.string().nullable().optional(),
  dnsCheckA: z.boolean().optional(),
  dnsCheckAaaa: z.boolean().optional(),
  dnsCheckCname: z.boolean().optional(),
  checkIntervalSeconds: z.number().int().optional(),
  isActive: z.boolean().optional(),
  monitorHttp: z.boolean().optional(),
  monitorDeploys: z.boolean().optional(),
});
export const monitoredEndpointPatch = monitoredEndpointInsert.partial();

export const deployIntegrationInsert = z.object({
  platform: z.string(),
  label: z.string(),
  config: jsonValue.optional(),
  tokenEnvVar: z.string().nullable().optional(),
  secretRef: z.string().nullable().optional(),
  isActive: z.boolean().optional(),
});
export const deployIntegrationPatch = deployIntegrationInsert.partial();

export const ignoredProjectInsert = z.object({
  platform: z.string(),
  projectName: z.string(),
});

/** A peer's base URL: an absolute http(s) origin. This schema stays STATIC (no config
 *  dependency) because it is also read as a bare shape — by `mcp/tools.ts`'s
 *  `inputSchema` and `openapi/paths/config.ts`'s `zodJson(...)` — at module-registration
 *  time, well before any request (and any config) exists. The "never this monitor's own
 *  URL" rule needs runtime config, so it is a separate, explicit check
 *  (`assertNotSelfPeerUrl` below) run by each write handler AFTER this shape validates,
 *  not folded into the shape itself. */
const peerBaseUrl = z.string().refine(isValidPeerBaseUrl, 'baseUrl must be an absolute http(s) URL');

export const peerInsert = z.object({
  label: z.string(),
  baseUrl: peerBaseUrl,
  token: z.string().nullable().optional(),
  isActive: z.boolean().optional(),
});
export const peerPatch = peerInsert.partial();

/** Reject a peer write whose `baseUrl` is this monitor's own URL — the two sibling
 *  deployments (`lewis` / `testing.lewis`) make pasting the wrong URL a one-keystroke
 *  mistake that would otherwise draw the same host twice: once live, once a
 *  poll-interval stale. Called explicitly by each write path (HTTP + the `add_peer`
 *  MCP tool) once `config` is in scope, since the static schema above cannot see it. */
function assertNotSelfPeerUrl(baseUrl: string, config: StatusConfig): void {
  if (isSelfPeerUrl(baseUrl, config)) {
    throw new HTTPException(400, {
      message: 'baseUrl is this monitor’s own URL — a monitor is already in its own fleet view',
    });
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseBody<T>(parsed: { success: true; data: T } | { success: false; error: unknown }): T {
  if (!parsed.success) {
    const err = parsed as { success: false; error: unknown };
    throw new HTTPException(400, { message: `Invalid request body: ${String(err.error)}` });
  }
  return (parsed as { success: true; data: T }).data;
}

/** Run a peer write, turning a duplicate `base_url` into a 409 the config UI can show
 *  as a sentence, instead of the driver's raw constraint text surfacing as a 500.
 *  `add_peer` (src/mcp/tools.ts) maps the same error to the same sentence. */
async function peerWrite<T>(run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (err) {
    if (isDuplicatePeerError(err)) {
      throw new HTTPException(409, { message: DUPLICATE_PEER_MESSAGE });
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Seed — the roster is the HOST's (../config/seed.ts, reached via AppDeps.seed);
// this package only knows how to turn one into groups, sites and endpoints.
// ---------------------------------------------------------------------------

function envHost(host: string, env: SeedEnvironment): string {
  if (env === 'production') return host;
  return `${env === 'staging' ? 'staging' : 'testing'}.${host}`;
}

async function runSeed(
  storage: Storage,
  config: StatusConfig,
  roster: SeedRoster,
): Promise<{ groups: number; sites: number; endpoints: number; integrations: number }> {
  // Collect distinct group names in order
  const groupNames = [...new Set(roster.map((s) => s.group))];

  // Create groups (slug = lowercased, spaces → dashes)
  const groupMap = new Map<string, string>(); // name → id
  for (const name of groupNames) {
    const slug = name.toLowerCase().replace(/\s+/g, '-');
    const row = await storage.config.createGroup({ name, slug });
    groupMap.set(name, row.id);
  }

  // Collect distinct (group, siteName) pairs in order
  type SiteKey = { group: string; name: string; baseSlug: string };
  const siteKeys: SiteKey[] = [];
  const seen = new Set<string>();
  for (const svc of roster) {
    const key = `${svc.group}|${svc.name}`;
    if (!seen.has(key)) {
      seen.add(key);
      siteKeys.push({ group: svc.group, name: svc.name, baseSlug: svc.baseSlug });
    }
  }

  const siteMap = new Map<string, string>(); // `${group}|${name}` → id
  for (const { group, name, baseSlug } of siteKeys) {
    const siteGroupId = groupMap.get(group)!;
    const row = await storage.config.createSite({ name, slug: baseSlug, siteGroupId });
    siteMap.set(`${group}|${name}`, row.id);
  }

  let endpointCount = 0;
  for (const svc of roster) {
    const siteId = siteMap.get(`${svc.group}|${svc.name}`)!;
    for (const env of svc.envs) {
      const host = envHost(svc.host, env);
      const url = `https://${host}${svc.path ?? ''}`;
      await storage.config.createEndpoint({
        siteId,
        url,
        kind: svc.kind,
        environment: env,
        expectedStatus: svc.expectedStatus ?? 200,
      });
      endpointCount++;
    }
  }

  // Auto-create a provider connection for each platform whose API token is present
  // in the env. Without these rows the cycle never polls deploys, so the dashboard
  // shows no projects and no "unconfigured project" warnings — the deploy isn't
  // turnkey. Only seed a provider when its token is set, and never duplicate one.
  const providerSeeds: { platform: string; label: string; tokenEnvVar: StatusCredentialName; config: Record<string, string> }[] = [
    { platform: 'vercel', label: 'Vercel', tokenEnvVar: 'VERCEL_API_TOKEN', config: config.credentials.VERCEL_TEAM_ID ? { teamId: config.credentials.VERCEL_TEAM_ID } : {} },
    { platform: 'railway', label: 'Railway', tokenEnvVar: 'RAILWAY_API_TOKEN', config: {} },
    { platform: 'crunchy', label: 'Crunchy Bridge', tokenEnvVar: 'CRUNCHY_API_TOKEN', config: {} },
    { platform: 'cloudflare', label: 'Cloudflare', tokenEnvVar: 'CLOUDFLARE_API_TOKEN', config: config.credentials.CLOUDFLARE_ACCOUNT_ID ? { accountId: config.credentials.CLOUDFLARE_ACCOUNT_ID } : {} },
  ];
  const existingIntegrations = await storage.config.listIntegrations();
  let integrations = 0;
  for (const p of providerSeeds) {
    if (!config.credentials[p.tokenEnvVar]) continue;
    if (existingIntegrations.some((i) => i.platform === p.platform)) continue;
    await storage.config.createIntegration({ platform: p.platform, label: p.label, tokenEnvVar: p.tokenEnvVar, config: p.config });
    integrations++;
  }

  return { groups: groupMap.size, sites: siteMap.size, endpoints: endpointCount, integrations };
}

// ---------------------------------------------------------------------------
// Router factory
// ---------------------------------------------------------------------------

export function configRoutes(storage: Storage, config: StatusConfig, seed: SeedRoster): Hono<{ Variables: { tier: Tier } }> {
  const app = new Hono<{ Variables: { tier: Tier } }>();

  // All /config/* is admin-gated (requireAuth already applied app-wide)
  app.use('*', requireAdmin);

  // --- site-groups -----------------------------------------------------------

  app.get('/site-groups', async (c) => {
    const rows = await storage.config.listSiteGroups();
    return c.json(rows);
  });

  app.post('/site-groups', async (c) => {
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(siteGroupInsert.safeParse(body));
    const row = await storage.config.createGroup(data);
    return c.json(row, 201);
  });

  app.patch('/site-groups/:id', async (c) => {
    const id = c.req.param('id');
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(siteGroupPatch.safeParse(body));
    const row = await storage.config.updateGroup(id, data);
    if (!row) throw new HTTPException(404, { message: 'Not found' });
    return c.json(row);
  });

  app.delete('/site-groups/:id', async (c) => {
    const id = c.req.param('id');
    await storage.config.deleteGroup(id);
    // Same inline sweep as DELETE /sites/:id — clear deploy-target issues the deleted
    // group's endpoints owned so Problems empties in this request, not next cycle.
    await reconcileBoardLedger(storage, config);
    return c.json({ ok: true });
  });

  // --- sites ----------------------------------------------------------------

  app.get('/sites', async (c) => {
    const rows = await storage.config.listSites();
    return c.json(rows);
  });

  app.post('/sites', async (c) => {
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(monitoredSiteInsert.safeParse(body));
    const row = await storage.config.createSite(data);
    return c.json(row, 201);
  });

  app.patch('/sites/:id', async (c) => {
    const id = c.req.param('id');
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(monitoredSitePatch.safeParse(body));
    const row = await storage.config.updateSite(id, data);
    if (!row) throw new HTTPException(404, { message: 'Not found' });
    return c.json(row);
  });

  app.delete('/sites/:id', async (c) => {
    const id = c.req.param('id');
    await storage.config.deleteSite(id);
    // Clear deploy-target issues that only this site owned — same sweep the monitor
    // cycle runs, done inline so Problems empties in this request, not next cycle.
    await reconcileBoardLedger(storage, config);
    return c.json({ ok: true });
  });

  // --- endpoints ------------------------------------------------------------

  app.get('/endpoints', async (c) => {
    const siteId = c.req.query('siteId');
    const rows = await storage.config.listEndpoints(siteId);
    return c.json(rows);
  });

  app.post('/endpoints', async (c) => {
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(monitoredEndpointInsert.safeParse(body));
    const row = await storage.config.createEndpoint(data);
    return c.json(row, 201);
  });

  app.patch('/endpoints/:id', async (c) => {
    const id = c.req.param('id');
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(monitoredEndpointPatch.safeParse(body));
    const row = await storage.config.updateEndpoint(id, data);
    if (!row) throw new HTTPException(404, { message: 'Not found' });
    // A PATCH can flip isActive / monitorHttp / monitorDeploys, which is Requirement A:
    // turning a switch off must remove the endpoint's targets from Problems. The BOARD
    // does that on its next read regardless (it re-derives from the roster), but the
    // LEDGER row and its alert-dedup state would lag a whole cycle — long enough for a
    // recovery on a monitor the operator just disabled to page on-call. Same inline
    // sweep the delete paths run.
    await reconcileBoardLedger(storage, config);
    return c.json(row);
  });

  app.delete('/endpoints/:id', async (c) => {
    const id = c.req.param('id');
    // Retire = delete the endpoint AND its site if that leaves the site empty, decided
    // atomically server-side (1:1 site→endpoint is the norm). Both the editor and the
    // "retire stale monitor" surface route here, so neither has to (mis)compute it from
    // a possibly-stale client endpoint list.
    const result = await storage.config.retireEndpoint(id);
    // Same inline sweep as DELETE /sites/:id — resolve deploy-target issues the retired
    // endpoint owned so Problems empties in this request, not next cycle.
    await reconcileBoardLedger(storage, config);
    return c.json({ ok: true, ...result });
  });

  // --- integrations ---------------------------------------------------------

  app.get('/integrations', async (c) => {
    const rows = await storage.config.listIntegrations();
    return c.json(rows);
  });

  app.post('/integrations', async (c) => {
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(deployIntegrationInsert.safeParse(body));
    const row = await storage.config.createIntegration(data);
    return c.json(row, 201);
  });

  app.patch('/integrations/:id', async (c) => {
    const id = c.req.param('id');
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(deployIntegrationPatch.safeParse(body));
    const row = await storage.config.updateIntegration(id, data);
    if (!row) throw new HTTPException(404, { message: 'Not found' });
    return c.json(row);
  });

  app.delete('/integrations/:id', async (c) => {
    const id = c.req.param('id');
    // `deleteIntegration` also clears `platform_health_state.configured` for the platform
    // this was the last active integration for — WITHOUT that half, the sweep below is
    // decorative: `platformProblems` reads that column, so the Problem would still derive
    // and its ledger row would still stay open until the next full cycle rewrote it.
    await storage.config.deleteIntegration(id);
    // Un-configured platform ⇒ every platform-health problem it raised (and every deploy
    // problem for projects only it could poll) stops being derivable. Sweep now, or those
    // rows sit open — and alert-deduped — until the next cycle.
    await reconcileBoardLedger(storage, config);
    return c.json({ ok: true });
  });

  // --- ignored-projects -----------------------------------------------------

  app.get('/ignored-projects', async (c) => {
    const rows = await storage.config.listIgnoredProjects();
    return c.json(rows);
  });

  app.post('/ignored-projects', async (c) => {
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(ignoredProjectInsert.safeParse(body));
    await storage.config.addIgnoredProject(data.platform, data.projectName);
    return c.json({ ok: true }, 201);
  });

  app.delete('/ignored-projects/:id', async (c) => {
    // id param here is a compound: platform|projectName (URL-encoded)
    // Accept either ?platform=&projectName= query params or the compound id
    const id = c.req.param('id');
    const [platform, ...rest] = id.split('|');
    const projectName = rest.join('|');
    if (!platform || !projectName) {
      throw new HTTPException(400, { message: 'id must be platform|projectName' });
    }
    await storage.config.removeIgnoredProject(platform, projectName);
    return c.json({ ok: true });
  });

  // --- peers ----------------------------------------------------------------

  // Peer rows carry the PEER_TOKEN fleet secret; every response is redacted so the
  // token never leaves the process (matching the MCP peer tools). The token is still
  // accepted on write (POST/PATCH bodies) — it just never comes back out; responses
  // carry `hasToken` in its place so the config UI can show whether one is set.
  app.get('/peers', async (c) => {
    const rows = await storage.config.listPeers();
    return c.json(rows.map(redactPeer));
  });

  app.post('/peers', async (c) => {
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(peerInsert.safeParse(body));
    assertNotSelfPeerUrl(data.baseUrl, config);
    const row = await peerWrite(() => storage.config.createPeer(data));
    return c.json(redactPeer(row), 201);
  });

  app.patch('/peers/:id', async (c) => {
    const id = c.req.param('id');
    const body = await c.req.json().catch(() => {
      throw new HTTPException(400, { message: 'Invalid JSON' });
    });
    const data = parseBody(peerPatch.safeParse(body));
    if (data.baseUrl !== undefined) assertNotSelfPeerUrl(data.baseUrl, config);
    const row = await peerWrite(() => storage.config.updatePeer(id, data));
    if (!row) throw new HTTPException(404, { message: 'Not found' });
    return c.json(redactPeer(row));
  });

  app.delete('/peers/:id', async (c) => {
    const id = c.req.param('id');
    await storage.config.deletePeer(id);
    return c.json({ ok: true });
  });

  // --- seed -----------------------------------------------------------------

  app.post('/seed', async (c) => {
    const counts = await runSeed(storage, config, seed);
    return c.json({ ok: true, ...counts });
  });


  return app;
}
