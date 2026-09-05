import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchVercelProductionStates, __resetTeamSlugCache } from '../src/monitor/fetch-vercel-projects';
import { _resetProviderCooldowns } from '@agentic-toolkit/deploy-platform/cooldown';

// The overall-budget / partial-return behavior of the projects poll — the same
// contract the Railway and Cloudflare fetchers already carry: a poll that can't
// finish inside its own budget returns what it managed (ok:false) instead of
// running past sync's 20s `guard` and being abandoned un-aborted (which left the
// fetch chain churning in the background and the board blind to Vercel).

afterEach(() => {
  vi.unstubAllGlobals();
  // The team slug is memoized module-scope for an hour (a slug changes ~never, and the
  // cache is what lets the budget rules below be strict without dropping every dashboard
  // link). Drop it between cases so each one exercises the cold path it was written for.
  __resetTeamSlugCache();
  // The 429 case below records a REAL cooldown in a module-scope registry that outlives
  // the test. `fetchVercelProductionStates` opens by bailing out on it, so without this
  // every later case in this file would return empty before issuing a single request —
  // passing vacuously wherever it asserts a failure, and failing outright wherever it
  // asserts a fetch.
  _resetProviderCooldowns();
});

/** One project fixture whose production target is READY and carries a custom-domain
 *  alias (so the domains API is never consulted). */
function project(name: string): unknown {
  return {
    name,
    targets: {
      production: {
        id: `dpl_${name}`,
        createdAt: 1_700_000_000_000,
        readyState: 'READY',
        target: 'production',
        alias: [`${name}.example.com`],
      },
    },
    latestDeployments: [
      { id: `dpl_${name}`, createdAt: 1_700_000_000_000, readyState: 'READY', target: 'production', url: `${name}.vercel.app` },
    ],
  };
}

/** Mock fetch routed by URL: team slug, then one handler per /v9/projects page. */
function routeFetch(pages: Array<() => unknown | Promise<unknown>>): typeof fetch {
  let page = 0;
  return vi.fn(async (url: string | URL) => {
    const u = String(url);
    if (u.includes('/v2/teams')) return Response.json({ teams: [{ id: 't1', slug: 'acme' }] });
    if (u.includes('/v9/projects')) {
      const body = await pages[Math.min(page++, pages.length - 1)]!();
      return Response.json(body);
    }
    return Response.json({});
  }) as unknown as typeof fetch;
}

describe('fetchVercelProductionStates — overall budget', () => {
  it('still enumerates a complete ok:true snapshot when the poll fits the budget', async () => {
    vi.stubGlobal(
      'fetch',
      routeFetch([() => ({ projects: [project('site-a'), project('site-b')], pagination: { next: null } })]),
    );
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok' });
    expect(out.ok).toBe(true);
    expect(out.states.map((s) => s.projectName)).toEqual(['site-a', 'site-b']);
    expect(out.meta.map((m) => m.projectName)).toEqual(['site-a', 'site-b']);
    expect(out.deploys).toHaveLength(2);
  });

  it('returns a PARTIAL (ok:false) instead of paginating past its budget', async () => {
    // Serial pagination over a large team was unbounded work: it blew sync's 20s guard
    // every cycle, and `guard()` only stops awaiting a poll — it never cancels it, so the
    // abandoned enumeration kept running behind the next cycle. Self-bound like the
    // Railway/Cloudflare fetchers: stop at the deadline, hand back what we have.
    vi.stubGlobal(
      'fetch',
      routeFetch([() => ({ projects: [project('never-reached')], pagination: { next: Date.now() } })]),
    );
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', overallBudgetMs: 0 });
    expect(out.ok).toBe(false); // partial → caller upserts it but skips the prune
    // The page loop never starts a request past the deadline — no project data at all.
    expect(out.states).toEqual([]);
    expect(out.meta).toEqual([]);
    expect(out.deploys).toEqual([]);
  });

  it('keeps the pages already fetched when a later page stalls (partial, ok:false)', async () => {
    vi.stubGlobal(
      'fetch',
      routeFetch([
        () => ({ projects: [project('site-a'), project('site-b')], pagination: { next: 123 } }),
        () => {
          // Page 2 aborts (what AbortSignal.timeout produces on a stalled API).
          throw new DOMException('The operation was aborted due to timeout', 'TimeoutError');
        },
      ]),
    );
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok' });
    expect(out.ok).toBe(false); // partial — caller upserts these but skips prune/mass-resolve
    expect(out.states.map((s) => s.projectName)).toEqual(['site-a', 'site-b']);
    expect(out.deploys).toHaveLength(2);
  });

  it('still fails the whole poll on a definitive API error (HTTP status, not a stall)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) =>
        String(url).includes('/v9/projects') ? new Response('nope', { status: 403 }) : Response.json({ teams: [] }),
      ) as unknown as typeof fetch,
    );
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok' });
    expect(out).toEqual({ ok: false, states: [], meta: [], deploys: [] });
  });

  it('puts a timeout on every request (an untimed fetch can hang the whole poll)', async () => {
    const seen: Array<RequestInit | undefined> = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL, init?: RequestInit) => {
        seen.push(init);
        if (String(url).includes('/v2/teams')) return Response.json({ teams: [{ id: 't1', slug: 'adh' }] });
        return Response.json({ projects: [], pagination: { next: null } });
      }) as unknown as typeof fetch,
    );

    await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok' });

    expect(seen.length).toBeGreaterThan(0);
    for (const init of seen) expect(init?.signal).toBeInstanceOf(AbortSignal);
  });
});

describe('fetchVercelProductionStates — the team slug never starves the enumeration', () => {
  /** Route fetch, recording every URL, with a configurable delay on the team lookup.
   *  The delay HONOURS `init.signal` — a mock that ignored it would answer a request the
   *  real `fetch` would have aborted, and the abort is exactly what's under test. */
  function routeWithSlowTeams(delayMs: number, seen: string[]): typeof fetch {
    return vi.fn(async (url: string | URL, init?: RequestInit) => {
      const u = String(url);
      seen.push(u);
      if (u.includes('/v2/teams')) {
        await new Promise((resolve, reject) => {
          const t = setTimeout(resolve, delayMs);
          init?.signal?.addEventListener('abort', () => {
            clearTimeout(t);
            reject(new DOMException('The operation was aborted due to timeout', 'TimeoutError'));
          });
        });
        return Response.json({ slug: 'acme', teams: [{ id: 't1', slug: 'acme' }] });
      }
      if (u.includes('/v9/projects')) return Response.json({ projects: [project('site-a')], pagination: { next: null } });
      return Response.json({});
    }) as unknown as typeof fetch;
  }

  it('enumerates the projects even when the team lookup burns the whole budget', async () => {
    // PROD, 2026-07-26: `Vercel team lookup /v2/teams/team_… failed: aborted due to timeout`.
    // The slug is COSMETIC (it only builds a dashboard link), but it was resolved BEFORE the
    // page walk and off the same deadline — so two 6s timeouts could eat 12s of the 18s
    // budget and leave the enumeration truncated. A truncated enumeration is `ok:false`,
    // which makes the caller SKIP the prune and skip narrowing the owned set — i.e. a Vercel
    // project deleted upstream keeps its unclearable Problem. The link must never outrank
    // the data.
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(60, seen));
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1', overallBudgetMs: 50 });
    expect(out.ok).toBe(true);
    expect(out.meta.map((m) => m.projectName)).toEqual(['site-a']);
    expect(out.states.map((s) => s.projectName)).toEqual(['site-a']);
    // Budget spent on the data; the cosmetic link is what degrades.
    expect(out.states[0]!.sourceUrl).toBeNull();
  });

  it('does not look up the team slug at all on a metaOnly read', async () => {
    // metaOnly returns before the states loop, which is the slug's ONLY consumer — so paying
    // up to two 6s timeouts for it is pure waste on the read path that backs the board's
    // Auto Configure / missing-project surfaces.
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(0, seen));
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1', metaOnly: true });
    expect(out.ok).toBe(true);
    expect(out.meta.map((m) => m.projectName)).toEqual(['site-a']);
    expect(seen.some((u) => u.includes('/v2/teams'))).toBe(false);
  });

  it('still resolves the slug when the budget allows it', async () => {
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(0, seen));
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1' });
    expect(out.states[0]!.sourceUrl).toBe('https://vercel.com/acme/site-a/site-a');
  });

  it('does not starve the BLIND-PROJECT backfill either — the slug is resolved after it', async () => {
    // The same "link outranks the data" bug, one step further down. A project whose whole
    // poll window is Ignored-Build-Step skips has NO verdict in this snapshot; the backfill
    // reads it directly, and it is guarded by `Date.now() < deadline`. With the slug resolved
    // FIRST, a slow team lookup consumed that budget and silently dropped the project's only
    // chance at a verdict — its issue could then neither open nor resolve.
    const seen: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL, init?: RequestInit) => {
        const u = String(url);
        seen.push(u);
        if (u.includes('/v2/teams')) {
          await new Promise((resolve, reject) => {
            const t = setTimeout(resolve, 500);
            init?.signal?.addEventListener('abort', () => {
              clearTimeout(t);
              reject(new DOMException('The operation was aborted due to timeout', 'TimeoutError'));
            });
          });
          return Response.json({ slug: 'acme' });
        }
        if (u.includes('/v9/projects')) {
          // One project whose only deployment is CANCELED → blind, needs the backfill.
          return Response.json({
            projects: [
              {
                name: 'skipped-site',
                targets: { production: { id: 'dpl_x', createdAt: 1_700_000_000_000, readyState: 'CANCELED', target: 'production', alias: ['skipped-site.example.com'] } },
                latestDeployments: [
                  { id: 'dpl_x', createdAt: 1_700_000_000_000, readyState: 'CANCELED', target: 'production', url: 'skipped-site.vercel.app' },
                ],
              },
            ],
            pagination: { next: null },
          });
        }
        if (u.includes('/v6/deployments')) {
          return Response.json({
            deployments: [{ id: 'dpl_real', createdAt: 1_700_000_100_000, readyState: 'ERROR', target: 'production', url: 'skipped-site.vercel.app' }],
          });
        }
        return Response.json({});
      }) as unknown as typeof fetch,
    );

    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1', overallBudgetMs: 200 });

    // The verdict was read — this is the data the recorders judge.
    expect(seen.some((u) => u.includes('/v6/deployments'))).toBe(true);
    expect(out.deploys.some((d) => d.id === 'vc_dpl_real')).toBe(true);
  });

  it('never issues a slug request that cannot possibly answer in the budget left', async () => {
    // With a few ms left, AbortSignal.timeout fires before the server can reply: the call
    // is doomed, and its only observable effect is a burnt connection plus a self-inflicted
    // "aborted due to timeout" in the logs that reads like a Vercel outage. Skip it.
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(0, seen));
    await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1', overallBudgetMs: 0 });
    expect(seen.some((u) => u.includes('/v2/teams'))).toBe(false);
  });

  it('memoizes the slug, so a later budget-starved cycle keeps its dashboard links', async () => {
    // A slug changes ~never (same reasoning as fetchProjectDomainList's hour cache). Without
    // the memo, every cycle that ran out of budget dropped EVERY project's sourceUrl to null
    // — and applyVercelStaleIssues would then write that null over a perfectly good link.
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(0, seen));
    const warm = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1' });
    expect(warm.states[0]!.sourceUrl).toBe('https://vercel.com/acme/site-a/site-a');

    const seen2: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(0, seen2));
    const starved = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1', overallBudgetMs: 0 });
    // Budget zero: no team call at all, yet the link survives from the cache.
    expect(seen2.some((u) => u.includes('/v2/teams'))).toBe(false);
    expect(starved.states[0]?.sourceUrl ?? null).toBe(null); // no projects enumerated at all
    // ...and a cycle that DOES enumerate still gets the cached slug with no new lookup.
    const seen3: string[] = [];
    vi.stubGlobal('fetch', routeWithSlowTeams(0, seen3));
    const again = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', VERCEL_TEAM_ID: 't1' });
    expect(seen3.some((u) => u.includes('/v2/teams'))).toBe(false);
    expect(again.states[0]!.sourceUrl).toBe('https://vercel.com/acme/site-a/site-a');
  });
});

describe('fetchVercelProductionStates — non-ok page mid-pagination', () => {
  /** Page 1 succeeds with a next cursor; page 2 answers 429. */
  function pagedFetchWith429(): typeof fetch {
    let page = 0;
    return vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.includes('/v2/teams')) return Response.json({ teams: [{ id: 't1', slug: 'acme' }] });
      if (u.includes('/v9/projects')) {
        page++;
        if (page === 1) return Response.json({ projects: [project('site-a')], pagination: { next: 123 } });
        return new Response('rate limited', { status: 429 });
      }
      return Response.json({});
    }) as unknown as typeof fetch;
  }

  it('keeps the pages already fetched when a later page answers non-ok (partial, ok:false)', async () => {
    // A transient 429/5xx on page 2+ of a large team used to WIPE every project
    // fetched on earlier pages — the whole provider read as unreachable and the
    // stale-issue pass was skipped, from one throttled page.
    vi.stubGlobal('fetch', pagedFetchWith429());
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok' });
    expect(out.ok).toBe(false); // partial → upsert what we got, skip prune/stale pass
    expect(out.meta.map((m) => m.projectName)).toEqual(['site-a']);
    expect(out.states.map((s) => s.projectName)).toEqual(['site-a']);
    expect(out.deploys).toHaveLength(1);
  });

  it('reports a definitive empty failure when the FIRST page answers non-ok', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) => {
        const u = String(url);
        if (u.includes('/v2/teams')) return Response.json({ teams: [] });
        return new Response('server error', { status: 500 });
      }) as unknown as typeof fetch,
    );
    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok' });
    expect(out).toMatchObject({ ok: false, states: [], meta: [], deploys: [] });
  });
});

describe('fetchVercelProductionStates — one retry per page', () => {
  /** Route fetch so the first `stalls` /v9/projects requests hang until their own signal
   *  aborts, and every later one answers. The mock HONOURS the signal — one that resolved
   *  anyway would answer a request the real fetch had already abandoned. */
  function routeStallingPages(stalls: number, seen: string[]): typeof fetch {
    let used = 0;
    return vi.fn(async (url: string | URL, init?: RequestInit) => {
      const u = String(url);
      if (u.includes('/v2/teams')) return Response.json({ teams: [{ id: 't1', slug: 'acme' }] });
      seen.push(u);
      if (used++ < stalls) {
        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () =>
            reject(new DOMException('The operation was aborted due to timeout', 'TimeoutError')),
          );
        });
      }
      return Response.json({ projects: [project('site-a')], pagination: { next: null } });
    }) as unknown as typeof fetch;
  }

  it('retries a page that lost to the box and reports a CLEAN read', async () => {
    // Page 0 carries a ~4MB body on a connection that is always cold (the deploy poll runs
    // every 5 minutes, far past any keep-alive), so it is the page that crosses the box —
    // prod logged this ~65 times a day. The retry runs on the connection the first attempt
    // just opened, i.e. the warm case. `ok` is the point: a partial makes the caller skip
    // the prune, so one slow page left deleted Vercel projects with unclearable Problems.
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeStallingPages(1, seen));

    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', callTimeoutMs: 20, overallBudgetMs: 2_000 });

    expect(seen).toHaveLength(2);
    expect(out.ok).toBe(true);
    expect(out.meta.map((m) => m.projectName)).toEqual(['site-a']);
  });

  it('stops at the second attempt and hands back a partial', async () => {
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeStallingPages(99, seen));

    const out = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 'tok', callTimeoutMs: 20, overallBudgetMs: 2_000 });

    expect(seen).toHaveLength(2);
    expect(out.ok).toBe(false);
    expect(out.meta).toEqual([]);
  });
});
