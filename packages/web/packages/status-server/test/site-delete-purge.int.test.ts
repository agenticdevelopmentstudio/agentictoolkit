import { describe, it, expect, beforeEach } from 'vitest';
import { createApp } from '../src/app';
import { deployments, healthChecks, issues, metricsHourly } from '../src/libsql/schema';
import { sessionHeaders } from './helpers/auth';
import { freshDb, type Db } from './helpers/db';
import { testConfig } from './helpers/config';

// Every delete path that removes a monitored endpoint must purge its history
// (health_checks, metrics_hourly — both keyed by service_slug = endpoint id) and CLOSE its
// open issues (keyed by target = endpoint id) IN THE SAME REQUEST, so a deleted site
// vanishes from Activity/Problems immediately instead of lingering until the next cycle
// sweep. The three UI-reachable paths are: DELETE /config/sites/:id (auto-configure
// rollback), DELETE /config/endpoints/:id (the dashboard's retire path), and
// DELETE /config/site-groups/:id (group delete). Each must purge ONLY the endpoints it
// removes — never a bystander site/group's history.
//
// Issues are RESOLVED, not deleted: the Problem drops out of the board (which reads
// `resolved_at is null`) while the incident stays in history. Each test therefore asserts
// both halves — gone from open, still present as resolved.
describe('config delete purge', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let adminAuth: { Cookie: string };

  beforeEach(async () => {
    db = await freshDb();
    adminAuth = await sessionHeaders(db, 'admin');
    app = createApp({ db, config: testConfig() });
  });

  const postJson = (path: string, body: unknown) =>
    app.request(path, {
      method: 'POST',
      headers: { ...adminAuth, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

  const del = (path: string) => app.request(path, { method: 'DELETE', headers: adminAuth });

  // Seed one health-check row, one hourly-metrics row, and one open issue keyed by an
  // endpoint id (its service slug / issue target).
  const seedHistory = async (epId: string) => {
    await db.insert(healthChecks).values({ serviceSlug: epId, status: 'down', statusCode: 500, responseTimeMs: 10, checkedAt: new Date() });
    await db.insert(metricsHourly).values({ serviceSlug: epId, hour: new Date(), totalChecks: 2, healthyChecks: 1, degradedChecks: 0, downChecks: 1 });
    await db.insert(issues).values({ target: epId, source: 'http', name: 'S', severity: 'major', state: 'down', detail: 'd' });
  };

  const checkSlugs = async () => (await db.select().from(healthChecks)).map((r) => r.serviceSlug);
  const metricSlugs = async () => (await db.select().from(metricsHourly)).map((r) => r.serviceSlug);
  // What the Problems panel shows (`resolved_at is null`) vs. what history retains.
  const rows = async () => await db.select().from(issues);
  const openTargets = async () => (await rows()).filter((r) => !r.resolvedAt).map((r) => r.target);
  const resolvedTargets = async () => (await rows()).filter((r) => r.resolvedAt).map((r) => r.target).sort();

  const makeGroup = async (slug: string) =>
    (await (await postJson('/config/site-groups', { name: slug.toUpperCase(), slug })).json()) as { id: string };
  const makeSite = async (groupId: string, slug: string) =>
    (await (await postJson('/config/sites', { name: slug.toUpperCase(), slug, siteGroupId: groupId })).json()) as { id: string };
  const makeEndpoint = async (siteId: string, host: string, wired?: { platform: string; deployProject: string }) =>
    (await (await postJson('/config/endpoints', { siteId, url: `https://${host}`, ...wired })).json()) as { id: string };

  it('DELETE /config/sites/:id purges only that site, leaving a sibling site untouched', async () => {
    const group = await makeGroup('g');
    const siteA = await makeSite(group.id, 'a');
    const epA = await makeEndpoint(siteA.id, 'a.example.com');
    const siteB = await makeSite(group.id, 'b');
    const epB = await makeEndpoint(siteB.id, 'b.example.com');
    await seedHistory(epA.id);
    await seedHistory(epB.id);

    const res = await del(`/config/sites/${siteA.id}`);
    expect(res.status).toBe(200);

    // A's history purged and its Problem closed; B's SURVIVE (over-deletion would drop
    // them too). A's issue row is kept as resolved history, not deleted.
    expect(await checkSlugs()).toEqual([epB.id]);
    expect(await metricSlugs()).toEqual([epB.id]);
    expect(await openTargets()).toEqual([epB.id]);
    expect(await resolvedTargets()).toEqual([epA.id]);
  });

  it('DELETE /config/endpoints/:id (retire) purges the retired endpoint but keeps a live sibling endpoint', async () => {
    // Two endpoints under ONE site: retiring one keeps the site (and the other endpoint).
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    const ep1 = await makeEndpoint(site.id, 's1.example.com');
    const ep2 = await makeEndpoint(site.id, 's2.example.com');
    await seedHistory(ep1.id);
    await seedHistory(ep2.id);

    const res = await del(`/config/endpoints/${ep1.id}`);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, endpointDeleted: true, siteDeleted: false });

    // Only ep1's history is purged and only its Problem closed; ep2 (still live) keeps both.
    expect(await checkSlugs()).toEqual([ep2.id]);
    expect(await metricSlugs()).toEqual([ep2.id]);
    expect(await openTargets()).toEqual([ep2.id]);
    expect(await resolvedTargets()).toEqual([ep1.id]);
  });

  it('DELETE /config/endpoints/:id (retire) of a 1:1 site cascades the empty site and purges its history', async () => {
    const group = await makeGroup('g');
    const site = await makeSite(group.id, 's');
    const ep = await makeEndpoint(site.id, 's.example.com');
    const other = await makeSite(group.id, 'o');
    const epOther = await makeEndpoint(other.id, 'o.example.com');
    await seedHistory(ep.id);
    await seedHistory(epOther.id);

    const res = await del(`/config/endpoints/${ep.id}`);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, endpointDeleted: true, siteDeleted: true });

    // The retired endpoint's history is gone; the untouched site's SURVIVES.
    expect(await checkSlugs()).toEqual([epOther.id]);
    expect(await metricSlugs()).toEqual([epOther.id]);
    expect(await openTargets()).toEqual([epOther.id]);
    expect(await resolvedTargets()).toEqual([ep.id]);
  });

  it('DELETE /config/sites/:id also closes the DEPLOY-target Problem its endpoint owned', async () => {
    // The other half of a site's Problems: issues keyed by `<platform>|<project>|<env>`,
    // not by endpoint slug. Deleting the site un-owns that deploy target, and the route's
    // inline reconcile must close it in the SAME request — this is the entry that used to
    // survive a delete and come back with the next Auto Configure run.
    const group = await makeGroup('g');
    const doomed = await makeSite(group.id, 'a');
    await makeEndpoint(doomed.id, 'a.example.com', { platform: 'vercel', deployProject: 'docs-old' });
    const keeper = await makeSite(group.id, 'b');
    await makeEndpoint(keeper.id, 'b.example.com', { platform: 'vercel', deployProject: 'web-prod' });
    // The FAILED BUILD behind each Problem, not just the ledger row. The ledger stopped
    // being truth when the board became the fold: `applyBoardToLedger` resolves any open
    // row the board no longer derives, so seeding `issues` alone makes the KEEPER's row
    // close as "recovered" on the delete's own reconcile — the test would then pass or
    // fail for a reason that has nothing to do with un-owning the deleted site's target.
    await db.insert(deployments).values(
      ['docs-old', 'web-prod'].map((projectName) => ({
        id: `vc_${projectName}`,
        platform: 'vercel',
        projectName,
        buildPhase: 'failed',
        deployPhase: 'none',
        environment: 'production',
        createdAt: new Date(),
      })),
    );
    await db.insert(issues).values([
      { target: 'vercel|docs-old|', source: 'vercel', name: 'docs-old', severity: 'major', state: 'failed' },
      { target: 'vercel|web-prod|', source: 'vercel', name: 'web-prod', severity: 'major', state: 'failed' },
    ]);

    expect((await del(`/config/sites/${doomed.id}`)).status).toBe(200);

    // The deleted site's build failure is off the board; the surviving site's stays.
    expect(await openTargets()).toEqual(['vercel|web-prod|']);
    expect(await resolvedTargets()).toEqual(['vercel|docs-old|']);
  });

  it('DELETE /config/site-groups/:id purges every endpoint across the group, leaving another group untouched', async () => {
    const groupG = await makeGroup('g');
    const siteA = await makeSite(groupG.id, 'a');
    const epA = await makeEndpoint(siteA.id, 'a.example.com');
    const siteB = await makeSite(groupG.id, 'b');
    const epB = await makeEndpoint(siteB.id, 'b.example.com');
    const groupH = await makeGroup('h');
    const siteC = await makeSite(groupH.id, 'c');
    const epC = await makeEndpoint(siteC.id, 'c.example.com');
    await seedHistory(epA.id);
    await seedHistory(epB.id);
    await seedHistory(epC.id);

    const res = await del(`/config/site-groups/${groupG.id}`);
    expect(res.status).toBe(200);

    // Both of group G's endpoints purged; group H's endpoint SURVIVES.
    expect(await checkSlugs()).toEqual([epC.id]);
    expect(await metricSlugs()).toEqual([epC.id]);
    expect(await openTargets()).toEqual([epC.id]);
    expect(await resolvedTargets()).toEqual([epA.id, epB.id].sort());
  });
});
