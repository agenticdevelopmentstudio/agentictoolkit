import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/libsql";
import type { LibSQLDatabase } from "drizzle-orm/libsql";
import { migrate } from "drizzle-orm/libsql/migrator";
import * as schema from "./schema";

// The libSQL/SQLite implementation of the server's storage. This subpath is the
// ONLY place that knows the driver, the schema and the migrations; a host opens a
// connection here and hands the resulting Db to createApp / the monitor.

export type Schema = typeof schema;
export type Db = LibSQLDatabase<Schema>;

/** Where the host's database lives. A `file:` URL is an embedded SQLite file (the
 *  default, cheapest mode); an https/libsql URL targets a remote libSQL/Turso. */
export interface LibsqlConnection {
  readonly url: string;
  readonly authToken?: string;
}

export function openLibsql(conn: LibsqlConnection): Db {
  if (!conn.url) throw new Error("libsql connection url is empty (e.g. file:./status.db)");
  return drizzle({ connection: { url: conn.url, authToken: conn.authToken }, schema });
}

/** Embedded-file connections are the ones we tune, checkpoint and snapshot;
 *  remote libsql/Turso manages its own journaling and durability. */
export function isEmbeddedFile(conn: LibsqlConnection): boolean {
  return conn.url.startsWith("file:");
}

/** Tune an embedded-file connection for MULTI-CONNECTION access — the API server
 *  and the monitor worker each hold their own connection to the same file. WAL
 *  lets the worker write while the server reads (and vice versa) instead of the
 *  default rollback journal's whole-file locking; busy_timeout makes a second
 *  writer WAIT (up to 5s) instead of failing SQLITE_BUSY on contention. WAL is a
 *  persistent property of the DB file, so re-applying it is a no-op. Remote
 *  libsql/Turso URLs manage their own journaling — skipped. */
export async function tuneDbForConcurrency(db: Db, conn: LibsqlConnection): Promise<void> {
  if (!isEmbeddedFile(conn)) return;
  await db.run(sql`PRAGMA journal_mode = WAL`);
  await db.run(sql`PRAGMA busy_timeout = 5000`);
  // NORMAL is the recommended pairing with WAL: fsync on checkpoint, not per-commit —
  // durable against app crashes (the monitor's write volume) without per-insert fsyncs.
  await db.run(sql`PRAGMA synchronous = NORMAL`);
}

/** Reclaim the WAL sidecar's disk footprint.
 *
 *  A checkpointed WAL is REUSED from the start, never shrunk, so the largest write
 *  transaction the process has ever run sets a high-water mark the file keeps forever.
 *  The retention sweep deleting from a multi-million-row health_checks is that
 *  transaction: prod's status.db-wal sat at 137MB while holding 12 live frames, and
 *  `wal_autocheckpoint` (the default 1000 pages, verified in force) can never fix it —
 *  autocheckpoint runs the PASSIVE mode, which resets the WAL without truncating.
 *  TRUNCATE is the only mode that returns the space to the volume.
 *
 *  Fail-soft by design: `busy` means a reader still held the old WAL (the API server
 *  holds its own connection), the DB is untouched, and the next maintenance pass tries
 *  again. Embedded-file DBs only — remote libsql/Turso manages its own storage. */
export async function checkpointWal(db: Db, conn: LibsqlConnection): Promise<{ busy: boolean; frames: number } | null> {
  if (!isEmbeddedFile(conn)) return null;
  const res = await db.run(sql`PRAGMA wal_checkpoint(TRUNCATE)`);
  const row = res.rows[0] as Record<string, unknown> | undefined;
  return { busy: Number(row?.busy ?? 0) === 1, frames: Number(row?.checkpointed ?? 0) };
}

/** This package's own root directory, found through Node's package self-reference so
 *  it is right from `src/` (tsx, vitest), from `dist/` (whatever chunk tsup put this
 *  code in) and from a host's vendored copy under node_modules. */
function packageRoot(): string {
  const require = createRequire(import.meta.url);
  return dirname(require.resolve("@agentic-toolkit/status-server/package.json"));
}

/** The migrations this package ships. They are applied in production already and
 *  are immutable: never edit one, only add. The host applies them on boot. */
export const MIGRATIONS_FOLDER = join(packageRoot(), "src", "libsql", "migrations");

/** Apply pending migrations. Run on boot for embedded-file deployments and from the
 *  host's deploy-time migrate step. Idempotent: drizzle records each applied
 *  migration in `__drizzle_migrations` and skips it afterwards. */
export async function migrateDb(db: Db, migrationsFolder: string = MIGRATIONS_FOLDER): Promise<void> {
  await migrate(db, { migrationsFolder });
}
