import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { telemetryRoutes } from '../src/routes/telemetry';
import type { Fetcher } from '../src/telemetry/ports';
import type { ErrorDTO, AnalyticsMetricDTO } from '../src/telemetry/types';
import { sessionHeaders } from './helpers/auth';
import { freshDb as bootDb } from './helpers/db';
import { testConfig } from './helpers/config';

async function parse(res: Response): Promise<Record<string, any>> {
  return (await res.json()) as Record<string, any>;
}

describe('telemetry read API', () => {
  let app: ReturnType<typeof createApp>;
  let db: Db;
  let viewAuth: { Cookie: string };

  beforeEach(async () => {
    // Ensure no provider env leaks in from the environment — the live snapshot
    // must return empty lists without hitting GlitchTip/PostHog.
    delete process.env.GLITCHTIP_URL;
    delete process.env.GLITCHTIP_API_TOKEN;
    delete process.env.GLITCHTIP_ORG;
    delete process.env.POSTHOG_HOST;
    delete process.env.POSTHOG_API_KEY;
    delete process.env.POSTHOG_PROJECT_ID;
    db = await bootDb();
    viewAuth = await sessionHeaders(db, 'viewer');
    app = createApp({ db, config: testConfig() });
  });

  it('/errors is gated — 401 without a token', async () => {
    expect((await app.request('/errors')).status).toBe(401);
  });

  it('/errors returns an empty list on an empty DB (with the view bearer)', async () => {
    const res = await app.request('/errors', { headers: viewAuth });
    expect(res.status).toBe(200);
    const body = await parse(res);
    expect(body).toEqual({ errors: [] });
  });

  it('/analytics is gated and returns an empty list on an empty DB', async () => {
    expect((await app.request('/analytics')).status).toBe(401);
    const res = await app.request('/analytics', { headers: viewAuth });
    expect(res.status).toBe(200);
    expect(await parse(res)).toEqual({ metrics: [] });
  });

  it('/analytics reduces a series to the latest captured value', async () => {
    const older = new Date('2026-06-01T00:00:00.000Z');
    const newer = new Date('2026-06-02T00:00:00.000Z');
    await db.insert(schema.analyticsMetrics).values([
      { metric: 'pageviews', window: '24h', scope: 'all', value: 100, capturedAt: older },
      { metric: 'pageviews', window: '24h', scope: 'all', value: 250, capturedAt: newer },
      { metric: 'visitors', window: '24h', scope: 'all', value: 42, capturedAt: newer },
    ]);
    const body = await parse(await app.request('/analytics', { headers: viewAuth }));
    expect(body.metrics).toHaveLength(2);
    const pv = body.metrics.find((m: { metric: string }) => m.metric === 'pageviews');
    // The newer row wins the reduce-latest-per-series.
    expect(pv).toMatchObject({ metric: 'pageviews', window: '24h', scope: 'all', value: 250 });
    expect(pv.capturedAt).toBe(newer.toISOString());
  });

  it('/errors surfaces an upserted issue and hides resolved ones', async () => {
    await db.insert(schema.errors).values({
      issueKey: 'gt-1',
      project: 'adh-app',
      title: 'TypeError: undefined is not a function',
      level: 'error',
      count: 7,
      userCount: 3,
      lastSeen: new Date('2026-06-02T00:00:00.000Z'),
      permalink: 'https://glitchtip.example/issues/1',
    });
    const body = await parse(await app.request('/errors', { headers: viewAuth }));
    expect(body.errors).toHaveLength(1);
    expect(body.errors[0]).toMatchObject({ issueKey: 'gt-1', project: 'adh-app', count: 7, userCount: 3 });
  });

  it('/telemetry is gated and returns an empty live snapshot when no provider env is set', async () => {
    expect((await app.request('/telemetry')).status).toBe(401);
    const res = await app.request('/telemetry?fresh=1', { headers: viewAuth });
    expect(res.status).toBe(200);
    const body = await parse(res);
    expect(body).toHaveProperty('generatedAt');
    expect(body.errors).toEqual([]);
    expect(body.analytics).toEqual([]);
  });

  it('/telemetry is NOT reachable with PEER_TOKEN (peers exchange health, not telemetry)', async () => {
    process.env.PEER_TOKEN = 'peer';
    const res = await app.request('/telemetry', { headers: { Authorization: 'Bearer peer' } });
    expect(res.status).toBe(401);
    delete process.env.PEER_TOKEN;
  });
});

// The live /telemetry snapshot's resilience seams, with INJECTED fetchers (the module
// defaults capture provider env at load, so a test can't vary them). The routes are
// requested directly — createApp's auth gate is exercised by the suite above.
describe('telemetry live snapshot — single-flight + stale fallback', () => {
  const errItem: ErrorDTO = {
    id: 'gt-1',
    issueKey: 'gt-1',
    project: 'adh-app',
    title: 'boom',
    culprit: null,
    level: 'error',
    count: 1,
    userCount: 1,
    firstSeen: null,
    lastSeen: new Date('2026-06-02T00:00:00.000Z').toISOString(),
    permalink: 'https://glitchtip.example/issues/1',
  };

  let db: Db;
  beforeEach(async () => {
    db = await bootDb();
  });

  it('concurrent cache misses share ONE provider poll (single-flight)', async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const errorsFetcher: Fetcher<ErrorDTO> = {
      fetch: vi.fn(async () => {
        await gate;
        return { ok: true as const, items: [errItem] };
      }),
    };
    const analyticsFetcher: Fetcher<AnalyticsMetricDTO> = { fetch: vi.fn(async () => ({ ok: true as const, items: [] })) };
    const routes = telemetryRoutes(db, testConfig(), { errorsFetcher, analyticsFetcher });

    const [a, b] = [routes.request('/telemetry'), routes.request('/telemetry?fresh=1')];
    release();
    const bodies = await Promise.all([a, b].map(async (p) => (await (await p).json()) as { errors: unknown[] }));
    expect(bodies[0]!.errors).toHaveLength(1);
    expect(bodies[1]!.errors).toHaveLength(1);
    // ONE build served both requests — a burst of page loads can no longer fan out
    // one provider poll per request.
    expect(errorsFetcher.fetch).toHaveBeenCalledTimes(1);
    expect(analyticsFetcher.fetch).toHaveBeenCalledTimes(1);
  });

  it('a failed poll serves the last GOOD stream instead of blanking the band', async () => {
    let fail = false;
    const errorsFetcher: Fetcher<ErrorDTO> = {
      fetch: async () => (fail ? { ok: false as const, items: [] } : { ok: true as const, items: [errItem] }),
    };
    const analyticsFetcher: Fetcher<AnalyticsMetricDTO> = { fetch: async () => ({ ok: true as const, items: [] }) };
    const routes = telemetryRoutes(db, testConfig(), { errorsFetcher, analyticsFetcher });

    const first = (await (await routes.request('/telemetry?fresh=1')).json()) as { errors: { issueKey: string }[] };
    expect(first.errors.map((e) => e.issueKey)).toEqual(['gt-1']);

    fail = true;
    const second = (await (await routes.request('/telemetry?fresh=1')).json()) as { errors: { issueKey: string }[] };
    // The provider outage is invisible to the band — last good read stands in.
    expect(second.errors.map((e) => e.issueKey)).toEqual(['gt-1']);
  });
});
