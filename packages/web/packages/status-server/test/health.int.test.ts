import { describe, it, expect, beforeAll } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

async function bootApp() {
  const client = createClient({ url: ':memory:' });
  const db = drizzle(client, { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return createApp({ db, config: testConfig() });
}

describe('public allowlist', () => {
  let app: Awaited<ReturnType<typeof bootApp>>;
  beforeAll(async () => {
    app = await bootApp();
  });

  it('GET /health returns ok', async () => {
    const res = await app.request('/health');
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ status: 'ok' });
  });

  it('GET /version returns the name', async () => {
    const res = await app.request('/version');
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ name: 'status-backend' });
  });

  it('GET /public/status-summary is reachable without auth and reports operational', async () => {
    const res = await app.request('/public/status-summary');
    expect(res.status).toBe(200);
    // No endpoints configured → nothing down → the landing's headline is green.
    expect(await res.json()).toMatchObject({ operational: true, status: 'healthy', downSites: [] });
  });
});
