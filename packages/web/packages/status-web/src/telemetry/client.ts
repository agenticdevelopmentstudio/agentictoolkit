import { localCache } from "./stores/local-cache";
import { liveSource } from "./sources/live";
import { tursoSource } from "./sources/turso";
import type { SnapshotCache, TelemetrySource } from "./ports";

// THE client composition root. `cache` is where the browser persists a snapshot
// (localStorage today) for instant paint + offline; `source` is where it reads a
// fresh snapshot from. Both implementations are wired below so either can be
// selected with no other change.
//
// RECONNECT THE TURSO BACKEND LATER = change `SOURCES.live` to `SOURCES.turso` on
// the one line marked below. The hook, the cache and the panels are untouched —
// the dashboard then serves errors/analytics from the database instead of the
// live poll, same TelemetrySnapshot contract.
const SOURCES = { live: liveSource, turso: tursoSource };

export const cache: SnapshotCache = localCache;
export const source: TelemetrySource = SOURCES.live; // ← reconnect: SOURCES.turso
