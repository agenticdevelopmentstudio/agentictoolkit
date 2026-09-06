import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from '../src/libsql/schema';
import type { Db } from '../src/libsql/client';
import { MIGRATIONS_FOLDER } from '../src/libsql/client';
import { createLibsqlStorage } from '../src/libsql';
import type { Storage } from '../src/storage/ports';

// The SQLite file on the single Railway volume is a single point of data loss —
// all hand-entered config (groups, sites, endpoints, integrations, users) lives
// in it with no backup of any kind. The maintenance phase now VACUUMs a
// consistent snapshot beside the DB (rotated), so a corrupted/lost live file
// can be restored from the volume; off-volume replication is the next layer.

let dir: string;
let db: Db;
let storage: Storage;
let dbPath: string;

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'snap-'));
  dbPath = path.join(dir, 'status.db');
  db = drizzle(createClient({ url: `file:${dbPath}` }), { schema });
  storage = createLibsqlStorage(db);
  await migrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  await db.insert(schema.siteGroups).values({ slug: 'g', name: 'Precious Config' });
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const listSnapshots = (): string[] =>
  readdirSync(path.join(dir, 'backups')).filter((f) => f.startsWith('status-') && f.endsWith('.db'));

describe('storage.maintenance.snapshotIfDue', () => {
  it('creates a restorable snapshot, then skips until the interval lapses', async () => {
    const t0 = Date.now();
    const first = await storage.maintenance.snapshotIfDue({ dbUrl: `file:${dbPath}`, now: () => t0 });
    expect(first.created).toBe(true);
    expect(listSnapshots()).toHaveLength(1);

    // Within the interval → no second snapshot.
    const again = await storage.maintenance.snapshotIfDue({ dbUrl: `file:${dbPath}`, now: () => t0 + 60_000 });
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
      const res = await storage.maintenance.snapshotIfDue({ dbUrl: `file:${dbPath}`, now: () => t0 + i * step, keep: 2 });
      expect(res.created).toBe(true);
    }
    expect(listSnapshots()).toHaveLength(2);
  });

  it('is a no-op for non-file databases', async () => {
    const mem = drizzle(createClient({ url: ':memory:' }), { schema });
    const memStorage = createLibsqlStorage(mem);
    const res = await memStorage.maintenance.snapshotIfDue({ dbUrl: ':memory:' });
    expect(res.created).toBe(false);
  });

  it('snapshots through the connection the storage was built with (no dbUrl override)', async () => {
    // The production wiring: the monitor cycle owns the connection descriptor and hands
    // it to `createLibsqlStorage(db, conn)`, and `snapshotIfDue` reads the file path
    // from it — the override the tests above pass is NOT the path prod takes.
    const wired = createLibsqlStorage(db, { url: `file:${dbPath}` });
    const res = await wired.maintenance.snapshotIfDue({ now: () => Date.now() });
    expect(res.created).toBe(true);
    expect(listSnapshots()).toHaveLength(1);
  });

  it('warns ONCE when the storage has no connection descriptor, so the silent skip is visible', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    try {
      // `storage` (from beforeEach) is built with no conn — the miswiring under test.
      expect((await storage.maintenance.snapshotIfDue()).created).toBe(false);
      expect((await storage.maintenance.snapshotIfDue()).created).toBe(false);
      expect(warn).toHaveBeenCalledTimes(1);
      expect(String(warn.mock.calls[0]?.[0])).toMatch(/without a connection descriptor/);
    } finally {
      warn.mockRestore();
    }
  });
});
