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

describe('/fleet', () => {
  let app: ReturnType<typeof createApp>;
  let viewAuth: { Cookie: string };

  beforeAll(async () => {
    const db: Db = drizzle(createClient({ url: ':memory:' }), { schema });
    await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
    viewAuth = await sessionHeaders(db, 'viewer');
    const p = (await db.insert(schema.peers).values({ label: 'B', baseUrl: 'https://b.example.com' }).returning())[0];
    await db.insert(schema.peerSnapshots).values({ peerId: p!.id, overall: 'down', reachable: true, payload: { overall: 'down' } });
    // A deactivated peer that still has a snapshot on file — nobody polls it any more,
    // so that snapshot is frozen and must not be drawn on the board.
    const off = (
      await db
        .insert(schema.peers)
        .values({ label: 'Off', baseUrl: 'https://off.example.com', isActive: false })
        .returning()
    )[0];
    await db.insert(schema.peerSnapshots).values({ peerId: off!.id, overall: 'ok', reachable: true, payload: { overall: 'ok' } });
    app = createApp({ db, config: testConfig() });
  });

  it('returns self + peer members', async () => {
    const res = await app.request('/fleet', { headers: viewAuth });
    expect(res.status).toBe(200);
    const members = (await res.json()) as Array<{ self: boolean; overall: string | null }>;
    expect(members.some((m) => m.self)).toBe(true);
    expect(members.some((m) => !m.self && m.overall === 'down')).toBe(true);
  });

  it('omits inactive peers — an unpolled peer must not show a frozen card', async () => {
    const res = await app.request('/fleet', { headers: viewAuth });
    const members = (await res.json()) as Array<{ self: boolean; label: string }>;
    expect(members.map((m) => m.label)).not.toContain('Off');
  });

  it('401 without a token', async () => {
    expect((await app.request('/fleet')).status).toBe(401);
  });
});
