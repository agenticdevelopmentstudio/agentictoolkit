import { describe, it, expect, vi, beforeEach, afterAll } from 'vitest';
import { createHmac } from 'node:crypto';
import type { Db } from '../src/libsql/client';

// Both behaviours below are about the ROUTE's control flow — what it answers when the
// roster cannot be read, and how many reconciles a burst of webhooks costs — not about
// SQL. So `../src/board` is stubbed and `db` is a sentinel: a real database would only
// make an unreadable roster and a countable reconcile harder to arrange.
const { readRoster, reconcileBoardLedger, ownsDeployProject, upsertDeployments } = vi.hoisted(
  () => ({
    readRoster: vi.fn<() => Promise<unknown[]>>(),
    reconcileBoardLedger: vi.fn<() => Promise<void>>(),
    ownsDeployProject: vi.fn<() => boolean>(),
    upsertDeployments: vi.fn<() => Promise<void>>(),
  }),
);

vi.mock('../src/board', () => ({
  readRoster,
  reconcileBoardLedger,
  ownsDeployProject,
  rosterDeployProjects: () => new Map<string, unknown>(),
}));
vi.mock('../src/monitor/sync', () => ({ upsertDeployments }));
vi.mock('../src/live/live-events', () => ({ emitLiveUpdate: vi.fn() }));
vi.mock('../src/monitor/alerts', () => ({ flushAlerts: vi.fn(async () => {}) }));

import { hooksRoutes } from '../src/routes/hooks';
import { testConfig } from './helpers/config';

const SECRET = 's3cr3t';
const db = {} as Db;

/** A distinct deployment per call, so nothing can be coalesced by deploy id. */
function vercelBody(n: number): string {
  return JSON.stringify({
    type: 'deployment.error',
    createdAt: new Date().toISOString(),
    payload: { target: 'production', deployment: { id: `dpl_${n}`, name: 'my-project' } },
  });
}

async function post(app: Hono, body: string): Promise<Response> {
  return app.request('/hooks/vercel', {
    method: 'POST',
    headers: {
      'x-vercel-signature': createHmac('sha1', SECRET).update(body).digest('hex'),
      'content-type': 'application/json',
    },
    body,
  });
}

type Hono = ReturnType<typeof hooksRoutes>;

/** Yield to the event loop until `done()` holds, so nothing here depends on tick counts. */
async function until(done: () => boolean): Promise<void> {
  for (let i = 0; i < 1_000 && !done(); i++) await new Promise((r) => setTimeout(r, 0));
  if (!done()) throw new Error('timed out waiting for the requests to reach the gate');
}

beforeEach(() => {
  process.env.VERCEL_WEBHOOK_SECRET = SECRET;
  readRoster.mockReset().mockResolvedValue([]);
  reconcileBoardLedger.mockReset().mockResolvedValue(undefined);
  ownsDeployProject.mockReset().mockReturnValue(true);
  upsertDeployments.mockReset().mockResolvedValue(undefined);
});

afterAll(() => {
  delete process.env.VERCEL_WEBHOOK_SECRET;
});

describe('the webhook ownership gate separates a verdict from an unreadable roster', () => {
  it('drops a project no site owns with 2xx — a final answer, nothing to retry', async () => {
    ownsDeployProject.mockReturnValue(false);
    const res = await post(hooksRoutes(db, testConfig()), vercelBody(1));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, ignored: 'not owned by a site' });
    expect(upsertDeployments).not.toHaveBeenCalled();
  });

  it('answers 503 when the roster CANNOT BE READ, so the provider redelivers', async () => {
    const quiet = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      readRoster.mockRejectedValue(new Error('database is locked'));
      const res = await post(hooksRoutes(db, testConfig()), vercelBody(2));
      // Answering 2xx here told the provider we had accepted an event we then discarded:
      // one DB blip during a deploy burst silently lost the fastest failure signal the
      // monitor gets, for every event in the burst.
      expect(res.status).toBe(503);
      expect(upsertDeployments).not.toHaveBeenCalled();
      expect(reconcileBoardLedger).not.toHaveBeenCalled();
    } finally {
      quiet.mockRestore();
    }
  });
});

describe('webhook reconciles are single-flight with one coalesced follow-up', () => {
  it('collapses a burst of concurrent events into exactly two reconciles', async () => {
    let openGate!: () => void;
    const gate = new Promise<void>((r) => {
      openGate = r;
    });
    // The first reconcile parks on `gate` so the other nine requests arrive while it is
    // genuinely in flight — the case webhooks actually arrive in, where a fleet-wide push
    // fans out to ~48 projects and a reconcile-per-event becomes a hundred concurrent
    // whole-board folds on the API thread.
    reconcileBoardLedger.mockImplementation(() => gate);

    const app = hooksRoutes(db, testConfig());
    const burst = Array.from({ length: 10 }, (_, i) => post(app, vercelBody(100 + i)));
    // Every request writes its row before it asks for a reconcile, so ten upserts means
    // all ten have reached the gate — no tick-counting, no sleep.
    await until(() => upsertDeployments.mock.calls.length === 10);
    openGate();

    const results = await Promise.all(burst);
    expect(results.map((r) => r.status)).toEqual(Array(10).fill(200));
    // One in-flight pass plus exactly ONE follow-up covering all nine later arrivals.
    // Never ten; and never one, because an arrival whose row landed after the in-flight
    // pass read its facts would be invisible until the next monitor cycle.
    expect(reconcileBoardLedger).toHaveBeenCalledTimes(2);
  });

  it('reconciles again for an event that arrives after the gate has drained', async () => {
    const app = hooksRoutes(db, testConfig());
    await post(app, vercelBody(300));
    await post(app, vercelBody(301));
    expect(reconcileBoardLedger).toHaveBeenCalledTimes(2);
  });
});
