import { parentPort, workerData } from "node:worker_threads";
import { openLibsql, tuneDbForConcurrency } from "../libsql/client";
import { attachCooldownState } from "@agentic-toolkit/deploy-platform/cooldown";
import { runMonitorCycle } from "./cycle-runner";
import type { CycleRequest, CycleReply, MonitorWorkerData } from "./worker-client";

// The monitor worker: runs the ENTIRE monitoring cycle on its own thread — its own
// event loop, its own DB connection — so the heavy full-sync phase (four provider
// APIs, telemetry, TLS handshakes, JSON parsing) can never starve the API server's
// event loop again. That starvation is what reset in-flight /auth/me and /auth/refresh
// proxy sockets (rendering the site signed-out) and made the supervisor's /health
// probes read "down" and restart the container. Glue only: the cycle logic lives in
// cycle-runner.ts; spawn/respawn/timeout policy lives in worker-client.ts.

const port = parentPort;
if (!port) throw new Error("monitor worker must be spawned via worker_threads (see worker-client.ts)");

// Fail fast on a malformed spawn rather than surfacing a confusing crash deep inside
// openLibsql/runMonitorCycle: `db`/`config` are the two things the client MUST supply
// (see MonitorWorkerData) and a missing one means the client itself is broken.
const { db: conn, config, cooldowns } = (workerData ?? {}) as Partial<MonitorWorkerData>;
if (!conn?.url) throw new Error("monitor worker spawned without workerData.db.url (see MonitorWorkerData)");
if (!config) throw new Error("monitor worker spawned without workerData.config (see MonitorWorkerData)");

// Adopt the parent's provider-cooldown state: the cycle here and the API thread's
// dashboard enumerations poll the SAME provider tokens, so a 429 either one sees
// must back BOTH off. Without this the worker would keep a private registry and
// keep hammering a provider the API thread already knows is throttled.
attachCooldownState(cooldowns);

// Migrations already ran on the main thread before this worker was spawned.
const db = openLibsql(conn);
await tuneDbForConcurrency(db, conn);

port.on("message", (msg: CycleRequest) => {
  void (async (): Promise<void> => {
    try {
      await runMonitorCycle(db, { fullSync: msg.fullSync, config, conn });
      port.postMessage({ seq: msg.seq, ok: true } satisfies CycleReply);
    } catch (err) {
      port.postMessage({
        seq: msg.seq,
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      } satisfies CycleReply);
    }
  })();
});
