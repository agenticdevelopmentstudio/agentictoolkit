import { describe, it, expect } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { sessionHeaders } from './helpers/auth';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

async function bootDb(): Promise<Db> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

const secAgo = (s: number): Date => new Date(Date.now() - s * 1000);
const hourStart = (hoursAgo: number): Date => {
  const t = Math.floor(Date.now() / 1000) - hoursAgo * 3600;
  return new Date(Math.floor(t / 3600) * 3600 * 1000);
};

describe('/response-history', () => {
  it('buckets a fine window from raw checks: UP checks only, placed oldest→newest', async () => {
    const db = await bootDb();
    const auth = await sessionHeaders(db, 'viewer');
    await db.insert(schema.healthChecks).values([
      // Newest bucket (age <10min): two healthy checks averaging 150.
      { serviceSlug: 'a', status: 'healthy', responseTimeMs: 100, statusCode: 200, checkedAt: secAgo(300) },
      { serviceSlug: 'b', status: 'healthy', responseTimeMs: 200, statusCode: 200, checkedAt: secAgo(300) },
      // A down check in the same bucket must NOT skew the average.
      { serviceSlug: 'a', status: 'down', responseTimeMs: 9_999, statusCode: 503, checkedAt: secAgo(300) },
      // Age ~35min → third bucket from the right (bucket span 10min).
      { serviceSlug: 'a', status: 'degraded', responseTimeMs: 300, statusCode: 200, checkedAt: secAgo(2_100) },
    ]);

    const res = await createApp({ db, config: testConfig() }).request('/response-history?hours=1&buckets=6', { headers: auth });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { hours: number; points: (number | null)[] };
    expect(body.points).toEqual([null, null, 300, null, null, 150]);
  });

  it('serves long windows from metrics_hourly (count-weighted), never scanning raw history', async () => {
    const db = await bootDb();
    const auth = await sessionHeaders(db, 'viewer');
    // Two rolled-up hours land in the NEWEST bucket of a 90-day/60-bucket
    // sparkline (bucket span 36h): weighted avg = (100·10 + 400·5) / 15 = 200.
    await db.insert(schema.metricsHourly).values([
      { serviceSlug: 'a', hour: hourStart(2), totalChecks: 10, healthyChecks: 10, degradedChecks: 0, downChecks: 0, avgResponseTimeMs: 100, minResponseTimeMs: 80, maxResponseTimeMs: 130 },
      { serviceSlug: 'b', hour: hourStart(3), totalChecks: 5, healthyChecks: 3, degradedChecks: 2, downChecks: 0, avgResponseTimeMs: 400, minResponseTimeMs: 300, maxResponseTimeMs: 600 },
      // A down-only hour has zero UP weight — it must not drag the bucket.
      { serviceSlug: 'c', hour: hourStart(4), totalChecks: 5, healthyChecks: 0, degradedChecks: 0, downChecks: 5, avgResponseTimeMs: 8_000, minResponseTimeMs: 8_000, maxResponseTimeMs: 8_000 },
    ]);
    // Poison pill: a raw check whose value would wreck the average if the long
    // window still scanned health_checks. The whole point of the rewrite is that
    // 90-day windows read the (bounded) hourly rollup, not up to 90 days × fleet
    // of raw rows materialized per request.
    await db.insert(schema.healthChecks).values({
      serviceSlug: 'a',
      status: 'healthy',
      responseTimeMs: 99_999,
      statusCode: 200,
      checkedAt: secAgo(3_600),
    });

    const res = await createApp({ db, config: testConfig() }).request('/response-history?hours=2160&buckets=60', { headers: auth });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { points: (number | null)[] };
    expect(body.points).toHaveLength(60);
    expect(body.points[59]).toBe(200);
    expect(body.points.slice(0, 59).every((p) => p === null)).toBe(true);
  });
});
