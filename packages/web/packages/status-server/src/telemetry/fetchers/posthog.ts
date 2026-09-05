import type { Fetcher, FetchResult } from "../ports";
import type { AnalyticsMetricDTO } from "../types";

// PostHog adapter for the Fetcher port. Headline KPIs via PostHog's HogQL query
// API — anonymous + aggregate only, matching the privacy-first capture (no person
// data ever leaves PostHog into here). PURE w.r.t. storage. No-ops (ok, []) until
// POSTHOG_HOST/_API_KEY/_PROJECT_ID are configured.
//
// NOTE: verify the query-API shape against your PostHog project when live —
// POST {host}/api/projects/{id}/query/ with a HogQL query returns
// { results: [[value]] }.

export interface PosthogEnv {
  POSTHOG_HOST?: string;
  POSTHOG_API_KEY?: string;
  POSTHOG_PROJECT_ID?: string;
}

interface QueryResult {
  results?: unknown[][];
}

interface MetricSpec {
  metric: string;
  window: string;
  days: number;
  distinct: boolean;
}

const METRICS: MetricSpec[] = [
  { metric: "pageviews", window: "24h", days: 1, distinct: false },
  { metric: "visitors", window: "24h", days: 1, distinct: true },
  { metric: "pageviews", window: "7d", days: 7, distinct: false },
  { metric: "visitors", window: "7d", days: 7, distinct: true },
];

// Each query owns its OWN timeout budget (not one shared across the batch): a
// single slow query times out on its own without hanging the batch. Failures are
// RETURNED (not logged here) so the batch can short-circuit and log ONE concise
// line — per-query logging turned a degraded provider into four lines per poll.
const QUERY_TIMEOUT_MS = 10_000;

async function hogql(
  host: string,
  projectId: string,
  apiKey: string,
  query: string,
): Promise<{ value: number | null; error: string | null }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), QUERY_TIMEOUT_MS);
  try {
    const res = await fetch(`${host.replace(/\/+$/, "")}/api/projects/${projectId}/query/`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query: { kind: "HogQLQuery", query } }),
      signal: controller.signal,
    });
    if (!res.ok) return { value: null, error: `HTTP ${res.status}` };
    const body = (await res.json()) as QueryResult;
    const v = body.results?.[0]?.[0];
    if (typeof v === "number") return { value: v, error: null };
    if (typeof v === "string") return { value: Number(v) || 0, error: null };
    return { value: null, error: null };
  } catch (err) {
    return { value: null, error: err instanceof Error ? err.message : String(err) };
  } finally {
    clearTimeout(timer);
  }
}

export function posthogFetcher(env: PosthogEnv): Fetcher<AnalyticsMetricDTO> {
  return {
    async fetch(): Promise<FetchResult<AnalyticsMetricDTO>> {
      const { POSTHOG_HOST, POSTHOG_API_KEY, POSTHOG_PROJECT_ID } = env;
      if (!POSTHOG_HOST || !POSTHOG_API_KEY || !POSTHOG_PROJECT_ID) return { ok: true, items: [] };

      const capturedAt = new Date().toISOString();
      const items: AnalyticsMetricDTO[] = [];
      // Sequential (not Promise.all) to stay gentle on the HogQL API — it 503s
      // under concurrent load. A SINGLE failure short-circuits the batch: a
      // provider that timed out / errored on one query does the same on the next
      // three (paying 4× the timeout and logging four lines); the queries already
      // answered are kept, the rest retry on the next poll. ONE concise log line.
      let failure: string | null = null;
      for (const m of METRICS) {
        // visitors is approximate under cookieless capture (distinct id resets
        // per session) — a deliberate trade for not tracking people across sessions.
        const select = m.distinct ? "count(DISTINCT person_id)" : "count()";
        const query = `SELECT ${select} FROM events WHERE event = '$pageview' AND timestamp > now() - INTERVAL ${m.days} DAY`;
        const { value, error } = await hogql(POSTHOG_HOST, POSTHOG_PROJECT_ID, POSTHOG_API_KEY, query);
        if (error) {
          failure = error;
          break;
        }
        if (value !== null) items.push({ metric: m.metric, window: m.window, scope: "all", value, capturedAt });
      }
      if (failure) console.warn(`[telemetry] PostHog poll failed (${failure}) — ${items.length}/${METRICS.length} queries answered`);
      // Persist whatever succeeded; only an all-failed batch is ok:false so a
      // total outage never overwrites good trend data with an empty set.
      if (items.length === 0) return { ok: false, items: [] };
      return { ok: true, items };
    },
  };
}
