import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { sessionHeaders } from './helpers/auth';
import { freshDb as bootDb, type Db as TestDb } from './helpers/db';
import { testConfig } from './helpers/config';

// GET /deployments/:id/log — the on-demand full build log. Unlike every other
// read, this one calls the provider, so the tests pin the two things that make
// it safe to expose: it is behind the auth seam, and a provider that says
// nothing (no token, no log, an error) degrades to `log: null` rather than
// failing the request. The persisted one-liner rides along either way.

/** A failed Vercel deployment row, the shape enrichment leaves behind. */
async function seedDeploy(db: TestDb, over: Partial<typeof schema.deployments.$inferInsert> = {}) {
  await db.insert(schema.deployments).values({
    id: 'vc_dpl_abc',
    platform: 'vercel',
    projectName: 'cookbook-testing',
    buildPhase: 'failed',
    deployPhase: 'none',
    environment: 'production',
    errorText: '[buildStep] Command "python3 build.py" exited with 1',
    createdAt: new Date(),
    fetchedAt: new Date(),
    ...over,
  });
}

/** The provider log endpoint answering with `events`; asserts nothing about the URL. */
function stubVercelEvents(events: unknown[]) {
  vi.stubGlobal('fetch', vi.fn(async () => Response.json(events)));
}

describe('GET /deployments/:id/log', () => {
  let db: TestDb;
  let app: ReturnType<typeof createApp>;
  let viewAuth: { Cookie: string };

  beforeAll(async () => {
    db = await bootDb();
    viewAuth = await sessionHeaders(db, 'viewer');
    app = createApp({ db, config: testConfig() });
    await seedDeploy(db);
    // The route reads its token the way the monitor does — the active integration
    // row names an env var, the env holds the secret.
    process.env.VERCEL_API_TOKEN = 'vc-tok';
    await db.insert(schema.deployIntegrations).values({
      platform: 'vercel',
      label: 'Vercel',
      tokenEnvVar: 'VERCEL_API_TOKEN',
      config: { teamId: 'team_1' },
    });
  });

  afterEach(() => vi.unstubAllGlobals());

  it('401 without a session', async () => {
    expect((await app.request('/deployments/vc_dpl_abc/log')).status).toBe(401);
  });

  it('404s for a deployment the monitor has never seen', async () => {
    const res = await app.request('/deployments/vc_dpl_nope/log', { headers: viewAuth });
    expect(res.status).toBe(404);
  });

  it('returns the WHOLE log, oldest line first', async () => {
    stubVercelEvents([
      { type: 'command', payload: { text: 'Running "python3 build.py"\n' } },
      { type: 'stdout', payload: { text: 'collecting pages' } },
      { type: 'deployment-state', payload: {} }, // no text — not a log line
      { type: 'stderr', payload: { text: 'ModuleNotFoundError: no module named yaml' } },
      { type: 'exit', payload: { text: 'Command exited with 1' } },
    ]);
    const res = await app.request('/deployments/vc_dpl_abc/log', { headers: viewAuth });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { log: string | null; errorText: string | null; projectName: string };
    expect(body.log).toBe(
      'Running "python3 build.py"\ncollecting pages\nModuleNotFoundError: no module named yaml\nCommand exited with 1',
    );
    // The reason the log matters: the persisted one-liner names the failing
    // command, the log names the actual cause (the missing module).
    expect(body.errorText).toContain('exited with 1');
    expect(body.projectName).toBe('cookbook-testing');
  });

  it('degrades to log:null (not an error) when the provider fetch fails', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('nope', { status: 500 })));
    const res = await app.request('/deployments/vc_dpl_abc/log', { headers: viewAuth });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { log: string | null }).log).toBeNull();
  });

  it('degrades to log:null for a platform with no build-log concept', async () => {
    await seedDeploy(db, { id: 'cf_1', platform: 'cloudflare-pages', errorText: null });
    stubVercelEvents([{ type: 'stdout', payload: { text: 'must not be reached' } }]);
    const res = await app.request('/deployments/cf_1/log', { headers: viewAuth });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { log: string | null }).log).toBeNull();
  });
});
