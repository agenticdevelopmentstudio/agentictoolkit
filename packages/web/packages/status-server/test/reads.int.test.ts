import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from 'vitest';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { _resetCfAccountCache } from '@agentic-toolkit/deploy-platform/providers';
import { rollupMetricsSql } from '../src/monitor/sync';
import { sessionHeaders } from './helpers/auth';
import { freshDb as bootDb, type Db as TestDb } from './helpers/db';
import { stubVercelAccount, type FakeVercelAccount } from './helpers/vercel-account';
import { testConfig } from './helpers/config';

/** Read a response body as a loosely-typed record — tests assert with toMatchObject. */
async function parse(res: Response): Promise<Record<string, any>> {
  return (await res.json()) as Record<string, any>;
}

/** One active group → site → endpoint. Returns the endpoint id (the probe slug). */
async function seedOneEndpoint(db: Db, url: string): Promise<string> {
  const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0]!;
  const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g.id, slug: 's', name: 'S' }).returning())[0]!;
  const ep = (await db.insert(schema.monitoredEndpoints).values({ siteId: s.id, url }).returning())[0]!;
  return ep.id;
}

describe('/live', () => {
  let app: ReturnType<typeof createApp>;
  let viewAuth: { Cookie: string };

  beforeAll(async () => {
    const db = await bootDb();
    viewAuth = await sessionHeaders(db, 'viewer');
    app = createApp({ db, config: testConfig() });
  });

  it('401 without a token', async () => {
    expect((await app.request('/live')).status).toBe(401);
  });

  it('returns a LiveSnapshot with a token (empty DB does not error)', async () => {
    const res = await app.request('/live', { headers: viewAuth });
    expect(res.status).toBe(200);
    const body = await parse(res);
    expect(body).toHaveProperty('generatedAt');
    expect(body).toHaveProperty('services');
    expect(body).toHaveProperty('deployments');
    expect(body).toHaveProperty('staleProd');
    expect(body).toHaveProperty('providers');
    expect(body).toHaveProperty('configDegraded', false);
    expect(body).toHaveProperty('configReason', null);
    // No probes yet → no freshness clock (banner stays inert, no false "stale" alarm).
    expect(body).toHaveProperty('lastCycleAt', null);
    // The probe interval rides the snapshot so the client's staleness window scales with it.
    expect(typeof body.probeIntervalMs).toBe('number');
    expect(body.probeIntervalMs).toBeGreaterThan(0);
    expect(Array.isArray(body.services)).toBe(true);
    // The empty-DB providers map still carries the three known keys.
    expect(body.providers).toHaveProperty('vercel');
    expect(body.providers).toHaveProperty('cloudflare-pages');
    expect(body.providers).toHaveProperty('railway');
  });

  it('/snapshot returns the compact payload (accepts view token)', async () => {
    const res = await app.request('/snapshot', { headers: viewAuth });
    expect(res.status).toBe(200);
    const body = await parse(res);
    expect(body).toHaveProperty('overall');
    expect(body).toHaveProperty('services');
    expect(body).toHaveProperty('openIssues');
    // No data → healthy overall.
    expect(body.overall).toBe('healthy');
  });
});

describe('reads with seeded data', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let slug: string;
  let viewAuth: { Cookie: string };

  beforeEach(async () => {
    db = await bootDb();
    viewAuth = await sessionHeaders(db, 'viewer');
    slug = await seedOneEndpoint(db, 'https://example.com');
    app = createApp({ db, config: testConfig() });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.CLOUDFLARE_API_TOKEN;
    delete process.env.CLOUDFLARE_ACCOUNT_ID;
    delete process.env.RAILWAY_API_TOKEN;
    _resetCfAccountCache(); // CF account discovery is memoized per token — don't leak it across tests
  });

  it('/live + /status surface a service derived from the latest health check', async () => {
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'healthy', responseTimeMs: 42, statusCode: 200 });

    const live = await parse(await app.request('/live', { headers: viewAuth }));
    expect(live.services).toHaveLength(1);
    expect(live.services[0]).toMatchObject({ slug, status: 'healthy', responseTimeMs: 42, dnsOk: true });
    // The freshness clock is the newest persisted probe (drives the "monitoring paused"
    // banner) — a real recent timestamp once a check exists, not the read-time clock.
    expect(typeof live.lastCycleAt).toBe('string');
    expect(Date.now() - Date.parse(live.lastCycleAt)).toBeLessThan(60_000);

    const status = await parse(await app.request('/status', { headers: viewAuth }));
    expect(status.overall).toBe('operational');
    expect(status.services[0]).toMatchObject({ slug, status: 'healthy' });
    // Canonical links ride each /status entry: `live` is the endpoint's own URL;
    // `platform` is null here (the seeded endpoint carries no deploy project).
    expect(status.services[0].links).toMatchObject({ live: 'https://example.com', platform: null });
  });

  it('/live derives staleProd from a persisted vercelProdState row for an OWNED project', async () => {
    // The endpoint wiring is load-bearing, not scenery: `/live` serves a stale row only
    // for a project a live site owns — the same gate sync applies before ever opening the
    // issue (`configured.vercel.has(...)`). Without it this asserted a row the writer
    // can't produce.
    await db.update(schema.monitoredEndpoints).set({ platform: 'vercel', deployProject: 'adh' });
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'adh' });
    await db.insert(schema.vercelProdState).values({
      projectName: 'adh',
      stale: true,
      detail: 'live production is behind',
      sourceUrl: 'https://vercel.com/team/adh',
      liveUrl: 'https://adh.example.com',
    });
    const live = await parse(await app.request('/live', { headers: viewAuth }));
    expect(live.staleProd).toHaveLength(1);
    expect(live.staleProd[0]).toMatchObject({ projectName: 'adh', environment: 'production', liveUrl: 'https://adh.example.com' });
  });

  it('/live drops a vercel-stale issue for a project NO live site owns', async () => {
    // Residue from an unwired/deleted site. It is unfixable by construction — nothing can
    // deploy it fresh again — so serving it pins a row the operator can never clear.
    // reconcileBoardLedger still owns resolving the row; the READ must not wait for it.
    //
    // Fix Round 1, item 6: this is double-guarded, not single-gated. The seeded endpoint's
    // project is reassigned to 'adh' below, so 'studio-production' is absent from the
    // roster ENTIRELY — both `configured.vercel.has(...)` (staleProdProblems.ts:338) and
    // `matchRosterEntry`'s byName lookup (derive-problems.ts:83-84) derive from that same
    // roster and independently reject it for the identical reason (no roster entry). As
    // currently written `configured.vercel` short-circuits the loop first, so
    // `matchRosterEntry` never actually runs for this row — but removing `configured.
    // vercel` alone would NOT turn this red, because `matchRosterEntry` would still reject
    // the same absent entry. This test pins "an unrostered project's stale-prod row never
    // surfaces," not `configured.vercel` specifically; a regression confined to one gate
    // while the other still holds would pass here silently.
    await db.update(schema.monitoredEndpoints).set({ platform: 'vercel', deployProject: 'adh' });
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'studio-production' });
    await db.insert(schema.vercelProdState).values({
      projectName: 'studio-production',
      stale: true,
      detail: 'live production is behind',
      sourceUrl: null,
      liveUrl: null,
    });
    const live = await parse(await app.request('/live', { headers: viewAuth }));
    // toEqual([]) rather than not.toContain(...): the only stale-prod row in this fixture is
    // the unrostered one, so `not.toContain` also holds for a `/live` that lost the whole
    // list — it would pass for a reason unrelated to the gate under test.
    expect(live.staleProd.map((s: { projectName: string }) => s.projectName)).toEqual([]);
  });

  it('/live marks a service dnsOk=false when its latest check failed DNS', async () => {
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'down', statusCode: null, dnsOk: false });
    const live = await parse(await app.request('/live', { headers: viewAuth }));
    expect(live.services[0]).toMatchObject({ dnsOk: false });
  });

  it('/live stamps downSince from the open http/dns issue openedAt (server-truth "down since")', async () => {
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'down', statusCode: null });
    const openedAt = new Date('2026-01-02T03:04:05.000Z');
    await db.insert(schema.issues).values({ target: slug, source: 'dns', name: 'S', severity: 'major', state: 'down', openedAt });
    const live = await parse(await app.request('/live', { headers: viewAuth }));
    expect(live.services[0].downSince).toBe(openedAt.toISOString());

    // A healthy service has no open issue → downSince is null (not "down since" anything).
    // Add a second endpoint under the SAME seeded site (seedOneEndpoint reuses slug 'g').
    const site = (await db.select().from(schema.monitoredSites))[0]!;
    const slug2 = (await db.insert(schema.monitoredEndpoints).values({ siteId: site.id, url: 'https://healthy.example.com' }).returning())[0]!.id;
    await db.insert(schema.healthChecks).values({ serviceSlug: slug2, status: 'healthy', statusCode: 200 });
    const live2 = await parse(await app.request('/live', { headers: viewAuth }));
    expect(live2.services.find((s: { slug: string }) => s.slug === slug2)?.downSince).toBeNull();
  });

  it('/snapshot rolls overall down when the only service is down + lists the open issue', async () => {
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'down' });
    await db.insert(schema.issues).values({ target: slug, source: 'http', name: 'S', severity: 'major', state: 'down' });
    const snap = await parse(await app.request('/snapshot', { headers: viewAuth }));
    expect(snap.overall).toBe('down');
    expect(snap.openIssues).toHaveLength(1);
    expect(snap.openIssues[0]).toMatchObject({ target: slug, source: 'http', state: 'down' });
  });

  it('/snapshot carries each issue\'s links and commit, not just its state', async () => {
    // Without these, a snapshot consumer can say WHAT is broken but can't point at
    // the failing build, the live site, or the commit that caused it — which is the
    // whole job of `adh-status issues show`.
    //
    // Seeded as the FACT, not as a ledger row: `/snapshot`'s openIssues is board-derived
    // (`routes/reads.ts`), so an `issues` insert with no deploy behind it is resolved as
    // recovered by the next fold and the assertion would be about a row nothing serves.
    // Every field below therefore has to survive the trip deployment → Problem → payload,
    // which is the trip that can actually drop them.
    const site = (await db.select().from(schema.monitoredSites))[0]!;
    await db.insert(schema.monitoredEndpoints).values({
      siteId: site.id,
      url: 'https://testing.agenticdevelopercookbook.com',
      platform: 'vercel',
      deployProject: 'cookbook-testing',
    });
    await db.insert(schema.deployments).values({
      id: 'vc_cookbook_fail',
      platform: 'vercel',
      projectName: 'cookbook-testing',
      buildPhase: 'failed',
      deployPhase: 'none',
      environment: 'production',
      url: 'https://vercel.com/team/cookbook-testing',
      liveHost: 'testing.agenticdevelopercookbook.com',
      commitHash: 'fe26aeb',
      commitMessage: 'fix: the thing',
      commitRepo: 'agenticdevelopmentstudio/agenticdeveloperhub-deployment',
      createdAt: new Date(),
    });
    const snap = await parse(await app.request('/snapshot', { headers: viewAuth }));
    const issue = snap.openIssues.find((i: { source: string }) => i.source === 'vercel');
    expect(issue).toMatchObject({
      sourceUrl: 'https://vercel.com/team/cookbook-testing',
      liveUrl: 'https://testing.agenticdevelopercookbook.com',
      commitHash: 'fe26aeb',
      commitRepo: 'agenticdevelopmentstudio/agenticdeveloperhub-deployment',
    });
  });

  it('/history returns one endpoint checks (accepts slug; 400 without it)', async () => {
    await db.insert(schema.healthChecks).values([
      { serviceSlug: slug, status: 'healthy', responseTimeMs: 10 },
      { serviceSlug: slug, status: 'degraded', responseTimeMs: 900 },
    ]);
    expect((await app.request('/history', { headers: viewAuth })).status).toBe(400);
    const res = await app.request(`/history?slug=${slug}&hours=24`, { headers: viewAuth });
    expect(res.status).toBe(200);
    const body = await parse(res);
    expect(body.service).toBe(slug);
    expect(body.hours).toBe(24);
    expect(body.checks).toHaveLength(2);
  });

  it('/uptime aggregates daily counts for the configured endpoint', async () => {
    await db.insert(schema.healthChecks).values([
      { serviceSlug: slug, status: 'healthy' },
      { serviceSlug: slug, status: 'down' },
    ]);
    const body = await parse(await app.request('/uptime?days=90', { headers: viewAuth }));
    expect(body.days).toBe(90);
    expect(body.services).toHaveLength(1);
    expect(body.services[0].slug).toBe(slug);
    expect(body.services[0].totalChecks).toBe(2);
    expect(body.services[0].uptimePercent).toBe(50);
  });

  it('/response-history returns a fixed-length bucket series', async () => {
    // Write through the REAL cycle path: insert the check AND roll up the hour
    // (sync.ts always does both in the same cycle). 24h/12 buckets spans ≥1h per
    // bucket, so the route reads the hourly rollup — a raw insert alone would be
    // invisible, and is a state the production writer never produces.
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'healthy', responseTimeMs: 100 });
    await db.run(rollupMetricsSql([slug]));
    const body = await parse(await app.request('/response-history?hours=24&buckets=12', { headers: viewAuth }));
    expect(body.hours).toBe(24);
    expect(body.points).toHaveLength(12);
    // The newest bucket (last element) holds the just-recorded sample.
    expect(body.points[body.points.length - 1]).toBe(100);
  });

  it('/deploy-projects returns projects from the meta snapshot, flagged wired/ignored', async () => {
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'adh', domain: 'adh.example.com' });
    const body = await parse(await app.request('/deploy-projects', { headers: viewAuth }));
    expect(Array.isArray(body.projects)).toBe(true);
    const adh = body.projects.find((p: { projectName: string }) => p.projectName === 'adh');
    expect(adh).toMatchObject({ platform: 'vercel', domain: 'adh.example.com', wired: false, ignored: false });
    // Additive canonical links: `live` is the project's primary domain as an absolute
    // URL. `platform` (a Vercel dashboard) needs VERCEL_TEAM_ID, so it's only present.
    expect(adh.links.live).toBe('https://adh.example.com');
    expect(adh.links).toHaveProperty('platform');
  });

  it('/deploy-projects attaches LIVE Cloudflare + Railway domains (not just Vercel meta)', async () => {
    // The bug this guards: CF workers + Railway projects carry no deployProjectMeta
    // row, so before the live-domain join they enumerated domain-less and could
    // never auto-configure. Stub each provider call the enumeration makes.
    process.env.CLOUDFLARE_API_TOKEN = 'cf-tok';
    process.env.RAILWAY_API_TOKEN = 'ry-tok';
    await db.insert(schema.deployIntegrations).values([
      { platform: 'cloudflare', label: 'Cloudflare', tokenEnvVar: 'CLOUDFLARE_API_TOKEN', config: { accountId: 'acct-1' } },
      {
        platform: 'railway',
        label: 'Railway',
        tokenEnvVar: 'RAILWAY_API_TOKEN',
        config: { projects: [{ id: 'proj-1', name: 'adh-backend' }] },
      },
    ]);

    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
        const u = String(url);
        if (u.includes('api.cloudflare.com') && u.includes('/workers/scripts')) {
          return Response.json({ success: true, result: [{ id: 'temporal-web' }] });
        }
        if (u.includes('api.cloudflare.com') && u.includes('/workers/domains')) {
          return Response.json({ success: true, result: [{ hostname: 'temporal.today', service: 'temporal-web' }] });
        }
        if (u.includes('backboard.railway.app')) {
          const q = String(init?.body ?? '');
          // Root `projects` query → enumerate the workspace's projects (the account
          // token authorizes this; the old `me { projects }` path is gone).
          if (q.includes('projects {')) {
            return Response.json({ data: { projects: { edges: [{ node: { id: 'proj-1', name: 'adh-backend' } }] } } });
          }
          // `project(id:)` query → that project's services × environments domains.
          return Response.json({
            data: {
              project: {
                environments: { edges: [{ node: { id: 'e1', name: 'production' } }] },
                services: {
                  edges: [
                    {
                      node: {
                        serviceInstances: {
                          edges: [
                            {
                              node: {
                                environmentId: 'e1',
                                domains: { customDomains: [{ domain: 'api.agenticdeveloperhub.com' }], serviceDomains: [] },
                              },
                            },
                          ],
                        },
                      },
                    },
                  ],
                },
              },
            },
          });
        }
        throw new Error(`unexpected fetch ${u}`);
      }),
    );

    const body = await parse(await app.request('/deploy-projects', { headers: viewAuth }));
    const cf = body.projects.find((p: { projectName: string }) => p.projectName === 'temporal-web');
    const ry = body.projects.find((p: { projectName: string }) => p.projectName === 'adh-backend');
    expect(cf).toBeDefined(); // a missing entry should fail clearly, not as a toMatchObject TypeError
    expect(ry).toBeDefined();
    expect(cf).toMatchObject({ platform: 'cloudflare-pages', domain: 'temporal.today' });
    // Railway is enumerated PER environment — this project has only production, so one
    // entry, exposing that env's FULL custom-domain set (here one host) so every
    // per-domain endpoint can match it.
    expect(ry).toMatchObject({ platform: 'railway', environment: 'production', domain: 'api.agenticdeveloperhub.com', domains: ['api.agenticdeveloperhub.com'] });
  });

  it('/deploy-projects splits a Railway project into one entry PER environment (provider-only staging surfaces)', async () => {
    // The bug part 7 fixes: a project serving production (custom domain) + staging (only a
    // *.up.railway.app provider host) collapsed to a single production entry, so staging
    // never got pulled in. It must now enumerate as TWO entries, staging addable via its
    // provider host.
    process.env.RAILWAY_API_TOKEN = 'ry-tok';
    await db.insert(schema.deployIntegrations).values({
      platform: 'railway',
      label: 'Railway',
      tokenEnvVar: 'RAILWAY_API_TOKEN',
      config: { projects: [{ id: 'proj-1', name: 'adh-backend' }] },
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
        const u = String(url);
        if (!u.includes('backboard.railway.app')) throw new Error(`unexpected fetch ${u}`);
        const q = String(init?.body ?? '');
        if (q.includes('projects {')) {
          return Response.json({ data: { projects: { edges: [{ node: { id: 'proj-1', name: 'adh-backend' } }] } } });
        }
        return Response.json({
          data: {
            project: {
              environments: { edges: [{ node: { id: 'e1', name: 'production' } }, { node: { id: 'e2', name: 'staging' } }] },
              services: {
                edges: [
                  {
                    node: {
                      serviceInstances: {
                        edges: [
                          { node: { environmentId: 'e1', domains: { customDomains: [{ domain: 'api.agenticdeveloperhub.com' }], serviceDomains: [] } } },
                          { node: { environmentId: 'e2', domains: { customDomains: [], serviceDomains: [{ domain: 'adh-backend-staging.up.railway.app' }] } } },
                        ],
                      },
                    },
                  },
                ],
              },
            },
          },
        });
      }),
    );

    const body = await parse(await app.request('/deploy-projects', { headers: viewAuth }));
    const ry = body.projects.filter((p: { projectName: string }) => p.projectName === 'adh-backend');
    expect(ry).toHaveLength(2);
    // Production first, then staging (production-first ordering).
    expect(ry[0]).toMatchObject({ environment: 'production', domain: 'api.agenticdeveloperhub.com' });
    // Staging surfaces via its provider host — the whole point of the per-env split.
    expect(ry[1]).toMatchObject({ environment: 'staging', domain: 'adh-backend-staging.up.railway.app', domains: ['adh-backend-staging.up.railway.app'] });
  });

  it('/deploy-projects: a CF worker still enumerates (domain null) when /workers/domains fails', async () => {
    // Guards the combined CF callback's fault isolation: listWorkerScripts succeeds but
    // listWorkerCustomDomains 403s → the worker is still listed, just without a domain
    // (graceful degradation to the pre-fix behaviour), not dropped entirely.
    process.env.CLOUDFLARE_API_TOKEN = 'cf-tok';
    await db.insert(schema.deployIntegrations).values({
      platform: 'cloudflare',
      label: 'Cloudflare',
      tokenEnvVar: 'CLOUDFLARE_API_TOKEN',
      config: { accountId: 'acct-1' },
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL | Request) => {
        const u = String(url);
        if (u.includes('/workers/scripts')) return Response.json({ success: true, result: [{ id: 'temporal-web' }] });
        if (u.includes('/workers/domains')) return new Response('forbidden', { status: 403 });
        throw new Error(`unexpected fetch ${u}`);
      }),
    );
    const body = await parse(await app.request('/deploy-projects', { headers: viewAuth }));
    const cf = body.projects.find((p: { projectName: string }) => p.projectName === 'temporal-web');
    expect(cf).toMatchObject({ platform: 'cloudflare-pages', domain: null });
  });

  it('/integrations returns the self-check report', async () => {
    const body = await parse(await app.request('/integrations', { headers: viewAuth }));
    expect(body).toHaveProperty('generatedAt');
    expect(body).toHaveProperty('overall');
    expect(Array.isArray(body.checks)).toBe(true);
    expect(body.checks.some((c: { id: string }) => c.id === 'stats')).toBe(true);
  });
});

// `deploy_project_meta` is the ONLY record of which Vercel projects exist, and it used to
// be written by the monitor and never corrected — so a project deleted at Vercel was still
// enumerated here, still offered by Auto Configure, and still owned a dead deploy target.
// The read path now re-verifies the mirror against the account BEFORE enumerating, so the
// board can never serve a project the platform no longer has.
describe('/deploy-projects re-verifies the project mirror', () => {
  let app: ReturnType<typeof createApp>;
  // The helper's Db (it carries `$client`, which stubVercelAccount's seeding needs).
  let db: TestDb;
  let viewAuth: { Cookie: string };
  let account: FakeVercelAccount;

  beforeEach(async () => {
    db = await bootDb();
    viewAuth = await sessionHeaders(db, 'viewer');
    account = await stubVercelAccount(db);
    app = createApp({ db, config: testConfig() });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  const namesFrom = (body: Record<string, any>): string[] =>
    body.projects.map((p: { projectName: string }) => p.projectName).sort();

  it('drops a project deleted at the platform instead of serving it from the stale mirror', async () => {
    account.add('reads-live');
    // The row a previous cycle left behind for a project since deleted upstream.
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'reads-ghost', domain: 'ghost.example.test' });

    const body = await parse(await app.request('/deploy-projects', { headers: viewAuth }));

    expect(namesFrom(body)).toEqual(['reads-live']);
    // …and the mirror itself is corrected, not merely filtered on the way out — otherwise
    // every other consumer of the table (Auto Configure, the issue narrowing) still sees it.
    expect((await db.select().from(schema.deployProjectMeta)).map((r) => r.projectName)).toEqual(['reads-live']);
  });

  it('re-verifies on ?fresh=1 — the read the Auto Configure modal makes', async () => {
    account.add('reads-live');
    expect(namesFrom(await parse(await app.request('/deploy-projects', { headers: viewAuth })))).toEqual(['reads-live']);

    // Deleted at Vercel between the two reads. Without ?fresh the cached enumeration
    // stands (that TTL is the point); with it, the mirror is re-verified and the project
    // is gone — which is what stops the modal re-offering a project that no longer exists.
    account.remove('reads-live');
    expect(namesFrom(await parse(await app.request('/deploy-projects', { headers: viewAuth })))).toEqual(['reads-live']);
    expect(namesFrom(await parse(await app.request('/deploy-projects?fresh=1', { headers: viewAuth })))).toEqual([]);
  });
});
