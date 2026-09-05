import { describe, it, expect, beforeEach } from 'vitest';
import { sql } from 'drizzle-orm';
import { healthChecks, metricsHourly } from '../src/libsql/schema';
import { rollupMetricsSql } from '../src/monitor/sync';
import { freshDb, type Db } from './helpers/db';

describe('rollupMetrics', () => {
  let db: Db;
  beforeEach(async () => {
    db = await freshDb();
  });

  it('aggregates ONLY the current hour, ignoring older history', async () => {
    const now = new Date();
    const anHourAgo = new Date(Date.now() - 90 * 60 * 1000);
    await db.insert(healthChecks).values([
      { serviceSlug: 'svc-a', status: 'healthy', responseTimeMs: 100, statusCode: 200, checkedAt: now },
      { serviceSlug: 'svc-a', status: 'healthy', responseTimeMs: 300, statusCode: 200, checkedAt: now },
      { serviceSlug: 'svc-a', status: 'down', responseTimeMs: 500, statusCode: 500, checkedAt: now },
      // Older history must NOT be folded into this hour's bucket.
      { serviceSlug: 'svc-a', status: 'down', responseTimeMs: 900, statusCode: 500, checkedAt: anHourAgo },
      { serviceSlug: 'svc-a', status: 'down', responseTimeMs: 900, statusCode: 500, checkedAt: anHourAgo },
    ]);

    await db.run(rollupMetricsSql(['svc-a']));

    const rows = await db.select().from(metricsHourly);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      serviceSlug: 'svc-a',
      totalChecks: 3,
      healthyChecks: 2,
      downChecks: 1,
      minResponseTimeMs: 100,
      maxResponseTimeMs: 500,
    });
  });

  it('is idempotent — re-running recomputes the bucket rather than doubling it', async () => {
    await db.insert(healthChecks).values([
      { serviceSlug: 'svc-a', status: 'healthy', responseTimeMs: 100, statusCode: 200, checkedAt: new Date() },
    ]);
    await db.run(rollupMetricsSql(['svc-a']));
    await db.run(rollupMetricsSql(['svc-a']));

    const rows = await db.select().from(metricsHourly);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.totalChecks).toBe(1);
  });

  it('SEEKS the hour via the index instead of scanning every historical row', async () => {
    // The regression guard for the outage. Wrapping `checked_at` in arithmetic
    // (`(checked_at / 3600) * 3600 = ...`) is not sargable: SQLite then walks EVERY row of
    // every probed slug on EVERY tick, so the cost grows with total history and eventually
    // exceeds the container's CPU quota — the event-loop starvation that had the supervisor
    // restarting the container. The plan must show a RANGE on the bare column.
    const plan = await db.run(sql`explain query plan ${rollupMetricsSql(['svc-a'])}`);
    const detail = (plan.rows as unknown as Array<{ detail: string }>).map((r) => r.detail).join(' | ');

    expect(detail).toMatch(/idx_health_service_checked/);
    expect(detail).toMatch(/checked_at>/); // an indexed range seek, not a full per-slug walk
  });
});
