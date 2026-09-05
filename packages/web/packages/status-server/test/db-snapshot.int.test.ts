import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import { maybeSnapshotDb } from '../src/monitor/db-snapshot';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';

// The SQLite file on the single Railway volume is a single point of data loss —
// all hand-entered config (groups, sites, endpoints, integrations, users) lives
// in it with no backup of any kind. The maintenance phase now VACUUMs a
// consistent snapshot beside the DB (rotated), so a corrupted/lost live file
// can be restored from the volume; off-volume replication is the next layer.

let dir: string;
let db: Db;
let dbPath: string;

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'snap-'));
  dbPath = path.join(dir, 'status.db');
  db = drizzle(createClient({ url: `file:${dbPath}` }), { schema });
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  await db.insert(schema.siteGroups).values({ slug: 'g', name: 'Precious Config' });
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const listSnapshots = (): string[] =>
  readdirSync(path.join(dir, 'backups')).filter((f) => f.startsWith('status-') && f.endsWith('.db'));

describe('maybeSnapshotDb', () => {
  it('creates a restorable snapshot, then skips until the interval lapses', async () => {
    const t0 = Date.now();
    const first = await maybeSnapshotDb(db, { dbUrl: `file:${dbPath}`, now: () => t0 });
    expect(first.created).toBe(true);
    expect(listSnapshots()).toHaveLength(1);

    // Within the interval → no second snapshot.
    const again = await maybeSnapshotDb(db, { dbUrl: `file:${dbPath}`, now: () => t0 + 60_000 });
    expect(again.created).toBe(false);
    expect(listSnapshots()).toHaveLength(1);

    // The snapshot is a REAL database: open it and read the seeded config back.
    const snapPath = path.join(dir, 'backups', listSnapshots()[0]!);
    const restored = drizzle(createClient({ url: `file:${snapPath}` }), { schema });
    const groups = await restored.select().from(schema.siteGroups);
    expect(groups[0]?.name).toBe('Precious Config');
  });

  it('rotates: keeps only the newest N snapshots', async () => {
    const t0 = Date.now();
    // A day + an hour per step: comfortably past the interval (the gate compares
    // the injected clock against REAL file mtimes, so exact-boundary steps are
    // off by the milliseconds the test itself takes).
    const step = 25 * 3_600_000;
    for (let i = 0; i < 3; i++) {
      const res = await maybeSnapshotDb(db, { dbUrl: `file:${dbPath}`, now: () => t0 + i * step, keep: 2 });
      expect(res.created).toBe(true);
    }
    expect(listSnapshots()).toHaveLength(2);
  });

  it('is a no-op for non-file databases', async () => {
    const mem = drizzle(createClient({ url: ':memory:' }), { schema });
    const res = await maybeSnapshotDb(mem, { dbUrl: ':memory:' });
    expect(res.created).toBe(false);
  });
});
