import { describe, it, expect, beforeAll } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { sessionHeaders } from './helpers/auth';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

describe('/status/badge.svg', () => {
  let app: ReturnType<typeof createApp>;
  let viewAuth: { Cookie: string };

  beforeAll(async () => {
    const db: Db = drizzle(createClient({ url: ':memory:' }), { schema });
    await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
    viewAuth = await sessionHeaders(db, 'viewer');
    app = createApp({ db, config: testConfig() });
  });

  it('401 without a token (gated)', async () => {
    expect((await app.request('/status/badge.svg')).status).toBe(401);
  });

  it('returns SVG with a view token', async () => {
    const res = await app.request('/status/badge.svg', { headers: viewAuth });
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('image/svg+xml');
    expect(await res.text()).toContain('<svg');
  });
});
