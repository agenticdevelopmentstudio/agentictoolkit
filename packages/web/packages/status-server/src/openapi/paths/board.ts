import { BEARER, okJson, ref, errors, type Paths, type Schemas } from '../shared';

// ---------------------------------------------------------------------------
// The board (src/routes/board.ts), behind the app-wide requireAuth seam.
//
//   GET  /board            the whole board in one read — Problems, Activity and the
//                          indicator, from one fold against one clock (src/board).
//                          View tier — it is the client's only read.
//   POST /board/reconcile  Requirement B: make the ledger agree with the board — the
//                          monitor cycle's own verb, so it OPENS, UPDATES and RESOLVES
//                          rows, and can page on-call while doing it. Mutates the ledger,
//                          so it carries a per-route requireAdmin AND the bearer scheme
//                          plus a 403.
// ---------------------------------------------------------------------------

const tag = 'board';

/** A nullable primitive (OpenAPI 3.1 union form). */
const nul = (t: string) => ({ type: [t, 'null'] });

// Mirrors `IssueSource` (src/monitor/issue-sources.ts) — the generated client narrows
// `Problem.source` to exactly these, so a member missing here is a client that rejects a
// payload this server really sends. `glitchtip` is a source like any other: it opens
// `errors|<project>` rows and `platform-health|glitchtip` rows.
const issueSource = {
  type: 'string',
  enum: ['dns', 'http', 'vercel', 'cloudflare-pages', 'railway', 'crunchy', 'glitchtip'],
};
const severity = { type: 'string', enum: ['critical', 'major', 'minor'] };

export const boardSchemas: Schemas = {
  // Problem (src/board/types.ts) — one row of the Problems list.
  Problem: {
    type: 'object',
    required: [
      'target', 'source', 'name', 'environment', 'severity', 'state', 'statusCode',
      'detail', 'sourceUrl', 'liveUrl', 'commitHash', 'commitMessage', 'commitRepo',
      'branch', 'errorText', 'since',
    ],
    properties: {
      target: { type: 'string' },
      source: issueSource,
      name: { type: 'string' },
      environment: nul('string'),
      severity,
      state: { type: 'string' },
      statusCode: nul('number'),
      detail: nul('string'),
      sourceUrl: nul('string'),
      liveUrl: nul('string'),
      commitHash: nul('string'),
      commitMessage: nul('string'),
      commitRepo: nul('string'),
      // The RAW git ref, alongside the tier in `environment` that was derived from it, and
      // the provider's own failure text. Both null on a problem that is not about a deploy.
      branch: nul('string'),
      errorText: nul('string'),
      since: { type: 'string' },
    },
  },
  // ActivityRow (src/board/types.ts) — one row of the Activity feed.
  ActivityRow: {
    type: 'object',
    required: [
      'id', 'kind', 'step', 'source', 'tone', 'verb', 'target', 'name', 'environment',
      'detail', 'sourceUrl', 'liveUrl', 'commitHash', 'commitMessage', 'commitRepo',
      'branch', 'errorText', 'at',
    ],
    properties: {
      id: { type: 'string' },
      kind: { type: 'string', enum: ['deploy', 'probe', 'platform'] },
      step: { type: ['string', 'null'], enum: ['build', 'deploy', null] },
      // Same spelling `Problem.source` uses, and nullable only where the server genuinely
      // could not attribute the row — the client reads its platform straight off it.
      source: { type: ['string', 'null'], enum: [...issueSource.enum, null] },
      tone: { type: 'string', enum: ['good', 'bad', 'progress', 'neutral', 'stale'] },
      verb: { type: 'string' },
      target: { type: 'string' },
      name: { type: 'string' },
      environment: nul('string'),
      detail: nul('string'),
      sourceUrl: nul('string'),
      liveUrl: nul('string'),
      commitHash: nul('string'),
      commitMessage: nul('string'),
      commitRepo: nul('string'),
      branch: nul('string'),
      errorText: nul('string'),
      at: { type: 'string' },
    },
  },
  // Board (src/board/types.ts) — the whole board. One read, one clock, one truth.
  Board: {
    type: 'object',
    required: [
      'generatedAt', 'dataAsOfMs', 'probeIntervalMs', 'activityFromMs', 'problems',
      'activity', 'indicator', 'monitoredTargets',
    ],
    properties: {
      generatedAt: { type: 'string' },
      // The DATA clock, not the derivation clock. Required-but-nullable on purpose: a
      // consumer that treats an absent field as "fine" would re-open the wedged-monitor
      // hole this exists to close, so the null has to arrive explicitly.
      dataAsOfMs: nul('number'),
      // The two facts the client used to source for itself: the configured probe cadence
      // it scales its staleness window by, and the activity window's own lower boundary.
      probeIntervalMs: { type: 'number' },
      activityFromMs: { type: 'number' },
      problems: { type: 'array', items: ref('Problem') },
      activity: { type: 'array', items: ref('ActivityRow') },
      indicator: { type: 'string', enum: ['operational', 'degraded', 'outage'] },
      monitoredTargets: { type: 'array', items: { type: 'string' } },
    },
  },
};

export const boardPaths: Paths = {
  '/board': {
    get: {
      tags: [tag],
      summary: 'The whole board in one read: Problems, Activity and the indicator',
      security: BEARER,
      responses: {
        200: okJson('Board', ref('Board')),
        ...errors(401),
      },
    },
  },
  '/board/reconcile': {
    post: {
      tags: [tag],
      summary: 'Requirement B: write the board into the ledger — opens, updates and resolves rows (can alert)',
      description:
        'Runs the monitor cycle\'s own ledger write. It opens a row for every derived problem that has none, ' +
        'refreshes the rows of problems still live, and resolves the ones the board no longer derives. ' +
        'Opening a row (and closing one as a recovery) queues an alert, which this endpoint flushes — so ' +
        'calling it can page on-call.',
      security: BEARER,
      responses: {
        200: okJson('Counts of what the ledger write did', {
          type: 'object',
          required: ['opened', 'updated', 'resolved', 'targets', 'checkedAt', 'skipped'],
          properties: {
            // Opening a row is the half that ALERTS — reporting only `resolved` hid it.
            opened: { type: 'number' },
            // Non-zero on a steady-state run: a live row's links and commit are refreshed.
            updated: { type: 'number' },
            resolved: { type: 'number' },
            targets: { type: 'array', items: { type: 'string' } },
            checkedAt: { type: 'string' },
            // True when the sweep declined to run (an empty roster read) rather than ran
            // and found nothing stale — `{ resolved: 0 }` alone can't tell those apart.
            skipped: { type: 'boolean' },
          },
        }),
        ...errors(401, 403),
      },
    },
  },
};
