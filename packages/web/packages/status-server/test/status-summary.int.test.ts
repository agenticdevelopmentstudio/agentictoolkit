import { describe, it, expect, vi } from 'vitest';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { freshDb as bootDb } from './helpers/db';
import { testConfig } from './helpers/config';

/** One active group → site → endpoint; returns the probe slug (endpoint id). */
async function seedEndpoint(db: Db): Promise<string> {
  const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'Group' }).returning())[0]!;
  const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g.id, slug: 's', name: 'App' }).returning())[0]!;
  const ep = (
    await db
      .insert(schema.monitoredEndpoints)
      .values({ siteId: s.id, url: 'https://app.example.com', environment: 'production' })
      .returning()
  )[0]!;
  return ep.id;
}

interface Summary {
  operational: boolean;
  status: 'healthy' | 'degraded' | 'down' | 'unknown';
  generatedAt: string;
  counts: { total: number; healthy: number; degraded: number; down: number; unknown: number };
  downSites: { name: string; status: 'down' | 'degraded'; since?: string }[];
}

describe('/public/status-summary (public, no auth)', () => {
  it('is operational with no failing health checks', async () => {
    const db = await bootDb();
    const slug = await seedEndpoint(db);
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'healthy', statusCode: 200 });
    const res = await createApp({ db, config: testConfig() }).request('/public/status-summary');
    expect(res.status).toBe(200);
    const body = (await res.json()) as Summary;
    expect(body.operational).toBe(true);
    expect(body.status).toBe('healthy');
    expect(typeof body.generatedAt).toBe('string');
    expect(body.counts).toEqual({ total: 1, healthy: 1, degraded: 0, down: 0, unknown: 0 });
    expect(body.downSites).toEqual([]);
  });

  it('reports `unknown` (never green) when no service has been probed yet', async () => {
    const db = await bootDb();
    await seedEndpoint(db); // configured endpoint, but NO health check inserted
    const body = (await (await createApp({ db, config: testConfig() }).request('/public/status-summary')).json()) as Summary;
    expect(body.operational).toBe(false);
    expect(body.status).toBe('unknown');
    expect(body.counts).toEqual({ total: 1, healthy: 0, degraded: 0, down: 0, unknown: 1 });
    expect(body.downSites).toEqual([]);
  });

  it('lists a hard-down site with `since` and is not operational', async () => {
    const db = await bootDb();
    const slug = await seedEndpoint(db);
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'down', statusCode: 503 });
    await db.insert(schema.issues).values({ target: slug, source: 'http', name: 'App', severity: 'major', state: 'down' });
    const body = (await (await createApp({ db, config: testConfig() }).request('/public/status-summary')).json()) as Summary;
    expect(body.operational).toBe(false);
    expect(body.status).toBe('down');
    expect(body.counts).toEqual({ total: 1, healthy: 0, degraded: 0, down: 1, unknown: 0 });
    expect(body.downSites).toHaveLength(1);
    expect(body.downSites[0].status).toBe('down');
    expect(body.downSites[0].name).toContain('App');
    expect(body.downSites[0].name).toContain('production');
    expect(typeof body.downSites[0].since).toBe('string');
  });

  it('surfaces a failing deploy/build in downSites even though every endpoint is healthy', async () => {
    // The live site serves HTTP 200 (healthy endpoint), but its newest Vercel build
    // keeps failing. That open deploy issue isn't an endpoint health check, so the
    // headline drops to `degraded` rather than claim "All systems operational" — and
    // the failing project is NAMED in downSites (status:'degraded', since the site
    // itself is up) so the public "experiencing issues" list isn't empty/unexplained.
    const db = await bootDb();
    const slug = await seedEndpoint(db);
    await db.update(schema.monitoredEndpoints).set({ platform: 'vercel', deployProject: 'personaregistry-production' });
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'healthy', statusCode: 200 });
    await db.insert(schema.deployments).values({
      id: 'vc_personaregistry_1',
      platform: 'vercel',
      projectName: 'personaregistry-production',
      environment: 'production',
      buildPhase: 'failed',
      deployPhase: 'none',
      createdAt: new Date(),
    });
    const body = (await (await createApp({ db, config: testConfig() }).request('/public/status-summary')).json()) as Summary;
    expect(body.operational).toBe(false);
    expect(body.status).toBe('degraded');
    expect(body.counts).toEqual({ total: 1, healthy: 1, degraded: 0, down: 0, unknown: 0 });
    expect(body.downSites).toHaveLength(1);
    expect(body.downSites[0].status).toBe('degraded');
    expect(body.downSites[0].name).toContain('personaregistry-production');
    expect(typeof body.downSites[0].since).toBe('string');
  });

  it('lists both a down endpoint and a failing deploy, endpoint failures first', async () => {
    // Mixed portfolio: one endpoint hard-down (a real outage) plus a separate
    // project whose deploy is failing. Both are "sites having issues", so both
    // appear — the endpoint outage ranked ahead of the deploy failure.
    const db = await bootDb();
    const slug = await seedEndpoint(db);
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'down', statusCode: 503 });
    await db.insert(schema.issues).values({ target: slug, source: 'http', name: 'App', severity: 'major', state: 'down' });
    await db.update(schema.monitoredEndpoints).set({ platform: 'vercel', deployProject: 'olylo.ai-production' });
    await db.insert(schema.deployments).values({
      id: 'vc_olylo_1',
      platform: 'vercel',
      projectName: 'olylo.ai-production',
      environment: 'production',
      buildPhase: 'failed',
      deployPhase: 'none',
      createdAt: new Date(),
    });
    const body = (await (await createApp({ db, config: testConfig() }).request('/public/status-summary')).json()) as Summary;
    expect(body.operational).toBe(false);
    expect(body.status).toBe('down');
    expect(body.downSites).toHaveLength(2);
    expect(body.downSites[0].status).toBe('down'); // the endpoint outage ranks first
    expect(body.downSites[0].name).toContain('App');
    expect(body.downSites[1].status).toBe('degraded');
    expect(body.downSites[1].name).toContain('olylo.ai-production');
  });

  it('surfaces a degraded site in downSites (status:degraded) and is not operational', async () => {
    const db = await bootDb();
    const slug = await seedEndpoint(db);
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'degraded', statusCode: 200 });
    const body = (await (await createApp({ db, config: testConfig() }).request('/public/status-summary')).json()) as Summary;
    expect(body.operational).toBe(false);
    expect(body.status).toBe('degraded');
    expect(body.counts).toEqual({ total: 1, healthy: 0, degraded: 1, down: 0, unknown: 0 });
    expect(body.downSites).toHaveLength(1);
    expect(body.downSites[0].status).toBe('degraded');
  });
});

describe('/public/status-summary caching (unauthenticated route must not re-query per request)', () => {
  it('serves a cached summary within the TTL and refreshes after it', async () => {
    vi.useFakeTimers();
    try {
      const db = await bootDb();
      const slug = await seedEndpoint(db);
      await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'healthy', statusCode: 200 });
      const app = createApp({ db, config: testConfig() });

      const first = (await (await app.request('/public/status-summary')).json()) as Summary;
      expect(first.status).toBe('healthy');

      // State changes, but within the TTL the public summary must serve the
      // cached snapshot — this route is unauthenticated, so its DB cost must
      // not scale with request rate (the anonymous-CPU-DoS guard).
      await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'down', statusCode: 503 });
      const cached = (await (await app.request('/public/status-summary')).json()) as Summary;
      expect(cached.status).toBe('healthy');
      expect(cached.generatedAt).toBe(first.generatedAt);

      // Past the TTL the summary rebuilds and sees the new state.
      vi.advanceTimersByTime(31_000);
      const fresh = (await (await app.request('/public/status-summary')).json()) as Summary;
      expect(fresh.status).toBe('down');
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('/public/status-summary CORS (open to any origin)', () => {
  it('reflects an arbitrary Origin on the public summary', async () => {
    const db = await bootDb();
    await seedEndpoint(db);
    const res = await createApp({ db, config: testConfig() }).request('/public/status-summary', {
      headers: { Origin: 'https://status.agenticdeveloperhub.com' },
    });
    expect(res.headers.get('access-control-allow-origin')).toBe('https://status.agenticdeveloperhub.com');
  });

  it('does NOT open CORS for a foreign origin on an authed route', async () => {
    const db = await bootDb();
    const res = await createApp({ db, config: testConfig() }).request('/live', {
      headers: { Origin: 'https://evil.example.com' },
    });
    expect(res.headers.get('access-control-allow-origin')).toBeNull();
  });
});

describe('/public/status-summary stampede guard', () => {
  /** Count the DB reads one request costs, by proxying the handle the app uses. */
  async function readsFor(run: (app: ReturnType<typeof createApp>) => Promise<unknown>): Promise<number> {
    const db = await bootDb();
    const slug = await seedEndpoint(db);
    await db.insert(schema.healthChecks).values({ serviceSlug: slug, status: 'healthy', statusCode: 200 });
    let reads = 0;
    const counting = new Proxy(db, {
      get(target, prop, receiver) {
        // buildSnapshot reads via .select() and .all() — count both.
        if (prop === 'select' || prop === 'all') reads++;
        return Reflect.get(target, prop, receiver) as unknown;
      },
    }) as typeof db;
    await run(createApp({ db: counting, config: testConfig() }));
    return reads;
  }

  it('collapses concurrent misses into ONE snapshot build (the anonymous route)', async () => {
    // This route is unauthenticated: a burst landing on a cold cache must NOT each
    // run buildSnapshot — that is precisely the per-request DB read the cache
    // exists to prevent, and the reason the other cached routes single-flight.
    const one = await readsFor(async (app) => {
      await app.request('/public/status-summary');
    });
    const five = await readsFor(async (app) => {
      await Promise.all(Array.from({ length: 5 }, () => app.request('/public/status-summary')));
    });

    expect(one).toBeGreaterThan(0);
    expect(five).toBe(one); // five concurrent callers, one build
  });
});
