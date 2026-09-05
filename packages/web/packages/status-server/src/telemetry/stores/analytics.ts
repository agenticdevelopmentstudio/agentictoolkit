import { desc } from "drizzle-orm";
import type { Db } from "../../libsql/client";
import { analyticsMetrics } from "../../libsql/schema";
import type { Store } from "../ports";
import type { AnalyticsMetricDTO } from "../types";

// SQLite/libSQL adapter of Store<AnalyticsMetricDTO> over the `analytics_metrics`
// table. Append-only — one row per (metric, window, scope) per poll — so the
// table is a trend store; `load` reduces a recent slice to the latest value per
// series. Takes the db handle explicitly (this backend has no db singleton).

export const analyticsStore: Store<AnalyticsMetricDTO> = {
  async save(db: Db, items: AnalyticsMetricDTO[]): Promise<void> {
    if (items.length === 0) return;
    await db.insert(analyticsMetrics).values(
      items.map((i) => ({
        metric: i.metric,
        window: i.window,
        scope: i.scope,
        value: i.value,
        capturedAt: new Date(i.capturedAt),
      })),
    );
  },

  async load(db: Db): Promise<AnalyticsMetricDTO[]> {
    const rows = await db
      .select()
      .from(analyticsMetrics)
      .orderBy(desc(analyticsMetrics.capturedAt))
      .limit(100);

    // Reduce to the latest snapshot per (metric, window, scope).
    const latest = new Map<string, typeof analyticsMetrics.$inferSelect>();
    for (const r of rows) {
      const key = `${r.metric}|${r.window}|${r.scope}`;
      if (!latest.has(key)) latest.set(key, r);
    }
    return Array.from(latest.values()).map((r) => ({
      metric: r.metric,
      window: r.window,
      scope: r.scope,
      value: r.value,
      capturedAt: r.capturedAt.toISOString(),
    }));
  },
};
