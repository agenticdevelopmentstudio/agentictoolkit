import { describe, it, expect, vi, afterEach } from 'vitest';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import type { Db } from '../src/libsql/client';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { testConfig } from './helpers/config';

// /auth/login and /auth/signup are unauthenticated and each attempt burns a
// bcrypt verification on the API thread — with no per-IP ceiling, credential
// stuffing doubles as a CPU attack on a small container.

async function boot(): Promise<{ app: ReturnType<typeof createApp>; db: Db }> {
  const db = drizzle(createClient({ url: ':memory:' }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  return { app: createApp({ db, config: testConfig() }), db };
}

const attempt = (app: ReturnType<typeof createApp>, path: string, ip: string, body: unknown) =>
  app.request(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-forwarded-for': ip },
    body: JSON.stringify(body),
  });

const creds = { email: 'nobody@test.local', password: 'wrong-password-123' };

afterEach(() => vi.useRealTimers());

describe('per-IP rate limit on pre-auth routes', () => {
  it('caps login attempts per IP, then recovers after the window', async () => {
    vi.useFakeTimers();
    const { app } = await boot();

    for (let i = 0; i < 10; i++) {
      expect((await attempt(app, '/auth/login', '203.0.113.7', creds)).status).toBe(401);
    }
    const blocked = await attempt(app, '/auth/login', '203.0.113.7', creds);
    expect(blocked.status).toBe(429);
    expect(blocked.headers.get('retry-after')).toBeTruthy();

    // A different IP is not punished for the first one's storm.
    expect((await attempt(app, '/auth/login', '198.51.100.9', creds)).status).toBe(401);

    // The window lapses; the first IP may try again.
    vi.advanceTimersByTime(61_000);
    expect((await attempt(app, '/auth/login', '203.0.113.7', creds)).status).toBe(401);
  });

  it('caps signup attempts per IP', async () => {
    vi.useFakeTimers();
    const { app } = await boot();
    for (let i = 0; i < 5; i++) {
      const res = await attempt(app, '/auth/signup', '203.0.113.8', {
        email: `user${i}@test.local`,
        password: 'password123',
      });
      expect(res.status).toBe(201);
    }
    const blocked = await attempt(app, '/auth/signup', '203.0.113.8', {
      email: 'user6@test.local',
      password: 'password123',
    });
    expect(blocked.status).toBe(429);
  });

  it('does not limit the high-frequency public probe /auth/me', async () => {
    const { app } = await boot();
    for (let i = 0; i < 30; i++) {
      const res = await app.request('/auth/me', { headers: { 'x-forwarded-for': '203.0.113.9' } });
      expect(res.status).toBe(200);
    }
  });
});

describe('rate-limit key is the TRUSTED hop, not a client-supplied one', () => {
  it('ignores a spoofed leading x-forwarded-for entry (attacker cannot mint fresh buckets)', async () => {
    // The edge APPENDS the real client IP to whatever XFF the client sent, so the
    // LEFTMOST entry is attacker-controlled: rotating it per request used to mint a
    // fresh bucket every time and bypass the ceiling entirely. The trustworthy value
    // is the RIGHTMOST — the one the trusted hop added.
    const { app } = await boot();
    const attempt = (spoofed: string) =>
      app.request('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-forwarded-for': `${spoofed}, 198.51.100.42` },
        body: JSON.stringify(creds),
      });

    for (let i = 0; i < 10; i++) {
      // A different forged IP each time — but the real hop (rightmost) is constant.
      expect((await attempt(`10.0.0.${i}`)).status).toBe(401);
    }
    expect((await attempt('10.0.0.99')).status).toBe(429); // still throttled
  });

  it('keys separately per real client when the edge reports different hops', async () => {
    const { app } = await boot();
    const from = (real: string) =>
      app.request('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-forwarded-for': `10.0.0.1, ${real}` },
        body: JSON.stringify(creds),
      });
    for (let i = 0; i < 10; i++) expect((await from('203.0.113.1')).status).toBe(401);
    expect((await from('203.0.113.1')).status).toBe(429);
    expect((await from('203.0.113.2')).status).toBe(401); // a different real client is unaffected
  });
});
