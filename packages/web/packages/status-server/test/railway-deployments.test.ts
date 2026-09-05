import { describe, it, expect, vi, afterEach } from 'vitest';
import { listRailwayProjects } from '@agentic-toolkit/deploy-platform/providers';
import { fetchRailwayDeployments } from '../src/monitor/fetch-railway';

afterEach(() => vi.unstubAllGlobals());

const signal = new AbortController().signal;

/** Route a mocked fetch by the GraphQL operation in the request body. The enumeration
 *  uses the ROOT `projects` query (workspace tokens can't use `me { projects }`); the
 *  per-project fetches use `environments(...)` / `deployments(...)`. */
function routeFetch(handlers: {
  projects?: () => unknown;
  environments?: () => unknown;
  deployments?: () => unknown;
}): typeof fetch {
  return vi.fn(async (_url: string | URL, init?: RequestInit) => {
    const query = String(JSON.parse(String(init?.body ?? '{}')).query ?? '');
    if (query.includes('environments(')) return Response.json(handlers.environments?.() ?? { data: { environments: { edges: [] } } });
    if (query.includes('deployments(')) return Response.json(handlers.deployments?.() ?? { data: { deployments: { edges: [] } } });
    if (query.includes('projects')) return Response.json(handlers.projects?.() ?? { data: { projects: { edges: [] } } });
    return Response.json({ data: {} });
  }) as unknown as typeof fetch;
}

const projectsBody = (...names: string[]): unknown => ({
  data: { projects: { edges: names.map((name, i) => ({ node: { id: `p${i}`, name } })) } },
});

describe('listRailwayProjects', () => {
  it('enumerates via the root projects query (NOT me{projects})', async () => {
    const fetchMock = routeFetch({ projects: () => projectsBody('adh-backend', 'cookbook-backend') });
    vi.stubGlobal('fetch', fetchMock);
    expect(await listRailwayProjects('tok', signal)).toEqual([
      { id: 'p0', name: 'adh-backend' },
      { id: 'p1', name: 'cookbook-backend' },
    ]);
    // Guard against regressing to the `me`-scoped query, which Railway no longer
    // authorizes for workspace tokens.
    const sentQuery = String(JSON.parse(String((fetchMock as unknown as ReturnType<typeof vi.fn>).mock.calls[0][1].body)).query);
    expect(sentQuery).not.toContain('me {');
    expect(sentQuery).toContain('projects {');
  });

  it('returns null when the token cannot enumerate (Not Authorized)', async () => {
    vi.stubGlobal('fetch', routeFetch({ projects: () => ({ errors: [{ message: 'Not Authorized' }] }) }));
    expect(await listRailwayProjects('tok', signal)).toBeNull();
  });

  it('returns [] when enumeration succeeds with zero projects (NOT null)', async () => {
    vi.stubGlobal('fetch', routeFetch({ projects: () => ({ data: { projects: { edges: [] } } }) }));
    expect(await listRailwayProjects('tok', signal)).toEqual([]);
  });
});

describe('fetchRailwayDeployments', () => {
  it('is a no-op (ok) when no token is configured', async () => {
    const out = await fetchRailwayDeployments({});
    expect(out).toEqual({ ok: true, deploys: [] });
  });

  it('reports ok:false when the token cannot enumerate AND no projects are configured', async () => {
    // A revoked/invalid or project-scoped token → "Not Authorized", and no fallback list:
    // we hold a token yet can see nothing. This must surface (so a platform-health issue
    // fires), NOT be silently ok with zero deploys.
    vi.stubGlobal('fetch', routeFetch({ projects: () => ({ errors: [{ message: 'Not Authorized' }] }) }));
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'unauthorized' });
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });

  it('reports ok:true when an authorized token genuinely has zero projects', async () => {
    vi.stubGlobal('fetch', routeFetch({ projects: () => ({ data: { projects: { edges: [] } } }) }));
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
    expect(out).toEqual({ ok: true, deploys: [] });
  });

  it('enumerates projects then fetches their deployments', async () => {
    vi.stubGlobal(
      'fetch',
      routeFetch({
        projects: () => projectsBody('adh-backend'),
        environments: () => ({ data: { environments: { edges: [{ node: { id: 'e1', name: 'production' } }] } } }),
        deployments: () => ({
          data: {
            deployments: {
              edges: [
                {
                  node: {
                    id: 'd1',
                    status: 'SUCCESS',
                    createdAt: '2026-06-26T00:00:00.000Z',
                    staticUrl: null,
                    meta: { branch: 'main', commitHash: 'abcdef123456' },
                    environmentId: 'e1',
                    serviceId: 's1',
                  },
                },
              ],
            },
          },
        }),
      }),
    );
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
    expect(out.ok).toBe(true);
    expect(out.deploys).toHaveLength(1);
    expect(out.deploys[0]).toMatchObject({ platform: 'railway', projectName: 'adh-backend', environment: 'production' });
  });

  it('falls back to the configured projects list when enumeration returns null', async () => {
    vi.stubGlobal(
      'fetch',
      routeFetch({
        projects: () => ({ errors: [{ message: 'Not Authorized' }] }),
        environments: () => ({ data: { environments: { edges: [{ node: { id: 'e1', name: 'production' } }] } } }),
        deployments: () => ({
          data: {
            deployments: {
              edges: [
                {
                  node: {
                    id: 'd1',
                    status: 'SUCCESS',
                    createdAt: '2026-06-26T00:00:00.000Z',
                    staticUrl: null,
                    meta: null,
                    environmentId: 'e1',
                    serviceId: 's1',
                  },
                },
              ],
            },
          },
        }),
      }),
    );
    const out = await fetchRailwayDeployments({
      RAILWAY_API_TOKEN: 'tok',
      projects: [{ id: 'p1', name: 'adh-backend' }],
    });
    expect(out.ok).toBe(true);
    expect(out.deploys).toHaveLength(1);
    expect(out.deploys[0]).toMatchObject({ platform: 'railway', projectName: 'adh-backend', environment: 'production' });
  });

  it('returns a partial (ok:false) instead of discarding the whole poll when the overall budget is spent', async () => {
    // A large/slow Railway account can push the poll past sync's 20s `guard`, which would
    // discard it as "unreachable" — zero deploys, so a build FAILURE never lands on the
    // board. Instead the fetcher stops at its own budget and returns what it managed to
    // fetch, marked not-fully-ok (so it upserts partial + skips prune, never silently
    // "all clear"). Budget 0 → every project skipped, but it degrades gracefully, no throw.
    vi.stubGlobal(
      'fetch',
      routeFetch({
        projects: () => projectsBody('adh-backend', 'cookbook-backend', 'olylo-backend'),
        environments: () => ({ data: { environments: { edges: [{ node: { id: 'e1', name: 'production' } }] } } }),
        deployments: () => ({ data: { deployments: { edges: [] } } }),
      }),
    );
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace', overallBudgetMs: 0 });
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });
});

describe('fetchRailwayDeployments — the environment map is load-bearing, not decoration', () => {
  // Railway is the ONLY platform whose board target carries an environment segment
  // (`railway|<project>|<env>`). A row whose environment is the raw environmentId UUID
  // therefore mints a target no roster entry can match in either index, `ownedDeployTarget`
  // returns null, and the deploy is invisible to Problems AND Activity — so a Railway build
  // that failed during an env-map outage produced no problem at all while the board went on
  // showing the last-known state as current. An absence of data must never render as health.
  const deployNode = (over: Record<string, unknown> = {}) => ({
    node: {
      id: 'd1', status: 'FAILED', createdAt: '2026-06-26T00:00:00.000Z', staticUrl: null,
      meta: null, environmentId: 'e1', serviceId: 's1', ...over,
    },
  });
  const oneFailedDeploy = () => ({ data: { deployments: { edges: [deployNode()] } } });

  it('reports ok:false and writes NOTHING when the env query returns GraphQL errors', async () => {
    vi.stubGlobal('fetch', routeFetch({
      projects: () => projectsBody('adh-backend'),
      environments: () => ({ errors: [{ message: 'Problem processing request' }] }),
      deployments: oneFailedDeploy,
    }));
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });

  it('reports ok:false and writes NOTHING when the env query returns a non-200', async () => {
    vi.stubGlobal('fetch', vi.fn(async (_url: string | URL, init?: RequestInit) => {
      const query = String(JSON.parse(String(init?.body ?? '{}')).query ?? '');
      if (query.includes('environments(')) return new Response('upstream boom', { status: 502 });
      if (query.includes('deployments(')) return Response.json(oneFailedDeploy());
      return Response.json(projectsBody('adh-backend'));
    }) as unknown as typeof fetch);
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });

  it('never emits a row whose environment is a raw id — the unresolvable one is dropped, its sibling kept', async () => {
    vi.stubGlobal('fetch', routeFetch({
      projects: () => projectsBody('adh-backend'),
      environments: () => ({ data: { environments: { edges: [{ node: { id: 'e1', name: 'production' } }] } } }),
      deployments: () => ({ data: { deployments: { edges: [
        deployNode({ id: 'd-orphan', environmentId: 'e-deleted-last-year' }),
        deployNode({ id: 'd-live', environmentId: 'e1' }),
      ] } } }),
    }));
    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
    // The map came from Railway itself, so an id missing from it names an environment
    // Railway no longer has. Keeping it as a UUID mints an unmatchable target; blanking it
    // to "" would collide with an environment-less roster entry and hand the orphan deploy
    // to the wrong site. Not-vacuous: the live sibling still lands.
    expect(out.deploys.map((d) => d.id)).toEqual(['ry_d-live']);
    expect(out.deploys[0]).toMatchObject({ environment: 'production' });
  });

  // The drop above is only sound if the map is COMPLETE. An unpinned connection field takes
  // whatever page size Railway defaults to, so a project past it would lose every deploy in
  // the unlisted environments one row at a time: the stored verdict stays `success`, the
  // FAILED row never lands, and no Problem is derived from what is actually missing data.
  it('pins an explicit page size on the environments query — the completeness premise', async () => {
    const fetchMock = routeFetch({
      projects: () => projectsBody('adh-backend'),
      environments: () => ({ data: { environments: { edges: [{ node: { id: 'e1', name: 'production' } }] } } }),
    });
    vi.stubGlobal('fetch', fetchMock);
    await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
    const calls = (fetchMock as unknown as ReturnType<typeof vi.fn>).mock.calls;
    const envCall = calls.find((c) => String(JSON.parse(String(c[1].body)).query).includes('environments('));
    const sent = JSON.parse(String(envCall![1].body)) as { query: string; variables?: { first?: number } };
    expect(sent.query).toMatch(/environments\([^)]*first:/);
    expect(sent.variables?.first).toBeGreaterThanOrEqual(100);
  });

  it('logs when the environments page comes back FULL — a possible truncation is never silent', async () => {
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      // 200 = the pinned page size. A full page is indistinguishable from a truncated one
      // here, and the per-row drop below would read it as "these environments were deleted".
      const edges = Array.from({ length: 200 }, (_v, i) => ({ node: { id: `e${i}`, name: `env-${i}` } }));
      vi.stubGlobal('fetch', routeFetch({
        projects: () => projectsBody('adh-backend'),
        environments: () => ({ data: { environments: { edges } } }),
        deployments: () => ({ data: { deployments: { edges: [deployNode({ id: 'd1', environmentId: 'e0' }) ] } } }),
      }));
      const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' });
      // Still a normal poll: the project is reachable and answering, so it must NOT be
      // routed to the platform-unreachable debounce — that would report the wrong outage.
      expect(out.ok).toBe(true);
      expect(out.deploys.map((d) => d.id)).toEqual(['ry_d1']);
      expect(err.mock.calls.some((c) => /FULL page/.test(String(c[0])))).toBe(true);
    } finally {
      err.mockRestore();
    }
  });

  it('an authorized project with genuinely ZERO environments is still ok — [] is not a failure', async () => {
    vi.stubGlobal('fetch', routeFetch({
      projects: () => projectsBody('adh-backend'),
      environments: () => ({ data: { environments: { edges: [] } } }),
      deployments: () => ({ data: { deployments: { edges: [] } } }),
    }));
    expect(await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'workspace' })).toEqual({ ok: true, deploys: [] });
  });
});

describe('fetchRailwayDeployments — budget covers the LISTING call', () => {
  it('spends the listing time against the overall budget (no per-project fetches once spent)', async () => {
    // The deadline used to be computed AFTER the (up to 6s) project listing, so
    // worst case ran ~6s listing + 18s budget + a last in-flight wave — past the
    // 20s sync guard, which then discarded the whole (mostly successful) poll.
    const fetchMock = vi.fn(async (_url: string | URL, init?: RequestInit) => {
      const query = String(JSON.parse(String(init?.body ?? '{}')).query ?? '');
      if (query.includes('projects')) {
        await new Promise((r) => setTimeout(r, 250)); // listing alone eats the whole budget
        return Response.json(projectsBody('adh-backend'));
      }
      return Response.json({ data: {} });
    });
    vi.stubGlobal('fetch', fetchMock);

    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok', overallBudgetMs: 150 });

    expect(out.ok).toBe(false); // partial/degraded — never a clean read
    expect(out.deploys).toEqual([]);
    const queries = fetchMock.mock.calls.map((c) => String(JSON.parse(String((c[1] as RequestInit).body)).query ?? ''));
    expect(queries.some((q) => q.includes('deployments('))).toBe(false);
  });
});

describe('fetchRailwayDeployments — one retry for OUR OWN time box', () => {
  /** A fetch whose first `stalls[op]` calls for an operation hang until the caller's own
   *  signal aborts. Honouring the signal is the whole point: a mock that resolved anyway
   *  would answer a request the real fetch would have aborted, and the abort is what is
   *  under test. */
  function routeStalling(stalls: { environments?: number; projects?: number }, seen: string[]): typeof fetch {
    const used: Record<string, number> = { environments: 0, projects: 0 };
    return vi.fn(async (_url: string | URL, init?: RequestInit) => {
      const query = String(JSON.parse(String(init?.body ?? '{}')).query ?? '');
      const op = query.includes('environments(') ? 'environments' : query.includes('deployments(') ? 'deployments' : 'projects';
      seen.push(op);
      if (op !== 'deployments' && used[op]!++ < (stalls[op as 'environments' | 'projects'] ?? 0)) {
        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () =>
            reject(new DOMException('This operation was aborted', 'AbortError')),
          );
        });
      }
      if (op === 'projects') return Response.json(projectsBody('adh-backend'));
      if (op === 'environments') {
        return Response.json({ data: { environments: { edges: [{ node: { id: 'e0', name: 'production' } }] } } });
      }
      return Response.json({
        data: {
          deployments: {
            edges: [{ node: { id: 'd0', status: 'SUCCESS', createdAt: new Date().toISOString(), environmentId: 'e0' } }],
          },
        },
      });
    }) as unknown as typeof fetch;
  }

  it('retries a project whose first call lost to the box, and reports a CLEAN poll', async () => {
    // The tail is independent per request, so the second attempt lands in the median. What
    // makes this worth a test is the VERDICT, not the row count: before the retry a single
    // transient abort made the whole poll ok:false, and the caller then SKIPS the prune —
    // so a Railway project deleted upstream kept an unclearable Problem because one call
    // happened to run slow.
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeStalling({ environments: 1 }, seen));

    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok', callTimeoutMs: 20, overallBudgetMs: 2_000 });

    expect(out.ok).toBe(true);
    expect(out.deploys.map((d) => d.id)).toEqual(['ry_d0']);
    expect(seen.filter((op) => op === 'environments')).toHaveLength(2);
  });

  it('gives up after the second attempt rather than retrying forever', async () => {
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeStalling({ environments: 99 }, seen));

    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok', callTimeoutMs: 20, overallBudgetMs: 2_000 });

    // Two attempts, then the project is reported as the provider failing us — which routes
    // to the existing platform-unreachable debounce instead of rendering the project as
    // legitimately deploy-less.
    expect(seen.filter((op) => op === 'environments')).toHaveLength(2);
    expect(out.ok).toBe(false);
    expect(out.deploys).toEqual([]);
  });

  it('does NOT retry an answer, only a timeout', async () => {
    // Railway answering "Not Authorized" is a real verdict. Repeating it just burns budget,
    // and that budget is shared with every other project in the poll.
    const seen: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (_url: string | URL, init?: RequestInit) => {
        const query = String(JSON.parse(String(init?.body ?? '{}')).query ?? '');
        if (query.includes('environments(')) {
          seen.push('environments');
          return Response.json({ errors: [{ message: 'Not Authorized' }] });
        }
        seen.push('projects');
        return Response.json(projectsBody('adh-backend'));
      }) as unknown as typeof fetch,
    );

    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok', callTimeoutMs: 20, overallBudgetMs: 2_000 });

    expect(seen.filter((op) => op === 'environments')).toHaveLength(1);
    expect(out.ok).toBe(false);
  });

  it('retries the LISTING too — the coldest call, and the one whose loss costs a cycle', async () => {
    const seen: string[] = [];
    vi.stubGlobal('fetch', routeStalling({ projects: 1 }, seen));

    const out = await fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok', callTimeoutMs: 20, overallBudgetMs: 2_000 });

    expect(seen.filter((op) => op === 'projects')).toHaveLength(2);
    expect(out.ok).toBe(true);
    expect(out.deploys.map((d) => d.id)).toEqual(['ry_d0']);
  });
});
