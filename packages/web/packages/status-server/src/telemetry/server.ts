import type { Db } from "../libsql/client";
import type { StatusConfig } from "../config/port";
import { glitchtipConfigured, posthogConfigured } from "../config/port";
import { recordPlatformObservations } from "../monitor/observations";
import { collect } from "./collect";
import { glitchtipFetcher } from "./fetchers/glitchtip";
import { posthogFetcher } from "./fetchers/posthog";
import { errorsStore } from "./stores/errors";
import { analyticsStore } from "./stores/analytics";
import type { Fetcher } from "./ports";
import type { AnalyticsMetricDTO, ErrorDTO } from "./types";

// THE server composition root — the single place that picks which provider feeds
// each stream and which store persists/serves it. Swap a store here and every
// trigger (the scheduler cycle) and read route that uses it follows; nothing else
// changes. Server-only: imported by routes + the scheduler cycle, never by client
// code (the stores pull in the db schema).

/** Build the errors-stream fetcher from the given config — no module-level env
 *  snapshot, so a test (or a config change) is never stuck with a fetcher built
 *  from whatever the environment held at import time. */
export function buildErrorsFetcher(config: StatusConfig): Fetcher<ErrorDTO> {
  return glitchtipFetcher({
    GLITCHTIP_URL: config.credentials.GLITCHTIP_URL,
    GLITCHTIP_API_TOKEN: config.credentials.GLITCHTIP_API_TOKEN,
    GLITCHTIP_ORG: config.credentials.GLITCHTIP_ORG,
  });
}

/** Build the analytics-stream fetcher from the given config — see {@link buildErrorsFetcher}. */
export function buildAnalyticsFetcher(config: StatusConfig): Fetcher<AnalyticsMetricDTO> {
  return posthogFetcher({
    POSTHOG_HOST: config.credentials.POSTHOG_HOST,
    POSTHOG_API_KEY: config.credentials.POSTHOG_API_KEY,
    POSTHOG_PROJECT_ID: config.credentials.POSTHOG_PROJECT_ID,
  });
}

// The stores take the db handle as a parameter (this backend has no db
// singleton) — the routes/scheduler pass it in. Re-exported for the read routes.
export { errorsStore, analyticsStore };

/** The in-process replacement for the old /api/cron/errors + /api/cron/analytics
 *  Vercel crons: poll each configured provider and persist into the SQLite trend
 *  store. GUARDED (skips a provider whose credentials are unset) + fail-soft (each
 *  in its own try/catch) so a provider outage can never abort the scheduler cycle. */
export async function collectTelemetry(db: Db, config: StatusConfig): Promise<void> {
  const gtConfigured = glitchtipConfigured(config);
  const errorsFetcher = buildErrorsFetcher(config);
  const analyticsFetcher = buildAnalyticsFetcher(config);
  // Poll the providers CONCURRENTLY, each independently fail-soft. Serially, the
  // cycle paid the SUM of both providers' timeouts — which, stacked on the deploy
  // polls, helped blow the scheduler's cycle budget and trigger container restarts.
  // Each still swallows its own error so one provider's outage can't abort the other.
  const [errorsReachable] = await Promise.all([
    gtConfigured
      ? collect(errorsFetcher, errorsStore, db)
          .then((r) => r.ok)
          .catch((err) => {
            console.error("[telemetry] errors collection failed", err);
            return false;
          })
      : // Unconfigured is not unreachable — nothing was asked, so nothing failed. Matches
        // `sync.ts`, where a tokenless deploy fetcher returns ok:true and is recorded
        // `configured:false, reachable:true`.
        Promise.resolve(true),
    posthogConfigured(config)
      ? collect(analyticsFetcher, analyticsStore, db).catch((err) =>
          console.error("[telemetry] analytics collection failed", err),
        )
      : Promise.resolve(),
  ]);

  // GlitchTip gets a platform-health row exactly as the four deploy platforms do, and it
  // is what makes the error rule honest about its own blindness. A failed poll persists
  // NOTHING (`collect`), so from the `errors` table alone an outage is indistinguishable
  // from a fleet that stopped erroring: every row's `last_seen` simply stops advancing,
  // and 24h later the fold's recency window would drop them all and page an all-clear.
  // Recording the blind spot here gives `platformProblems` its usual debounced
  // "GlitchTip API unreachable" row for free, and gives `errorProblems` the flag it needs
  // to FREEZE its rows instead of falsely recovering them.
  //
  // Recorded UNCONDITIONALLY, including when unconfigured: the row's `configured` column
  // is how the fold learns the feature is off, and an absent row would leave a stale
  // `configured:true` behind after the env var was removed.
  //
  // Fail-soft like everything else in this cycle — a write that throws must not abort it.
  try {
    await recordPlatformObservations(db, [
      { source: "glitchtip", configured: gtConfigured, reachable: errorsReachable },
    ]);
  } catch (err) {
    console.error("[telemetry] recording GlitchTip platform health failed", err);
  }
}
