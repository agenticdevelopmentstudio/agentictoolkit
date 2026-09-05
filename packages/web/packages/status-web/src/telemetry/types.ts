// The data contract for the telemetry subsystem — pure shapes with ZERO runtime
// dependencies (no db, no fetch, no react). Every fetcher, store, source, route
// and panel speaks in these DTOs, so the shape is defined in exactly one place
// and the same value flows whether it came from a live poll or the database.

/** One grouped error issue, as summarized by GlitchTip (Sentry-API-compatible). */
export interface ErrorDTO {
  /** Stable identity for keying (the GlitchTip issue id live; the DB row id from Turso). */
  id: string;
  /** GlitchTip issue id — stable across polls, the store's upsert key. */
  issueKey: string;
  project: string;
  title: string;
  culprit: string | null;
  level: string | null;
  count: number;
  userCount: number;
  firstSeen: string | null; // ISO
  lastSeen: string | null; // ISO
  permalink: string | null;
}

/** One headline analytics KPI sample — anonymous + aggregate (from PostHog). */
export interface AnalyticsMetricDTO {
  metric: string; // 'pageviews' | 'visitors'
  window: string; // '24h' | '7d'
  scope: string; // 'all' or a site slug
  value: number;
  capturedAt: string; // ISO
}

/** One self-contained read of everything the production-visibility band shows. */
export interface TelemetrySnapshot {
  generatedAt: string; // ISO
  errors: ErrorDTO[];
  analytics: AnalyticsMetricDTO[];
}

export function emptySnapshot(): TelemetrySnapshot {
  return { generatedAt: "", errors: [], analytics: [] };
}
