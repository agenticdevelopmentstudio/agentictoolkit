import { BEARER, okJson, ref, errors, type Paths, type Schemas } from '../shared';

// ---------------------------------------------------------------------------
// Production-visibility telemetry (src/routes/telemetry.ts), behind the app-wide
// requireAuth seam. Response DTOs are defined in src/telemetry/types.ts. Each error
// row carries GlitchTip's own `permalink` deep link; analytics rows are anonymous,
// aggregate PostHog KPIs. (No deep-link URL is constructed here — the permalink is
// whatever GlitchTip returned; there is nothing to extract into lib/links.ts.)
// ---------------------------------------------------------------------------

const tag = 'telemetry';

export const telemetrySchemas: Schemas = {
  // ErrorDTO (telemetry/types.ts) — one grouped GlitchTip issue.
  ErrorDTO: {
    type: 'object',
    required: ['id', 'issueKey', 'project', 'title', 'culprit', 'level', 'count', 'userCount', 'firstSeen', 'lastSeen', 'permalink'],
    properties: {
      id: { type: 'string' },
      issueKey: { type: 'string' },
      project: { type: 'string' },
      title: { type: 'string' },
      culprit: { type: ['string', 'null'] },
      level: { type: ['string', 'null'] },
      count: { type: 'number' },
      userCount: { type: 'number' },
      firstSeen: { type: ['string', 'null'] },
      lastSeen: { type: ['string', 'null'] },
      permalink: { type: ['string', 'null'] },
    },
  },
  // AnalyticsMetricDTO (telemetry/types.ts) — one anonymous, aggregate KPI sample.
  AnalyticsMetricDTO: {
    type: 'object',
    required: ['metric', 'window', 'scope', 'value', 'capturedAt'],
    properties: {
      metric: { type: 'string' },
      window: { type: 'string' },
      scope: { type: 'string' },
      value: { type: 'number' },
      capturedAt: { type: 'string' },
    },
  },
};

export const telemetryPaths: Paths = {
  '/telemetry': {
    get: {
      tags: [tag],
      summary: 'One combined read of the production-visibility band (errors + analytics)',
      security: BEARER,
      responses: {
        200: okJson('The telemetry snapshot', {
          type: 'object',
          required: ['generatedAt', 'errors', 'analytics'],
          properties: {
            generatedAt: { type: 'string' },
            errors: { type: 'array', items: ref('ErrorDTO') },
            analytics: { type: 'array', items: ref('AnalyticsMetricDTO') },
          },
        }),
        ...errors(401),
      },
    },
  },
  '/errors': {
    get: {
      tags: [tag],
      summary: 'The current grouped error issues',
      security: BEARER,
      responses: {
        200: okJson('The error issues', {
          type: 'object',
          required: ['errors'],
          properties: { errors: { type: 'array', items: ref('ErrorDTO') } },
        }),
        ...errors(401),
      },
    },
  },
  '/analytics': {
    get: {
      tags: [tag],
      summary: 'The headline analytics KPI samples',
      security: BEARER,
      responses: {
        200: okJson('The analytics metrics', {
          type: 'object',
          required: ['metrics'],
          properties: { metrics: { type: 'array', items: ref('AnalyticsMetricDTO') } },
        }),
        ...errors(401),
      },
    },
  },
};
