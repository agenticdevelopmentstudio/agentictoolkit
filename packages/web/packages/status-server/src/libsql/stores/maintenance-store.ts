import { promises as fs } from "node:fs";
import path from "node:path";
import { sql, type SQL } from "drizzle-orm";
import { checkpointWal, type Db, type LibsqlConnection } from "../client";
import { siteGroups } from "../schema";
import type { MaintenanceStore, SnapshotOptions } from "../../storage/ports";

// ---------------------------------------------------------------------------
// The libSQL implementation of `MaintenanceStore` — rollup, retention prune, WAL
// checkpoint and on-volume snapshot. Bodies moved verbatim from `monitor/sync.ts`
// (rollup + prune) and `monitor/db-snapshot.ts` (snapshot); see those files'
// history for the per-statement rationale (sargability, chunking, fail-soft).
// ---------------------------------------------------------------------------

/**
 * The per-tick `metrics_hourly` upsert, as SQL. Exported so the test can EXPLAIN the
 * REAL statement (see rollup-metrics.int.test.ts) rather than a copy that could drift.
 *
 * The hour predicate must stay a RANGE OVER THE BARE COLUMN — see the original comment
 * in `monitor/sync.ts` git history for the sargability regression this guards against.
 */
export function rollupMetricsSql(serviceSlugs: string[]): SQL {
  return sql`
    insert into metrics_hourly (
      service_slug, hour, total_checks, healthy_checks, degraded_checks,
      down_checks, avg_response_time_ms, min_response_time_ms, max_response_time_ms
    )
    select
      service_slug,
      (checked_at / 3600) * 3600 as hour,
      count(*),
      sum(case when status = 'healthy' then 1 else 0 end),
      sum(case when status = 'degraded' then 1 else 0 end),
      sum(case when status = 'down' then 1 else 0 end),
      avg(response_time_ms),
      min(response_time_ms),
      max(response_time_ms)
    from health_checks
    where service_slug in (${sql.join(serviceSlugs, sql`, `)})
      and checked_at >= (unixepoch() / 3600) * 3600
      and checked_at < (unixepoch() / 3600) * 3600 + 3600
    group by service_slug, hour
    on conflict(service_slug, hour) do update set
      total_checks = excluded.total_checks,
      healthy_checks = excluded.healthy_checks,
      degraded_checks = excluded.degraded_checks,
      down_checks = excluded.down_checks,
      avg_response_time_ms = excluded.avg_response_time_ms,
      min_response_time_ms = excluded.min_response_time_ms,
      max_response_time_ms = excluded.max_response_time_ms
  `;
}

/** Rows deleted per DELETE statement, and per `runMaintenance` call. Chunked so the
 *  prune is many small transactions instead of one enormous one. */
const PRUNE_CHUNK_ROWS = 25_000;
const PRUNE_MAX_ROWS_PER_RUN = 100_000;

/** metrics_hourly horizon: /response-history serves sparklines up to 90 days, so
 *  keep at least that — longer when a group's configured retention exceeds it. */
const METRICS_MIN_RETENTION_DAYS = 90;
/** analytics_metrics horizon: the trend store is only ever read as "the newest
 *  rows", so 90 days is already generous. */
const ANALYTICS_RETENTION_DAYS = 90;
/** RESOLVED issues horizon — closed incidents are kept as history but bounded
 *  like every other accruing table. Open issues are untouched. */
const ISSUE_RESOLVED_RETENTION_DAYS = 90;

/** One table's chunked age prune: delete rows whose `timeCol` is before
 *  `cutoffSec`, by id from an indexed seek, at most `budget` rows in chunks of
 *  `chunkRows`. `done` is false when the budget ran out with backlog remaining. */
async function pruneChunked(
  db: Db,
  table: "health_checks" | "metrics_hourly" | "analytics_metrics" | "issues",
  timeCol: "checked_at" | "hour" | "captured_at" | "resolved_at",
  cutoffSec: number,
  chunkRows: number,
  budget: number,
): Promise<{ deleted: number; done: boolean }> {
  let deleted = 0;
  while (deleted < budget) {
    const limit = Math.min(chunkRows, budget - deleted);
    const res = await db.run(sql`
      delete from ${sql.raw(table)}
      where id in (select id from ${sql.raw(table)} where ${sql.raw(timeCol)} < ${cutoffSec} limit ${limit})
    `);
    const n = Number(res.rowsAffected ?? 0);
    deleted += n;
    if (n < limit) return { deleted, done: true }; // drained this table's backlog
  }
  return { deleted, done: false }; // budget exhausted; more next run
}

const SNAPSHOT_INTERVAL_MS = 24 * 3_600_000;
const SNAPSHOT_KEEP = 7;
const TMP_SWEEP_AGE_MS = 3_600_000;

/** Build the `MaintenanceStore` port over one connection. `conn` is OPTIONAL: the monitor
 *  cycle (which owns the connection) passes it so WAL truncation and VACUUM INTO can run;
 *  a host with no live connection (e.g. `POST /cron/maintenance`'s AppDeps) gets the prune
 *  with the checkpoint skipped, and snapshotting simply refuses (no connection to vacuum). */
export function createMaintenanceStore(db: Db, conn?: LibsqlConnection): MaintenanceStore {
  return {
    /** Roll up `metrics_hourly` for the hour buckets touched by this cycle's checks.
     *  Recomputes each (service, hour) bucket from `health_checks` and upserts it, so
     *  reruns are idempotent. */
    async rollupMetrics(serviceSlugs: string[]): Promise<void> {
      const slugs = [...new Set(serviceSlugs)];
      if (slugs.length === 0) return;
      await db.run(rollupMetricsSql(slugs));
    },

    /**
     * Retention prune over EVERY accruing table — an unpruned table is a future
     * CPU/disk bomb. `conn` (if given) also runs the post-prune WAL checkpoint, so the
     * volume gets back the space the sweep's own write transaction inflated.
     */
    async runMaintenance(
      opts: { maxRows?: number; chunkRows?: number } = {},
    ): Promise<{ deleted: number; done: boolean }> {
      const maxRows = opts.maxRows ?? PRUNE_MAX_ROWS_PER_RUN;
      const chunkRows = opts.chunkRows ?? PRUNE_CHUNK_ROWS;

      const groups = await db.select({ retentionDays: siteGroups.retentionDays }).from(siteGroups);
      // The conservative horizon: keep checks at least as long as the LONGEST
      // configured retention.
      const maxRetentionDays = groups.reduce((max, g) => Math.max(max, g.retentionDays), 14);
      const nowSec = Math.floor(Date.now() / 1000);

      const sweeps = [
        { table: "health_checks", timeCol: "checked_at", cutoffSec: nowSec - maxRetentionDays * 86_400 },
        {
          table: "metrics_hourly",
          timeCol: "hour",
          cutoffSec: nowSec - Math.max(METRICS_MIN_RETENTION_DAYS, maxRetentionDays) * 86_400,
        },
        { table: "analytics_metrics", timeCol: "captured_at", cutoffSec: nowSec - ANALYTICS_RETENTION_DAYS * 86_400 },
        // Only CLOSED incidents age out — an open issue has a NULL resolved_at, which no
        // `<` comparison ever selects.
        { table: "issues", timeCol: "resolved_at", cutoffSec: nowSec - ISSUE_RESOLVED_RETENTION_DAYS * 86_400 },
      ] as const;

      let deleted = 0;
      let done = true;
      for (const s of sweeps) {
        const budget = maxRows - deleted;
        if (budget <= 0) {
          done = false; // budget exhausted before this table got a turn
          break;
        }
        const r = await pruneChunked(db, s.table, s.timeCol, s.cutoffSec, chunkRows, budget);
        deleted += r.deleted;
        if (!r.done) {
          done = false;
          break;
        }
      }

      // Expired sessions: a tiny table (rows = logins), so one unchunked statement
      // outside the budget.
      const reaped = await db.run(sql`delete from sessions where expires_at < ${nowSec}`);
      deleted += Number(reaped.rowsAffected ?? 0);

      // Pruning rows frees PAGES, not BYTES — truncate the WAL immediately after the sweep
      // that grew it, so the volume gets the space back. Fail-soft: a busy checkpoint just
      // retries next pass; a throw must not lose the prune result already earned.
      if (conn) {
        try {
          await checkpointWal(db, conn);
        } catch (err) {
          console.error(`[maintenance] wal checkpoint failed: ${err instanceof Error ? err.message : String(err)}`);
        }
      }

      return { deleted, done };
    },

    /** Snapshot the embedded DB if the interval has lapsed. Fail-soft: any error is
     *  logged and swallowed — a failing backup must never fail the cycle. Uses the
     *  connection this store was built with unless `opts.dbUrl` overrides it (tests
     *  only) — the host never has to thread its own connection url through. */
    async snapshotIfDue(opts: SnapshotOptions = {}): Promise<{ created: boolean; path?: string }> {
      const url = opts.dbUrl ?? conn?.url;
      if (!url || !url.startsWith("file:")) return { created: false }; // remote/memory DBs manage their own durability
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
    },
  };
}
