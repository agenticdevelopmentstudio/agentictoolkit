"use client";
import { useCallback, useEffect, useState } from "react";

/** Default age-out window for the Activity list: one hour. */
export const DEFAULT_ACTIVITY_TTL_MS = 60 * 60 * 1000;
/** Selectable age-out choices (minutes); `null` (handled separately) means "never". */
export const ACTIVITY_TTL_OPTIONS_MIN = [1, 15, 30, 60];

// The storage key predates the Healthy → Activity rename and is deliberately
// unchanged: renaming it would silently reset every existing reader's choice back
// to the default. The key is an opaque handle, not documentation.
const KEY = "adh-healthy-ttl";
const DEFAULT_MIN = DEFAULT_ACTIVITY_TTL_MS / 60_000;
const VALID = new Set<number>(ACTIVITY_TTL_OPTIONS_MIN);

/** A persisted age-out choice: a number of minutes, or `null` to keep activity
 *  until it's cleared manually (the menu's "clear" option). */
export type ActivityTtl = number | null;

/**
 * How long activity stays in the list — the user's choice, persisted to
 * localStorage so it survives reloads (mirrors {@link useEnvFilter}). Defaults to
 * one hour. Starts at the default on first render and hydrates from storage in an
 * effect, so SSR/first-paint match. `ttlMs` is the convenience form the view uses
 * (null → no age-out); live problems are exempt from it structurally — the server's
 * `Board.problems` is its own list, never folded through the activity ttl filter
 * (see OverviewTab's `problems`/`activity` derivation).
 */
export function useActivityTtl(): { ttlMin: ActivityTtl; ttlMs: number | null; setTtl: (v: ActivityTtl) => void } {
  const [ttlMin, setTtlMin] = useState<ActivityTtl>(DEFAULT_MIN);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw === null) return;
      const parsed = JSON.parse(raw) as unknown;
      // One-shot hydration after first render so SSR/first-paint match — external
      // store sync, not derived state. `null` is a valid stored value ("clear").
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (parsed === null) setTtlMin(null);
      // eslint-disable-next-line react-hooks/set-state-in-effect
      else if (typeof parsed === "number" && VALID.has(parsed)) setTtlMin(parsed);
    } catch {
      // localStorage unavailable / bad JSON — keep the default.
    }
  }, []);

  const setTtl = useCallback((v: ActivityTtl) => {
    setTtlMin(v);
    try {
      localStorage.setItem(KEY, JSON.stringify(v));
    } catch {
      // ignore persistence failure — the in-memory choice still applies
    }
  }, []);

  return { ttlMin, ttlMs: ttlMin == null ? null : ttlMin * 60_000, setTtl };
}
