import { promises as fs } from "node:fs";
import path from "node:path";
import { sql } from "drizzle-orm";
import type { Db } from "../libsql/client";

// Periodic on-volume DB snapshots. The embedded SQLite file is a single point
// of data loss: ALL hand-entered config (groups, sites, endpoints,
// integrations, users) lives in it, with — until this — no backup of any kind.
// Each maintenance pass calls maybeSnapshotDb; once per interval it VACUUMs a
// consistent, compacted copy into <db-dir>/backups/ and rotates old ones.
//
// VACUUM INTO takes a transactional snapshot, so it's safe against the live
// writer. The copy is written to a .tmp name and renamed only on success — a
// snapshot killed mid-write (worker terminate, container restart) never counts
// as a backup, and the stale .tmp is swept on the next pass.
//
// Interval state is the newest snapshot file's mtime — stateless, so it
// survives restarts and needs no table. This protects against DB corruption
// and fat-fingered data loss; it does NOT protect against losing the volume
// itself (off-volume replication, e.g. Litestream → R2, is that next layer).

const SNAPSHOT_INTERVAL_MS = 24 * 3_600_000;
const SNAPSHOT_KEEP = 7;
const TMP_SWEEP_AGE_MS = 3_600_000;

export interface SnapshotOptions {
  dbUrl: string;
  intervalMs?: number;
  keep?: number;
  now?: () => number;
}

/** Snapshot the embedded DB if the interval has lapsed. Fail-soft: any error is
 *  logged and swallowed — a failing backup must never fail the cycle. `dbUrl` is
 *  the host's connection url (`conn.url`) — this module never reads env itself. */
export async function maybeSnapshotDb(db: Db, opts: SnapshotOptions): Promise<{ created: boolean; path?: string }> {
  const url = opts.dbUrl;
  if (!url.startsWith("file:")) return { created: false }; // remote/memory DBs manage their own durability
  const now = opts.now ?? Date.now;
  const intervalMs = opts.intervalMs ?? SNAPSHOT_INTERVAL_MS;
  const keep = opts.keep ?? SNAPSHOT_KEEP;
  const dbPath = url.slice("file:".length);
  const dir = path.join(path.dirname(path.resolve(dbPath)), "backups");

  try {
    await fs.mkdir(dir, { recursive: true });
    const entries = await fs.readdir(dir);

    // Sweep stale .tmp leftovers from a killed snapshot attempt.
    for (const f of entries.filter((f) => f.endsWith(".tmp"))) {
      const st = await fs.stat(path.join(dir, f)).catch(() => null);
      if (st && now() - st.mtimeMs > TMP_SWEEP_AGE_MS) await fs.unlink(path.join(dir, f)).catch(() => {});
    }

    const snapshots = entries.filter((f) => f.startsWith("status-") && f.endsWith(".db")).sort();
    if (snapshots.length > 0) {
      const newest = await fs.stat(path.join(dir, snapshots[snapshots.length - 1]!)).catch(() => null);
      if (newest && now() - newest.mtimeMs < intervalMs) return { created: false };
    }

    const stamp = new Date(now()).toISOString().replace(/[:.]/g, "-");
    const finalPath = path.join(dir, `status-${stamp}.db`);
    const tmpPath = `${finalPath}.tmp`;
    // The path is server-generated (no user input); escape quotes for the SQL literal.
    await db.run(sql.raw(`VACUUM INTO '${tmpPath.replaceAll("'", "''")}'`));
    await fs.rename(tmpPath, finalPath);

    // Rotate: keep the newest `keep` completed snapshots.
    const all = [...snapshots, path.basename(finalPath)].sort();
    for (const f of all.slice(0, Math.max(0, all.length - keep))) {
      await fs.unlink(path.join(dir, f)).catch(() => {});
    }

    console.log(`[snapshot] wrote ${finalPath}`);
    return { created: true, path: finalPath };
  } catch (err) {
    console.error(`[snapshot] failed: ${err instanceof Error ? err.message : String(err)}`);
    return { created: false };
  }
}
