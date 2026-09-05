import { sql } from "drizzle-orm";
import type { Db } from "../client";
import type { BadRunOnsetRow, HealthStore, LatestCheckRow } from "../../storage/ports";

// ---------------------------------------------------------------------------
// The libSQL implementation of `HealthStore`. Bodies moved verbatim from the
// pre-port `src/storage/health-store.ts`; the raw SQL and its sargability /
// tiebreak rationale are unchanged, only wrapped as methods over a `db` closure
// instead of exported SQL-builder functions a caller had to `db.all(...)` itself.
// ---------------------------------------------------------------------------

/**
 * The latest-check-per-slug read. THE ONLY WAY anything reads "the current
 * health of these endpoints" — the board fold (`readEndpointFacts`) and every route
 * read (`latestCheckBySlug` in `routes/reads.ts`) both go through this one statement,
 * so `/live` and the board can never disagree about which probe is the newest.
 *
 * This must stay O(slugs · log rows): ONE backward covering seek per requested slug
 * on `idx_health_service_checked` — `id` is the rowid tail of that index, so the
 * `checked_at desc, id desc` tiebreak rides the index order with no sort. Driven
 * from the caller's ACTIVE slug list. The previous form — `row_number() over
 * (partition by service_slug ...)` with no predicate — walked EVERY historical row
 * of health_checks on EVERY board read, SSE publish, and the unauthenticated status
 * summary; against the multi-million-row backlog that made each request take seconds
 * and a fresh login (which fans out into several of these) feel minutes-long. Same
 * unbounded-table × per-request-cost class as the rollup bug (rollupMetricsSql) —
 * keep the read anchored to index seeks.
 *
 * The `checked_at desc, id desc` tiebreak is also the CORRECTNESS half. `checked_at` is
 * whole seconds, so two probes for one slug in the same second (a manual re-probe
 * overlapping a cycle) are a real tie. The board used to resolve that tie with SQLite's
 * bare-column rule under `max(checked_at)`, which is documented as ARBITRARY among tied
 * rows — so `/live` could say `healthy` while the board derived `down` from the other
 * row of the same pair. One statement, one tiebreak: the later INSERT wins, everywhere.
 */
export function latestCheckBySlugSql(slugs: string[]) {
  return sql`
    select hc.service_slug, hc.status, hc.response_time_ms, hc.status_code, hc.error, hc.checked_at, hc.dns_ok
    from json_each(${JSON.stringify(slugs)}) as slug_list
    join health_checks hc on hc.id = (
      select id from health_checks
      where service_slug = slug_list.value
      order by checked_at desc, id desc
      limit 1
    )
  `;
}

/**
 * The onset of each slug's CURRENT unbroken bad run — the oldest check newer than that
 * slug's last healthy one — for every slug given, in ONE statement. This is where
 * "down since" comes from, and the reason it survives a browser reload.
 *
 * ONE statement for N slugs, not N statements: the board fold ran this per bad endpoint,
 * sequentially awaited, so a fleet-wide outage (the moment the board matters most) cost one
 * serial round trip per down site on every board read, SSE publish and status summary. The
 * shape is unchanged — a correlated `max(checked_at)` over the healthy rows, seeking
 * `idx_health_service_checked` per slug exactly as before — only the trip count is.
 *
 * A slug with NO healthy check ever falls back to the `coalesce(..., 0)` floor, so its run
 * starts at its first check. A slug whose rows are all healthy contributes no row at all,
 * and the caller falls back to the check's own timestamp.
 */
function badRunOnsetBySlugSql(slugs: string[]) {
  return sql`
    select hc.service_slug as service_slug, min(hc.checked_at) as since
    from json_each(${JSON.stringify(slugs)}) as slug_list
    join health_checks hc on hc.service_slug = slug_list.value
    where hc.checked_at > coalesce((
      select max(h2.checked_at) from health_checks h2
      where h2.service_slug = slug_list.value and h2.status not in ('down','degraded')
    ), 0)
    group by hc.service_slug
  `;
}

/** Build the `HealthStore` port over one connection. */
export function createHealthStore(db: Db): HealthStore {
  return {
    latestChecks(slugs: string[]): Promise<LatestCheckRow[]> {
      return db.all<LatestCheckRow>(latestCheckBySlugSql(slugs));
    },

    badRunOnsets(slugs: string[]): Promise<BadRunOnsetRow[]> {
      return db.all<BadRunOnsetRow>(badRunOnsetBySlugSql(slugs));
    },
  };
}
