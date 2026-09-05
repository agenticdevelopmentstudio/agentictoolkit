import { BEARER, jsonBody, ref, errors, okJson, pathParam, queryParam, type Paths, type Schemas } from '../shared';

// ---------------------------------------------------------------------------
// The READ API (src/routes/reads.ts) — the dashboard's data plane. All sit behind
// the app-wide requireAuth seam (view tier; /snapshot also admits a peer token),
// so every op is documented with the bearer scheme + a 401. Response shapes mirror
// the DTOs in src/monitor/{types,live-types}.ts and buildDeployProjects().
// ---------------------------------------------------------------------------

const tag = 'reads';

/** A nullable primitive (OpenAPI 3.1 union form). */
const nul = (t: string) => ({ type: [t, 'null'] });

export const readsSchemas: Schemas = {
  // Canonical deep links attached to a site / project read entry (src/lib/links.ts).
  Links: {
    type: 'object',
    required: ['live', 'platform'],
    properties: {
      live: { ...nul('string'), description: 'Live production URL (absolute), or null' },
      platform: { ...nul('string'), description: 'Hosting-platform dashboard URL, or null when it cannot be built' },
    },
  },
  // ServiceStatusDTO (monitor/types.ts) + the additive, optional `links`.
  ServiceStatus: {
    type: 'object',
    required: [
      'slug', 'group', 'name', 'url', 'environment', 'platform', 'deployProject',
      'status', 'responseTimeMs', 'statusCode', 'error', 'lastCheckedAt',
    ],
    properties: {
      slug: { type: 'string' },
      group: { type: 'string' },
      name: { type: 'string' },
      url: { type: 'string' },
      environment: { type: 'string' },
      platform: nul('string'),
      deployProject: nul('string'),
      status: { type: 'string', enum: ['healthy', 'degraded', 'down', 'unknown'] },
      responseTimeMs: nul('number'),
      statusCode: nul('number'),
      error: nul('string'),
      lastCheckedAt: nul('string'),
      // Additive canonical links (GET /status only); absent on the other reads.
      links: ref('Links'),
    },
  },
  // LiveServiceDTO = ServiceStatusDTO + dnsOk + downSince (monitor/live-types.ts).
  LiveService: {
    allOf: [
      ref('ServiceStatus'),
      {
        type: 'object',
        required: ['dnsOk', 'downSince'],
        properties: { dnsOk: { type: 'boolean' }, downSince: nul('string') },
      },
    ],
  },
  // DeploymentDTO (monitor/types.ts) — the key fields; the provider mapper adds more.
  Deployment: {
    type: 'object',
    required: ['id', 'platform', 'projectName', 'providerProjectId', 'environment', 'tier', 'createdAt'],
    properties: {
      id: { type: 'string' },
      platform: { type: 'string' },
      projectName: { type: 'string' },
      // REQUIRED even though it is nullable: a board target's identity segment is
      // `providerProjectId ?? projectName`, so a consumer correlating a target to a
      // deployment must be able to read the id's ABSENCE, not just its value.
      providerProjectId: nul('string'),
      status: { type: 'string' },
      buildPhase: nul('string'),
      deployPhase: { type: 'string' },
      environment: nul('string'),
      // REQUIRED even though it is nullable, for the same reason as providerProjectId: the
      // whole point of the field is that a consumer must never fall back to `environment`
      // to badge a row, and it cannot tell "this build belongs to no tier" from "this
      // build of the API predates the field" unless the absence is on the contract.
      tier: nul('string'),
      commitHash: nul('string'),
      commitMessage: nul('string'),
      branch: nul('string'),
      commitRepo: nul('string'),
      url: nul('string'),
      errorText: nul('string'),
      liveHost: nul('string'),
      createdAt: { type: 'string' },
      phaseConfirmedAt: nul('string'),
    },
  },
  // The web's DeployProject (buildDeployProjects, routes/reads.ts) + additive links.
  DeployProject: {
    type: 'object',
    required: [
      'platform', 'projectName', 'environment', 'environments', 'latestAt', 'deployCount',
      'latestStatus', 'wired', 'ignored', 'domain', 'domains', 'gitRepo', 'gitBranch',
      'rootDirectory', 'framework',
    ],
    properties: {
      platform: { type: 'string' },
      projectName: { type: 'string' },
      environment: nul('string'),
      environments: { type: 'array', items: { type: 'string' } },
      latestAt: nul('string'),
      deployCount: { type: 'number' },
      latestStatus: nul('string'),
      wired: { type: 'boolean' },
      ignored: { type: 'boolean' },
      domain: nul('string'),
      domains: { type: 'array', items: { type: 'string' } },
      gitRepo: nul('string'),
      gitBranch: nul('string'),
      rootDirectory: nul('string'),
      framework: nul('string'),
      // Additive canonical links (GET /deploy-projects only).
      links: ref('Links'),
    },
  },
  // IntegrationCheck (monitor/types.ts) — one provider self-check row.
  IntegrationCheck: {
    type: 'object',
    required: ['id', 'label', 'configured', 'ok', 'state', 'detail'],
    properties: {
      id: { type: 'string' },
      label: { type: 'string' },
      configured: { type: 'boolean' },
      ok: { type: 'boolean' },
      state: { type: 'string' },
      detail: nul('string'),
      missingEnv: { type: 'array', items: { type: 'string' } },
      unreachable: { type: 'boolean' },
      correlated: { type: 'boolean' },
    },
  },
  // UptimeService + its per-day rows (monitor/types.ts).
  UptimeService: {
    type: 'object',
    required: ['slug', 'name', 'uptimePercent', 'totalChecks', 'daily'],
    properties: {
      slug: { type: 'string' },
      name: { type: 'string' },
      uptimePercent: { type: 'number' },
      totalChecks: { type: 'number' },
      daily: {
        type: 'array',
        items: {
          type: 'object',
          required: ['day', 'status', 'uptimePercent'],
          properties: {
            day: { type: 'string' },
            status: { type: 'string' },
            uptimePercent: { type: 'number' },
          },
        },
      },
    },
  },
};

const unconfiguredSite = {
  type: 'object',
  required: ['id', 'name'],
  properties: { id: { type: 'string' }, name: { type: 'string' } },
};

export const readsPaths: Paths = {
  '/live': {
    get: {
      tags: [tag],
      summary: 'Full live snapshot (parity contract) from the last persisted cycle',
      security: BEARER,
      responses: {
        200: okJson('LiveSnapshot', {
          type: 'object',
          required: [
            'generatedAt', 'lastCycleAt', 'probeIntervalMs', 'monitorVersion', 'services',
            'deployments', 'staleProd', 'providers', 'configDegraded', 'configReason',
          ],
          properties: {
            generatedAt: { type: 'string' },
            lastCycleAt: nul('string'),
            probeIntervalMs: { type: 'number' },
            monitorVersion: nul('string'),
            services: { type: 'array', items: ref('LiveService') },
            deployments: { type: 'array', items: ref('Deployment') },
            staleProd: {
              type: 'array',
              items: {
                type: 'object',
                required: ['projectName', 'environment', 'detail', 'sourceUrl', 'liveUrl'],
                properties: {
                  projectName: { type: 'string' },
                  environment: { type: 'string' },
                  detail: nul('string'),
                  sourceUrl: nul('string'),
                  liveUrl: nul('string'),
                },
              },
            },
            providers: {
              type: 'object',
              additionalProperties: {
                type: 'object',
                required: ['configured', 'ok'],
                properties: { configured: { type: 'boolean' }, ok: { type: 'boolean' } },
              },
            },
            configDegraded: { type: 'boolean' },
            configReason: nul('string'),
          },
        }),
        ...errors(401),
      },
    },
  },
  '/status': {
    get: {
      tags: [tag],
      summary: 'Overall rollup + per-service summary (site entries carry canonical links)',
      security: BEARER,
      responses: {
        200: okJson('StatusResponse', {
          type: 'object',
          required: ['overall', 'services', 'checkedAt'],
          properties: {
            overall: { type: 'string', enum: ['operational', 'degraded', 'major_outage', 'unknown'] },
            services: { type: 'array', items: ref('ServiceStatus') },
            checkedAt: { type: 'string' },
          },
        }),
        ...errors(401),
      },
    },
  },
  '/snapshot': {
    get: {
      tags: [tag],
      summary: 'Compact per-monitor unit the fleet consumes (also accepts a peer token)',
      security: BEARER,
      responses: {
        200: okJson('CompactSnapshot', {
          type: 'object',
          required: ['generatedAt', 'overall', 'services', 'openIssues'],
          properties: {
            generatedAt: { type: 'string' },
            overall: { type: 'string', enum: ['healthy', 'degraded', 'down'] },
            services: { type: 'array', items: ref('ServiceStatus') },
            openIssues: {
              type: 'array',
              items: {
                type: 'object',
                required: [
                  'target', 'source', 'name', 'environment', 'severity', 'state', 'detail', 'openedAt',
                  'sourceUrl', 'liveUrl', 'commitHash', 'commitMessage', 'commitRepo',
                ],
                properties: {
                  target: { type: 'string' },
                  source: { type: 'string' },
                  name: { type: 'string' },
                  environment: nul('string'),
                  severity: { type: 'string' },
                  state: { type: 'string' },
                  detail: nul('string'),
                  openedAt: { type: 'string' },
                  sourceUrl: { ...nul('string'), description: 'Platform page to debug this issue on, or null' },
                  liveUrl: { ...nul('string'), description: "The affected site's live URL, or null" },
                  commitHash: { ...nul('string'), description: 'Commit that produced a failed deploy; null for http/dns issues' },
                  commitMessage: nul('string'),
                  commitRepo: { ...nul('string'), description: '"owner/name" — build a GitHub commit link with commitHash' },
                },
              },
            },
          },
        }),
        ...errors(401),
      },
    },
  },
  '/history': {
    get: {
      tags: [tag],
      summary: "One endpoint's recent health-check samples",
      security: BEARER,
      parameters: [queryParam('slug'), queryParam('service'), queryParam('hours')],
      responses: {
        200: okJson('History', {
          type: 'object',
          required: ['service', 'hours', 'checks'],
          properties: {
            service: { type: 'string' },
            hours: { type: 'number' },
            checks: {
              type: 'array',
              items: {
                type: 'object',
                required: ['status', 'responseTimeMs', 'statusCode', 'error', 'checkedAt'],
                properties: {
                  status: { type: 'string' },
                  responseTimeMs: nul('number'),
                  statusCode: nul('number'),
                  error: nul('string'),
                  checkedAt: { type: 'string' },
                },
              },
            },
          },
        }),
        ...errors(400, 401),
      },
    },
  },
  '/uptime': {
    get: {
      tags: [tag],
      summary: 'Per-endpoint daily uptime over the last N days',
      security: BEARER,
      parameters: [queryParam('days')],
      responses: {
        200: okJson('UptimeResponse', {
          type: 'object',
          required: ['services', 'days'],
          properties: {
            services: { type: 'array', items: ref('UptimeService') },
            days: { type: 'number' },
          },
        }),
        ...errors(401),
      },
    },
  },
  '/response-history': {
    get: {
      tags: [tag],
      summary: 'Portfolio-wide response-time sparkline buckets (oldest → newest)',
      security: BEARER,
      parameters: [queryParam('hours'), queryParam('buckets')],
      responses: {
        200: okJson('ResponseHistory', {
          type: 'object',
          required: ['hours', 'points'],
          properties: {
            hours: { type: 'number' },
            points: { type: 'array', items: nul('number') },
          },
        }),
        ...errors(401),
      },
    },
  },
  '/deploy-projects': {
    get: {
      tags: [tag],
      summary: 'The deploy projects an endpoint can wire to (project entries carry canonical links)',
      security: BEARER,
      parameters: [queryParam('fresh')],
      responses: {
        200: okJson('Deploy projects', {
          type: 'object',
          required: ['projects', 'verifiedPlatforms'],
          properties: {
            projects: { type: 'array', items: ref('DeployProject') },
            // Which platforms this listing was a COMPLETE, authenticated read of — the only
            // ones whose absence is evidence a project is gone. A platform that degraded to
            // its configured fallback list is enumerated but NOT named here, so a client
            // can't mistake "we didn't see it" for "it doesn't exist".
            verifiedPlatforms: { type: 'array', items: { type: 'string' } },
          },
        }),
        ...errors(401),
      },
    },
  },
  '/deploy-projects/unconfigured': {
    get: {
      tags: [tag],
      summary: 'The configuration gaps: pending/addable projects + unconfigured endpoints',
      security: BEARER,
      parameters: [queryParam('fresh')],
      responses: {
        200: okJson('Unconfigured partition', {
          type: 'object',
          required: ['pending', 'addable', 'noDomain', 'unconfiguredSites'],
          properties: {
            pending: { type: 'array', items: ref('DeployProject') },
            addable: { type: 'array', items: ref('DeployProject') },
            noDomain: { type: 'array', items: ref('DeployProject') },
            unconfiguredSites: { type: 'array', items: unconfiguredSite },
          },
        }),
        ...errors(401),
      },
    },
  },
  // src/routes/deploy-logs.ts — documented with the reads it completes.
  '/deployments/{id}/log': {
    get: {
      tags: [tag],
      summary: "One deployment's full build log, fetched from the provider on demand",
      security: BEARER,
      parameters: [pathParam('id')],
      responses: {
        200: okJson('DeploymentLog', {
          type: 'object',
          required: ['id', 'platform', 'projectName', 'environment', 'errorText', 'log'],
          properties: {
            id: { type: 'string' },
            platform: { type: 'string' },
            projectName: { type: 'string' },
            environment: nul('string'),
            errorText: { ...nul('string'), description: "The persisted one-line failure reason, or null" },
            log: {
              ...nul('string'),
              description:
                'The whole build log, oldest line first. Null when the platform has no build log, ' +
                'no token is configured, or the provider fetch failed.',
            },
          },
        }),
        ...errors(401, 404),
      },
    },
  },
  '/integrations': {
    get: {
      tags: [tag],
      summary: 'Provider reachability + stats-freshness self-check',
      security: BEARER,
      parameters: [queryParam('fresh')],
      responses: {
        200: okJson('IntegrationsResponse', {
          type: 'object',
          required: ['generatedAt', 'overall', 'checks'],
          properties: {
            generatedAt: { type: 'string' },
            overall: { type: 'string' },
            checks: { type: 'array', items: ref('IntegrationCheck') },
          },
        }),
        ...errors(401),
      },
    },
  },
};
