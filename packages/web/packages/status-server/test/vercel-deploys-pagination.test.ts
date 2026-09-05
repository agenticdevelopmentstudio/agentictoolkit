import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchVercelDeployments } from '../src/monitor/fetch-vercel';

// The deploys poll used to fetch ONE page — the newest 100 deployments TEAM-WIDE.
// That is not a depth problem, it is a TIME problem: a push touching a shared path
// rebuilds ~90 sites at once (135 projects exist), and a measured 225-deploy burst
// had its newest 100 spanning just 74 SECONDS. Every older deploy in that burst was
// invisible to the poll — permanently, since nothing newer ever pushes it back into
// view — so its row stayed `building` forever as far as the poll was concerned, and
// only the by-id reconcile could rescue it at 10 per 60s tick. That is ~9 minutes of
// the board asserting "building" for sites that finished long ago.

afterEach(() => vi.unstubAllGlobals());

const MIN = 60_000;

/** A deployment fixture `agoMs` old. */
function dep(uid: string, agoMs: number): unknown {
  return {
    uid,
    name: uid.split('-')[0],
    created: Date.now() - agoMs,
    state: 'READY',
    target: 'production',
  };
}

/** Stub fetch with one JSON body per successive call. */
function stubPages(pages: unknown[]) {
  const calls: string[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      calls.push(String(url));
      const body = pages[Math.min(calls.length - 1, pages.length - 1)];
      return { ok: true, status: 200, json: async () => body, headers: new Headers() };
    }),
  );
  return calls;
}

describe('vercel deploys poll — pagination', () => {
  it('pages past the first 100 so a burst is fully visible', async () => {
    // 100 recent + a second page: the exact shape of a burst larger than one page.
    const page1 = { deployments: Array.from({ length: 100 }, (_, i) => dep(`a${i}`, 60_000 + i)), pagination: { next: 123 } };
    const page2 = { deployments: Array.from({ length: 35 }, (_, i) => dep(`b${i}`, 200_000 + i)), pagination: { next: null } };
    const calls = stubPages([page1, page2]);

    const out = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });

    expect(out.ok).toBe(true);
    expect(out.deploys).toHaveLength(135); // NOT 100 — the whole burst
    expect(calls).toHaveLength(2);
    expect(calls[1]).toContain('until=123'); // paged via pagination.next, not a guessed cursor
  });

  it('stops once the lookback window is covered rather than walking all history', async () => {
    // Page 1's oldest row is already older than the 30m lookback → no second call.
    const page1 = { deployments: [dep('old', 45 * MIN), dep('new', 1 * MIN)], pagination: { next: 999 } };
    const calls = stubPages([page1, { deployments: [], pagination: { next: null } }]);

    const out = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });

    expect(out.ok).toBe(true);
    expect(calls).toHaveLength(1);
  });

  it('returns a partial with ok:false when the budget is spent mid-pagination', async () => {
    // Never satisfies the lookback and always offers another page: only the budget
    // can stop it. ok:false is the contract the projects/Railway/Cloudflare fetchers
    // carry — the caller upserts the partial but must not read absence as a verdict.
    const page = { deployments: [dep('x', 1 * MIN)], pagination: { next: 1 } };
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        await new Promise((r) => setTimeout(r, 5));
        return { ok: true, status: 200, json: async () => page, headers: new Headers() };
      }),
    );

    const out = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok', overallBudgetMs: 1 });

    expect(out.ok).toBe(false);
    expect(out.deploys.length).toBeGreaterThanOrEqual(0);
  });

  it('a FIRST-page failure is definitive (nothing fetched → unreachable)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: false, status: 500, json: async () => ({}), headers: new Headers() })));
    const out = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });
    expect(out).toEqual({ ok: false, deploys: [] });
  });

  it('a LATER-page failure keeps the pages already fetched', async () => {
    let n = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        n += 1;
        if (n === 1) {
          return {
            ok: true,
            status: 200,
            json: async () => ({ deployments: [dep('kept', 1 * MIN)], pagination: { next: 42 } }),
            headers: new Headers(),
          };
        }
        return { ok: false, status: 500, json: async () => ({}), headers: new Headers() };
      }),
    );

    const out = await fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' });

    expect(out.ok).toBe(false); // partial
    expect(out.deploys.map((d) => d.id)).toEqual(['vc_kept']); // but NOT wiped
  });
});
