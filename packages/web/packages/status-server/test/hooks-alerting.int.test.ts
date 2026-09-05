import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createHmac } from 'node:crypto';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { clearDeployEvents } from '../src/monitor/live-buffer';
import { _resetAlerts } from '../src/monitor/alerts';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

// A webhook is the FASTEST signal the monitor gets — a provider telling us a
// deploy failed, seconds after it did. Persisting it and pushing it to the
// dashboard while leaving the alert to the next full sync (~5 min later) means
// the one path that could page on-call immediately is the one path that doesn't.

const SECRET = 's3cr3t';

const failedVercelEvent = (project: string) =>
  JSON.stringify({
    type: 'deployment.error',
    createdAt: new Date().toISOString(),
    payload: {
      target: 'production',
      deployment: { id: 'dpl_fail_1', name: project, url: `${project}.vercel.app` },
      links: { deployment: `https://vercel.com/org/${project}/dpl_fail_1` },
    },
  });

const sign = (body: string) => createHmac('sha1', SECRET).update(body).digest('hex'); // bare hex — Vercel sends no prefix

async function bootApp() {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0]!;
  const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g.id, slug: 's', name: 'S' }).returning())[0]!;
  await db.insert(schema.monitoredEndpoints).values({
    siteId: s.id,
    url: 'https://my-project.example.com',
    platform: 'vercel',
    deployProject: 'my-project',
  });
  return { app: createApp({ db, config: testConfig() }), db };
}

let sent: { text: string }[];

beforeEach(() => {
  _resetAlerts();
  clearDeployEvents();
  sent = [];
  process.env.VERCEL_WEBHOOK_SECRET = SECRET;
  vi.stubEnv('ALERT_WEBHOOK_URL', 'https://hooks.example.com/alert');
  vi.stubGlobal(
    'fetch',
    vi.fn(async (_u: string | URL, init?: RequestInit) => {
      sent.push(JSON.parse(String(init?.body)) as { text: string });
      return new Response('ok');
    }),
  );
});

afterEach(() => {
  delete process.env.VERCEL_WEBHOOK_SECRET;
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('webhook ingest raises the alert immediately', () => {
  it('alerts on a webhook-reported FAILED deploy without waiting for the next full sync', async () => {
    const { app, db } = await bootApp();

    const body = failedVercelEvent('my-project');
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-vercel-signature': sign(body) },
      body,
    });
    expect(res.status).toBe(200);

    // The issue is derived from the webhook's own deploy row, and the alert goes
    // out on THIS request — not on the next cycle, minutes later.
    const open = await db.select().from(schema.issues);
    expect(open).toHaveLength(1);
    expect(open[0]?.target).toContain('my-project');
    expect(sent).toHaveLength(1);
    expect(sent[0]!.text).toMatch(/opened/i);
    expect(sent[0]!.text).toContain('my-project');
  });

  it('stays silent for a SUCCESSFUL deploy (nothing to page about)', async () => {
    const { app, db } = await bootApp();
    const body = JSON.stringify({
      type: 'deployment.succeeded',
      createdAt: new Date().toISOString(),
      payload: { target: 'production', deployment: { id: 'dpl_ok_1', name: 'my-project' } },
    });
    await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-vercel-signature': sign(body) },
      body,
    });
    expect(await db.select().from(schema.issues)).toHaveLength(0);
    expect(sent).toHaveLength(0);
  });
});
