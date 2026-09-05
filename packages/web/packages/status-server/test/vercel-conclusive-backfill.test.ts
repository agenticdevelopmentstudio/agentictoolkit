import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchVercelProductionStates } from '../src/monitor/fetch-vercel-projects';

// The last line of defence for "a skip is not a verdict".
//
// The poll asks Vercel for the 10 newest deployments per project, but EVERY commit to main
// creates a deployment on EVERY project (canceled by the Ignored Build Step for the sites it
// didn't touch). So a site left untouched for 10 straight commits has nothing but skips in
// the window, and its last real build is invisible to the poll. If the DB never recorded
// that build either — the monitor was down when it landed, which is exactly the crash-loop
// that started this — the recorders would be left with NO verdict to judge: the issue could
// neither open nor resolve, forever.
//
// So a project whose window is all skips gets its verdict read straight from the
// deployments API (`state=READY,ERROR`), which has no window to age out of.

afterEach(() => vi.unstubAllGlobals());

const skip = (n: number) => ({
  id: `dpl_skip${n}`,
  createdAt: 2_000 + n,
  readyState: 'CANCELED',
  target: 'production',
  url: `skip${n}.vercel.app`,
});

/** A project with a custom-domain alias (so the domains API is never consulted) whose whole
 *  deployment window is Ignored-Build-Step skips. */
function allSkipsProject(name: string): unknown {
  return {
    name,
    targets: { production: { ...skip(9), alias: [`${name}.example.com`] } },
    latestDeployments: Array.from({ length: 10 }, (_, i) => skip(i)),
  };
}

function routeFetch(onDeployments: () => unknown): typeof fetch {
  return vi.fn(async (url: string | URL) => {
    const u = String(url);
    if (u.includes('/v2/teams')) return Response.json({ teams: [{ id: 't1', slug: 'acme' }] });
    if (u.includes('/v9/projects')) return Response.json({ projects: [allSkipsProject('web-prod')], pagination: { next: null } });
    if (u.includes('/v6/deployments')) return Response.json(onDeployments());
    return new Response('not found', { status: 404 });
  }) as unknown as typeof fetch;
}

describe('conclusive-deploy backfill', () => {
  it('asks Vercel for a 10-deep window (the default of 2 ages out after two commits)', async () => {
    const spy = vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.includes('/v2/teams')) return Response.json({ teams: [] });
      if (u.includes('/v9/projects')) return Response.json({ projects: [], pagination: { next: null } });
      return new Response('not found', { status: 404 });
    });
    vi.stubGlobal('fetch', spy);

    await fetchVercelProductionStates({ VERCEL_API_TOKEN: 't' });

    const projectsCall = spy.mock.calls.map((c) => String(c[0])).find((u) => u.includes('/v9/projects'))!;
    expect(projectsCall).toContain('latestDeployments=10');
  });

  it('reads the verdict directly when the whole window is skips', async () => {
    vi.stubGlobal(
      'fetch',
      routeFetch(() => ({
        deployments: [
          { id: 'dpl_real', createdAt: 1_000, readyState: 'ERROR', target: 'production', url: 'real.vercel.app' },
        ],
      })),
    );

    const res = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 't' });

    // The newest skip is still supplied (the board shows it)…
    expect(res.deploys.find((d) => d.id === 'vc_dpl_skip9')?.buildPhase).toBe('canceled');
    // …and the buried verdict is recovered, so the recorders can act on it.
    const verdict = res.deploys.find((d) => d.id === 'vc_dpl_real');
    expect(verdict?.buildPhase).toBe('failed');
    expect(verdict?.projectName).toBe('web-prod');
  });

  it('does NOT call the deployments API when the window already holds a verdict', async () => {
    const spy = vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.includes('/v2/teams')) return Response.json({ teams: [] });
      if (u.includes('/v9/projects')) {
        return Response.json({
          projects: [
            {
              name: 'web-prod',
              targets: { production: { ...skip(9), alias: ['web-prod.example.com'] } },
              latestDeployments: [skip(9), { id: 'dpl_ok', createdAt: 1_000, readyState: 'READY', target: 'production' }],
            },
          ],
          pagination: { next: null },
        });
      }
      return new Response('not found', { status: 404 });
    });
    vi.stubGlobal('fetch', spy);

    await fetchVercelProductionStates({ VERCEL_API_TOKEN: 't' });

    // Zero extra calls in the normal case — the backfill is a fallback, not a per-cycle cost.
    expect(spy.mock.calls.map((c) => String(c[0])).filter((u) => u.includes('/v6/deployments'))).toHaveLength(0);
  });

  it('a failed backfill leaves the poll intact (best-effort, never fails the cycle)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL) => {
        const u = String(url);
        if (u.includes('/v2/teams')) return Response.json({ teams: [] });
        if (u.includes('/v9/projects')) return Response.json({ projects: [allSkipsProject('web-prod')], pagination: { next: null } });
        return new Response('boom', { status: 500 });
      }),
    );

    const res = await fetchVercelProductionStates({ VERCEL_API_TOKEN: 't' });

    expect(res.ok).toBe(true);
    expect(res.deploys.map((d) => d.id)).toEqual(['vc_dpl_skip9']); // the skip still lands
  });
});
