// `@agentic-toolkit/status-server/libsql` — the libSQL/SQLite storage implementation:
// connection, tuning, checkpointing, migrations, the drizzle schema, and the
// concrete `Storage` port adapters (the only place in this package permitted to
// speak drizzle/@libsql — see ../storage/ports.ts for the interfaces themselves).
export * from "./client";
export * as schema from "./schema";

import type { Db } from "./client";
import type { Storage } from "../storage/ports";
import { createConfigStore } from "./stores/config-store";
import { createAuthStore } from "./stores/auth-store";
import { createTokenStore } from "./stores/token-store";
import { createHealthStore } from "./stores/health-store";

/**
 * Build the full `Storage` port over one connection — the libSQL adapter a host
 * passes to `createApp`. Composed from the per-concern stores by name; a host
 * never reaches for a raw `Db` past this call.
 */
export function createLibsqlStorage(db: Db): Storage {
  return {
    config: createConfigStore(db),
    auth: createAuthStore(db),
    tokens: createTokenStore(db),
    health: createHealthStore(db),
  };
}
