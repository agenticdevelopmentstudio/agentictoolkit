"use client";
import { useEffect, useState } from "react";

/**
 * A coarse, stable-per-render clock: `Date.now()` snapshotted on mount and
 * refreshed every `intervalMs` (default 30s). Use this instead of calling
 * `Date.now()` directly in render — an in-render `Date.now()` is impure (it makes
 * "time ago" labels jump on unrelated re-renders, and the React rules-of-hooks
 * lint flags it). The interval also keeps relative times ticking on their own.
 */
export function useNow(intervalMs = 30_000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}
