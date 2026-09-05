import { Hono } from 'hono';
import type { Db } from '../libsql/client';
import type { StatusConfig } from '../config/port';
import type { Tier } from '../middleware/auth';
import {
  buildAnalyticsFetcher,
  analyticsStore,
  buildErrorsFetcher,
  errorsStore,
} from '../telemetry/server';
import type { Fetcher } from '../telemetry/ports';
import { cachedSingleFlight } from '@agentic-toolkit/deploy-platform/util';
import type { AnalyticsMetricDTO, ErrorDTO, TelemetrySnapshot } from '../telemetry/types';

// ---------------------------------------------------------------------------
// The TELEMETRY read API — the production-visibility band (errors + analytics).
//
//   /telemetry   LIVE snapshot — polls GlitchTip + PostHog directly (NOT the DB),
//                a 30s in-memory cache dampens the provider fan-out; ?fresh=1
//                bypasses it. A failed poll contributes an empty list rather than
//                clearing the other stream, so one provider outage never blanks
//                the band.
//   /errors      the SQLite-backed errors stream (errorsStore.load)
//   /analytics   the SQLite-backed analytics stream, reduced to the latest value
//                per (metric, window, scope) (analyticsStore.load)
//
// These sit behind the app-wide requireAuth (VIEW/ADMIN/cookie — the frontend
// proxy attaches the cookie). They are NOT /snapshot, so PEER_TOKEN does NOT
// apply, which is correct: peers exchange health snapshots, not telemetry.
// ---------------------------------------------------------------------------

const CACHE_TTL_MS = 30_000;

export function telemetryRoutes(
  db: Db,
  config: StatusConfig,
  // Injectable for tests (a fetcher built once at call time can't be varied
  // per-case otherwise); production wiring passes nothing.
  deps: { errorsFetcher?: Fetcher<ErrorDTO>; analyticsFetcher?: Fetcher<AnalyticsMetricDTO> } = {},
): Hono<{ Variables: { tier: Tier } }> {
  const errorsFetcher = deps.errorsFetcher ?? buildErrorsFetcher(config);
  const analyticsFetcher = deps.analyticsFetcher ?? buildAnalyticsFetcher(config);
  const app = new Hono<{ Variables: { tier: Tier } }>();

  // Last stream that ACTUALLY polled ok, per provider — a failed poll serves this
  // instead of blanking the band (an empty-because-failed stream is indistinguishable
  // from a healthy "no errors" to the client, so substitute the last good read).
  const lastGood: { errors: ErrorDTO[] | null; analytics: AnalyticsMetricDTO[] | null } = {
    errors: null,
    analytics: null,
  };

  async function build(): Promise<TelemetrySnapshot> {
    const [er, ar] = await Promise.all([errorsFetcher.fetch(), analyticsFetcher.fetch()]);
    if (er.ok) lastGood.errors = er.items;
    if (ar.ok) lastGood.analytics = ar.items;
    return {
      generatedAt: new Date().toISOString(),
      // A failed poll serves the last good stream (or nothing on a cold start)
      // rather than clearing the other stream — one provider outage never blanks
      // the band, and a transient one doesn't even blank its own stream.
      errors: er.ok ? er.items : (lastGood.errors ?? []),
      analytics: ar.ok ? ar.items : (lastGood.analytics ?? []),
    };
  }

  // TTL + single-flight (the shared primitive): concurrent cache misses — a burst of
  // page loads, several panes — share ONE provider poll instead of each fanning out
  // its own GlitchTip + PostHog round, which is what turned one slow provider into a
  // page-load-multiplied wall of "[telemetry] … failed" log lines. A ?fresh=1 during
  // an in-flight build joins it: a poll started moments ago IS fresh.
  const cachedSnapshot = cachedSingleFlight(CACHE_TTL_MS, build);

  app.get('/telemetry', async (c) => {
    const snapshot = await cachedSnapshot(c.req.query('fresh') === '1');
    return c.json(snapshot, 200, { 'Cache-Control': 'no-store' });
  });

  app.get('/errors', async (c) => {
    const errors = await errorsStore.load(db);
    return c.json({ errors }, 200, { 'Cache-Control': 'public, max-age=30' });
  });

  app.get('/analytics', async (c) => {
    const metrics = await analyticsStore.load(db);
    return c.json({ metrics }, 200, { 'Cache-Control': 'public, max-age=30' });
  });

  return app;
}
