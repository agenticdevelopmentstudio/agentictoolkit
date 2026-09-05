import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { deployProjectMeta } from '../src/libsql/schema';
import { syncVercelProjectMeta, refreshVercelProjectMeta } from '../src/monitor/refresh-project-meta';
import { freshDb, type Db } from './helpers/db';

// `deploy_project_meta` is the ONLY source of "which Vercel projects exist" (the
// enumeration seeds its Vercel pairs from this table), and it used to be upsert-only —
// so a project deleted at Vercel was enumerated forever, kept being offered by Auto
// Configure, and its dead deploy target reopened an unclearable Problem. These tests pin
// the eviction AND the two cases where evicting would be wrong: a partial read, and a
// read with no token (which the fetcher reports as `{ ok: true, meta: [] }`).

const META = (projectName: string, domain: string | null = `${projectName}.example.com`) => ({
  projectName,
  domain,
  gitRepo: 'acme/repo',
  gitBranch: 'main',
  rootDirectory: null,
  framework: 'nextjs',
});

describe('syncVercelProjectMeta', () => {
  let db: Db;

  beforeEach(async () => {
    db = await freshDb();
    // Two Vercel projects and one Cloudflare row already recorded — the state a prior
    // cycle's upsert leaves behind.
    await db.insert(deployProjectMeta).values([
      { platform: 'vercel', projectName: 'live-site', domain: 'live.example.com' },
      { platform: 'vercel', projectName: 'deleted-site', domain: 'gone.example.com' },
      { platform: 'cloudflare-pages', projectName: 'worker-a', domain: 'worker.example.com' },
    ]);
  });

  const rows = async () =>
    (await db.select().from(deployProjectMeta)).map((r) => `${r.platform}|${r.projectName}`).sort();

  it('evicts a project a COMPLETE enumeration did not return, and refreshes the ones it did', async () => {
    const out = await syncVercelProjectMeta(db, {
      meta: [META('live-site', 'renamed.example.com'), META('new-site')],
      ok: true,
      configured: true,
    });

    expect(out.pruned).toEqual(['deleted-site']);
    // The reconcile also HANDS BACK what still exists, so the cycle narrows its owned
    // targets from this verdict instead of re-deriving the same predicate.
    expect([...(out.live ?? [])].sort()).toEqual(['live-site', 'new-site']);
    // The absent project is gone; the returned ones are present — and the Cloudflare row
    // is untouched (this prune is Vercel-only; CF/Railway are polled live).
    expect(await rows()).toEqual(['cloudflare-pages|worker-a', 'vercel|live-site', 'vercel|new-site']);
    const live = (await db.select().from(deployProjectMeta)).find((r) => r.projectName === 'live-site');
    expect(live?.domain).toBe('renamed.example.com');
  });

  it('upserts and prunes in CHUNKS, so a big account cannot blow the statement parameter cap', async () => {
    // 400 projects × 7 bound params is already past SQLite's old 999-bind limit in ONE
    // statement, and the prune binds one per name; both are chunked, so team size can't
    // turn this read path into a runtime failure.
    const many = Array.from({ length: 400 }, (_, i) => META(`p${i}`));
    const first = await syncVercelProjectMeta(db, { meta: many, ok: true, configured: true });
    expect(first.pruned.sort()).toEqual(['deleted-site', 'live-site']);
    expect((await db.select().from(deployProjectMeta)).filter((r) => r.platform === 'vercel')).toHaveLength(400);

    // …and now delete all 400 upstream: the eviction is chunked the same way.
    const second = await syncVercelProjectMeta(db, { meta: [], ok: true, configured: true });
    expect(second.pruned).toHaveLength(400);
    expect(await rows()).toEqual(['cloudflare-pages|worker-a']);
  });

  it('evicts NOTHING from a PARTIAL enumeration, but still records what it did get', async () => {
    // ok:false = budget-truncated or API failure: the missing projects may well exist,
    // so the upsert still lands (a real build failure must not be lost) and nothing is cut.
    const out = await syncVercelProjectMeta(db, { meta: [META('new-site')], ok: false, configured: true });

    expect(out.pruned).toEqual([]);
    // …and it says so: `live: null` means "this read proves nothing about what's gone",
    // which is what stops the cycle narrowing anything off a partial.
    expect(out.live).toBeNull();
    expect(await rows()).toEqual([
      'cloudflare-pages|worker-a',
      'vercel|deleted-site',
      'vercel|live-site',
      'vercel|new-site',
    ]);
  });

  it('evicts NOTHING when no token is configured', async () => {
    // The exact shape fetchVercelProductionStates returns with no VERCEL_API_TOKEN.
    // Without the `configured` gate this would wipe every project the moment the token
    // went missing.
    const out = await syncVercelProjectMeta(db, { meta: [], ok: true, configured: false });

    expect(out.pruned).toEqual([]);
    expect(out.live).toBeNull();
    expect(await rows()).toEqual(['cloudflare-pages|worker-a', 'vercel|deleted-site', 'vercel|live-site']);
  });

  it('evicts every Vercel project when a real account has had its LAST one deleted', async () => {
    // The case `meta.length > 0` as a prune gate would get wrong: an empty list from an
    // authenticated, complete read is the truth, not a failure.
    const out = await syncVercelProjectMeta(db, { meta: [], ok: true, configured: true });

    expect(out.pruned.sort()).toEqual(['deleted-site', 'live-site']);
    expect(await rows()).toEqual(['cloudflare-pages|worker-a']);
  });
});

describe('refreshVercelProjectMeta', () => {
  let db: Db;

  beforeEach(async () => {
    db = await freshDb();
    await db.insert(deployProjectMeta).values([
      { platform: 'vercel', projectName: 'live-site', domain: 'live.example.com' },
      { platform: 'vercel', projectName: 'deleted-site', domain: 'gone.example.com' },
    ]);
  });

  afterEach(() => vi.unstubAllGlobals());

  it('fetches, then evicts the projects the account no longer has', async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) => {
        const u = String(url);
        urls.push(u);
        if (u.includes('/v2/teams')) return Response.json({ teams: [] });
        if (u.includes('/v9/projects'))
          return Response.json({
            projects: [
              {
                name: 'live-site',
                targets: {
                  production: { id: 'dpl_1', createdAt: 1_700_000_000_000, readyState: 'READY', target: 'production', alias: ['live.example.com'] },
                },
                latestDeployments: [
                  { id: 'dpl_1', createdAt: 1_700_000_000_000, readyState: 'READY', target: 'production', url: 'live.vercel.app' },
                ],
              },
            ],
            pagination: { next: null },
          });
        return Response.json({});
      }),
    );

    const out = await refreshVercelProjectMeta(db, { VERCEL_API_TOKEN: 'tok' });

    expect(out).toEqual({ ok: true, configured: true, pruned: ['deleted-site'] });
    expect((await db.select().from(deployProjectMeta)).map((r) => r.projectName)).toEqual(['live-site']);
    // This read exists ONLY to learn which projects still exist, so it asks for the shallowest
    // deployment window the API allows — a read path on the request thread must not drag the
    // monitor's whole 10-deep history behind it.
    const projectList = urls.find((u) => u.includes('/v9/projects'));
    expect(projectList).toContain('latestDeployments=1');
  });

  it('reports ok:false and touches nothing when no token is configured', async () => {
    // Fail-closed: with no token there is nothing to verify against, so callers must not
    // treat the (stale) table as truth. Asserted via a fetch that would throw if called.
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('must not call Vercel without a token'); }));

    const out = await refreshVercelProjectMeta(db, {});

    // `configured:false` is what tells callers "no verdict", as distinct from a configured
    // read that failed — the Auto Configure banner only warns about the latter.
    expect(out).toEqual({ ok: false, configured: false, pruned: [] });
    expect((await db.select().from(deployProjectMeta)).length).toBe(2);
  });
});
