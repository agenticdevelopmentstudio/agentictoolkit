import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import { createHmac } from 'node:crypto';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { clearDeployEvents } from '../src/monitor/live-buffer';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

const VERCEL_SECRET = 's3cr3t';
const RAILWAY_SECRET = 'ry_s3cr3t';

// Minimal Vercel deployment.succeeded event that mapVercelDeployEvent accepts.
// Requires: `type` in VERCEL_STATE, `payload.deployment.id`, `payload.deployment.name`.
const VERCEL_BODY = JSON.stringify({
  type: 'deployment.succeeded',
  createdAt: new Date().toISOString(),
  payload: {
    target: 'production',
    deployment: {
      id: 'dpl_abc123',
      name: 'my-project',
      url: 'my-project.vercel.app',
      meta: {
        githubCommitSha: 'aabbcc1122334455',
        githubCommitMessage: 'fix: something',
        githubCommitRef: 'main',
        githubCommitOrg: 'myorg',
        githubCommitRepo: 'myrepo',
      },
    },
    links: { deployment: 'https://vercel.com/myorg/my-project/dpl_abc123' },
  },
});

// Minimal Railway event that mapRailwayDeployEvent accepts.
// Requires: `id`, `status` (or `type` like "Deployment.success"), `project.name`.
const RAILWAY_BODY = JSON.stringify({
  id: 'ry_deploy_xyz',
  status: 'SUCCESS',
  project: { id: 'proj-001', name: 'my-railway-project' },
  environment: { name: 'production' },
  commitHash: 'deadbeef',
  commitMessage: 'chore: deploy',
  branch: 'main',
  repo: 'myorg/myrepo',
  timestamp: new Date().toISOString(),
});

async function bootApp() {
  const client = createClient({ url: ':memory:' });
  const db = drizzle(client, { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  // Seed sites that OWN the webhook projects, so their events pass the ownership gate.
  const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0]!;
  const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g.id, slug: 's', name: 'S' }).returning())[0]!;
  await db.insert(schema.monitoredEndpoints).values([
    { siteId: s.id, url: 'https://my-project.example.com', platform: 'vercel', deployProject: 'my-project' },
    { siteId: s.id, url: 'https://my-railway-project.example.com', platform: 'railway', deployProject: 'my-railway-project' },
  ]);
  return createApp({ db, config: testConfig() });
}

/** A Vercel deployment.succeeded body for an arbitrary project name (re-signed per test). */
function vercelBodyFor(projectName: string): string {
  const e = JSON.parse(VERCEL_BODY) as { payload: { deployment: { name: string } } };
  e.payload.deployment.name = projectName;
  return JSON.stringify(e);
}

/** A Railway deploy body for an arbitrary project name. */
function railwayBodyFor(projectName: string): string {
  const e = JSON.parse(RAILWAY_BODY) as { project: { name: string } };
  e.project.name = projectName;
  return JSON.stringify(e);
}

describe('/hooks/vercel', () => {
  let app: Awaited<ReturnType<typeof bootApp>>;

  beforeAll(async () => {
    process.env.VERCEL_WEBHOOK_SECRET = VERCEL_SECRET;
    app = await bootApp();
  });

  afterAll(() => {
    delete process.env.VERCEL_WEBHOOK_SECRET; // don't leak the secret to other test files
  });

  afterEach(() => {
    clearDeployEvents();
  });

  it('rejects a bad signature (401) without needing a view/admin token', async () => {
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'x-vercel-signature': 'bad', 'Content-Type': 'application/json' },
      body: VERCEL_BODY,
    });
    expect(res.status).toBe(401);
  });

  it('accepts a valid HMAC-SHA1 signature and returns 200 with the deploy id', async () => {
    const sig = createHmac('sha1', VERCEL_SECRET).update(VERCEL_BODY).digest('hex');
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'x-vercel-signature': sig, 'Content-Type': 'application/json' },
      body: VERCEL_BODY,
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; id: string };
    expect(body.ok).toBe(true);
    expect(body.id).toBe('vc_dpl_abc123');
  });

  it('drops a deploy event for a project NO site owns (valid signature, never buffered)', async () => {
    const body = vercelBodyFor('unowned-project');
    const sig = createHmac('sha1', VERCEL_SECRET).update(body).digest('hex');
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'x-vercel-signature': sig, 'Content-Type': 'application/json' },
      body,
    });
    expect(res.status).toBe(200); // 2xx so the provider doesn't retry-storm
    const json = (await res.json()) as { ok: boolean; ignored?: string; id?: string };
    expect(json.ignored).toBe('not owned by a site');
    expect(json.id).toBeUndefined();
  });

  it('returns 200 (no retry-storm) for a valid-signature unparseable body', async () => {
    const raw = 'not-json';
    const sig = createHmac('sha1', VERCEL_SECRET).update(raw).digest('hex');
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'x-vercel-signature': sig, 'Content-Type': 'text/plain' },
      body: raw,
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; ignored: string };
    expect(body.ignored).toBe('unparseable');
  });

  it('returns 503 when VERCEL_WEBHOOK_SECRET is unset', async () => {
    const saved = process.env.VERCEL_WEBHOOK_SECRET;
    delete process.env.VERCEL_WEBHOOK_SECRET;
    try {
      const res = await app.request('/hooks/vercel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: VERCEL_BODY,
      });
      expect(res.status).toBe(503);
    } finally {
      process.env.VERCEL_WEBHOOK_SECRET = saved;
    }
  });
});

// A webhook derives issues on the ingest thread, over the SAME target namespace the
// monitor cycle uses. If it derived them from the un-narrowed owned set, every provider
// retry for a project that has since been DELETED at Vercel would reopen — and page for —
// the very Problem the cycle just resolved as "unmonitored". This pins the narrowing at
// the one place it can be observed end-to-end: an issue row after a POST.
describe('/hooks/vercel issue derivation', () => {
  async function bootWithDb() {
    const client = createClient({ url: ':memory:' });
    const db = drizzle(client, { schema });
    await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
    const g = (await db.insert(schema.siteGroups).values({ slug: 'g', name: 'G' }).returning())[0]!;
    const s = (await db.insert(schema.monitoredSites).values({ siteGroupId: g.id, slug: 's', name: 'S' }).returning())[0]!;
    // BOTH projects are wired to a live site — the only difference is whether the
    // project still exists at Vercel, which `deploy_project_meta` mirrors.
    await db.insert(schema.monitoredEndpoints).values([
      { siteId: s.id, url: 'https://live-project.example.com', platform: 'vercel', deployProject: 'live-project' },
      { siteId: s.id, url: 'https://ghost-project.example.com', platform: 'vercel', deployProject: 'ghost-project' },
    ]);
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'live-project' });
    return { app: createApp({ db, config: testConfig() }), db };
  }

  /** A FAILED production deploy webhook for `projectName`. */
  function failedBody(projectName: string): string {
    const e = JSON.parse(VERCEL_BODY) as { type: string; payload: { deployment: { id: string; name: string } } };
    e.type = 'deployment.error';
    e.payload.deployment.id = `dpl_${projectName}`;
    e.payload.deployment.name = projectName;
    return JSON.stringify(e);
  }

  async function postFailure(app: Awaited<ReturnType<typeof bootWithDb>>['app'], projectName: string): Promise<void> {
    const body = failedBody(projectName);
    const sig = createHmac('sha1', VERCEL_SECRET).update(body).digest('hex');
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'x-vercel-signature': sig, 'Content-Type': 'application/json' },
      body,
    });
    expect(res.status).toBe(200);
  }

  beforeAll(() => { process.env.VERCEL_WEBHOOK_SECRET = VERCEL_SECRET; });
  afterAll(() => { delete process.env.VERCEL_WEBHOOK_SECRET; });
  afterEach(() => { clearDeployEvents(); });

  it('opens a Problem for a live project but NOT for one deleted at Vercel', async () => {
    const { app, db } = await bootWithDb();

    await postFailure(app, 'live-project');
    await postFailure(app, 'ghost-project');

    const open = (await db.select().from(schema.issues))
      .filter((i) => i.resolvedAt === null)
      .map((i) => i.target);
    expect(open).toEqual(['vercel|live-project|']);
  });
});

describe('/hooks/railway', () => {
  let app: Awaited<ReturnType<typeof bootApp>>;

  beforeAll(async () => {
    process.env.RAILWAY_WEBHOOK_SECRET = RAILWAY_SECRET;
    app = await bootApp();
  });

  afterAll(() => {
    delete process.env.RAILWAY_WEBHOOK_SECRET;
  });

  afterEach(() => {
    clearDeployEvents();
  });

  it('rejects a missing/wrong secret (401) without needing a view/admin token', async () => {
    const res = await app.request('/hooks/railway', {
      method: 'POST',
      headers: { 'x-webhook-secret': 'wrong', 'Content-Type': 'application/json' },
      body: RAILWAY_BODY,
    });
    expect(res.status).toBe(401);
  });

  it('accepts a valid secret in the x-webhook-secret header and returns 200', async () => {
    const res = await app.request('/hooks/railway', {
      method: 'POST',
      headers: {
        'x-webhook-secret': RAILWAY_SECRET,
        'Content-Type': 'application/json',
      },
      body: RAILWAY_BODY,
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; id: string };
    expect(body.ok).toBe(true);
    expect(body.id).toBe('ry_ry_deploy_xyz');
  });

  it('drops a deploy event for a project NO site owns (valid secret, never buffered)', async () => {
    const res = await app.request('/hooks/railway', {
      method: 'POST',
      headers: { 'x-webhook-secret': RAILWAY_SECRET, 'Content-Type': 'application/json' },
      body: railwayBodyFor('unowned-railway-project'),
    });
    expect(res.status).toBe(200);
    const json = (await res.json()) as { ok: boolean; ignored?: string; id?: string };
    expect(json.ignored).toBe('not owned by a site');
    expect(json.id).toBeUndefined();
  });

  it('accepts a valid secret via ?token= query param and returns 200', async () => {
    const res = await app.request(`/hooks/railway?token=${RAILWAY_SECRET}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: RAILWAY_BODY,
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; id: string };
    expect(body.ok).toBe(true);
  });

  it('returns 503 when RAILWAY_WEBHOOK_SECRET is unset', async () => {
    const saved = process.env.RAILWAY_WEBHOOK_SECRET;
    delete process.env.RAILWAY_WEBHOOK_SECRET;
    try {
      const res = await app.request('/hooks/railway', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: RAILWAY_BODY,
      });
      expect(res.status).toBe(503);
    } finally {
      process.env.RAILWAY_WEBHOOK_SECRET = saved;
    }
  });
});
