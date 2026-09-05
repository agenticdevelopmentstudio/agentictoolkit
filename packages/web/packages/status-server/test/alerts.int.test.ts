import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import { notifyIssueAlert, flushAlerts, _resetAlerts } from '../src/monitor/alerts';
import { applyBoardToLedger, openByTarget } from '../src/monitor/issues';
import type { Board, Problem } from '../src/board';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';

// The monitor detected outages but told NO ONE — an issue was only visible to
// someone already looking at the wallboard. Issue open/resolve transitions now
// post to ALERT_WEBHOOK_URL (one batched webhook per cycle), fail-soft.

async function freshDb(): Promise<Db> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

// Alert emission is `openIssue`/`resolveIssue`'s, and both survived Task 12 — only the
// DRIVER changed. The per-source recorders that used to re-derive a verdict here are
// gone; `applyBoardToLedger` records the verdict the board already made, so each step
// below states the board directly instead of feeding an observation to a recorder.
const board = (problems: Problem[], monitoredTargets: string[]): Board => ({
  generatedAt: new Date(3000).toISOString(),
  dataAsOfMs: 3000, probeIntervalMs: 60_000, activityFromMs: 0,
  indicator: problems.length > 0 ? 'degraded' : 'operational',
  problems,
  activity: [],
  monitoredTargets,
});

/** The endpoint problem the HTTP probe used to produce. Endpoint targets are the
 *  endpoint's BARE id, which is what `applyHttpIssues` always wrote. */
const appDown: Problem = {
  target: 'ep-1',
  source: 'http',
  name: 'App',
  environment: 'production',
  severity: 'major',
  state: 'down',
  statusCode: 503,
  detail: 'HTTP 503',
  sourceUrl: 'https://app.example.com',
  liveUrl: 'https://app.example.com',
  commitHash: null,
  commitMessage: null,
  commitRepo: null,
  branch: null,
  errorText: null,
  since: new Date(2000).toISOString(),
};

/** The platform-health problem the debounce used to produce once the streak was met.
 *  Two segments, no trailing pipe — a provider is not a deploy target. */
const vercelUnreachable: Problem = {
  target: 'platform-health|vercel',
  source: 'vercel',
  name: 'Vercel',
  environment: null,
  severity: 'minor',
  state: 'unreachable',
  statusCode: null,
  detail: "Vercel API unreachable — deploys for this platform can't be monitored",
  sourceUrl: null,
  liveUrl: null,
  commitHash: null,
  commitMessage: null,
  commitRepo: null,
  branch: null,
  errorText: null,
  since: new Date(2000).toISOString(),
};

const ALERT_URL = 'https://hooks.example.com/alert';

let sent: { url: string; body: Record<string, unknown> }[];

beforeEach(() => {
  _resetAlerts();
  sent = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (u: string | URL, init?: RequestInit) => {
      sent.push({ url: String(u), body: JSON.parse(String(init?.body)) as Record<string, unknown> });
      return new Response('ok');
    }),
  );
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('alert queue', () => {
  it('batches queued alerts into ONE webhook POST on flush', async () => {
    notifyIssueAlert({ kind: 'opened', target: 'a', name: 'Site A', environment: 'production', state: 'down', detail: 'HTTP 503' });
    notifyIssueAlert({ kind: 'opened', target: 'b', name: 'Site B', environment: null, state: 'failed', detail: null });
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1);
    const { body } = sent[0]!;
    expect(String(body.text)).toContain('Site A');
    expect(String(body.text)).toContain('Site B');
    expect((body.alerts as unknown[]).length).toBe(2);
    // A second flush with nothing queued sends nothing.
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1);
  });

  it('is a no-op with a null url and fail-soft on delivery errors', async () => {
    notifyIssueAlert({ kind: 'opened', target: 'a', name: 'A', environment: null, state: 'down', detail: null });
    await flushAlerts(null);
    expect(sent).toHaveLength(0);

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('webhook down');
      }),
    );
    notifyIssueAlert({ kind: 'opened', target: 'a', name: 'A', environment: null, state: 'down', detail: null });
    await expect(flushAlerts(ALERT_URL)).resolves.toBeUndefined();
  });
});

describe('issue lifecycle alerts (real recorder path)', () => {
  it('emits opened on a new outage and resolved on recovery — silent in between', async () => {
    const db = await freshDb();

    await applyBoardToLedger(db, board([appDown], ['ep-1']));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1);
    expect(String(sent[0]!.body.text)).toMatch(/opened/i);
    expect(String(sent[0]!.body.text)).toContain('App');

    // Still down next cycle: the open issue persists, no re-alert.
    await applyBoardToLedger(db, board([appDown], ['ep-1']));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1);
    expect([...(await openByTarget(db)).keys()]).toEqual(['ep-1']); // one row, still open

    // Healthy: the board derives no problem for a target it still WATCHES.
    await applyBoardToLedger(db, board([], ['ep-1']));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(2);
    expect(String(sent[1]!.body.text)).toMatch(/resolved/i);
    expect(String(sent[1]!.body.text)).toContain('App');
  });
});

describe('config-driven resolves must NOT alert (they are not recoveries)', () => {
  it('stays silent when a platform-health issue clears because its TOKEN was removed', async () => {
    const db = await freshDb();

    // 1) Vercel unreachable past the debounce window → the board carries the problem and
    //    the issue opens (a real alert). The debounce itself is the fold's now
    //    (`platformProblems` + the streak `recordPlatformObservations` keeps), so this
    //    states the post-debounce board rather than replaying two failing polls.
    await applyBoardToLedger(db, board([vercelUnreachable], ['platform-health|vercel']));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1);
    expect(String(sent[0]!.body.text)).toMatch(/opened/i);

    // 2) The operator REMOVES the Vercel token. An unconfigured platform is not in
    //    `monitoredTargets` at all, so the issue is resolved because we stopped monitoring
    //    the platform — not because Vercel recovered. Alerting "✅ resolved" here tells
    //    on-call the outage cleared when it did not.
    await applyBoardToLedger(db, board([], []));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1); // still just the open — no resolve alert

    const rows = await db.select().from(schema.issues);
    expect(rows[0]?.resolvedAt).not.toBeNull(); // but the issue IS closed
    expect(rows[0]?.resolvedReason).toBe('unmonitored');
  });

  it('still alerts when the platform genuinely RECOVERS (token intact)', async () => {
    const db = await freshDb();
    await applyBoardToLedger(db, board([vercelUnreachable], ['platform-health|vercel']));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(1);

    // Reachable again — still configured, so still WATCHED. That is a recovery.
    await applyBoardToLedger(db, board([], ['platform-health|vercel']));
    await flushAlerts(ALERT_URL);
    expect(sent).toHaveLength(2);
    expect(String(sent[1]!.body.text)).toMatch(/resolved/i);
  });
});
