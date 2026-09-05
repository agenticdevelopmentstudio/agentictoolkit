import { vi } from 'vitest';
import { deployIntegrations } from '../../src/libsql/schema';
import type { Db } from './db';

/** Which env var the seeded integration row points `tokenEnvVar` at. Deliberately NOT
 *  `VERCEL_API_TOKEN`: a developer's real token sitting in the environment must never be
 *  what a test authenticates with. */
const TOKEN_ENV_VAR = 'STATUS_TEST_VERCEL_TOKEN';
const RAILWAY_TOKEN_ENV_VAR = 'STATUS_TEST_RAILWAY_TOKEN';

export interface FakeVercelAccount {
  /** Register a project as EXISTING in the account (what the projects API returns). */
  add(projectName: string, domain?: string | null): void;
  /** Delete a project upstream — the projects API stops returning it. */
  remove(projectName: string): void;
  /** Make the projects API fail (500 on the first page) — the fetcher's DEFINITIVE
   *  failure path, which reports `ok:false` so callers verify nothing this run. */
  setBroken(broken: boolean): void;
  /** Take a HOST off the air: HTTP probes of it answer 503. Deleting a Vercel project
   *  takes its domains with it, so "project gone but its URL still serves 200" is not a
   *  state production can reach — and a monitor still serving is explicitly protected from
   *  retirement, so a fixture that skips this quietly asserts nothing. */
  failHost(host: string): void;
  /** Register a LIVE Railway project — one returned by the root `projects` query and
   *  serving `domain` as a custom domain in its `production` environment. Only takes
   *  effect when the account was stubbed with `{ railway: true }`; without that there is
   *  no railway integration row, so the enumeration never asks Railway anything. */
  addRailway(projectName: string, domain: string): void;
}

/**
 * Stand up a fake Vercel account for an integration test: an ACTIVE `deploy_integrations`
 * row (so `providerConnFromConfig` yields a token) plus a global `fetch` stub that serves
 * the projects API from an in-memory list.
 *
 * Why tests now register projects HERE instead of inserting `deploy_project_meta` rows
 * directly: that table is no longer something a caller may write and then trust. The
 * refresh treats a Vercel row it cannot re-verify against the account as stale, so an
 * "offline" fixture proves the fail-closed path rather than the wiring one. Registering
 * the project with the account is what "this project exists" means now, and the refresh
 * populates the table from it — the same way production does.
 *
 * Undo with `vi.unstubAllGlobals()` + `vi.unstubAllEnvs()` in `afterEach`.
 */
export async function stubVercelAccount(db: Db, opts: { railway?: boolean } = {}): Promise<FakeVercelAccount> {
  await db.insert(deployIntegrations).values({
    platform: 'vercel',
    label: 'test',
    config: {},
    tokenEnvVar: TOKEN_ENV_VAR,
    isActive: true,
  });
  vi.stubEnv(TOKEN_ENV_VAR, 'test-vercel-token');

  // A SECOND live platform, opt-in. Off by default because merely having the row changes
  // what the enumeration can vouch for: a railway token that lists successfully makes
  // `railway` a VERIFIED platform, and absence from a verified platform is evidence.
  if (opts.railway) {
    await db.insert(deployIntegrations).values({
      platform: 'railway',
      label: 'test',
      config: {},
      tokenEnvVar: RAILWAY_TOKEN_ENV_VAR,
      isActive: true,
    });
    vi.stubEnv(RAILWAY_TOKEN_ENV_VAR, 'test-railway-token');
  }

  const projects = new Map<string, string | null>();
  const railwayProjects = new Map<string, string>();
  const deadHosts = new Set<string>();
  let broken = false;

  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string | URL, init?: { body?: string }) => {
      const u = String(url);
      // Railway speaks ONE GraphQL endpoint, so the two queries the enumeration makes are
      // told apart by their body: the root project listing, then one domains query per
      // project. Anything else answers empty — the enumeration only needs these two.
      if (u.startsWith('https://backboard.railway.app/graphql/v2')) {
        const { query, variables } = JSON.parse(init?.body ?? '{}') as { query?: string; variables?: { id?: string } };
        if (query?.includes('projects { edges')) {
          return Response.json({
            data: { projects: { edges: [...railwayProjects.keys()].map((name) => ({ node: { id: `proj_${name}`, name } })) } },
          });
        }
        const name = (variables?.id ?? '').replace(/^proj_/, '');
        const domain = railwayProjects.get(name);
        if (!domain) return Response.json({ data: { project: null } });
        return Response.json({
          data: {
            project: {
              environments: { edges: [{ node: { id: 'env_production', name: 'production' } }] },
              services: {
                edges: [
                  {
                    node: {
                      serviceInstances: {
                        edges: [
                          {
                            node: {
                              environmentId: 'env_production',
                              domains: { serviceDomains: [], customDomains: [{ domain }] },
                            },
                          },
                        ],
                      },
                    },
                  },
                ],
              },
            },
          },
        });
      }
      if (deadHosts.size > 0 && URL.canParse(u) && deadHosts.has(new URL(u).host)) {
        return new Response('gone', { status: 503 });
      }
      if (u.includes('/v2/teams')) return Response.json({ teams: [] });
      // The full-domain-list lookup the enumeration fans out per project. No verified
      // custom domains, so every project keeps its alias-derived domain from below.
      // (Its cache is module-scope and keyed by project NAME, so answering the same way
      // for every project is what keeps tests independent of each other.)
      if (/\/v9\/projects\/[^/?]+\/domains/.test(u)) return Response.json({ domains: [] });
      if (u.includes('/v9/projects')) {
        if (broken) return new Response('boom', { status: 500 });
        // `createdAt: now` so the project reads as freshly deployed — these fixtures are
        // about which projects EXIST, never about staleness.
        const at = Date.now();
        return Response.json({
          projects: [...projects].map(([name, domain]) => ({
            name,
            targets: {
              production: {
                id: `dpl_${name}`,
                createdAt: at,
                readyState: 'READY',
                target: 'production',
                alias: domain ? [domain] : [],
              },
            },
            latestDeployments: [
              { id: `dpl_${name}`, createdAt: at, readyState: 'READY', target: 'production', url: `${name}.vercel.app` },
            ],
          })),
          pagination: { next: null },
        });
      }
      return Response.json({});
    }),
  );

  return {
    add: (projectName, domain = `${projectName}.example.test`) => projects.set(projectName, domain),
    remove: (projectName) => projects.delete(projectName),
    setBroken: (b) => {
      broken = b;
    },
    failHost: (host) => deadHosts.add(host),
    addRailway: (projectName, domain) => railwayProjects.set(projectName, domain),
  };
}
