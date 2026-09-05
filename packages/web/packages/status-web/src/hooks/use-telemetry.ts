"use client";
import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { cache, source } from "../telemetry/client";
import { emptySnapshot, type TelemetrySnapshot } from "../telemetry/types";

export const TELEMETRY_POLL_MS = 60_000;

// Polls the configured TelemetrySource and persists each snapshot to the cache
// (localStorage). Hydrates from the cache AFTER mount (not during render) so SSR
// and the first client paint match; then the cached snapshot fills in and the
// live poll refreshes it. The hook knows only the source + cache ports — never
// GlitchTip/PostHog/Turso — so swapping the backend (telemetry/client.ts) leaves
// it untouched.
export function useTelemetry(): TelemetrySnapshot {
  const [cached, setCached] = useState<TelemetrySnapshot | null>(null);
  useEffect(() => {
    setCached(cache.load());
  }, []);

  const query = useQuery<TelemetrySnapshot>({
    queryKey: ["telemetry"],
    queryFn: () => source.get(),
    refetchInterval: TELEMETRY_POLL_MS,
    refetchOnWindowFocus: true,
    retry: 1,
  });

  useEffect(() => {
    if (query.data) cache.save(query.data);
  }, [query.data]);

  // Live data wins; the cached snapshot covers the gap before the first poll
  // lands (and a brief source outage); empty until either arrives.
  return query.data ?? cached ?? emptySnapshot();
}
