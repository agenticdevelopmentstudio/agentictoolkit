import type { TelemetrySnapshot } from "./types";

// The PORTS of the telemetry subsystem. Every concrete piece — a GlitchTip
// poller, the Turso tables, the localStorage cache, the live API endpoint — is
// an ADAPTER behind one of these interfaces. A trigger (cron, request, webhook)
// composes a Fetcher with a Store without either knowing the other's
// implementation; the client reads through a Source without knowing whether the
// data is live or from the database. You mix and match by swapping adapters at
// the composition roots (server.ts / client.ts) — nothing above the port moves.

export interface FetchResult<T> {
  /** False → the provider poll failed. Callers must NOT treat an empty list as
   *  "no data" (don't overwrite/clear a store on a transient provider outage). */
  ok: boolean;
  items: T[];
}

/** A SOURCE of telemetry items, pulled live from a provider. Knows no storage. */
export interface Fetcher<T> {
  fetch(): Promise<FetchResult<T>>;
}

/** Server-side persistence for one telemetry stream. Knows no provider/trigger. */
export interface Store<T> {
  /** Persist a freshly-fetched set (upsert or append per the stream's semantics). */
  save(items: T[]): Promise<void>;
  /** Read the current set for surfacing. */
  load(): Promise<T[]>;
}

/** Client-side snapshot cache (localStorage today) — instant paint + last-known
 *  view when the source is briefly unreachable. */
export interface SnapshotCache {
  load(): TelemetrySnapshot | null;
  save(snapshot: TelemetrySnapshot): void;
}

/** Where the CLIENT reads a snapshot from — an HTTP boundary hides the server
 *  store. `live` → /api/telemetry; `turso` → /api/errors + /api/analytics. */
export interface TelemetrySource {
  get(): Promise<TelemetrySnapshot>;
}
