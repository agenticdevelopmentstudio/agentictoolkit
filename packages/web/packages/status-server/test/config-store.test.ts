import { describe, it, expect } from 'vitest';
import { eq, sql } from 'drizzle-orm';
import { siteGroups, monitoredSites, monitoredEndpoints, issues } from '../src/libsql/schema';
import {
  createEndpoint, purgeEndpointHistory, reconcileOrphanedEndpoints, retireEndpoint,
} from '../src/storage/config-store';
import { freshDb as baseDb, type Db } from './helpers/db';

// reconcileOrphanedEndpoints defends the no-FK-enforcement deployment mode (libSQL
// over HTTP / Turso, where ON DELETE CASCADE is NOT enforced — see config-store.ts).
// The embedded test DB enforces FKs (a cascade would auto-clean before the reconcile
// runs, and a bad-FK insert would be rejected), so we turn them OFF to reproduce the
// exact condition orphans can actually arise in.
async function freshDb(): Promise<Db> {
  const db = await baseDb();
  await db.run(sql`PRAGMA foreign_keys = OFF`);
  return db;
}
type DB = Awaited<ReturnType<typeof freshDb>>;

/** A full group→site→endpoint chain. Returns the ids. */
async function chain(db: DB, tag: string) {
  const g = (await db.insert(siteGroups).values({ slug: `g-${tag}`, name: `G ${tag}` }).returning())[0]!;
  const s = (await db.insert(monitoredSites).values({ siteGroupId: g.id, slug: `s-${tag}`, name: `S ${tag}` }).returning())[0]!;
  const e = (await db.insert(monitoredEndpoints).values({ siteId: s.id, url: `https://${tag}.example.com` }).returning())[0]!;
  return { groupId: g.id, siteId: s.id, endpointId: e.id };
}

const endpointIds = (db: DB) => db.select({ id: monitoredEndpoints.id }).from(monitoredEndpoints);
const siteIds = (db: DB) => db.select({ id: monitoredSites.id }).from(monitoredSites);

describe('reconcileOrphanedEndpoints (every endpoint/site must be owned by a configured site)', () => {
  it('deletes an endpoint whose owning site no longer exists, keeps the owned one', async () => {
    const db = await freshDb();
    const live = await chain(db, 'live');
    const ghost = await chain(db, 'ghost');
    // Simulate a no-FK-cascade leftover: delete the ghost SITE row directly, leaving
    // its endpoint dangling (site_id points at a now-missing site).
    await db.delete(monitoredSites).where(eq(monitoredSites.id, ghost.siteId));

    const res = await reconcileOrphanedEndpoints(db);

    expect(res.endpoints).toBe(1);
    expect(res.prunedEndpointIds).toEqual([ghost.endpointId]);
    expect((await endpointIds(db)).map((r) => r.id)).toEqual([live.endpointId]);
  });

  it('deletes a group-less ghost site and its endpoints, keeps the configured chain', async () => {
    const db = await freshDb();
    const live = await chain(db, 'live');
    const ghost = await chain(db, 'ghost');
    // Delete the ghost GROUP directly → its site is now group-less (not "configured"),
    // and the endpoint under it is not owned by a configured site.
    await db.delete(siteGroups).where(eq(siteGroups.id, ghost.groupId));

    const res = await reconcileOrphanedEndpoints(db);

    expect(res).toMatchObject({ endpoints: 1, sites: 1 });
    expect(res.prunedEndpointIds).toEqual([ghost.endpointId]);
    expect((await endpointIds(db)).map((r) => r.id)).toEqual([live.endpointId]);
    expect((await siteIds(db)).map((r) => r.id)).toEqual([live.siteId]);
  });

  it('keeps everything when the full group→site→endpoint chain is intact', async () => {
    const db = await freshDb();
    await chain(db, 'a');
    await chain(db, 'b');

    const res = await reconcileOrphanedEndpoints(db);

    expect(res).toMatchObject({ endpoints: 0, sites: 0 });
    expect(await endpointIds(db)).toHaveLength(2);
    expect(await siteIds(db)).toHaveLength(2);
  });

  it('does NOTHING when there are zero configured sites (never mass-delete an empty/transient config)', async () => {
    const db = await freshDb();
    // A dangling endpoint pointing at a site that never existed, and NO configured
    // sites at all. The guard must refuse to delete — an empty config read could be
    // transient, and wiping everything on it would be catastrophic.
    await db.insert(monitoredEndpoints).values({ siteId: 'no-such-site', url: 'https://orphan.example.com' });

    const res = await reconcileOrphanedEndpoints(db);

    expect(res).toMatchObject({ endpoints: 0, sites: 0 });
    expect(await endpointIds(db)).toHaveLength(1); // left intact, not mass-deleted
  });
});

describe('retireEndpoint (delete endpoint + atomically drop a now-empty site)', () => {
  it('deletes the endpoint and its now-empty site', async () => {
    const db = await freshDb();
    const c = await chain(db, 'a');

    const res = await retireEndpoint(db, c.endpointId);

    expect(res).toEqual({ endpointDeleted: true, siteDeleted: true });
    expect(await endpointIds(db)).toHaveLength(0);
    expect(await siteIds(db)).toHaveLength(0);
  });

  it('keeps the site when other endpoints remain (deletes only the named endpoint)', async () => {
    const db = await freshDb();
    const c = await chain(db, 'a');
    const e2 = (await db.insert(monitoredEndpoints).values({ siteId: c.siteId, url: 'https://b.example.com' }).returning())[0]!;

    const res = await retireEndpoint(db, c.endpointId);

    expect(res).toEqual({ endpointDeleted: true, siteDeleted: false });
    expect((await endpointIds(db)).map((r) => r.id)).toEqual([e2.id]);
    expect((await siteIds(db)).map((r) => r.id)).toEqual([c.siteId]);
  });

  it('no-ops for an unknown endpoint id', async () => {
    const db = await freshDb();
    const c = await chain(db, 'a');

    const res = await retireEndpoint(db, 'no-such-endpoint');

    expect(res).toEqual({ endpointDeleted: false, siteDeleted: false });
    expect(await endpointIds(db)).toHaveLength(1); // untouched
    expect((await siteIds(db)).map((r) => r.id)).toEqual([c.siteId]);
  });
});

describe('purgeEndpointHistory (why an issue closed is never left unknown)', () => {
  async function openIssue(db: DB, target: string, opened: Date) {
    await db.insert(issues).values({
      target, source: 'http', name: target, severity: 'critical', state: 'down', openedAt: opened,
    });
  }
  const issueRows = (db: DB) =>
    db.select({ target: issues.target, resolvedAt: issues.resolvedAt, resolvedReason: issues.resolvedReason })
      .from(issues);

  it("closes the purged endpoint's open issues as `unmonitored`, not as unknown", async () => {
    // NULL is documented as "resolved before this column existed — unknown, so the fold
    // claims nothing". This close knows exactly why it happened: the monitor was deleted,
    // and NOTHING was observed to recover. Both closes are silent either way, so only the
    // column's contract can catch this being wrong.
    const db = await freshDb();
    await openIssue(db, 'ep-purged', new Date(Date.now() - 3600_000));

    await purgeEndpointHistory(db, ['ep-purged']);

    expect(await issueRows(db)).toMatchObject([{ target: 'ep-purged', resolvedReason: 'unmonitored' }]);
  });

  it('leaves an ALREADY-resolved issue exactly as it closed — reason and timestamp both', async () => {
    const db = await freshDb();
    // Whole seconds: `issues.resolved_at` is a unix-second integer column, so a Date
    // carrying millis would not survive the round-trip and this test would fail for a
    // reason that has nothing to do with the rule it pins.
    const closedAt = new Date(Math.floor((Date.now() - 86_400_000) / 1000) * 1000);
    await db.insert(issues).values({
      target: 'ep-purged', source: 'http', name: 'ep-purged', severity: 'critical', state: 'down',
      openedAt: new Date(Date.now() - 2 * 86_400_000), resolvedAt: closedAt, resolvedReason: 'recovered',
    });

    await purgeEndpointHistory(db, ['ep-purged']);

    expect(await issueRows(db)).toEqual([
      { target: 'ep-purged', resolvedAt: closedAt, resolvedReason: 'recovered' },
    ]);
  });

  it('touches no other endpoint’s issues', async () => {
    const db = await freshDb();
    await openIssue(db, 'ep-purged', new Date(Date.now() - 3600_000));
    await openIssue(db, 'ep-kept', new Date(Date.now() - 3600_000));

    await purgeEndpointHistory(db, ['ep-purged']);

    const kept = (await issueRows(db)).find((r) => r.target === 'ep-kept');
    expect(kept).toMatchObject({ resolvedAt: null, resolvedReason: null });
  });
});

describe('createEndpoint (monitoring switch fields)', () => {
  it('persists monitorHttp and monitorDeploys when explicitly set to false', async () => {
    const db = await freshDb();
    const c = await chain(db, 'a');

    const ep = await createEndpoint(db, {
      siteId: c.siteId,
      url: 'https://test.example.com',
      monitorHttp: false,
      monitorDeploys: false,
    });

    expect(ep.monitorHttp).toBe(false);
    expect(ep.monitorDeploys).toBe(false);
  });

  it('defaults to true when monitorHttp and monitorDeploys are omitted', async () => {
    const db = await freshDb();
    const c = await chain(db, 'a');

    const ep = await createEndpoint(db, {
      siteId: c.siteId,
      url: 'https://test.example.com',
    });

    expect(ep.monitorHttp).toBe(true);
    expect(ep.monitorDeploys).toBe(true);
  });

  it('persists a deployProjectId it is given', async () => {
    const db = await freshDb();
    const c = await chain(db, 'a');

    const ep = await createEndpoint(db, {
      siteId: c.siteId,
      url: 'https://test.example.com',
      deployProjectId: 'prj_abc',
    });

    expect(ep.deployProjectId).toBe('prj_abc');
  });
});
