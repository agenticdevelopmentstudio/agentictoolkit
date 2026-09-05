"use client";
import { useCallback, useEffect, useState } from "react";
import { ENVIRONMENTS } from "../api/monitored-sites";

const KEY = "adh-env-filter";
const ALL: readonly string[] = ENVIRONMENTS;

/**
 * Which environments the Overview shows, persisted to localStorage so the choice
 * survives reloads. Defaults to all selected (no filter). Starts at the default on
 * first render and hydrates from storage in an effect — so SSR/first-paint match.
 */
export function useEnvFilter(): { envs: Set<string>; all: readonly string[]; toggle: (env: string) => void } {
  const [envs, setEnvs] = useState<Set<string>>(() => new Set(ALL));

  useEffect(() => {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return;
      const arr = JSON.parse(raw) as unknown;
      // One-shot hydration from localStorage on mount — deliberately after first
      // render so SSR/first-paint match; this is external-store sync, not derived state.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (Array.isArray(arr)) setEnvs(new Set(arr.filter((e): e is string => typeof e === "string" && ALL.includes(e))));
    } catch {
      // localStorage unavailable / bad JSON — keep the default.
    }
  }, []);

  const toggle = useCallback((env: string) => {
    setEnvs((prev) => {
      const next = new Set(prev);
      if (next.has(env)) next.delete(env);
      else next.add(env);
      try {
        localStorage.setItem(KEY, JSON.stringify([...next]));
      } catch {
        // ignore persistence failure
      }
      return next;
    });
  }, []);

  return { envs, all: ALL, toggle };
}
