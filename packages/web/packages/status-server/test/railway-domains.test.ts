import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  listRailwayProjectDomains,
  railwayProjectEnvironments,
  type RailwayServiceDomains,
} from '@agentic-toolkit/deploy-platform/providers';

afterEach(() => vi.unstubAllGlobals());

const signal = new AbortController().signal;

/** Shape one project-domains GraphQL response from (envName, customDomains, serviceDomains) rows. */
function projectDomainsBody(
  rows: { env: string; custom?: string[]; service?: string[] }[],
): unknown {
  const envIds = [...new Set(rows.map((r) => r.env))];
  return {
    data: {
      project: {
        environments: { edges: envIds.map((name) => ({ node: { id: `env-${name}`, name } })) },
        services: {
          edges: rows.map((r) => ({
            node: {
              serviceInstances: {
                edges: [
                  {
                    node: {
                      environmentId: `env-${r.env}`,
                      domains: {
                        customDomains: (r.custom ?? []).map((domain) => ({ domain })),
                        serviceDomains: (r.service ?? []).map((domain) => ({ domain })),
                      },
                    },
                  },
                ],
              },
            },
          })),
        },
      },
    },
  };
}

describe('listRailwayProjectDomains', () => {
  it('flattens services × environments into domain rows with the resolved env name', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () =>
        Response.json(
          projectDomainsBody([
            { env: 'production', custom: ['api.example.com'], service: ['svc-production.up.railway.app'] },
            { env: 'staging', custom: ['staging.api.example.com'] },
            { env: 'production', service: ['db-production.up.railway.app'] }, // a no-custom service instance
          ]),
        ),
      ),
    );
    const out = await listRailwayProjectDomains('tok', 'proj-1', signal);
    expect(out).toEqual<RailwayServiceDomains[]>([
      { environment: 'production', customDomains: ['api.example.com'], serviceDomains: ['svc-production.up.railway.app'] },
      { environment: 'staging', customDomains: ['staging.api.example.com'], serviceDomains: [] },
      { environment: 'production', customDomains: [], serviceDomains: ['db-production.up.railway.app'] },
    ]);
  });

  it('omits service instances that expose no domains at all', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => Response.json(projectDomainsBody([{ env: 'production' }]))),
    );
    expect(await listRailwayProjectDomains('tok', 'p', signal)).toEqual([]);
  });

  it('returns null on a non-2xx response (caller falls back to no-domain)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('no', { status: 403 })));
    expect(await listRailwayProjectDomains('tok', 'p', signal)).toBeNull();
  });

  it('returns null when GraphQL reports errors (e.g. unauthorized)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ errors: [{ message: 'Not Authorized' }] })));
    expect(await listRailwayProjectDomains('tok', 'p', signal)).toBeNull();
  });

  it('returns null when fetch throws', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('net'); }));
    expect(await listRailwayProjectDomains('tok', 'p', signal)).toBeNull();
  });
});

describe('railwayProjectEnvironments', () => {
  it('splits into ONE entry per environment (production-first), each with its own domains incl. provider hosts', () => {
    const services: RailwayServiceDomains[] = [
      {
        environment: 'production',
        customDomains: ['mcp.agenticdeveloperhub.com', 'api.agenticdeveloperhub.com'],
        serviceDomains: ['adh-backend-production.up.railway.app'],
      },
      {
        // Provider-only staging — the common case: no custom domain on a non-prod env.
        environment: 'staging',
        customDomains: [],
        serviceDomains: ['adh-backend-staging.up.railway.app'],
      },
      { environment: 'testing', customDomains: ['testing.api.agenticdeveloperhub.com'], serviceDomains: [] },
    ];
    expect(railwayProjectEnvironments(services)).toEqual([
      {
        environment: 'production',
        domain: 'api.agenticdeveloperhub.com', // canonical custom wins over the provider host
        // per-env full set includes the provider host, deduped + sorted.
        domains: ['adh-backend-production.up.railway.app', 'api.agenticdeveloperhub.com', 'mcp.agenticdeveloperhub.com'],
      },
      {
        environment: 'staging',
        domain: 'adh-backend-staging.up.railway.app', // provider host is the only option → representative
        domains: ['adh-backend-staging.up.railway.app'],
      },
      {
        environment: 'testing',
        domain: 'testing.api.agenticdeveloperhub.com',
        domains: ['testing.api.agenticdeveloperhub.com'],
      },
    ]);
  });

  it('drops environments with no domain at all (a Postgres/Redis env contributes no entry)', () => {
    const services: RailwayServiceDomains[] = [
      { environment: 'production', customDomains: ['api.example.com'], serviceDomains: [] },
      { environment: 'production', customDomains: [], serviceDomains: [] }, // a domain-less DB service in the same env
    ];
    // The prod env still yields one entry (its web service's domain); the empty one adds nothing.
    expect(railwayProjectEnvironments(services)).toEqual([
      { environment: 'production', domain: 'api.example.com', domains: ['api.example.com'] },
    ]);
    // A project with no domain anywhere → no entries at all.
    expect(railwayProjectEnvironments([{ environment: 'production', customDomains: [], serviceDomains: [] }])).toEqual([]);
    expect(railwayProjectEnvironments([])).toEqual([]);
  });
});
