import { describe, it, expect, beforeEach } from 'vitest';
import { sql } from 'drizzle-orm';
import { healthChecks, monitoredEndpoints, monitoredSites, siteGroups } from '../src/libsql/schema';
import { latestCheckBySlugSql } from '../src/storage/health-store';
import { readBoardFacts } from '../src/board';
import { freshDb, type Db } from './helpers/db';
import { testConfig } from './helpers/config';

type Row = { service_slug: string; status: string; checked_at: number };

async function latestFor(db: Db, slugs: string[]): Promise<Row[]> {
  return await db.all<Row>(latestCheckBySlugSql(slugs));
}

describe('latestCheckBySlug', () => {
  let db: Db;
  beforeEach(async () => {
    db = await freshDb();
  });

  it('returns the newest check per requested slug, and only requested slugs', async () => {
    const older = new Date(Date.now() - 120_000);
    const newest = new Date();
    await db.insert(healthChecks).values([
      { serviceSlug: 'svc-a', status: 'down', responseTimeMs: 900, statusCode: 500, checkedAt: older },
      { serviceSlug: 'svc-a', status: 'healthy', responseTimeMs: 100, statusCode: 200, checkedAt: newest },
      { serviceSlug: 'svc-b', status: 'degraded', responseTimeMs: 400, statusCode: 200, checkedAt: older },
      // svc-retired has history but is NOT requested (deleted endpoint) — must not appear.
      { serviceSlug: 'svc-retired', status: 'down', responseTimeMs: null, statusCode: null, checkedAt: newest },
    ]);

    const rows = await latestFor(db, ['svc-a', 'svc-b', 'svc-never-probed']);

    expect(rows).toHaveLength(2); // never-probed slug is simply absent
    expect(rows.find((r) => r.service_slug === 'svc-a')?.status).toBe('healthy');
    expect(rows.find((r) => r.service_slug === 'svc-b')?.status).toBe('degraded');
  });

  it('breaks a same-timestamp tie toward the later insert, like the window form did', async () => {
    const t = new Date();
    await db.insert(healthChecks).values([
      { serviceSlug: 'svc-a', status: 'down', responseTimeMs: 900, statusCode: 500, checkedAt: t },
    ]);
    await db.insert(healthChecks).values([
      { serviceSlug: 'svc-a', status: 'healthy', responseTimeMs: 100, statusCode: 200, checkedAt: t },
    ]);

    const rows = await latestFor(db, ['svc-a']);
    const ids = await db.all<{ id: number }>(sql`select id from health_checks order by id desc limit 1`);
    const winner = await db.all<{ status: string }>(
      sql`select status from health_checks where id = ${ids[0]!.id}`,
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]!.status).toBe(winner[0]!.status);
  });

  it('SEEKS each slug via the index instead of scanning health_checks', async () => {
    // The regression guard for the slow-board/slow-login outage. The previous form
    // (`row_number() over (partition by service_slug ...)` with no predicate) walked
    // EVERY historical health_checks row on EVERY board read, SSE publish, and the
    // public status summary — cost grew with total history, exactly the class that
    // starved the container's CPU. The plan must never SCAN health_checks; each
    // requested slug is an idx_health_service_checked seek.
    const plan = await db.run(sql`explain query plan ${latestCheckBySlugSql(['svc-a', 'svc-b'])}`);
    const lines = (plan.rows as unknown as Array<{ detail: string }>).map((r) => r.detail);

    expect(lines.join(' | ')).toMatch(/idx_health_service_checked/);
    // EXPLAIN reports the joined table under its ALIAS (`SCAN hc`, never
    // `SCAN health_checks`), so guard by allowlist: the only SCAN this plan may
    // contain is the slug_list json_each virtual table — any other SCAN is the
    // O(total-history) walk coming back under whatever name the plan gives it.
    for (const line of lines.filter((l) => /\bSCAN\b/.test(l))) {
      expect(line).toMatch(/slug_list/);
    }
  });

  // The guard above is bound to the STATEMENT, so it was structurally incapable of
  // seeing the board's second reader: `readEndpointFacts` had its own unpredicated
  // `group by service_slug`, which planned as `SCAN health_checks USING INDEX
  // idx_health_service_checked` and ran on /live, /snapshot, /fleet, /badge, GET /board,
  // every SSE publish and the MCP tools — the same outage, past its own regression test.
  // These two cases cover the BOARD's call site: one proves the read is predicated by
  // the roster, the other EXPLAINs the statement it issues.
  describe("the board's endpoint read", () => {
    async function seedRoster(db: Db) {
      await db.insert(siteGroups).values({ id: 'grp-1', name: 'Hub', slug: 'hub' });
      await db.insert(monitoredSites).values({ id: 'site-1', siteGroupId: 'grp-1', name: 'Hub Help', slug: 'hub-help' });
      await db.insert(monitoredEndpoints).values([
        { id: 'ep-1', siteId: 'site-1', url: 'https://a.example.com', isActive: true },
        { id: 'ep-retired', siteId: 'site-1', url: 'https://b.example.com', isActive: false },
      ]);
    }

    it('fetches only the ACTIVE roster slugs, never the whole table', async () => {
      await seedRoster(db);
      await db.insert(healthChecks).values([
        { serviceSlug: 'ep-1', status: 'healthy', responseTimeMs: 100, statusCode: 200, checkedAt: new Date() },
        { serviceSlug: 'ep-retired', status: 'down', responseTimeMs: null, statusCode: 500, checkedAt: new Date() },
        // History for an endpoint that no longer exists in config at all.
        { serviceSlug: 'ep-deleted', status: 'down', responseTimeMs: null, statusCode: 500, checkedAt: new Date() },
      ]);

      const facts = await readBoardFacts(db, Date.now(), testConfig());
      expect(facts.endpoints.map((e) => e.endpointId)).toEqual(['ep-1']);
    });

    it('SEEKS per slug, exactly like the route read — same statement, same plan', async () => {
      await seedRoster(db);
      const facts = await readBoardFacts(db, Date.now(), testConfig());
      // Drive the EXPLAIN from the slug list the board actually assembled, so this
      // cannot pass against a list no caller would ever produce.
      const slugs = facts.roster.filter((e) => e.isActive).map((e) => e.endpointId);
      expect(slugs).toEqual(['ep-1']);

      const plan = await db.run(sql`explain query plan ${latestCheckBySlugSql(slugs)}`);
      const lines = (plan.rows as unknown as Array<{ detail: string }>).map((r) => r.detail);
      expect(lines.join(' | ')).toMatch(/idx_health_service_checked/);
      for (const line of lines.filter((l) => /\bSCAN\b/.test(l))) {
        expect(line).toMatch(/slug_list/);
      }
    });
  });
});
