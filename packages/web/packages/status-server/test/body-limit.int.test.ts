import { describe, it, expect } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

async function bootDb(): Promise<Db> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return db;
}

describe('request body limit (app-wide)', () => {
  it('rejects an oversized body on the pre-auth webhook with 413 before any processing', async () => {
    // /hooks/vercel must buffer the raw body for its HMAC check and sits BEFORE
    // the auth seam — without a global cap, an anonymous POST could buffer an
    // arbitrarily large body into memory before the signature rejects it.
    const db = await bootDb();
    const app = createApp({ db, config: testConfig() });
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: 'x'.repeat(1_048_577), // one byte past 1MB
    });
    expect(res.status).toBe(413);
  });

  it('passes normal-sized bodies through to the route untouched', async () => {
    const db = await bootDb();
    const app = createApp({ db, config: testConfig() });
    // No webhook secret configured → the handler itself answers 503; reaching it
    // proves the limit middleware let the small body pass.
    const res = await app.request('/hooks/vercel', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'deployment.created' }),
    });
    expect(res.status).toBe(503);
  });

  it('does not interfere with auth routes', async () => {
    const db = await bootDb();
    const app = createApp({ db, config: testConfig() });
    const res = await app.request('/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'nobody@test.local', password: 'wrong-password' }),
    });
    expect(res.status).toBe(401); // reached the handler; not 413/500
  });
});
