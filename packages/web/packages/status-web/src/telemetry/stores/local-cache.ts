import type { SnapshotCache } from "../ports";
import type { TelemetrySnapshot } from "../types";

// localStorage adapter of SnapshotCache — the client's "store for now". Persists
// the latest telemetry snapshot so the band paints instantly on reload and shows
// a last-known view while the source is briefly unreachable. The pure parse is
// split out (parseSnapshot) so it's unit-testable without a browser; the adapter
// only adds the window/localStorage I/O.

const KEY = "adh-telemetry-v1";

/** Defensive, shape-gated parse of a stored snapshot — anything off → null. */
export function parseSnapshot(raw: string | null): TelemetrySnapshot | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as Partial<TelemetrySnapshot> | null;
    if (!v || typeof v.generatedAt !== "string" || !Array.isArray(v.errors) || !Array.isArray(v.analytics)) {
      return null;
    }
    return { generatedAt: v.generatedAt, errors: v.errors, analytics: v.analytics };
  } catch {
    return null;
  }
}

export const localCache: SnapshotCache = {
  load(): TelemetrySnapshot | null {
    if (typeof window === "undefined") return null;
    try {
      return parseSnapshot(window.localStorage.getItem(KEY));
    } catch {
      return null;
    }
  },
  save(snapshot: TelemetrySnapshot): void {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.setItem(KEY, JSON.stringify(snapshot));
    } catch {
      // best-effort — the in-memory query result is the live truth
    }
  },
};
