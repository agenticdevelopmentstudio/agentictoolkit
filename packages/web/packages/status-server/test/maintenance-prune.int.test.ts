import { describe, it, expect, beforeEach } from 'vitest';
import { sql } from 'drizzle-orm';
import * as schema from '../src/libsql/schema';
import { healthChecks, metricsHourly, analyticsMetrics, siteGroups, users, sessions, issues } from '../src/libsql/schema';
import { runMaintenance, ISSUE_RESOLVED_RETENTION_DAYS } from '../src/monitor/sync';
import { freshDb, type Db } from './helpers/db';

const DAY_MS = 86_400_000;

async function seed(db: Db, opts: { old: number; recent: number }): Promise<void> {
  const rows = [
    ...Array.from({ length: opts.old }, () => ({
      serviceSlug: 'svc-a',
      status: 'healthy',
      responseTimeMs: 100,
      statusCode: 200,
      checkedAt: new Date(Date.now() - 30 * DAY_MS), // past the 14-day default horizon
    })),
    ...Array.from({ length: opts.recent }, () => ({
      serviceSlug: 'svc-a',
      status: 'healthy',
      responseTimeMs: 100,
      statusCode: 200,
      checkedAt: new Date(), // inside the horizon
    })),
  ];
  if (rows.length > 0) await db.insert(healthChecks).values(rows);
}

async function count(db: Db): Promise<number> {
  const r = await db.run(sql`select count(*) as n from health_checks`);
  return Number((r.rows as unknown as Array<{ n: number }>)[0]?.n ?? 0);
}

describe('runMaintenance (health_checks retention prune)', () => {
  let db: Db;
  beforeEach(async () => {
    db = await freshDb();
  });

  it('drops rows past the retention horizon and keeps recent ones', async () => {
    await seed(db, { old: 10, recent: 5 });

    const res = await runMaintenance(db);

    expect(res).toEqual({ deleted: 10, done: true });
    expect(await count(db)).toBe(5);
  });

  it('is BOUNDED per run — a huge backlog drains over successive cycles', async () => {
    // The first prune on a table that was never pruned has millions of rows to clear. One
    // unbounded DELETE would be a single enormous transaction on a container volume, so the
    // prune is chunked and capped, and reports that there is more to do.
    await seed(db, { old: 10, recent: 2 });

    const first = await runMaintenance(db, undefined, { maxRows: 4, chunkRows: 2 });
    expect(first).toEqual({ deleted: 4, done: false }); // capped, backlog remains
    expect(await count(db)).toBe(8);

    const second = await runMaintenance(db, undefined, { maxRows: 100, chunkRows: 2 });
    expect(second).toEqual({ deleted: 6, done: true }); // caught up
    expect(await count(db)).toBe(2); // only the recent rows survive
  });

  it('is a no-op once caught up', async () => {
    await seed(db, { old: 3, recent: 4 });
    await runMaintenance(db);

    const again = await runMaintenance(db);

    expect(again).toEqual({ deleted: 0, done: true });
    expect(await count(db)).toBe(4);
  });
});

// Every unpruned table is a future CPU/disk bomb — the exact class that took the
// container down via health_checks. Maintenance must bound ALL the accruing
// tables, not just the biggest one.
describe('runMaintenance (metrics_hourly / analytics_metrics / sessions retention)', () => {
  let db: Db;
  beforeEach(async () => {
    db = await freshDb();
  });

  const metricsRow = (daysAgo: number) => ({
    serviceSlug: 'svc-a',
    hour: new Date(Date.now() - daysAgo * DAY_MS),
    totalChecks: 10,
    healthyChecks: 10,
    degradedChecks: 0,
    downChecks: 0,
    avgResponseTimeMs: 100,
    minResponseTimeMs: 80,
    maxResponseTimeMs: 130,
  });

  it('prunes metrics_hourly past the 90-day sparkline horizon, keeping newer rows', async () => {
    await db.insert(metricsHourly).values([metricsRow(100), metricsRow(10)]);

    const res = await runMaintenance(db);

    expect(res).toEqual({ deleted: 1, done: true });
    const left = await db.select().from(metricsHourly);
    expect(left).toHaveLength(1);
  });

  it('keeps metrics as long as the LONGEST group retention when it exceeds 90 days', async () => {
    await db.insert(siteGroups).values({ slug: 'g', name: 'G', retentionDays: 120 });
    await db.insert(metricsHourly).values([metricsRow(100), metricsRow(130)]);

    const res = await runMaintenance(db);

    expect(res).toEqual({ deleted: 1, done: true }); // only the 130-day row goes
    const left = await db.select().from(metricsHourly);
    expect(left).toHaveLength(1);
  });

  it('prunes analytics_metrics past 90 days (the trend store only ever serves recent rows)', async () => {
    await db.insert(analyticsMetrics).values([
      { metric: 'pageviews', window: '24h', scope: 'all', value: 10, capturedAt: new Date(Date.now() - 100 * DAY_MS) },
      { metric: 'pageviews', window: '24h', scope: 'all', value: 20, capturedAt: new Date() },
    ]);

    const res = await runMaintenance(db);

    expect(res).toEqual({ deleted: 1, done: true });
    const left = await db.select().from(analyticsMetrics);
    expect(left).toHaveLength(1);
    expect(left[0]?.value).toBe(20);
  });

  it('prunes long-RESOLVED issues but never an OPEN one, however old', async () => {
    // Resolving an issue instead of deleting it is what keeps a site's history readable —
    // but it also means `issues` now accrues forever, exactly the shape that took the
    // container down via health_checks. An OPEN issue has a NULL resolved_at and must
    // survive regardless of age: a service that has been down for a year is still down.
    const issue = (target: string, resolvedDaysAgo: number | null, openedDaysAgo: number) => ({
      target,
      source: 'http',
      name: target,
      severity: 'major',
      state: 'down',
      openedAt: new Date(Date.now() - openedDaysAgo * DAY_MS),
      resolvedAt: resolvedDaysAgo === null ? null : new Date(Date.now() - resolvedDaysAgo * DAY_MS),
    });
    await db.insert(issues).values([
      issue('ancient', ISSUE_RESOLVED_RETENTION_DAYS + 10, 400),
      issue('recent', 3, 10),
      issue('still-down', null, 400),
    ]);

    const res = await runMaintenance(db);

    expect(res).toEqual({ deleted: 1, done: true });
    expect((await db.select().from(issues)).map((r) => r.target).sort()).toEqual(['recent', 'still-down']);
  });

  it('reaps expired sessions and keeps live ones', async () => {
    const u = (await db.insert(users).values({ email: 'a@test.local', displayName: 'A', role: 'viewer' }).returning())[0]!;
    await db.insert(sessions).values([
      { userId: u.id, tokenHash: 'dead', expiresAt: new Date(Date.now() - DAY_MS) },
      { userId: u.id, tokenHash: 'live', expiresAt: new Date(Date.now() + DAY_MS) },
    ]);

    const res = await runMaintenance(db);

    expect(res).toEqual({ deleted: 1, done: true });
    const left = await db.select().from(sessions);
    expect(left).toHaveLength(1);
    expect(left[0]?.tokenHash).toBe('live');
  });
});
