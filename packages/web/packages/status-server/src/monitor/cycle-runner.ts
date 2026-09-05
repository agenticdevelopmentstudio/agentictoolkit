import type { Db, LibsqlConnection } from "../libsql/client";
import type { StatusConfig } from "../config/port";
import { runCycle, runMaintenance } from "./sync";
import { fetchPeers } from "../peers/fetch";
import { collectTelemetry } from "../telemetry/server";
import { pingHeartbeat } from "./heartbeat";
import { flushAlerts } from "./alerts";
import { maybeSnapshotDb } from "./db-snapshot";

/**
 * The complete monitor cycle body — the cheap endpoint probe every tick, the
 * expensive deploy/peer/telemetry/maintenance phase only on a FULL sync (the
 * cadence decision itself stays with the scheduler wiring in index.ts). Extracted
 * so the worker entry (worker.ts) is pure glue and this composition stays
 * importable/testable without threads.
 *
 * THE monitor composition root: `config` and `conn` arrive from the host (via
 * `index.ts` on the API thread, via `worker.ts`'s `workerData` on the worker
 * thread) and are threaded to every function below that needs a setting or the
 * connection url — nothing here reads env or a config singleton.
 */
export async function runMonitorCycle(
  db: Db,
  opts: { fullSync: boolean; config: StatusConfig; conn: LibsqlConnection },
): Promise<void> {
  const { config, conn } = opts;
  try {
    await runCycle(db, config, { skipDeploys: !opts.fullSync });
  } finally {
    // Deliver whatever the recorders queued even when a later phase of the
    // cycle throws — an outage alert must not be lost to an unrelated failure.
    await flushAlerts(config.alertWebhookUrl);
  }
  if (opts.fullSync) {
    await fetchPeers(db);
    await collectTelemetry(db, config); // guarded + fail-soft; no-op when GlitchTip/PostHog unset
    // Bound every accruing table (health_checks, metrics_hourly, analytics_metrics,
    // expired sessions). THIS is the only caller in the running process — the
    // `POST /cron/maintenance` route needs an external cron that Railway never had, so
    // health_checks was never pruned and grew forever, which is what drove the per-tick
    // rollup cost past the container's CPU quota. Chunked + bounded per run, so a long
    // backlog is cleared over successive cycles rather than in one huge transaction.
    const pruned = await runMaintenance(db, conn);
    if (pruned.deleted > 0) {
      console.log(`[maintenance] pruned ${pruned.deleted} retention rows${pruned.done ? '' : ' — more next cycle'}`);
    }
    // On-volume DB snapshot (once per day; fail-soft; embedded-file DBs only) —
    // the config the operator hand-entered must survive a corrupted live file.
    await maybeSnapshotDb(db, { dbUrl: conn.url });
    // Dead-man check-in — LAST, so it only fires when the whole full sync
    // succeeded. A failing or wedged monitor stops pinging, and the external
    // service (healthchecks.io-style) raises the alert no in-container code
    // could. Fail-soft + bounded; probe-only ticks never ping.
    await pingHeartbeat(config.heartbeatUrl);
  }
}
