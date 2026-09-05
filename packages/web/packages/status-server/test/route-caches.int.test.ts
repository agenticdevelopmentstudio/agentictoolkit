import { describe, it, expect } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { sessionHeaders } from './helpers/auth';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

// /deploy-projects and /integrations fan out live provider calls per request
// with no dampening — unlike /telemetry, which grew a 30s cache + single-flight
// for exactly this reason. A burst of dashboard loads multiplied provider
// polls (each up to seconds of latency, feeding straight into rate limits).

async function boot(): Promise<{ app: ReturnType<typeof createApp>; db: Db; auth: { Cookie: string } }> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  const auth = await sessionHeaders(db, 'viewer');
  return { app: createApp({ db, config: testConfig() }), db, auth };
}

describe('/deploy-projects caching', () => {
  it('serves the cached enumeration within the TTL; ?fresh=1 re-enumerates', async () => {
    const { app, db, auth } = await boot();
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'site-a' });

    const first = (await (await app.request('/deploy-projects', { headers: auth })).json()) as { projects: unknown[] };
    expect(first.projects).toHaveLength(1);

    // New meta appears, but within the TTL the cached enumeration is served.
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'site-b' });
    const cached = (await (await app.request('/deploy-projects', { headers: auth })).json()) as { projects: unknown[] };
    expect(cached.projects).toHaveLength(1);

    const fresh = (await (await app.request('/deploy-projects?fresh=1', { headers: auth })).json()) as { projects: unknown[] };
    expect(fresh.projects).toHaveLength(2);
  });
});

describe('/deploy-projects/unconfigured caching', () => {
  it('shares the /deploy-projects 30s single-flight cache; ?fresh=1 re-enumerates', async () => {
    const { app, db, auth } = await boot();
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'site-a' });

    // Prime the shared enumeration cache via the sibling route.
    const primed = (await (await app.request('/deploy-projects', { headers: auth })).json()) as { projects: unknown[] };
    expect(primed.projects).toHaveLength(1);

    // New meta appears, but the unconfigured read (no ?fresh) coalesces on the cached
    // enumeration — it must NOT trigger its own fresh provider fan-out.
    await db.insert(schema.deployProjectMeta).values({ platform: 'vercel', projectName: 'site-b' });
    const cached = (await (await app.request('/deploy-projects/unconfigured', { headers: auth })).json()) as { pending: unknown[] };
    expect(cached.pending).toHaveLength(1); // both unwired, but site-b invisible until the cache busts

    // ?fresh=1 (what the Auto Configure modal sends) re-enumerates, so both appear.
    const fresh = (await (await app.request('/deploy-projects/unconfigured?fresh=1', { headers: auth })).json()) as { pending: unknown[] };
    expect(fresh.pending).toHaveLength(2);
  });
});

describe('/integrations caching', () => {
  it('serves the cached check within the TTL; ?fresh=1 re-probes', async () => {
    const { app, auth } = await boot();
    const first = (await (await app.request('/integrations', { headers: auth })).json()) as { generatedAt: string };
    const second = (await (await app.request('/integrations', { headers: auth })).json()) as { generatedAt: string };
    expect(second.generatedAt).toBe(first.generatedAt); // same build — cached

    await new Promise((r) => setTimeout(r, 5));
    const fresh = (await (await app.request('/integrations?fresh=1', { headers: auth })).json()) as { generatedAt: string };
    expect(fresh.generatedAt).not.toBe(first.generatedAt);
  });
});
