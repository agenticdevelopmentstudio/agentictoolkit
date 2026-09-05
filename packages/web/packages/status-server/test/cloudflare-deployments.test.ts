import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchCloudflareDeployments } from '../src/monitor/fetch-cloudflare';

afterEach(() => vi.unstubAllGlobals());

/** Route a mocked Cloudflare REST fetch by URL: the account script LISTING
 *  (`/workers/scripts`) vs a per-script DEPLOYMENTS fetch
 *  (`/workers/scripts/<id>/deployments`). */
function routeFetch(handlers: {
  scripts?: () => unknown;
  deployments?: (script: string) => { status?: number; body: unknown };
}): typeof fetch {
  return vi.fn(async (url: string | URL) => {
    const u = String(url);
    const depl = u.match(/\/workers\/scripts\/([^/]+)\/deployments/);
    if (depl) {
      const r = handlers.deployments?.(depl[1]!) ?? { body: { success: true, result: { deployments: [] } } };
      return Response.json(r.body, { status: r.status ?? 200 });
    }
    if (u.endsWith('/workers/scripts')) return Response.json(handlers.scripts?.() ?? { success: true, result: [] });
    return Response.json({ success: true, result: [] });
  }) as unknown as typeof fetch;
}

const scriptsBody = (...ids: string[]): unknown => ({ success: true, result: ids.map((id) => ({ id })) });
const oneDeployment = (): { body: unknown } => ({
  body: {
    success: true,
    result: {
      deployments: [
        { id: 'd1', created_on: '2026-06-26T00:00:00.000Z', metadata: { commit_hash: 'abcdef123456', branch: 'main' } },
      ],
    },
  },
});

describe('fetchCloudflareDeployments', () => {
  it('is a no-op (ok) when the token or account id is not configured', async () => {
    expect(await fetchCloudflareDeployments({})).toEqual({ ok: true, deploys: [] });
    expect(await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't' })).toEqual({ ok: true, deploys: [] });
  });

  it('lists the account workers then fetches each one’s deployments', async () => {
    vi.stubGlobal('fetch', routeFetch({ scripts: () => scriptsBody('web'), deployments: oneDeployment }));
    const out = await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' });
    expect(out.ok).toBe(true);
    expect(out.deploys).toHaveLength(1);
    expect(out.deploys[0]).toMatchObject({ platform: 'cloudflare-pages', projectName: 'web', environment: 'production' });
  });

  it('marks the poll not-ok when a script fetch errors, but keeps the others’ deploys', async () => {
    // A single failing worker must surface (ok:false → platform-health issue) without
    // discarding the deploys we DID fetch from the healthy workers.
    vi.stubGlobal(
      'fetch',
      routeFetch({
        scripts: () => scriptsBody('web', 'broken'),
        deployments: (s) => (s === 'broken' ? { status: 500, body: { success: false } } : oneDeployment()),
      }),
    );
    const out = await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' });
    expect(out.ok).toBe(false);
    expect(out.deploys).toHaveLength(1); // 'web' still landed
  });

  it('returns a partial (ok:false) instead of discarding the whole poll when the overall budget is spent', async () => {
    // A large account (many Worker scripts) polled SERIALLY can push the loop past sync's
    // 20s `guard`, which would discard it as "unreachable" — zero deploys, so a deploy
    // never lands on the board. Instead the fetcher stops at its own budget and returns
    // what it managed to fetch, marked not-fully-ok. Budget 0 → every script skipped, but
    // it degrades gracefully (no throw), same contract as the Railway fetcher.
    vi.stubGlobal(
      'fetch',
      routeFetch({ scripts: () => scriptsBody('web', 'admin', 'landing'), deployments: oneDeployment }),
    );
    const out = await fetchCloudflareDeployments({
      CLOUDFLARE_API_TOKEN: 't',
      CLOUDFLARE_ACCOUNT_ID: 'a',
      overallBudgetMs: 0,
    });
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });
});

describe('fetchCloudflareDeployments — budget + listing contract', () => {
  it('spends the listing time against the overall budget (no per-script fetches once spent)', async () => {
    // Same off-by-a-listing bug the Railway fetcher had: the deadline was
    // computed AFTER the (up to 6s) script listing, so the real worst case ran
    // past the 20s sync guard and the whole poll was discarded.
    const fetchMock = vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.endsWith('/workers/scripts')) {
        await new Promise((r) => setTimeout(r, 250)); // listing alone eats the whole budget
        return Response.json(scriptsBody('web'));
      }
      return Response.json({ success: true, result: { deployments: [] } });
    });
    vi.stubGlobal('fetch', fetchMock);

    const out = await fetchCloudflareDeployments({
      CLOUDFLARE_API_TOKEN: 't',
      CLOUDFLARE_ACCOUNT_ID: 'a',
      overallBudgetMs: 150,
    });

    expect(out.ok).toBe(false); // partial/degraded — never a clean read
    expect(out.deploys).toEqual([]);
    expect(fetchMock.mock.calls.map((c) => String(c[0])).some((u) => u.includes('/deployments'))).toBe(false);
  });

  it('reports ok:false when the listing fails AND no fallback scripts are configured', async () => {
    // A token that cannot list workers with no configured fallback is a blind
    // spot, not a healthy empty account — it must surface as unreachable so the
    // platform-health issue fires (the Railway fetcher already holds this contract).
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('network down');
      }),
    );
    const out = await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' });
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });
});

describe('fetchCloudflareDeployments — bounded parallel enumeration', () => {
  it('fetches script deployments concurrently, not serially', async () => {
    // The per-script loop was serial (N x up-to-6s), so a many-worker account
    // chronically hit the overall budget and returned partials every cycle —
    // Railway solved the identical shape with a bounded fan-out.
    const DELAY = 120;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) => {
        const u = String(url);
        if (u.endsWith('/workers/scripts')) return Response.json(scriptsBody('w1', 'w2', 'w3'));
        await new Promise((r) => setTimeout(r, DELAY));
        return Response.json(oneDeployment().body);
      }),
    );
    const t0 = Date.now();
    const out = await fetchCloudflareDeployments({ CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' });
    const elapsed = Date.now() - t0;
    expect(out.ok).toBe(true);
    expect(out.deploys).toHaveLength(3);
    expect(elapsed).toBeLessThan(DELAY * 2.5); // serial would be >= 3 x DELAY
  });
});
