import type { Db } from "../libsql/client";
import type { TelemetrySnapshot } from "./types";

// The PORTS of the telemetry subsystem. Every concrete piece — a GlitchTip
// poller, the SQLite tables, the live API endpoint — is an ADAPTER behind one of
// these interfaces. A trigger (the scheduler cycle, a request) composes a Fetcher
// with a Store without either knowing the other's implementation. You mix and
// match by swapping adapters at the composition root (server.ts) — nothing above
// the port moves.
//
// This backend has no db singleton, so the Store methods take the `db` handle
// explicitly (dependency injection) rather than closing over an imported client.

export interface FetchResult<T> {
  /** False → the provider poll failed. Callers must NOT treat an empty list as
   *  "no data" (don't overwrite/clear a store on a transient provider outage). */
  ok: boolean;
  items: T[];
  /**
   * Is `items` the provider's COMPLETE current set, or one page of it?
   *
   * Only a store that RECONCILES needs this, and it needs it absolutely: `errorsStore`
   * reads "absent from this set" as "resolved upstream", which is sound for a whole
   * answer and catastrophic for a page — issue 101 of 140 would be resolved on every
   * poll and reopened on the next, flapping the board and paging on-call forever.
   *
   * Optional, defaulting to TRUE, because every other fetcher here returns a whole
   * answer by construction; a paginating fetcher must set it explicitly.
   */
  complete?: boolean;
}

/** A SOURCE of telemetry items, pulled live from a provider. Knows no storage. */
export interface Fetcher<T> {
  fetch(): Promise<FetchResult<T>>;
}

/** Server-side persistence for one telemetry stream. Knows no provider/trigger.
 *  Takes the db handle explicitly (this backend has no db singleton). */
export interface Store<T> {
  /** Persist a freshly-fetched set (upsert or append per the stream's semantics).
   *  `opts.complete` is the fetcher's `FetchResult.complete`, threaded through by
   *  `collect` — an APPENDING store ignores it; a RECONCILING one must not. */
  save(db: Db, items: T[], opts?: { complete?: boolean }): Promise<void>;
  /** Read the current set for surfacing. */
  load(db: Db): Promise<T[]>;
}

/** Where a client reads a snapshot from — an HTTP boundary hides the server
 *  store. `live` → /telemetry; `stored` → /errors + /analytics. */
export interface TelemetrySource {
  get(): Promise<TelemetrySnapshot>;
}
