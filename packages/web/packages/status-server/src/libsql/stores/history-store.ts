import { and, eq, gte, sql } from "drizzle-orm";
import type { Db } from "../client";
import { healthChecks } from "../schema";
import type { DailyCountsRow, HistoryCheckRow, HistoryStore } from "../../storage/ports";

// The libSQL implementation of `HistoryStore`. Bodies moved verbatim from
// `routes/reads.ts` — see there for the reasoning behind the two query shapes
// `responseBuckets` picks between.

export function createHistoryStore(db: Db): HistoryStore {
  return {
    /** The newest checked_at across ALL history (one MAX index seek on
     *  idx_health_checked) — the poller's "last ran" clock, deliberately reading the
     *  whole table rather than any active-slug subset (see `routes/reads.ts`'s
     *  original doc comment on this query for why). */
    async newestCheckAt(): Promise<Date | null> {
      const rows = await db.all<{ last: number | null }>(sql`select max(checked_at) as last from health_checks`);
      const last = rows[0]?.last;
      return last == null ? null : new Date(Number(last) * 1000);
    },

    /** One endpoint's health-check samples within the last `hours`, ascending. */
    async checksFor(slug: string, hours: number): Promise<HistoryCheckRow[]> {
      const cutoff = new Date(Date.now() - hours * 3_600_000);
      return db
        .select({
          status: healthChecks.status,
          responseTimeMs: healthChecks.responseTimeMs,
          statusCode: healthChecks.statusCode,
          error: healthChecks.error,
          checkedAt: healthChecks.checkedAt,
        })
        .from(healthChecks)
        .where(and(eq(healthChecks.serviceSlug, slug), gte(healthChecks.checkedAt, cutoff)))
        .orderBy(healthChecks.checkedAt);
    },

    /** One endpoint's per-UTC-day check counts over the last `days`, ascending. */
    async dailyCounts(slug: string, days: number): Promise<DailyCountsRow[]> {
      const cutoff = new Date(Date.now() - days * 86_400_000);
      const rows = await db.all<{
        day: string;
        total: number;
        healthy: number;
        degraded: number;
        down: number;
      }>(sql`
        select
          strftime('%Y-%m-%d', checked_at, 'unixepoch') as day,
          count(*) as total,
          sum(case when status = 'healthy' then 1 else 0 end) as healthy,
          sum(case when status = 'degraded' then 1 else 0 end) as degraded,
          sum(case when status = 'down' then 1 else 0 end) as down
        from health_checks
        where service_slug = ${slug} and checked_at >= ${Math.floor(cutoff.getTime() / 1000)}
        group by day
        order by day asc
      `);
      return rows.map((r) => ({
        day: r.day,
        total: Number(r.total),
        healthy: Number(r.healthy),
        degraded: Number(r.degraded),
        down: Number(r.down),
      }));
    },

    /** Portfolio-wide response-time sparkline: `buckets` buckets over the last `hours`
     *  (oldest → newest), each the avg response of UP checks, null where no data. See
     *  `routes/reads.ts`'s original doc comment for why the source depends on the window. */
    async responseBuckets(hours: number, buckets: number): Promise<(number | null)[]> {
      const nowMs = Date.now();
      const spanMs = hours * 3_600_000;
      const bucketMs = Math.max(1, Math.round(spanMs / buckets));
      const cutoff = Math.floor((nowMs - spanMs) / 1000);
      const nowSec = Math.floor(nowMs / 1000);

      if (bucketMs >= 3_600_000) {
        const rows = await db.all<{ hour: number; ups: number; weighted: number }>(sql`
          select hour,
                 sum(case when avg_response_time_ms is not null then healthy_checks + degraded_checks else 0 end) as ups,
                 sum(case when avg_response_time_ms is not null then avg_response_time_ms * (healthy_checks + degraded_checks) else 0 end) as weighted
          from metrics_hourly
          where hour > ${cutoff} and hour <= ${nowSec}
          group by hour
        `);
        const sums = new Array<number>(buckets).fill(0);
        const counts = new Array<number>(buckets).fill(0);
        for (const r of rows) {
          const idx = Math.min(buckets - 1, Math.floor((nowMs - Number(r.hour) * 1000) / bucketMs));
          sums[idx]! += Number(r.weighted);
          counts[idx]! += Number(r.ups);
        }
        return Array.from({ length: buckets }, (_, i) => {
          const b = buckets - 1 - i;
          return counts[b]! > 0 ? Math.round(sums[b]! / counts[b]!) : null;
        });
      }

      const rows = await db.all<{ bucket: number; s: number; n: number }>(sql`
        select min(cast((${nowMs} - checked_at * 1000) / ${bucketMs} as integer), ${buckets - 1}) as bucket,
               sum(response_time_ms) as s, count(*) as n
        from health_checks
        where checked_at > ${cutoff}
          and checked_at <= ${nowSec}
          and status in ('healthy', 'degraded')
          and response_time_ms is not null
        group by bucket
      `);
      const byBucket = new Map(rows.map((r) => [Number(r.bucket), { s: Number(r.s), n: Number(r.n) }]));
      return Array.from({ length: buckets }, (_, i) => {
        const r = byBucket.get(buckets - 1 - i);
        return r ? Math.round(r.s / r.n) : null;
      });
    },
  };
}
