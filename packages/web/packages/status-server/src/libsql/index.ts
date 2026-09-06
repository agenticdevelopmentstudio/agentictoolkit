// `@agentic-toolkit/status-server/libsql` — the libSQL/SQLite storage implementation:
// connection, tuning, checkpointing, migrations, the drizzle schema, and the
// concrete `Storage` port adapters (the only place in this package permitted to
// speak drizzle/@libsql — see ../storage/ports.ts for the interfaces themselves).
export * from "./client";
export * as schema from "./schema";

import type { Db, LibsqlConnection } from "./client";
import type { Storage } from "../storage/ports";
import { createConfigStore } from "./stores/config-store";
import { createAuthStore } from "./stores/auth-store";
import { createTokenStore } from "./stores/token-store";
import { createHealthStore } from "./stores/health-store";
import { createDeployStore } from "./stores/deploy-store";
import { createIssueStore } from "./stores/issue-store";
import { createObservationStore } from "./stores/observation-store";
import { createMaintenanceStore } from "./stores/maintenance-store";
import { createBoardStore } from "./stores/board-store";
import { createHistoryStore } from "./stores/history-store";
import { createDeviceStore } from "./stores/device-store";
import { createPeerStore } from "./stores/peer-store";
import { createTelemetryStore } from "./stores/telemetry-store";

/**
 * Build the full `Storage` port over one connection — the libSQL adapter a host
 * passes to `createApp`. Composed from the per-concern stores by name; a host
 * never reaches for a raw `Db` past this call.
 *
 * `conn` is OPTIONAL and used only by `maintenance` (WAL checkpoint + VACUUM INTO
 * snapshot need the raw connection, not just `Db`) — a host with no live connection
 * (e.g. a route-only AppDeps) still gets every other concern, minus those two
 * disk-level steps.
 */
export function createLibsqlStorage(db: Db, conn?: LibsqlConnection): Storage {
  return {
    config: createConfigStore(db),
    auth: createAuthStore(db),
    tokens: createTokenStore(db),
    health: createHealthStore(db),
    deploy: createDeployStore(db),
    issues: createIssueStore(db),
    observations: createObservationStore(db),
    maintenance: createMaintenanceStore(db, conn),
    board: createBoardStore(db),
    history: createHistoryStore(db),
    device: createDeviceStore(db),
    peers: createPeerStore(db),
    telemetry: createTelemetryStore(db),
  };
}
